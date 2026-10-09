import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/models/host.dart';
import '../../data/models/snippet.dart';
import '../../data/models/ssh_key.dart';
import '../sync_section.dart';
import '../sync_snapshot.dart';

/// 이 기기의 로컬 셸 호스트 id. 기본 로컬 셸은 id(`local-default-*`)가 기기마다
/// 같으므로, 거기에 딸린 메모·스니펫도 기기별 데이터로 본다.
Future<Set<String>> _localShellHostIds(AppDatabase db) async {
  final rows =
      await (db.select(db.hosts)..where(
            (t) => t.connectionType.equals(HostConnectionType.localShell.index),
          ))
          .get();
  return {for (final row in rows) row.id};
}

/// 다른 기기의 삭제를 이기도록 Identity·키의 변경 시각을 바꾼다.
Future<void> _touch(
  AppDatabase db,
  String table,
  String id,
  DateTime deletedAt,
) => db.customStatement('UPDATE $table SET updated_at = ? WHERE id = ?', [
  syncKeepSeconds(deletedAt),
  id,
]);

class HostsSyncSection extends RowSyncSection<HostRow> {
  HostsSyncSection(super.db, super.secureStore);

  @override
  String get name => SyncSectionNames.hosts;

  @override
  TableInfo<Table, HostRow> get table => db.hosts;

  @override
  Future<List<HostRow>> loadRows() => db.select(db.hosts).get();

  /// 로컬 셸은 id(`local-default-*`)가 기기마다 겹치고 경로·사용자가 달라
  /// 기기별 데이터로 본다.
  @override
  bool includes(HostRow row) =>
      row.connectionType != HostConnectionType.localShell.index;

  @override
  String idOf(HostRow row) => row.id;

  @override
  DateTime updatedAtOf(HostRow row) => row.updatedAt;

  @override
  Map<String, Object?> encode(HostRow row) => {
    'alias': row.alias,
    'hostname': row.hostname,
    'port': row.port,
    'username': row.username,
    'connectionType': syncEnumName(
      HostConnectionType.values,
      row.connectionType,
    ),
    'authType': syncEnumName(HostAuthType.values, row.authType),
    'localShellType': syncEnumName(LocalShellType.values, row.localShellType),
    'workingDirectory': row.workingDirectory,
    'credentialRef': row.credentialRef,
    'jumpHostId': row.jumpHostId,
    'kubernetesGateway': syncEnumName(
      KubernetesGateway.values,
      row.kubernetesGateway,
    ),
    'kubernetesGatewayHostId': row.kubernetesGatewayHostId,
    'kubernetesContext': row.kubernetesContext,
    'kubernetesNamespace': row.kubernetesNamespace,
    'kubernetesResource': row.kubernetesResource,
    'kubernetesContainer': row.kubernetesContainer,
    'remoteSessionPersistence': syncEnumName(
      RemoteSessionPersistence.values,
      row.remoteSessionPersistence,
    ),
    'agentForwarding': row.agentForwarding,
    'x11Forwarding': row.x11Forwarding,
    'identityId': row.identityId,
    'startupScript': row.startupScript,
    'terminalPreferences': _decodePreferences(row.terminalPreferences),
    'createdAt': syncDate(row.createdAt),
  };

  @override
  Insertable<HostRow> decode(SyncRecord record, HostRow? existing) {
    final preferences = record.data['terminalPreferences'];
    return HostsCompanion.insert(
      id: record.id,
      alias: record.string('alias'),
      hostname: record.string('hostname'),
      port: Value(record.integer('port', 22)),
      username: record.string('username'),
      connectionType: Value(
        record.enumIndex('connectionType', HostConnectionType.values, 0),
      ),
      authType: Value(record.enumIndex('authType', HostAuthType.values, 0)),
      localShellType: Value(
        record.enumIndex('localShellType', LocalShellType.values, 0),
      ),
      workingDirectory: Value(record.optionalString('workingDirectory')),
      credentialRef: Value(record.optionalString('credentialRef')),
      jumpHostId: Value(record.optionalString('jumpHostId')),
      kubernetesGateway: Value(
        record.enumIndex('kubernetesGateway', KubernetesGateway.values, 0),
      ),
      kubernetesGatewayHostId: Value(
        record.optionalString('kubernetesGatewayHostId'),
      ),
      kubernetesContext: Value(record.optionalString('kubernetesContext')),
      kubernetesNamespace: Value(record.optionalString('kubernetesNamespace')),
      kubernetesResource: Value(record.optionalString('kubernetesResource')),
      kubernetesContainer: Value(record.optionalString('kubernetesContainer')),
      remoteSessionPersistence: Value(
        record.enumIndex(
          'remoteSessionPersistence',
          RemoteSessionPersistence.values,
          0,
        ),
      ),
      agentForwarding: Value(record.boolean('agentForwarding')),
      x11Forwarding: Value(record.boolean('x11Forwarding')),
      identityId: Value(record.optionalString('identityId')),
      startupScript: Value(record.optionalString('startupScript')),
      terminalPreferences: Value(
        preferences is Map ? jsonEncode(preferences) : null,
      ),
      createdAt: record.date('createdAt', record.updatedAt),
      updatedAt: record.updatedAt,
    );
  }

  static Object? _decodePreferences(String? value) {
    if (value == null) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
}

class SnippetsSyncSection extends RowSyncSection<SnippetRow> {
  SnippetsSyncSection(super.db, super.secureStore);

  @override
  String get name => SyncSectionNames.snippets;

  @override
  TableInfo<Table, SnippetRow> get table => db.snippets;

  Set<String> _localShells = const {};

  @override
  Future<List<SnippetRow>> loadRows() async {
    _localShells = await _localShellHostIds(db);
    return db.select(db.snippets).get();
  }

  @override
  bool includes(SnippetRow row) => !_localShells.contains(row.hostId);

  @override
  bool accepts(SyncRecord record) =>
      !_localShells.contains(record.optionalString('hostId'));

  @override
  String idOf(SnippetRow row) => row.id;

  @override
  DateTime updatedAtOf(SnippetRow row) => row.updatedAt;

  @override
  Map<String, Object?> encode(SnippetRow row) => {
    'name': row.name,
    'body': row.body,
    'scope': syncEnumName(SnippetScope.values, row.scope),
    'hostId': row.hostId,
    'defaultRunMode': syncEnumName(SnippetRunMode.values, row.defaultRunMode),
    'sortOrder': row.sortOrder,
    'createdAt': syncDate(row.createdAt),
  };

  @override
  Insertable<SnippetRow> decode(SyncRecord record, SnippetRow? existing) =>
      SnippetsCompanion.insert(
        id: record.id,
        name: record.string('name'),
        body: record.string('body'),
        scope: Value(record.enumIndex('scope', SnippetScope.values, 0)),
        hostId: Value(record.optionalString('hostId')),
        defaultRunMode: Value(
          record.enumIndex('defaultRunMode', SnippetRunMode.values, 0),
        ),
        sortOrder: Value(record.integer('sortOrder', 0)),
        createdAt: record.date('createdAt', record.updatedAt),
        updatedAt: record.updatedAt,
      );
}

/// 호스트 메모. 버전 기록은 기기의 편집 이력이라 동기화하지 않는다.
class MemosSyncSection extends RowSyncSection<MemoRow> {
  MemosSyncSection(super.db, super.secureStore);

  @override
  String get name => SyncSectionNames.memos;

  @override
  TableInfo<Table, MemoRow> get table => db.memos;

  Set<String> _localShells = const {};

  @override
  Future<List<MemoRow>> loadRows() async {
    _localShells = await _localShellHostIds(db);
    return db.select(db.memos).get();
  }

  @override
  bool includes(MemoRow row) => !_localShells.contains(row.hostId);

  @override
  bool accepts(SyncRecord record) => !_localShells.contains(record.id);

  @override
  String idOf(MemoRow row) => row.hostId;

  @override
  DateTime updatedAtOf(MemoRow row) => row.updatedAt;

  @override
  Map<String, Object?> encode(MemoRow row) => {'body': row.body};

  @override
  Insertable<MemoRow> decode(SyncRecord record, MemoRow? existing) =>
      MemosCompanion.insert(
        hostId: record.id,
        body: record.string('body'),
        updatedAt: record.updatedAt,
      );
}

class SshKeysSyncSection extends RowSyncSection<SshKeyRow> {
  SshKeysSyncSection(super.db, super.secureStore);

  @override
  String get name => SyncSectionNames.sshKeys;

  @override
  TableInfo<Table, SshKeyRow> get table => db.sshKeys;

  @override
  Future<List<SshKeyRow>> loadRows() => db.select(db.sshKeys).get();

  @override
  String idOf(SshKeyRow row) => row.id;

  @override
  DateTime updatedAtOf(SshKeyRow row) => row.updatedAt;

  @override
  String? secretRefOf(SshKeyRow row) => row.secretRef;

  @override
  Future<bool> isReferenced(String id) async => (await (db.select(
    db.identities,
  )..where((t) => t.keyId.equals(id))).get()).isNotEmpty;

  @override
  Future<void> keepReferenced(String id, {required DateTime after}) =>
      _touch(db, name, id, after);

  @override
  String? secretRefOfRecord(SyncRecord record) =>
      record.optionalString('secretRef');

  @override
  Map<String, Object?> encode(SshKeyRow row) => {
    'name': row.name,
    'keyType': row.keyType,
    'publicKey': row.publicKey,
    'fingerprint': row.fingerprint,
    'secretRef': row.secretRef,
    'source': syncEnumName(SshKeySource.values, row.source),
    'createdAt': syncDate(row.createdAt),
  };

  @override
  Insertable<SshKeyRow> decode(SyncRecord record, SshKeyRow? existing) =>
      SshKeysCompanion.insert(
        id: record.id,
        name: record.string('name'),
        keyType: record.string('keyType'),
        publicKey: record.string('publicKey'),
        fingerprint: record.string('fingerprint'),
        secretRef: record.string('secretRef', 'sshkey-${record.id}'),
        source: Value(
          record.enumIndex(
            'source',
            SshKeySource.values,
            SshKeySource.imported.index,
          ),
        ),
        createdAt: record.date('createdAt', record.updatedAt),
        updatedAt: record.updatedAt,
      );
}

class IdentitiesSyncSection extends RowSyncSection<IdentityRow> {
  IdentitiesSyncSection(super.db, super.secureStore);

  @override
  String get name => SyncSectionNames.identities;

  @override
  TableInfo<Table, IdentityRow> get table => db.identities;

  @override
  Future<List<IdentityRow>> loadRows() => db.select(db.identities).get();

  @override
  String idOf(IdentityRow row) => row.id;

  @override
  DateTime updatedAtOf(IdentityRow row) => row.updatedAt;

  @override
  String? secretRefOf(IdentityRow row) => row.secretRef;

  @override
  Future<bool> isReferenced(String id) async => (await (db.select(
    db.hosts,
  )..where((t) => t.identityId.equals(id))).get()).isNotEmpty;

  @override
  Future<void> keepReferenced(String id, {required DateTime after}) =>
      _touch(db, name, id, after);

  @override
  String? secretRefOfRecord(SyncRecord record) =>
      record.optionalString('secretRef');

  @override
  Map<String, Object?> encode(IdentityRow row) => {
    'label': row.label,
    'username': row.username,
    'authType': syncEnumName(HostAuthType.values, row.authType),
    'keyId': row.keyId,
    'secretRef': row.secretRef,
    'hostScoped': row.hostScoped,
    'createdAt': syncDate(row.createdAt),
  };

  @override
  Insertable<IdentityRow> decode(SyncRecord record, IdentityRow? existing) =>
      IdentitiesCompanion.insert(
        id: record.id,
        label: record.string('label'),
        username: record.string('username'),
        authType: Value(record.enumIndex('authType', HostAuthType.values, 0)),
        keyId: Value(record.optionalString('keyId')),
        secretRef: Value(record.optionalString('secretRef')),
        hostScoped: Value(record.boolean('hostScoped')),
        createdAt: record.date('createdAt', record.updatedAt),
        updatedAt: record.updatedAt,
      );
}

/// 고정한 호스트 키. 고정 시각을 변경 시각으로 쓰고, 마지막 접속 시각은
/// 기기마다 다르므로 넣지 않는다.
class HostKeysSyncSection extends RowSyncSection<HostKeyRow> {
  HostKeysSyncSection(super.db, super.secureStore);

  @override
  String get name => SyncSectionNames.hostKeys;

  @override
  TableInfo<Table, HostKeyRow> get table => db.hostKeys;

  @override
  Future<List<HostKeyRow>> loadRows() => db.select(db.hostKeys).get();

  @override
  String idOf(HostKeyRow row) => row.id;

  @override
  DateTime updatedAtOf(HostKeyRow row) => row.pinnedAt;

  @override
  Map<String, Object?> encode(HostKeyRow row) => {
    'hostname': row.hostname,
    'port': row.port,
    'keyType': row.keyType,
    'fingerprint': row.fingerprint,
  };

  @override
  Insertable<HostKeyRow> decode(SyncRecord record, HostKeyRow? existing) =>
      HostKeysCompanion.insert(
        id: record.id,
        hostname: record.string('hostname'),
        port: record.integer('port', 22),
        keyType: record.string('keyType'),
        fingerprint: record.string('fingerprint'),
        pinnedAt: record.updatedAt,
        lastSeenAt: Value(existing?.lastSeenAt),
      );
}
