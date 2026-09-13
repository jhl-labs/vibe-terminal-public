import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../models/host.dart';

class HostRepository {
  HostRepository(this._db);
  final AppDatabase _db;

  Future<List<Host>> getAll() async {
    final rows = await _db.select(_db.hosts).get();
    return rows.map(_toModel).toList();
  }

  Future<Host?> getById(String id) async {
    final row = await (_db.select(
      _db.hosts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<void> upsert(Host host) async {
    await _db.into(_db.hosts).insertOnConflictUpdate(_toRow(host));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.hosts)..where((t) => t.id.equals(id))).go();
  }

  T _enumValue<T>(List<T> values, int index, T fallback) {
    if (index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  Host _toModel(HostRow r) => Host(
    id: r.id,
    alias: r.alias,
    hostname: r.hostname,
    port: r.port,
    username: r.username,
    connectionType: _enumValue(
      HostConnectionType.values,
      r.connectionType,
      HostConnectionType.ssh,
    ),
    authType: _enumValue(
      HostAuthType.values,
      r.authType,
      HostAuthType.password,
    ),
    localShellType: _enumValue(
      LocalShellType.values,
      r.localShellType,
      LocalShellType.powershell,
    ),
    workingDirectory: r.workingDirectory,
    credentialRef: r.credentialRef,
    jumpHostId: r.jumpHostId,
    kubernetesContext: r.kubernetesContext,
    kubernetesNamespace: r.kubernetesNamespace,
    kubernetesResource: r.kubernetesResource,
    kubernetesSshPort: r.kubernetesSshPort,
    kubernetesUsername: r.kubernetesUsername,
    kubernetesAuthType: _enumValue(
      HostAuthType.values,
      r.kubernetesAuthType,
      HostAuthType.password,
    ),
    kubernetesCredentialRef: r.kubernetesCredentialRef,
    remoteSessionPersistence: _enumValue(
      RemoteSessionPersistence.values,
      r.remoteSessionPersistence,
      RemoteSessionPersistence.none,
    ),
    agentForwarding: r.agentForwarding,
    x11Forwarding: r.x11Forwarding,
    startupScript: r.startupScript,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );

  HostsCompanion _toRow(Host h) => HostsCompanion.insert(
    id: h.id,
    alias: h.alias,
    hostname: h.hostname,
    port: Value(h.port),
    username: h.username,
    connectionType: Value(h.connectionType.index),
    authType: Value(h.authType.index),
    localShellType: Value(h.localShellType.index),
    workingDirectory: Value(h.workingDirectory),
    credentialRef: Value(h.credentialRef),
    jumpHostId: Value(h.jumpHostId),
    kubernetesContext: Value(h.kubernetesContext),
    kubernetesNamespace: Value(h.kubernetesNamespace),
    kubernetesResource: Value(h.kubernetesResource),
    kubernetesSshPort: Value(h.kubernetesSshPort),
    kubernetesUsername: Value(h.kubernetesUsername),
    kubernetesAuthType: Value(h.kubernetesAuthType.index),
    kubernetesCredentialRef: Value(h.kubernetesCredentialRef),
    remoteSessionPersistence: Value(h.remoteSessionPersistence.index),
    agentForwarding: Value(h.agentForwarding),
    x11Forwarding: Value(h.x11Forwarding),
    startupScript: Value(h.startupScript),
    createdAt: h.createdAt,
    updatedAt: h.updatedAt,
  );
}
