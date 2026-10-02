import 'dart:convert';

import 'package:drift/drift.dart';
import '../../settings/terminal_preferences.dart';

import '../../security/secure_store.dart';
import '../../ssh/ssh_credentials.dart';
import '../db/app_database.dart';
import '../models/host.dart';
import '../models/identity.dart';
import '../models/ssh_key.dart';
import 'identity_repository.dart';
import 'ssh_key_repository.dart';

class HostRepository {
  HostRepository(this._db, {SecureStore? secureStore})
    : _secureStore = secureStore,
      _identities = IdentityRepository(
        _db,
        secureStore ?? InMemorySecureStore(),
      ),
      _keys = SshKeyRepository(_db, secureStore ?? InMemorySecureStore());

  final AppDatabase _db;
  final SecureStore? _secureStore;
  final IdentityRepository _identities;
  final SshKeyRepository _keys;

  Future<List<Host>> getAll() async {
    final rows = await _db.select(_db.hosts).get();
    final hosts = <Host>[];
    for (final row in rows) {
      hosts.add(await _withIdentity(_toModel(row)));
    }
    return hosts;
  }

  Future<Host?> getById(String id) async {
    final row = await (_db.select(
      _db.hosts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _withIdentity(_toModel(row));
  }

  /// 저장 전에 인증 원본을 Identity로 맞춘다. identityId가 없는 SSH 호스트는
  /// 호스트 전용 Identity(`host-<id>`)를 만들어 연결한다.
  Future<void> upsert(Host host) async {
    var next = host;
    if (!host.isLocalShell && host.identityId == null) {
      final identity = await _ensureHostScopedIdentity(host);
      next = host.copyWith(identityId: identity.id);
    }
    await _db.into(_db.hosts).insertOnConflictUpdate(_toRow(next));
  }

  Future<bool> setTerminalPreferences(
    String id,
    TerminalPreferences value,
  ) async {
    final count = await (_db.update(_db.hosts)..where((t) => t.id.equals(id)))
        .write(
          HostsCompanion(
            terminalPreferences: Value(jsonEncode(value.toJson())),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return count > 0;
  }

  Future<void> delete(String id) async {
    final host = await getById(id);
    await (_db.delete(_db.hosts)..where((t) => t.id.equals(id))).go();
    // 호스트 전용 Identity는 호스트와 운명을 같이한다. 비밀은 남겨 두지 않는다.
    final identityId = host?.identityId;
    if (identityId != null && identityId == 'host-$id') {
      try {
        await _identities.delete(identityId);
      } on IdentityInUseException {
        // 다른 호스트가 복제 등으로 같은 Identity를 참조하면 남겨 둔다.
      }
    }
  }

  /// identity_id가 비어 있는 SSH 호스트를 Identity 체계로 옮긴다. 앱 시작 시
  /// 한 번 호출한다. 처리한 호스트 수를 돌려준다.
  Future<int> migrateLegacyIdentities() async {
    final rows = await (_db.select(
      _db.hosts,
    )..where((t) => t.identityId.isNull())).get();
    var migrated = 0;
    for (final row in rows) {
      final host = _toModel(row);
      if (host.isLocalShell) continue;
      await upsert(host);
      migrated++;
    }
    return migrated;
  }

  Future<Identity> _ensureHostScopedIdentity(Host host) async {
    final id = 'host-${host.id}';
    final existing = await _identities.getById(id);
    final now = DateTime.now();
    String? keyId;
    String? secretRef = host.credentialRef;
    if (host.authType == HostAuthType.publicKey && host.credentialRef != null) {
      final key =
          await _keys.findBySecretRef(host.credentialRef!) ??
          await _importLegacyKey(host);
      keyId = key?.id;
      if (key != null) secretRef = null;
    }
    return _identities.upsert(
      Identity(
        id: id,
        label: host.alias,
        username: host.username,
        authType: host.authType,
        keyId: keyId,
        secretRef: secretRef,
        hostScoped: true,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  /// 기존 호스트가 직접 들고 있던 개인키를 키체인 항목으로 분리한다.
  /// secure store가 없거나 파싱에 실패하면 null — 호스트는 credentialRef로 계속 동작한다.
  Future<SshKey?> _importLegacyKey(Host host) async {
    final store = _secureStore;
    final ref = host.credentialRef;
    if (store == null || ref == null) return null;
    try {
      final secret = await store.readSecret(ref);
      if (secret == null || secret.isEmpty) return null;
      final credential = SshCredentialPayload.publicKeyFromSecret(secret);
      return await _keys.create(
        name: host.alias,
        privateKeyPem: credential.privateKeyPem,
        passphrase: credential.passphrase,
        secretRef: ref,
      );
    } on DuplicateSshKeyException catch (e) {
      return e.existing;
    } catch (_) {
      return null;
    }
  }

  Future<Host> _withIdentity(Host host) async {
    final identityId = host.identityId;
    if (identityId == null) return host;
    final identity = await _identities.getById(identityId);
    if (identity == null) return host;
    String? credentialRef = identity.secretRef;
    if (identity.keyId != null) {
      final key = await _keys.getById(identity.keyId!);
      if (key != null) credentialRef = key.secretRef;
    }
    return host.copyWith(
      username: identity.username,
      authType: identity.authType,
      credentialRef: credentialRef,
    );
  }

  T _enumValue<T>(List<T> values, int index, T fallback) {
    if (index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  TerminalPreferences _terminalPreferencesFromJson(String? value) {
    if (value == null) return const TerminalPreferences();
    try {
      return TerminalPreferences.fromJson(jsonDecode(value));
    } on FormatException {
      return const TerminalPreferences();
    }
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
    identityId: r.identityId,
    jumpHostId: r.jumpHostId,
    kubernetesGateway: _enumValue(
      KubernetesGateway.values,
      r.kubernetesGateway,
      KubernetesGateway.local,
    ),
    kubernetesGatewayHostId: r.kubernetesGatewayHostId,
    kubernetesContext: r.kubernetesContext,
    kubernetesNamespace: r.kubernetesNamespace,
    kubernetesResource: r.kubernetesResource,
    kubernetesContainer: r.kubernetesContainer,
    remoteSessionPersistence: _enumValue(
      RemoteSessionPersistence.values,
      r.remoteSessionPersistence,
      RemoteSessionPersistence.none,
    ),
    agentForwarding: r.agentForwarding,
    x11Forwarding: r.x11Forwarding,
    startupScript: r.startupScript,
    terminalPreferences: _terminalPreferencesFromJson(r.terminalPreferences),
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
    identityId: Value(h.identityId),
    jumpHostId: Value(h.jumpHostId),
    kubernetesGateway: Value(h.kubernetesGateway.index),
    kubernetesGatewayHostId: Value(h.kubernetesGatewayHostId),
    kubernetesContext: Value(h.kubernetesContext),
    kubernetesNamespace: Value(h.kubernetesNamespace),
    kubernetesResource: Value(h.kubernetesResource),
    kubernetesContainer: Value(h.kubernetesContainer),
    remoteSessionPersistence: Value(h.remoteSessionPersistence.index),
    agentForwarding: Value(h.agentForwarding),
    x11Forwarding: Value(h.x11Forwarding),
    startupScript: Value(h.startupScript),
    terminalPreferences: Value(jsonEncode(h.terminalPreferences.toJson())),
    createdAt: h.createdAt,
    updatedAt: h.updatedAt,
  );
}
