import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../models/memo.dart';

class MemoRepository {
  MemoRepository(this._db);
  final AppDatabase _db;

  /// 해당 host의 메모. 없으면 null.
  Future<Memo?> getForHost(String hostId) async {
    final row = await (_db.select(
      _db.memos,
    )..where((t) => t.hostId.equals(hostId))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// 메모가 있는 모든 host의 메모를 최근 수정순으로 반환한다.
  /// 활성 세션이 없을 때 목록에서 메모를 열어보기 위해 사용한다.
  Future<List<Memo>> listAll() async {
    final query = _db.select(_db.memos)
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.hostId),
      ]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// host 메모를 저장한다. Host당 하나이므로 upsert.
  Future<void> save(String hostId, String body, DateTime updatedAt) async {
    await _db
        .into(_db.memos)
        .insertOnConflictUpdate(
          MemosCompanion.insert(
            hostId: hostId,
            body: body,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> delete(String hostId) async {
    await (_db.delete(_db.memos)..where((t) => t.hostId.equals(hostId))).go();
  }

  Memo _toModel(MemoRow r) =>
      Memo(hostId: r.hostId, body: r.body, updatedAt: r.updatedAt);
}
