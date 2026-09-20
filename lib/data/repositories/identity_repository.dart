import 'package:drift/drift.dart';

import '../../security/secure_store.dart';
import '../db/app_database.dart';
import '../models/host.dart';
import '../models/identity.dart';

/// 이 Identity를 참조하는 호스트가 있어 삭제할 수 없을 때 던진다.
class IdentityInUseException implements Exception {
  const IdentityInUseException(this.count);
  final int count;
  @override
  String toString() => '이 Identity를 사용하는 호스트가 $count개 있습니다';
}

/// Identity(사용자명 + 인증 방식) 메타데이터(DB)와 비밀번호(secure store)를 관리한다.
class IdentityRepository {
  IdentityRepository(this._db, this._secureStore);
  final AppDatabase _db;
  final SecureStore _secureStore;

  Future<List<Identity>> getAll({bool includeHostScoped = false}) async {
    final query = _db.select(_db.identities)
      ..orderBy([(t) => OrderingTerm.asc(t.label)]);
    if (!includeHostScoped) {
      query.where((t) => t.hostScoped.equals(false));
    }
    return (await query.get()).map(_toModel).toList();
  }

  Future<Identity?> getById(String id) async {
    final row = await (_db.select(
      _db.identities,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// [password]를 주면 secure store에 저장하고 secretRef를 채운다. 비밀번호
  /// 방식이 아니게 바뀌면 남아 있던 비밀번호 비밀을 지운다.
  Future<Identity> upsert(Identity identity, {String? password}) async {
    var next = identity.copyWith(updatedAt: DateTime.now());
    final previous = await getById(identity.id);
    if (next.authType == HostAuthType.password) {
      if (password != null && password.isNotEmpty) {
        final ref = next.secretRef ?? 'identity-${next.id}';
        await _secureStore.writeSecret(ref, password);
        next = next.copyWith(secretRef: ref);
      }
    } else if (previous?.secretRef != null &&
        previous!.authType == HostAuthType.password) {
      await _secureStore.deleteSecret(previous.secretRef!);
      next = next.copyWith(secretRef: null);
    }
    await _db.into(_db.identities).insertOnConflictUpdate(_toRow(next));
    return next;
  }

  /// 이 Identity를 참조하는 호스트 개수.
  Future<int> usageCount(String id) async {
    final count = _db.hosts.id.count();
    final row =
        await (_db.selectOnly(_db.hosts)
              ..addColumns([count])
              ..where(_db.hosts.identityId.equals(id)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> delete(String id) async {
    final used = await usageCount(id);
    if (used > 0) throw IdentityInUseException(used);
    final identity = await getById(id);
    if (identity == null) return;
    await (_db.delete(_db.identities)..where((t) => t.id.equals(id))).go();
    if (identity.authType == HostAuthType.password &&
        identity.secretRef != null) {
      await _secureStore.deleteSecret(identity.secretRef!);
    }
  }

  Identity _toModel(IdentityRow r) => Identity(
    id: r.id,
    label: r.label,
    username: r.username,
    authType: r.authType >= 0 && r.authType < HostAuthType.values.length
        ? HostAuthType.values[r.authType]
        : HostAuthType.password,
    keyId: r.keyId,
    secretRef: r.secretRef,
    hostScoped: r.hostScoped,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );

  IdentitiesCompanion _toRow(Identity i) => IdentitiesCompanion.insert(
    id: i.id,
    label: i.label,
    username: i.username,
    authType: Value(i.authType.index),
    keyId: Value(i.keyId),
    secretRef: Value(i.secretRef),
    hostScoped: Value(i.hostScoped),
    createdAt: i.createdAt,
    updatedAt: i.updatedAt,
  );
}
