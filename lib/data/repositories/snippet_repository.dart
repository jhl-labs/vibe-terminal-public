import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../models/snippet.dart';

class SnippetRepository {
  SnippetRepository(this._db);
  final AppDatabase _db;

  Future<List<Snippet>> getAll() async {
    final query = _db.select(_db.snippets)
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  Future<List<Snippet>> forHost(String? hostId) async {
    final all = await getAll();
    return all
        .where(
          (s) =>
              s.scope == SnippetScope.global ||
              (hostId != null && s.hostId == hostId),
        )
        .toList();
  }

  Future<void> upsert(Snippet s) async {
    await _db.into(_db.snippets).insertOnConflictUpdate(_toRow(s));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.snippets)..where((t) => t.id.equals(id))).go();
  }

  /// 새 스니펫에 부여할 sortOrder. 기존 최댓값 + 1이라 항상 목록 끝에 붙는다.
  Future<int> nextSortOrder() async {
    final maxOrder = _db.snippets.sortOrder.max();
    final row = await (_db.selectOnly(
      _db.snippets,
    )..addColumns([maxOrder])).getSingle();
    final current = row.read(maxOrder);
    return current == null ? 0 : current + 1;
  }

  /// 두 스니펫의 sortOrder를 맞바꾼다(목록에서 위/아래로 한 칸 이동).
  ///
  /// 예전 데이터처럼 sortOrder가 겹쳐 있으면 맞바꿔도 순서가 바뀌지 않으므로,
  /// 먼저 현재 표시 순서대로 0..n-1을 다시 매긴 뒤 교환한다.
  Future<void> swapSortOrder(String idA, String idB) async {
    if (idA == idB) return;
    await _db.transaction(() async {
      var all = await getAll();
      final orders = all.map((s) => s.sortOrder).toSet();
      if (orders.length != all.length) {
        all = [
          for (var i = 0; i < all.length; i++) all[i].copyWith(sortOrder: i),
        ];
        for (final s in all) {
          await _setSortOrder(s.id, s.sortOrder);
        }
      }
      Snippet? a;
      Snippet? b;
      for (final s in all) {
        if (s.id == idA) a = s;
        if (s.id == idB) b = s;
      }
      if (a == null || b == null) return;
      await _setSortOrder(a.id, b.sortOrder);
      await _setSortOrder(b.id, a.sortOrder);
    });
  }

  Future<void> _setSortOrder(String id, int sortOrder) async {
    await (_db.update(_db.snippets)..where((t) => t.id.equals(id))).write(
      SnippetsCompanion(sortOrder: Value(sortOrder)),
    );
  }

  Snippet _toModel(SnippetRow r) => Snippet(
    id: r.id,
    name: r.name,
    body: r.body,
    scope: SnippetScope.values[r.scope],
    hostId: r.hostId,
    defaultRunMode: SnippetRunMode.values[r.defaultRunMode],
    sortOrder: r.sortOrder,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );

  SnippetsCompanion _toRow(Snippet s) => SnippetsCompanion.insert(
    id: s.id,
    name: s.name,
    body: s.body,
    scope: Value(s.scope.index),
    hostId: Value(s.hostId),
    defaultRunMode: Value(s.defaultRunMode.index),
    sortOrder: Value(s.sortOrder),
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
  );
}
