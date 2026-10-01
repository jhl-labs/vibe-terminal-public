import '../data/db/app_database.dart';
import '../data/models/host.dart';
import '../data/models/snippet.dart';
import '../data/repositories/host_repository.dart';
import '../data/repositories/identity_repository.dart';
import '../data/repositories/snippet_repository.dart';
import '../data/repositories/ssh_key_repository.dart';
import '../security/host_key_store.dart';
import '../security/secure_store.dart';
import '../settings/app_settings.dart';
import 'sync_crypto.dart';

class CloudSyncSnapshotService {
  CloudSyncSnapshotService({
    required AppDatabase database,
    required this.secureStore,
    SyncCryptoService? crypto,
  }) : _db = database,
       _crypto = crypto ?? SyncCryptoService();

  final AppDatabase _db;
  final SecureStore secureStore;
  final SyncCryptoService _crypto;

  Future<Map<String, Object?>> buildPlainSnapshot(AppSettings settings) async {
    final hosts = await HostRepository(_db, secureStore: secureStore).getAll();
    final snippets = await SnippetRepository(_db).getAll();
    final memos = await _db.select(_db.memos).get();

    final keyRepository = SshKeyRepository(_db, secureStore);
    final identityRepository = IdentityRepository(_db, secureStore);
    final sshKeys = await keyRepository.getAll();
    final identities = await identityRepository.getAll(includeHostScoped: true);
    final hostKeys = await HostKeyStore(_db).listAll();

    final keySecrets = <String, String>{};
    for (final key in sshKeys) {
      final secret = await secureStore.readSecret(key.secretRef);
      if (secret != null) keySecrets[key.secretRef] = secret;
    }
    final identitySecrets = <String, String>{};
    for (final identity in identities) {
      final ref = identity.secretRef;
      if (ref == null) continue;
      final secret = await secureStore.readSecret(ref);
      if (secret != null) identitySecrets[ref] = secret;
    }

    return {
      'format': 'vibe-terminal-sync',
      'version': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'data': {
        'hosts': hosts.map(_hostToJson).toList(),
        'snippets': snippets.map(_snippetToJson).toList(),
        'memos': [
          for (final memo in memos)
            {
              'hostId': memo.hostId,
              'body': memo.body,
              'updatedAt': memo.updatedAt.toUtc().toIso8601String(),
            },
        ],
        'sshKeys': [
          for (final k in sshKeys)
            {
              'id': k.id,
              'name': k.name,
              'keyType': k.keyType,
              'publicKey': k.publicKey,
              'fingerprint': k.fingerprint,
              'secretRef': k.secretRef,
              'source': k.source.name,
              'createdAt': k.createdAt.toUtc().toIso8601String(),
              'updatedAt': k.updatedAt.toUtc().toIso8601String(),
            },
        ],
        'keySecrets': keySecrets,
        'identities': [
          for (final i in identities)
            {
              'id': i.id,
              'label': i.label,
              'username': i.username,
              'authType': i.authType.name,
              'keyId': i.keyId,
              'secretRef': i.secretRef,
              'hostScoped': i.hostScoped,
              'createdAt': i.createdAt.toUtc().toIso8601String(),
              'updatedAt': i.updatedAt.toUtc().toIso8601String(),
            },
        ],
        'identitySecrets': identitySecrets,
        'hostKeys': [
          for (final k in hostKeys)
            {
              'hostname': k.hostname,
              'port': k.port,
              'keyType': k.keyType,
              'fingerprint': k.fingerprint,
              'pinnedAt': k.pinnedAt.toUtc().toIso8601String(),
              'lastSeenAt': k.lastSeenAt?.toUtc().toIso8601String(),
            },
        ],
      },
    };
  }

  Future<EncryptedSyncBlob> buildEncryptedSnapshot(
    AppSettings settings,
    String encryptionKey,
  ) async {
    final plain = await buildPlainSnapshot(settings);
    return _crypto.encryptJson(plain, encryptionKey);
  }

  Map<String, Object?> _hostToJson(Host host) => {
    'id': host.id,
    'alias': host.alias,
    'hostname': host.hostname,
    'port': host.port,
    'username': host.username,
    'connectionType': host.connectionType.name,
    'authType': host.authType.name,
    'localShellType': host.localShellType.name,
    'workingDirectory': host.workingDirectory,
    'credentialRef': host.credentialRef,
    'jumpHostId': host.jumpHostId,
    'kubernetesGateway': host.kubernetesGateway.name,
    'kubernetesGatewayHostId': host.kubernetesGatewayHostId,
    'kubernetesContext': host.kubernetesContext,
    'kubernetesNamespace': host.kubernetesNamespace,
    'kubernetesResource': host.kubernetesResource,
    'kubernetesContainer': host.kubernetesContainer,
    'remoteSessionPersistence': host.remoteSessionPersistence.name,
    'agentForwarding': host.agentForwarding,
    'x11Forwarding': host.x11Forwarding,
    'identityId': host.identityId,
    'startupScript': host.startupScript,
    'terminalPreferences': host.terminalPreferences.toJson(),
    'createdAt': host.createdAt.toUtc().toIso8601String(),
    'updatedAt': host.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> _snippetToJson(Snippet snippet) => {
    'id': snippet.id,
    'name': snippet.name,
    'body': snippet.body,
    'scope': snippet.scope.name,
    'hostId': snippet.hostId,
    'defaultRunMode': snippet.defaultRunMode.name,
    'sortOrder': snippet.sortOrder,
    'createdAt': snippet.createdAt.toUtc().toIso8601String(),
    'updatedAt': snippet.updatedAt.toUtc().toIso8601String(),
  };
}
