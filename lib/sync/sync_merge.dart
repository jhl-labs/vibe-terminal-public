import 'sync_snapshot.dart';

/// 삭제 기록 보관 기간. 이보다 오래 꺼져 있던 기기가 돌아오면 지워진 항목이
/// 되살아날 수 있다.
const kSyncTombstoneRetention = Duration(days: 90);

/// 로컬에 반영할 섹션별 변경.
class SyncSectionChanges {
  const SyncSectionChanges({
    this.upserts = const [],
    this.deletes = const [],
    this.deletedAt = const {},
  });

  final List<SyncRecord> upserts;
  final List<String> deletes;

  /// 지우는 레코드별 삭제 기록 시각.
  final Map<String, DateTime> deletedAt;

  bool get isEmpty => upserts.isEmpty && deletes.isEmpty;
  int get count => upserts.length + deletes.length;
}

class SyncMergeResult {
  const SyncMergeResult({
    required this.merged,
    required this.localChanges,
    required this.settingsFromRemote,
    required this.pushed,
  });

  /// 병합 결과. 원격에 올릴 내용이자 로컬이 갖게 될 내용이다.
  final SyncSnapshot merged;

  /// 로컬이 아는 섹션에 한한 변경. 모르는 섹션은 원격에만 보존된다.
  final Map<String, SyncSectionChanges> localChanges;

  /// 원격 설정이 이겨 로컬 설정을 바꿔야 하면 그 값.
  final SyncSettingsBlock? settingsFromRemote;

  /// 원격과 달라진 항목 수(설정 묶음은 1개로 센다).
  final int pushed;

  /// 로컬에 반영되는 항목 수(설정 묶음은 1개로 센다).
  int get pulled =>
      localChanges.values.fold(0, (sum, c) => sum + c.count) +
      (settingsFromRemote == null ? 0 : 1);
}

/// 레코드마다 마지막에 고친 쪽을 남긴다. 삭제 기록이 레코드보다 늦거나 같으면
/// 지운다. [initial]이면 처음 합치는 것이므로 이 기기의 삭제 기록은 쓰지 않는다.
///
/// [local]의 섹션 목록이 이 기기가 아는 섹션이다. 원격에만 있는 섹션(이 앱
/// 빌드가 다루지 않는 데이터)은 그대로 결과에 남겨 다른 기기의 데이터를
/// 지키며, 로컬 변경에는 넣지 않는다.
SyncMergeResult mergeSnapshots({
  required SyncSnapshot local,
  required SyncSnapshot remote,
  required DateTime now,
  bool initial = false,
}) {
  final cutoff = now.toUtc().subtract(kSyncTombstoneRetention);
  final tombstones = <String, SyncTombstone>{};
  // 처음 맞추는 저장소에는 이 기기의 삭제 기록을 쓰지 않는다. 다른 저장소와
  // 동기화하던 때나 동기화 전의 기록이라 이 저장소의 항목과는 관계가 없다.
  // 원격의 삭제 기록은 이 저장소에서 실제로 지운 것이므로 따른다.
  final candidates = initial
      ? remote.tombstones
      : [...local.tombstones, ...remote.tombstones];
  for (final tombstone in candidates) {
    if (tombstone.deletedAt.isBefore(cutoff)) continue;
    final existing = tombstones[tombstone.key];
    if (existing == null || tombstone.deletedAt.isAfter(existing.deletedAt)) {
      tombstones[tombstone.key] = tombstone;
    }
  }

  final mergedSections = <String, List<SyncRecord>>{};
  final localChanges = <String, SyncSectionChanges>{};
  var pushed = 0;
  final names = {...local.sections.keys, ...remote.sections.keys};
  for (final name in names) {
    final known = local.sections.containsKey(name);
    final localById = _byId(local.sections[name]);
    final remoteById = _byId(remote.sections[name]);
    final records = <SyncRecord>[];
    final upserts = <SyncRecord>[];
    final deletes = <String>[];
    final deletedAt = <String, DateTime>{};
    for (final id in {...localById.keys, ...remoteById.keys}) {
      final localRecord = localById[id];
      final remoteRecord = remoteById[id];
      SyncRecord? winner = _newer(localRecord, remoteRecord);
      final tombstoneKey = SyncTombstone.keyOf(name, id);
      final tombstone = tombstones[tombstoneKey];
      if (tombstone != null && winner != null) {
        if (winner.updatedAt.isAfter(tombstone.deletedAt)) {
          tombstones.remove(tombstoneKey);
        } else {
          winner = null;
        }
      }

      if (winner != null) records.add(winner);
      if (known) {
        if (winner == null && localRecord != null) {
          deletes.add(id);
          deletedAt[id] = tombstone!.deletedAt;
        }
        if (winner != null &&
            (localRecord == null || !localRecord.sameAs(winner))) {
          upserts.add(winner);
        }
      }
      final remoteChanged = winner == null
          ? remoteRecord != null
          : remoteRecord == null || !remoteRecord.sameAs(winner);
      if (remoteChanged) pushed++;
    }
    mergedSections[name] = records;
    if (known && (upserts.isNotEmpty || deletes.isNotEmpty)) {
      localChanges[name] = SyncSectionChanges(
        upserts: upserts,
        deletes: deletes,
        deletedAt: deletedAt,
      );
    }
  }

  final settings = _newerSettings(local.settings, remote.settings);
  final settingsFromRemote =
      settings != null &&
          identical(settings, remote.settings) &&
          !_sameSettings(settings, local.settings)
      ? settings
      : null;
  if (!_sameSettings(settings, remote.settings)) pushed++;

  return SyncMergeResult(
    merged: SyncSnapshot(
      settings: settings,
      sections: mergedSections,
      tombstones: tombstones.values.toList(),
    ),
    localChanges: localChanges,
    settingsFromRemote: settingsFromRemote,
    pushed: pushed,
  );
}

Map<String, SyncRecord> _byId(List<SyncRecord>? records) => {
  for (final record in records ?? const <SyncRecord>[]) record.id: record,
};

/// 늦게 고친 쪽. 시각이 같으면 내용을 정해진 순서로 비교해 모든 기기가 같은
/// 쪽을 고르게 한다.
SyncRecord? _newer(SyncRecord? a, SyncRecord? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (a.updatedAt.isAfter(b.updatedAt)) return a;
  if (b.updatedAt.isAfter(a.updatedAt)) return b;
  return a.canonicalData.compareTo(b.canonicalData) >= 0 ? a : b;
}

SyncSettingsBlock? _newerSettings(
  SyncSettingsBlock? local,
  SyncSettingsBlock? remote,
) {
  if (local == null) return remote;
  if (remote == null) return local;
  final localAt = local.updatedAt;
  final remoteAt = remote.updatedAt;
  // 한 번도 바꾸지 않은 쪽(null)은 바꾼 쪽에 진다.
  if (localAt == null && remoteAt != null) return remote;
  if (remoteAt == null && localAt != null) return local;
  if (localAt != null && remoteAt != null) {
    if (localAt.isAfter(remoteAt)) return local;
    if (remoteAt.isAfter(localAt)) return remote;
  }
  // 시각이 같거나 둘 다 없으면 내용으로 정한다. 기기마다 자기 쪽을 고르면
  // 서로 번갈아 덮어쓰며 끝없이 다시 올린다.
  return canonicalJson(local.values).compareTo(canonicalJson(remote.values)) >=
          0
      ? local
      : remote;
}

bool _sameSettings(SyncSettingsBlock? a, SyncSettingsBlock? b) {
  if (a == null || b == null) return a == b;
  final sameTime = a.updatedAt == null
      ? b.updatedAt == null
      : b.updatedAt != null && a.updatedAt!.isAtSameMomentAs(b.updatedAt!);
  return sameTime && canonicalJson(a.values) == canonicalJson(b.values);
}
