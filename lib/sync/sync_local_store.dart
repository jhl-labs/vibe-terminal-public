import 'package:drift/drift.dart';

import '../data/db/app_database.dart';
import '../security/secure_store.dart';
import 'sync_merge.dart';
import 'sync_section.dart';
import 'sync_snapshot.dart';

/// 병합 결과를 적용하기 직전 로컬이 그새 바뀌었으면 던진다. 엔진은 다시 받는다.
class SyncLocalChangedException implements Exception {
  const SyncLocalChangedException();

  @override
  String toString() => '동기화하는 동안 로컬 데이터가 바뀌었습니다.';
}

/// 로컬 스냅샷과, 적용 전 변경 감지에 쓰는 지문.
class SyncLocalState {
  const SyncLocalState({required this.snapshot, required this.fingerprint});

  final SyncSnapshot snapshot;
  final String fingerprint;
}

/// 로컬 반영 결과.
class SyncApplied {
  const SyncApplied({
    required this.fingerprint,
    this.changed = 0,
    this.needsAnotherPass = false,
  });

  /// 반영 직후의 지문.
  final String fingerprint;

  /// 실제로 바뀐 로컬 항목 수(설정 묶음은 1개). 기기별 데이터라 건너뛴
  /// 레코드는 세지 않는다.
  final int changed;

  /// 병합 결과와 다르게 남긴 행이 있다(다른 기기에서 지웠지만 이 기기가 아직
  /// 쓰는 Identity·키). 원격에 다시 올리려면 한 번 더 병합해야 한다.
  final bool needsAnotherPass;
}

abstract interface class SyncLocalStore {
  Future<SyncLocalState> read();

  /// [result]를 로컬에 반영한다. 로컬 지문이 [expectedFingerprint]와 다르면
  /// 아무것도 바꾸지 않고 [SyncLocalChangedException]을 던진다.
  Future<SyncApplied> apply(
    SyncMergeResult result, {
    required String expectedFingerprint,
  });
}

/// 앱 DB·보안 저장소·설정을 동기화 스냅샷으로 읽고 쓴다.
class AppSyncLocalStore implements SyncLocalStore {
  AppSyncLocalStore({
    required AppDatabase database,
    required this._secureStore,
    required this._sections,
    required this._readSettings,
    required this._applySettings,
  }) : _db = database;

  final AppDatabase _db;
  final SecureStore _secureStore;
  final List<SyncSection> _sections;
  final SyncSettingsBlock Function() _readSettings;
  final void Function(SyncSettingsBlock settings) _applySettings;

  @override
  Future<SyncLocalState> read() async {
    // 지문을 먼저 잡는다. 스냅샷을 읽는 사이에 생긴 변경은 지문과 어긋나
    // 적용 직전 비교에서 걸리고, 엔진이 다시 읽는다.
    final fingerprint = await _fingerprint();
    return SyncLocalState(
      snapshot: await _snapshot(includeSecrets: true),
      fingerprint: fingerprint,
    );
  }

  @override
  Future<SyncApplied> apply(
    SyncMergeResult result, {
    required String expectedFingerprint,
  }) async {
    final secretRefsToDelete = <String>[];
    var keptReferenced = false;
    var changed = 0;
    final applied = await _db.transaction(() async {
      if (await _fingerprint() != expectedFingerprint) {
        throw const SyncLocalChangedException();
      }
      // 참조되는 쪽(키 → Identity → 호스트) 순서로 넣고, 지울 때는 반대로
      // 지워 참조 중인 행을 판단할 때 이번 변경이 모두 반영돼 있게 한다.
      for (final section in _sections) {
        final changes = result.localChanges[section.name];
        if (changes != null) {
          changed += await section.applyUpserts(changes.upserts);
        }
      }
      for (final section in _sections.reversed) {
        final changes = result.localChanges[section.name];
        if (changes == null) continue;
        final outcome = await section.applyDeletes(
          changes,
          secretRefsToDelete: secretRefsToDelete,
        );
        changed += outcome.deleted;
        if (outcome.kept > 0) keptReferenced = true;
      }
      // 위 삭제가 트리거로 남긴 기록을 병합된 기록(원래 삭제 시각)으로 바꾼다.
      await _db.delete(_db.syncTombstones).go();
      await _db.batch((batch) {
        batch.insertAll(_db.syncTombstones, [
          for (final tombstone in result.merged.tombstones)
            SyncTombstonesCompanion.insert(
              entity: tombstone.entity,
              recordId: tombstone.id,
              deletedAt: tombstone.deletedAt,
            ),
        ]);
      });
      return _fingerprint();
    });
    for (final ref in secretRefsToDelete) {
      await _secureStore.deleteSecret(ref);
    }
    final settings = result.settingsFromRemote;
    if (settings != null) {
      _applySettings(settings);
      changed++;
    }
    return SyncApplied(
      fingerprint: settings == null ? applied : await _fingerprint(),
      changed: changed,
      needsAnotherPass: keptReferenced,
    );
  }

  /// 동기화를 쓰지 않아도 삭제 기록이 쌓이지 않게 보관 기간이 지난 것을 지운다.
  Future<void> pruneTombstones(DateTime now) async {
    final cutoff = now.subtract(kSyncTombstoneRetention);
    await (_db.delete(
      _db.syncTombstones,
    )..where((t) => t.deletedAt.isSmallerThanValue(cutoff))).go();
  }

  Future<SyncSnapshot> _snapshot({required bool includeSecrets}) async {
    final tombstones = await _db.select(_db.syncTombstones).get();
    return SyncSnapshot(
      settings: _readSettings(),
      sections: {
        for (final section in _sections)
          section.name: await section.read(includeSecrets: includeSecrets),
      },
      tombstones: [
        for (final row in tombstones)
          SyncTombstone(
            entity: row.entity,
            id: row.recordId,
            deletedAt: row.deletedAt,
          ),
      ],
    );
  }

  /// 보안 저장소를 읽지 않는 변경 감지 값. 비밀값은 레코드 변경 시각과 함께
  /// 바뀌므로 레코드만 비교해도 된다.
  Future<String> _fingerprint() async {
    return (await _snapshot(includeSecrets: false)).contentHash;
  }
}
