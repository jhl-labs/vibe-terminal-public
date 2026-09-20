import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../models/memo.dart';
import '../models/memo_version.dart';

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
    await (_db.delete(
      _db.memoVersions,
    )..where((t) => t.hostId.equals(hostId))).go();
  }

  // ── 버전 히스토리 ──────────────────────────────────────────────────────

  /// host당 보관하는 자동 버전 상한. 수동(label 있는) 버전은 세지 않는다.
  static const maxAutoVersions = 50;

  /// 이 시간 안에 이어지는 자동 저장은 같은 자동 버전으로 병합된다.
  static const autoMergeWindow = Duration(minutes: 10);

  /// 사용자가 직접 남기는 버전. 항상 새 행을 만든다.
  Future<void> snapshot(
    String hostId,
    String body,
    DateTime createdAt, {
    String? label,
  }) async {
    await _db
        .into(_db.memoVersions)
        .insert(
          MemoVersionsCompanion.insert(
            hostId: hostId,
            body: body,
            createdAt: createdAt,
            label: Value(label),
          ),
        );
  }

  /// 자동 저장 후 호출되는 버전 기록. 최신 버전과 본문이 같으면 건너뛰고,
  /// 최신 버전이 자동 버전이면서 [autoMergeWindow] 안이면 그 행을 갱신한다.
  /// 그 외에는 새 자동 버전을 만들고 상한을 넘는 오래된 자동 버전을 지운다.
  Future<void> autoSnapshot(String hostId, String body, DateTime now) async {
    final latest =
        await (_db.select(_db.memoVersions)
              ..where((t) => t.hostId.equals(hostId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (latest != null && latest.body == body) return;
    if (latest != null &&
        latest.label == null &&
        now.difference(latest.createdAt) < autoMergeWindow) {
      await (_db.update(
        _db.memoVersions,
      )..where((t) => t.id.equals(latest.id))).write(
        MemoVersionsCompanion(body: Value(body), createdAt: Value(now)),
      );
      return;
    }
    await snapshot(hostId, body, now);
    await _pruneAutoVersions(hostId);
  }

  Future<void> _pruneAutoVersions(String hostId) async {
    final autos =
        await (_db.select(_db.memoVersions)
              ..where((t) => t.hostId.equals(hostId) & t.label.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ]))
            .get();
    if (autos.length <= maxAutoVersions) return;
    final stale = autos.skip(maxAutoVersions).map((r) => r.id).toList();
    await (_db.delete(_db.memoVersions)..where((t) => t.id.isIn(stale))).go();
  }

  /// host의 버전을 최신순으로 반환한다.
  Future<List<MemoVersion>> listVersions(String hostId) async {
    final rows =
        await (_db.select(_db.memoVersions)
              ..where((t) => t.hostId.equals(hostId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ]))
            .get();
    return rows
        .map(
          (r) => MemoVersion(
            id: r.id,
            hostId: r.hostId,
            body: r.body,
            createdAt: r.createdAt,
            label: r.label,
          ),
        )
        .toList();
  }

  Future<void> deleteVersion(int id) async {
    await (_db.delete(_db.memoVersions)..where((t) => t.id.equals(id))).go();
  }

  Memo _toModel(MemoRow r) =>
      Memo(hostId: r.hostId, body: r.body, updatedAt: r.updatedAt);
}
