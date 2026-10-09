import 'package:drift/drift.dart';

import '../data/db/app_database.dart';
import '../security/secure_store.dart';
import 'sync_merge.dart';
import 'sync_snapshot.dart';

/// 레코드의 비밀값 필드. 스냅샷 전체가 암호화되므로 레코드 안에 함께 둔다.
const kSyncSecretField = 'secret';

/// 로컬 테이블 하나를 동기화 레코드로 읽고 쓴다.
abstract interface class SyncSection {
  /// 섹션 이름. 로컬 테이블 이름이며 삭제 기록의 entity와 같다.
  String get name;

  /// [includeSecrets]가 false면 보안 저장소를 읽지 않는다(변경 감지용).
  Future<List<SyncRecord>> read({bool includeSecrets = true});

  /// DB 트랜잭션 안에서 호출된다. 모든 섹션의 추가·수정이 삭제보다 먼저
  /// 끝나므로, 삭제는 다른 섹션의 최종 상태를 보고 판단할 수 있다. 실제로
  /// 쓴 행 수를 돌려준다(기기별 데이터라 건너뛴 레코드는 세지 않는다).
  Future<int> applyUpserts(List<SyncRecord> records);

  /// DB 트랜잭션 안에서 호출된다. 비밀값 삭제는 롤백할 수 없으므로
  /// [secretRefsToDelete]에 모아 두면 커밋 뒤에 지운다. 지운 행 수와, 참조
  /// 중이라 지우지 않고 되살린 행 수를 돌려준다.
  Future<({int deleted, int kept})> applyDeletes(
    SyncSectionChanges changes, {
    required List<String> secretRefsToDelete,
  });
}

/// 한 행이 한 레코드인 테이블의 공통 처리. 저장소 클래스를 거치지 않고 행을
/// 직접 쓴다. 저장소의 쓰기는 변경 시각을 지금으로 바꾸는 등 부수효과가 있어,
/// 받은 레코드를 그대로 재현하지 못한다.
abstract class RowSyncSection<R> implements SyncSection {
  RowSyncSection(this.db, this.secureStore);

  final AppDatabase db;
  final SecureStore secureStore;

  TableInfo<Table, R> get table;
  Future<List<R>> loadRows();
  String idOf(R row);
  DateTime updatedAtOf(R row);

  /// 레코드 데이터(비밀값 제외). 기기와 무관한 의미 있는 값만 넣는다.
  Map<String, Object?> encode(R row);

  /// 레코드를 행으로 만든다. [existing]은 같은 id의 현재 행이다.
  Insertable<R> decode(SyncRecord record, R? existing);

  /// 비밀값이 있는 테이블이면 그 보안 저장소 키.
  String? secretRefOf(R row) => null;

  /// 받은 레코드의 비밀값을 저장할 키.
  String? secretRefOfRecord(SyncRecord record) => null;

  /// 동기화하지 않는 행(예: 기기별 로컬 셸 호스트). 이런 행은 받은 레코드로
  /// 덮어쓰거나 지우지 않는다.
  bool includes(R row) => true;

  /// 이 기기에 들이지 않을 레코드(예: 이 기기의 로컬 셸에 딸린 메모).
  bool accepts(SyncRecord record) => true;

  /// 다른 행이 아직 참조하는 행인지. 참조 중이면 지우지 않는다.
  Future<bool> isReferenced(String id) async => false;

  /// 참조 중이라 지우지 않은 행을 다른 기기에도 되살리도록 변경 시각을
  /// [after]보다 늦게 바꾼다. 변경 시각 컬럼이 있는 테이블만 재정의한다.
  Future<void> keepReferenced(String id, {required DateTime after}) async {}

  /// 보안 저장소의 비밀값을 아직 다른 행이 쓰는지. 호스트의 credentialRef는
  /// Identity·키의 비밀을 함께 가리키므로 세 테이블을 모두 본다.
  Future<bool> secretInUse(String ref) async {
    if ((await loadRows()).any((row) => secretRefOf(row) == ref)) return true;
    final rows = await db
        .customSelect(
          'SELECT 1 FROM ssh_keys WHERE secret_ref = ?1 '
          'UNION ALL SELECT 1 FROM identities WHERE secret_ref = ?1 '
          'UNION ALL SELECT 1 FROM hosts WHERE credential_ref = ?1 LIMIT 1',
          variables: [Variable<String>(ref)],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<List<SyncRecord>> read({bool includeSecrets = true}) async {
    final records = <SyncRecord>[];
    for (final row in await loadRows()) {
      if (!includes(row)) continue;
      final data = encode(row);
      final ref = includeSecrets ? secretRefOf(row) : null;
      if (ref != null) {
        final secret = await secureStore.readSecret(ref);
        if (secret != null) data[kSyncSecretField] = secret;
      }
      records.add(
        SyncRecord(id: idOf(row), updatedAt: updatedAtOf(row), data: data),
      );
    }
    return records;
  }

  @override
  Future<int> applyUpserts(List<SyncRecord> records) async {
    if (records.isEmpty) return 0;
    var written = 0;
    final existing = {for (final row in await loadRows()) idOf(row): row};
    for (final record in records) {
      final current = existing[record.id];
      if (current != null && !includes(current)) continue;
      if (!accepts(record)) continue;
      final secret = record.data[kSyncSecretField];
      final ref = secretRefOfRecord(record);
      if (secret is String && ref != null) {
        await secureStore.writeSecret(ref, secret);
      }
      await db.into(table).insertOnConflictUpdate(decode(record, current));
      written++;
    }
    return written;
  }

  @override
  Future<({int deleted, int kept})> applyDeletes(
    SyncSectionChanges changes, {
    required List<String> secretRefsToDelete,
  }) async {
    final ids = changes.deletes;
    var deleted = 0;
    var kept = 0;
    final existing = {for (final row in await loadRows()) idOf(row): row};
    final idColumn = AppDatabase.syncTrackedTables[name]!;
    for (final id in ids) {
      final row = existing[id];
      if (row == null || !includes(row)) continue;
      // 다른 기기에서 지웠지만 이 기기의 호스트가 아직 쓰고 있다(오프라인 중에
      // 연결한 경우 등). 지우면 접속 정보가 끊기므로 남기고 다시 올린다.
      if (await isReferenced(id)) {
        await keepReferenced(
          id,
          after: changes.deletedAt[id] ?? DateTime.now(),
        );
        kept++;
        continue;
      }
      await db.customStatement('DELETE FROM $name WHERE $idColumn = ?', [id]);
      deleted++;
      final ref = secretRefOf(row);
      if (ref != null && !await secretInUse(ref)) secretRefsToDelete.add(ref);
    }
    return (deleted: deleted, kept: kept);
  }
}

/// 삭제 기록([deletedAt])을 이기는 변경 시각을 drift 저장 형식(유닉스 초)으로
/// 만든다. 지금이 삭제와 같은 초이면 시각이 같아 삭제가 이기므로 1초 뒤로 둔다.
int syncKeepSeconds(DateTime deletedAt) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final deleted = deletedAt.millisecondsSinceEpoch ~/ 1000;
  return now > deleted ? now : deleted + 1;
}

/// 레코드 데이터를 읽는 도우미. 형식이 틀린 값은 기본값으로 둔다.
extension SyncRecordFields on SyncRecord {
  String string(String key, [String fallback = '']) {
    final value = data[key];
    return value is String ? value : fallback;
  }

  String? optionalString(String key) {
    final value = data[key];
    return value is String ? value : null;
  }

  int integer(String key, int fallback) {
    final value = data[key];
    return value is num ? value.toInt() : fallback;
  }

  bool boolean(String key, {bool fallback = false}) {
    final value = data[key];
    return value is bool ? value : fallback;
  }

  DateTime date(String key, DateTime fallback) {
    final value = data[key];
    return value is String
        ? DateTime.tryParse(value)?.toUtc() ?? fallback
        : fallback;
  }

  /// enum 이름을 DB에 저장하는 인덱스로 바꾼다.
  int enumIndex(String key, List<Enum> values, int fallback) {
    final name = data[key];
    for (final value in values) {
      if (value.name == name) return value.index;
    }
    return fallback;
  }
}

String syncDate(DateTime value) => value.toUtc().toIso8601String();

/// DB 인덱스를 enum 이름으로 바꾼다. 범위를 벗어나면 첫 값을 쓴다.
String syncEnumName(List<Enum> values, int index) =>
    (index >= 0 && index < values.length ? values[index] : values.first).name;
