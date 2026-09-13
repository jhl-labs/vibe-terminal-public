import '../data/db/app_database.dart';
import '../data/models/host.dart';
import '../data/models/snippet.dart';
import '../data/repositories/host_repository.dart';
import '../data/repositories/snippet_repository.dart';
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
    final hosts = await HostRepository(_db).getAll();
    final snippets = await SnippetRepository(_db).getAll();
    final memos = await _db.select(_db.memos).get();

    final hostSecrets = <String, String>{};
    for (final host in hosts) {
      final ref = host.credentialRef;
      if (ref != null && ref.isNotEmpty) {
        final secret = await secureStore.readSecret(ref);
        if (secret != null) hostSecrets[ref] = secret;
      }
      final kubernetesRef = host.kubernetesCredentialRef;
      if (kubernetesRef != null && kubernetesRef.isNotEmpty) {
        final secret = await secureStore.readSecret(kubernetesRef);
        if (secret != null) hostSecrets[kubernetesRef] = secret;
      }
    }

    return {
      'format': 'vibe-terminal-sync',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'data': {
        'hosts': hosts.map(_hostToJson).toList(),
        'hostSecrets': hostSecrets,
        'snippets': snippets.map(_snippetToJson).toList(),
        'memos': [
          for (final memo in memos)
            {
              'hostId': memo.hostId,
              'body': memo.body,
              'updatedAt': memo.updatedAt.toUtc().toIso8601String(),
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
    'kubernetesContext': host.kubernetesContext,
    'kubernetesNamespace': host.kubernetesNamespace,
    'kubernetesResource': host.kubernetesResource,
    'kubernetesSshPort': host.kubernetesSshPort,
    'kubernetesUsername': host.kubernetesUsername,
    'kubernetesAuthType': host.kubernetesAuthType.name,
    'kubernetesCredentialRef': host.kubernetesCredentialRef,
    'remoteSessionPersistence': host.remoteSessionPersistence.name,
    'agentForwarding': host.agentForwarding,
    'x11Forwarding': host.x11Forwarding,
    'startupScript': host.startupScript,
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
