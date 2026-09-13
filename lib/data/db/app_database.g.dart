// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $HostsTable extends Hosts with TableInfo<$HostsTable, HostRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostnameMeta = const VerificationMeta(
    'hostname',
  );
  @override
  late final GeneratedColumn<String> hostname = GeneratedColumn<String>(
    'hostname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(22),
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _connectionTypeMeta = const VerificationMeta(
    'connectionType',
  );
  @override
  late final GeneratedColumn<int> connectionType = GeneratedColumn<int>(
    'connection_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _authTypeMeta = const VerificationMeta(
    'authType',
  );
  @override
  late final GeneratedColumn<int> authType = GeneratedColumn<int>(
    'auth_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _localShellTypeMeta = const VerificationMeta(
    'localShellType',
  );
  @override
  late final GeneratedColumn<int> localShellType = GeneratedColumn<int>(
    'local_shell_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _workingDirectoryMeta = const VerificationMeta(
    'workingDirectory',
  );
  @override
  late final GeneratedColumn<String> workingDirectory = GeneratedColumn<String>(
    'working_directory',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _credentialRefMeta = const VerificationMeta(
    'credentialRef',
  );
  @override
  late final GeneratedColumn<String> credentialRef = GeneratedColumn<String>(
    'credential_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jumpHostIdMeta = const VerificationMeta(
    'jumpHostId',
  );
  @override
  late final GeneratedColumn<String> jumpHostId = GeneratedColumn<String>(
    'jump_host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kubernetesContextMeta = const VerificationMeta(
    'kubernetesContext',
  );
  @override
  late final GeneratedColumn<String> kubernetesContext =
      GeneratedColumn<String>(
        'kubernetes_context',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _kubernetesNamespaceMeta =
      const VerificationMeta('kubernetesNamespace');
  @override
  late final GeneratedColumn<String> kubernetesNamespace =
      GeneratedColumn<String>(
        'kubernetes_namespace',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _kubernetesResourceMeta =
      const VerificationMeta('kubernetesResource');
  @override
  late final GeneratedColumn<String> kubernetesResource =
      GeneratedColumn<String>(
        'kubernetes_resource',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _kubernetesSshPortMeta = const VerificationMeta(
    'kubernetesSshPort',
  );
  @override
  late final GeneratedColumn<int> kubernetesSshPort = GeneratedColumn<int>(
    'kubernetes_ssh_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(22),
  );
  static const VerificationMeta _kubernetesUsernameMeta =
      const VerificationMeta('kubernetesUsername');
  @override
  late final GeneratedColumn<String> kubernetesUsername =
      GeneratedColumn<String>(
        'kubernetes_username',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _kubernetesAuthTypeMeta =
      const VerificationMeta('kubernetesAuthType');
  @override
  late final GeneratedColumn<int> kubernetesAuthType = GeneratedColumn<int>(
    'kubernetes_auth_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _kubernetesCredentialRefMeta =
      const VerificationMeta('kubernetesCredentialRef');
  @override
  late final GeneratedColumn<String> kubernetesCredentialRef =
      GeneratedColumn<String>(
        'kubernetes_credential_ref',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remoteSessionPersistenceMeta =
      const VerificationMeta('remoteSessionPersistence');
  @override
  late final GeneratedColumn<int> remoteSessionPersistence =
      GeneratedColumn<int>(
        'remote_session_persistence',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _agentForwardingMeta = const VerificationMeta(
    'agentForwarding',
  );
  @override
  late final GeneratedColumn<bool> agentForwarding = GeneratedColumn<bool>(
    'agent_forwarding',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("agent_forwarding" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _x11ForwardingMeta = const VerificationMeta(
    'x11Forwarding',
  );
  @override
  late final GeneratedColumn<bool> x11Forwarding = GeneratedColumn<bool>(
    'x11_forwarding',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("x11_forwarding" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _startupScriptMeta = const VerificationMeta(
    'startupScript',
  );
  @override
  late final GeneratedColumn<String> startupScript = GeneratedColumn<String>(
    'startup_script',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    alias,
    hostname,
    port,
    username,
    connectionType,
    authType,
    localShellType,
    workingDirectory,
    credentialRef,
    jumpHostId,
    kubernetesContext,
    kubernetesNamespace,
    kubernetesResource,
    kubernetesSshPort,
    kubernetesUsername,
    kubernetesAuthType,
    kubernetesCredentialRef,
    remoteSessionPersistence,
    agentForwarding,
    x11Forwarding,
    startupScript,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hosts';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('hostname')) {
      context.handle(
        _hostnameMeta,
        hostname.isAcceptableOrUnknown(data['hostname']!, _hostnameMeta),
      );
    } else if (isInserting) {
      context.missing(_hostnameMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('connection_type')) {
      context.handle(
        _connectionTypeMeta,
        connectionType.isAcceptableOrUnknown(
          data['connection_type']!,
          _connectionTypeMeta,
        ),
      );
    }
    if (data.containsKey('auth_type')) {
      context.handle(
        _authTypeMeta,
        authType.isAcceptableOrUnknown(data['auth_type']!, _authTypeMeta),
      );
    }
    if (data.containsKey('local_shell_type')) {
      context.handle(
        _localShellTypeMeta,
        localShellType.isAcceptableOrUnknown(
          data['local_shell_type']!,
          _localShellTypeMeta,
        ),
      );
    }
    if (data.containsKey('working_directory')) {
      context.handle(
        _workingDirectoryMeta,
        workingDirectory.isAcceptableOrUnknown(
          data['working_directory']!,
          _workingDirectoryMeta,
        ),
      );
    }
    if (data.containsKey('credential_ref')) {
      context.handle(
        _credentialRefMeta,
        credentialRef.isAcceptableOrUnknown(
          data['credential_ref']!,
          _credentialRefMeta,
        ),
      );
    }
    if (data.containsKey('jump_host_id')) {
      context.handle(
        _jumpHostIdMeta,
        jumpHostId.isAcceptableOrUnknown(
          data['jump_host_id']!,
          _jumpHostIdMeta,
        ),
      );
    }
    if (data.containsKey('kubernetes_context')) {
      context.handle(
        _kubernetesContextMeta,
        kubernetesContext.isAcceptableOrUnknown(
          data['kubernetes_context']!,
          _kubernetesContextMeta,
        ),
      );
    }
    if (data.containsKey('kubernetes_namespace')) {
      context.handle(
        _kubernetesNamespaceMeta,
        kubernetesNamespace.isAcceptableOrUnknown(
          data['kubernetes_namespace']!,
          _kubernetesNamespaceMeta,
        ),
      );
    }
    if (data.containsKey('kubernetes_resource')) {
      context.handle(
        _kubernetesResourceMeta,
        kubernetesResource.isAcceptableOrUnknown(
          data['kubernetes_resource']!,
          _kubernetesResourceMeta,
        ),
      );
    }
    if (data.containsKey('kubernetes_ssh_port')) {
      context.handle(
        _kubernetesSshPortMeta,
        kubernetesSshPort.isAcceptableOrUnknown(
          data['kubernetes_ssh_port']!,
          _kubernetesSshPortMeta,
        ),
      );
    }
    if (data.containsKey('kubernetes_username')) {
      context.handle(
        _kubernetesUsernameMeta,
        kubernetesUsername.isAcceptableOrUnknown(
          data['kubernetes_username']!,
          _kubernetesUsernameMeta,
        ),
      );
    }
    if (data.containsKey('kubernetes_auth_type')) {
      context.handle(
        _kubernetesAuthTypeMeta,
        kubernetesAuthType.isAcceptableOrUnknown(
          data['kubernetes_auth_type']!,
          _kubernetesAuthTypeMeta,
        ),
      );
    }
    if (data.containsKey('kubernetes_credential_ref')) {
      context.handle(
        _kubernetesCredentialRefMeta,
        kubernetesCredentialRef.isAcceptableOrUnknown(
          data['kubernetes_credential_ref']!,
          _kubernetesCredentialRefMeta,
        ),
      );
    }
    if (data.containsKey('remote_session_persistence')) {
      context.handle(
        _remoteSessionPersistenceMeta,
        remoteSessionPersistence.isAcceptableOrUnknown(
          data['remote_session_persistence']!,
          _remoteSessionPersistenceMeta,
        ),
      );
    }
    if (data.containsKey('agent_forwarding')) {
      context.handle(
        _agentForwardingMeta,
        agentForwarding.isAcceptableOrUnknown(
          data['agent_forwarding']!,
          _agentForwardingMeta,
        ),
      );
    }
    if (data.containsKey('x11_forwarding')) {
      context.handle(
        _x11ForwardingMeta,
        x11Forwarding.isAcceptableOrUnknown(
          data['x11_forwarding']!,
          _x11ForwardingMeta,
        ),
      );
    }
    if (data.containsKey('startup_script')) {
      context.handle(
        _startupScriptMeta,
        startupScript.isAcceptableOrUnknown(
          data['startup_script']!,
          _startupScriptMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HostRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      hostname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hostname'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      connectionType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}connection_type'],
      )!,
      authType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}auth_type'],
      )!,
      localShellType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_shell_type'],
      )!,
      workingDirectory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}working_directory'],
      ),
      credentialRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_ref'],
      ),
      jumpHostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jump_host_id'],
      ),
      kubernetesContext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kubernetes_context'],
      ),
      kubernetesNamespace: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kubernetes_namespace'],
      ),
      kubernetesResource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kubernetes_resource'],
      ),
      kubernetesSshPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kubernetes_ssh_port'],
      )!,
      kubernetesUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kubernetes_username'],
      ),
      kubernetesAuthType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kubernetes_auth_type'],
      )!,
      kubernetesCredentialRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kubernetes_credential_ref'],
      ),
      remoteSessionPersistence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_session_persistence'],
      )!,
      agentForwarding: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}agent_forwarding'],
      )!,
      x11Forwarding: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}x11_forwarding'],
      )!,
      startupScript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}startup_script'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $HostsTable createAlias(String alias) {
    return $HostsTable(attachedDatabase, alias);
  }
}

class HostRow extends DataClass implements Insertable<HostRow> {
  final String id;
  final String alias;
  final String hostname;
  final int port;
  final String username;
  final int connectionType;
  final int authType;
  final int localShellType;
  final String? workingDirectory;
  final String? credentialRef;
  final String? jumpHostId;
  final String? kubernetesContext;
  final String? kubernetesNamespace;
  final String? kubernetesResource;
  final int kubernetesSshPort;
  final String? kubernetesUsername;
  final int kubernetesAuthType;
  final String? kubernetesCredentialRef;
  final int remoteSessionPersistence;
  final bool agentForwarding;
  final bool x11Forwarding;
  final String? startupScript;
  final DateTime createdAt;
  final DateTime updatedAt;
  const HostRow({
    required this.id,
    required this.alias,
    required this.hostname,
    required this.port,
    required this.username,
    required this.connectionType,
    required this.authType,
    required this.localShellType,
    this.workingDirectory,
    this.credentialRef,
    this.jumpHostId,
    this.kubernetesContext,
    this.kubernetesNamespace,
    this.kubernetesResource,
    required this.kubernetesSshPort,
    this.kubernetesUsername,
    required this.kubernetesAuthType,
    this.kubernetesCredentialRef,
    required this.remoteSessionPersistence,
    required this.agentForwarding,
    required this.x11Forwarding,
    this.startupScript,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['alias'] = Variable<String>(alias);
    map['hostname'] = Variable<String>(hostname);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    map['connection_type'] = Variable<int>(connectionType);
    map['auth_type'] = Variable<int>(authType);
    map['local_shell_type'] = Variable<int>(localShellType);
    if (!nullToAbsent || workingDirectory != null) {
      map['working_directory'] = Variable<String>(workingDirectory);
    }
    if (!nullToAbsent || credentialRef != null) {
      map['credential_ref'] = Variable<String>(credentialRef);
    }
    if (!nullToAbsent || jumpHostId != null) {
      map['jump_host_id'] = Variable<String>(jumpHostId);
    }
    if (!nullToAbsent || kubernetesContext != null) {
      map['kubernetes_context'] = Variable<String>(kubernetesContext);
    }
    if (!nullToAbsent || kubernetesNamespace != null) {
      map['kubernetes_namespace'] = Variable<String>(kubernetesNamespace);
    }
    if (!nullToAbsent || kubernetesResource != null) {
      map['kubernetes_resource'] = Variable<String>(kubernetesResource);
    }
    map['kubernetes_ssh_port'] = Variable<int>(kubernetesSshPort);
    if (!nullToAbsent || kubernetesUsername != null) {
      map['kubernetes_username'] = Variable<String>(kubernetesUsername);
    }
    map['kubernetes_auth_type'] = Variable<int>(kubernetesAuthType);
    if (!nullToAbsent || kubernetesCredentialRef != null) {
      map['kubernetes_credential_ref'] = Variable<String>(
        kubernetesCredentialRef,
      );
    }
    map['remote_session_persistence'] = Variable<int>(remoteSessionPersistence);
    map['agent_forwarding'] = Variable<bool>(agentForwarding);
    map['x11_forwarding'] = Variable<bool>(x11Forwarding);
    if (!nullToAbsent || startupScript != null) {
      map['startup_script'] = Variable<String>(startupScript);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  HostsCompanion toCompanion(bool nullToAbsent) {
    return HostsCompanion(
      id: Value(id),
      alias: Value(alias),
      hostname: Value(hostname),
      port: Value(port),
      username: Value(username),
      connectionType: Value(connectionType),
      authType: Value(authType),
      localShellType: Value(localShellType),
      workingDirectory: workingDirectory == null && nullToAbsent
          ? const Value.absent()
          : Value(workingDirectory),
      credentialRef: credentialRef == null && nullToAbsent
          ? const Value.absent()
          : Value(credentialRef),
      jumpHostId: jumpHostId == null && nullToAbsent
          ? const Value.absent()
          : Value(jumpHostId),
      kubernetesContext: kubernetesContext == null && nullToAbsent
          ? const Value.absent()
          : Value(kubernetesContext),
      kubernetesNamespace: kubernetesNamespace == null && nullToAbsent
          ? const Value.absent()
          : Value(kubernetesNamespace),
      kubernetesResource: kubernetesResource == null && nullToAbsent
          ? const Value.absent()
          : Value(kubernetesResource),
      kubernetesSshPort: Value(kubernetesSshPort),
      kubernetesUsername: kubernetesUsername == null && nullToAbsent
          ? const Value.absent()
          : Value(kubernetesUsername),
      kubernetesAuthType: Value(kubernetesAuthType),
      kubernetesCredentialRef: kubernetesCredentialRef == null && nullToAbsent
          ? const Value.absent()
          : Value(kubernetesCredentialRef),
      remoteSessionPersistence: Value(remoteSessionPersistence),
      agentForwarding: Value(agentForwarding),
      x11Forwarding: Value(x11Forwarding),
      startupScript: startupScript == null && nullToAbsent
          ? const Value.absent()
          : Value(startupScript),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory HostRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostRow(
      id: serializer.fromJson<String>(json['id']),
      alias: serializer.fromJson<String>(json['alias']),
      hostname: serializer.fromJson<String>(json['hostname']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      connectionType: serializer.fromJson<int>(json['connectionType']),
      authType: serializer.fromJson<int>(json['authType']),
      localShellType: serializer.fromJson<int>(json['localShellType']),
      workingDirectory: serializer.fromJson<String?>(json['workingDirectory']),
      credentialRef: serializer.fromJson<String?>(json['credentialRef']),
      jumpHostId: serializer.fromJson<String?>(json['jumpHostId']),
      kubernetesContext: serializer.fromJson<String?>(
        json['kubernetesContext'],
      ),
      kubernetesNamespace: serializer.fromJson<String?>(
        json['kubernetesNamespace'],
      ),
      kubernetesResource: serializer.fromJson<String?>(
        json['kubernetesResource'],
      ),
      kubernetesSshPort: serializer.fromJson<int>(json['kubernetesSshPort']),
      kubernetesUsername: serializer.fromJson<String?>(
        json['kubernetesUsername'],
      ),
      kubernetesAuthType: serializer.fromJson<int>(json['kubernetesAuthType']),
      kubernetesCredentialRef: serializer.fromJson<String?>(
        json['kubernetesCredentialRef'],
      ),
      remoteSessionPersistence: serializer.fromJson<int>(
        json['remoteSessionPersistence'],
      ),
      agentForwarding: serializer.fromJson<bool>(json['agentForwarding']),
      x11Forwarding: serializer.fromJson<bool>(json['x11Forwarding']),
      startupScript: serializer.fromJson<String?>(json['startupScript']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'alias': serializer.toJson<String>(alias),
      'hostname': serializer.toJson<String>(hostname),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'connectionType': serializer.toJson<int>(connectionType),
      'authType': serializer.toJson<int>(authType),
      'localShellType': serializer.toJson<int>(localShellType),
      'workingDirectory': serializer.toJson<String?>(workingDirectory),
      'credentialRef': serializer.toJson<String?>(credentialRef),
      'jumpHostId': serializer.toJson<String?>(jumpHostId),
      'kubernetesContext': serializer.toJson<String?>(kubernetesContext),
      'kubernetesNamespace': serializer.toJson<String?>(kubernetesNamespace),
      'kubernetesResource': serializer.toJson<String?>(kubernetesResource),
      'kubernetesSshPort': serializer.toJson<int>(kubernetesSshPort),
      'kubernetesUsername': serializer.toJson<String?>(kubernetesUsername),
      'kubernetesAuthType': serializer.toJson<int>(kubernetesAuthType),
      'kubernetesCredentialRef': serializer.toJson<String?>(
        kubernetesCredentialRef,
      ),
      'remoteSessionPersistence': serializer.toJson<int>(
        remoteSessionPersistence,
      ),
      'agentForwarding': serializer.toJson<bool>(agentForwarding),
      'x11Forwarding': serializer.toJson<bool>(x11Forwarding),
      'startupScript': serializer.toJson<String?>(startupScript),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  HostRow copyWith({
    String? id,
    String? alias,
    String? hostname,
    int? port,
    String? username,
    int? connectionType,
    int? authType,
    int? localShellType,
    Value<String?> workingDirectory = const Value.absent(),
    Value<String?> credentialRef = const Value.absent(),
    Value<String?> jumpHostId = const Value.absent(),
    Value<String?> kubernetesContext = const Value.absent(),
    Value<String?> kubernetesNamespace = const Value.absent(),
    Value<String?> kubernetesResource = const Value.absent(),
    int? kubernetesSshPort,
    Value<String?> kubernetesUsername = const Value.absent(),
    int? kubernetesAuthType,
    Value<String?> kubernetesCredentialRef = const Value.absent(),
    int? remoteSessionPersistence,
    bool? agentForwarding,
    bool? x11Forwarding,
    Value<String?> startupScript = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => HostRow(
    id: id ?? this.id,
    alias: alias ?? this.alias,
    hostname: hostname ?? this.hostname,
    port: port ?? this.port,
    username: username ?? this.username,
    connectionType: connectionType ?? this.connectionType,
    authType: authType ?? this.authType,
    localShellType: localShellType ?? this.localShellType,
    workingDirectory: workingDirectory.present
        ? workingDirectory.value
        : this.workingDirectory,
    credentialRef: credentialRef.present
        ? credentialRef.value
        : this.credentialRef,
    jumpHostId: jumpHostId.present ? jumpHostId.value : this.jumpHostId,
    kubernetesContext: kubernetesContext.present
        ? kubernetesContext.value
        : this.kubernetesContext,
    kubernetesNamespace: kubernetesNamespace.present
        ? kubernetesNamespace.value
        : this.kubernetesNamespace,
    kubernetesResource: kubernetesResource.present
        ? kubernetesResource.value
        : this.kubernetesResource,
    kubernetesSshPort: kubernetesSshPort ?? this.kubernetesSshPort,
    kubernetesUsername: kubernetesUsername.present
        ? kubernetesUsername.value
        : this.kubernetesUsername,
    kubernetesAuthType: kubernetesAuthType ?? this.kubernetesAuthType,
    kubernetesCredentialRef: kubernetesCredentialRef.present
        ? kubernetesCredentialRef.value
        : this.kubernetesCredentialRef,
    remoteSessionPersistence:
        remoteSessionPersistence ?? this.remoteSessionPersistence,
    agentForwarding: agentForwarding ?? this.agentForwarding,
    x11Forwarding: x11Forwarding ?? this.x11Forwarding,
    startupScript: startupScript.present
        ? startupScript.value
        : this.startupScript,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  HostRow copyWithCompanion(HostsCompanion data) {
    return HostRow(
      id: data.id.present ? data.id.value : this.id,
      alias: data.alias.present ? data.alias.value : this.alias,
      hostname: data.hostname.present ? data.hostname.value : this.hostname,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      connectionType: data.connectionType.present
          ? data.connectionType.value
          : this.connectionType,
      authType: data.authType.present ? data.authType.value : this.authType,
      localShellType: data.localShellType.present
          ? data.localShellType.value
          : this.localShellType,
      workingDirectory: data.workingDirectory.present
          ? data.workingDirectory.value
          : this.workingDirectory,
      credentialRef: data.credentialRef.present
          ? data.credentialRef.value
          : this.credentialRef,
      jumpHostId: data.jumpHostId.present
          ? data.jumpHostId.value
          : this.jumpHostId,
      kubernetesContext: data.kubernetesContext.present
          ? data.kubernetesContext.value
          : this.kubernetesContext,
      kubernetesNamespace: data.kubernetesNamespace.present
          ? data.kubernetesNamespace.value
          : this.kubernetesNamespace,
      kubernetesResource: data.kubernetesResource.present
          ? data.kubernetesResource.value
          : this.kubernetesResource,
      kubernetesSshPort: data.kubernetesSshPort.present
          ? data.kubernetesSshPort.value
          : this.kubernetesSshPort,
      kubernetesUsername: data.kubernetesUsername.present
          ? data.kubernetesUsername.value
          : this.kubernetesUsername,
      kubernetesAuthType: data.kubernetesAuthType.present
          ? data.kubernetesAuthType.value
          : this.kubernetesAuthType,
      kubernetesCredentialRef: data.kubernetesCredentialRef.present
          ? data.kubernetesCredentialRef.value
          : this.kubernetesCredentialRef,
      remoteSessionPersistence: data.remoteSessionPersistence.present
          ? data.remoteSessionPersistence.value
          : this.remoteSessionPersistence,
      agentForwarding: data.agentForwarding.present
          ? data.agentForwarding.value
          : this.agentForwarding,
      x11Forwarding: data.x11Forwarding.present
          ? data.x11Forwarding.value
          : this.x11Forwarding,
      startupScript: data.startupScript.present
          ? data.startupScript.value
          : this.startupScript,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostRow(')
          ..write('id: $id, ')
          ..write('alias: $alias, ')
          ..write('hostname: $hostname, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('connectionType: $connectionType, ')
          ..write('authType: $authType, ')
          ..write('localShellType: $localShellType, ')
          ..write('workingDirectory: $workingDirectory, ')
          ..write('credentialRef: $credentialRef, ')
          ..write('jumpHostId: $jumpHostId, ')
          ..write('kubernetesContext: $kubernetesContext, ')
          ..write('kubernetesNamespace: $kubernetesNamespace, ')
          ..write('kubernetesResource: $kubernetesResource, ')
          ..write('kubernetesSshPort: $kubernetesSshPort, ')
          ..write('kubernetesUsername: $kubernetesUsername, ')
          ..write('kubernetesAuthType: $kubernetesAuthType, ')
          ..write('kubernetesCredentialRef: $kubernetesCredentialRef, ')
          ..write('remoteSessionPersistence: $remoteSessionPersistence, ')
          ..write('agentForwarding: $agentForwarding, ')
          ..write('x11Forwarding: $x11Forwarding, ')
          ..write('startupScript: $startupScript, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    alias,
    hostname,
    port,
    username,
    connectionType,
    authType,
    localShellType,
    workingDirectory,
    credentialRef,
    jumpHostId,
    kubernetesContext,
    kubernetesNamespace,
    kubernetesResource,
    kubernetesSshPort,
    kubernetesUsername,
    kubernetesAuthType,
    kubernetesCredentialRef,
    remoteSessionPersistence,
    agentForwarding,
    x11Forwarding,
    startupScript,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostRow &&
          other.id == this.id &&
          other.alias == this.alias &&
          other.hostname == this.hostname &&
          other.port == this.port &&
          other.username == this.username &&
          other.connectionType == this.connectionType &&
          other.authType == this.authType &&
          other.localShellType == this.localShellType &&
          other.workingDirectory == this.workingDirectory &&
          other.credentialRef == this.credentialRef &&
          other.jumpHostId == this.jumpHostId &&
          other.kubernetesContext == this.kubernetesContext &&
          other.kubernetesNamespace == this.kubernetesNamespace &&
          other.kubernetesResource == this.kubernetesResource &&
          other.kubernetesSshPort == this.kubernetesSshPort &&
          other.kubernetesUsername == this.kubernetesUsername &&
          other.kubernetesAuthType == this.kubernetesAuthType &&
          other.kubernetesCredentialRef == this.kubernetesCredentialRef &&
          other.remoteSessionPersistence == this.remoteSessionPersistence &&
          other.agentForwarding == this.agentForwarding &&
          other.x11Forwarding == this.x11Forwarding &&
          other.startupScript == this.startupScript &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class HostsCompanion extends UpdateCompanion<HostRow> {
  final Value<String> id;
  final Value<String> alias;
  final Value<String> hostname;
  final Value<int> port;
  final Value<String> username;
  final Value<int> connectionType;
  final Value<int> authType;
  final Value<int> localShellType;
  final Value<String?> workingDirectory;
  final Value<String?> credentialRef;
  final Value<String?> jumpHostId;
  final Value<String?> kubernetesContext;
  final Value<String?> kubernetesNamespace;
  final Value<String?> kubernetesResource;
  final Value<int> kubernetesSshPort;
  final Value<String?> kubernetesUsername;
  final Value<int> kubernetesAuthType;
  final Value<String?> kubernetesCredentialRef;
  final Value<int> remoteSessionPersistence;
  final Value<bool> agentForwarding;
  final Value<bool> x11Forwarding;
  final Value<String?> startupScript;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const HostsCompanion({
    this.id = const Value.absent(),
    this.alias = const Value.absent(),
    this.hostname = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.connectionType = const Value.absent(),
    this.authType = const Value.absent(),
    this.localShellType = const Value.absent(),
    this.workingDirectory = const Value.absent(),
    this.credentialRef = const Value.absent(),
    this.jumpHostId = const Value.absent(),
    this.kubernetesContext = const Value.absent(),
    this.kubernetesNamespace = const Value.absent(),
    this.kubernetesResource = const Value.absent(),
    this.kubernetesSshPort = const Value.absent(),
    this.kubernetesUsername = const Value.absent(),
    this.kubernetesAuthType = const Value.absent(),
    this.kubernetesCredentialRef = const Value.absent(),
    this.remoteSessionPersistence = const Value.absent(),
    this.agentForwarding = const Value.absent(),
    this.x11Forwarding = const Value.absent(),
    this.startupScript = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostsCompanion.insert({
    required String id,
    required String alias,
    required String hostname,
    this.port = const Value.absent(),
    required String username,
    this.connectionType = const Value.absent(),
    this.authType = const Value.absent(),
    this.localShellType = const Value.absent(),
    this.workingDirectory = const Value.absent(),
    this.credentialRef = const Value.absent(),
    this.jumpHostId = const Value.absent(),
    this.kubernetesContext = const Value.absent(),
    this.kubernetesNamespace = const Value.absent(),
    this.kubernetesResource = const Value.absent(),
    this.kubernetesSshPort = const Value.absent(),
    this.kubernetesUsername = const Value.absent(),
    this.kubernetesAuthType = const Value.absent(),
    this.kubernetesCredentialRef = const Value.absent(),
    this.remoteSessionPersistence = const Value.absent(),
    this.agentForwarding = const Value.absent(),
    this.x11Forwarding = const Value.absent(),
    this.startupScript = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       alias = Value(alias),
       hostname = Value(hostname),
       username = Value(username),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<HostRow> custom({
    Expression<String>? id,
    Expression<String>? alias,
    Expression<String>? hostname,
    Expression<int>? port,
    Expression<String>? username,
    Expression<int>? connectionType,
    Expression<int>? authType,
    Expression<int>? localShellType,
    Expression<String>? workingDirectory,
    Expression<String>? credentialRef,
    Expression<String>? jumpHostId,
    Expression<String>? kubernetesContext,
    Expression<String>? kubernetesNamespace,
    Expression<String>? kubernetesResource,
    Expression<int>? kubernetesSshPort,
    Expression<String>? kubernetesUsername,
    Expression<int>? kubernetesAuthType,
    Expression<String>? kubernetesCredentialRef,
    Expression<int>? remoteSessionPersistence,
    Expression<bool>? agentForwarding,
    Expression<bool>? x11Forwarding,
    Expression<String>? startupScript,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (alias != null) 'alias': alias,
      if (hostname != null) 'hostname': hostname,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (connectionType != null) 'connection_type': connectionType,
      if (authType != null) 'auth_type': authType,
      if (localShellType != null) 'local_shell_type': localShellType,
      if (workingDirectory != null) 'working_directory': workingDirectory,
      if (credentialRef != null) 'credential_ref': credentialRef,
      if (jumpHostId != null) 'jump_host_id': jumpHostId,
      if (kubernetesContext != null) 'kubernetes_context': kubernetesContext,
      if (kubernetesNamespace != null)
        'kubernetes_namespace': kubernetesNamespace,
      if (kubernetesResource != null) 'kubernetes_resource': kubernetesResource,
      if (kubernetesSshPort != null) 'kubernetes_ssh_port': kubernetesSshPort,
      if (kubernetesUsername != null) 'kubernetes_username': kubernetesUsername,
      if (kubernetesAuthType != null)
        'kubernetes_auth_type': kubernetesAuthType,
      if (kubernetesCredentialRef != null)
        'kubernetes_credential_ref': kubernetesCredentialRef,
      if (remoteSessionPersistence != null)
        'remote_session_persistence': remoteSessionPersistence,
      if (agentForwarding != null) 'agent_forwarding': agentForwarding,
      if (x11Forwarding != null) 'x11_forwarding': x11Forwarding,
      if (startupScript != null) 'startup_script': startupScript,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostsCompanion copyWith({
    Value<String>? id,
    Value<String>? alias,
    Value<String>? hostname,
    Value<int>? port,
    Value<String>? username,
    Value<int>? connectionType,
    Value<int>? authType,
    Value<int>? localShellType,
    Value<String?>? workingDirectory,
    Value<String?>? credentialRef,
    Value<String?>? jumpHostId,
    Value<String?>? kubernetesContext,
    Value<String?>? kubernetesNamespace,
    Value<String?>? kubernetesResource,
    Value<int>? kubernetesSshPort,
    Value<String?>? kubernetesUsername,
    Value<int>? kubernetesAuthType,
    Value<String?>? kubernetesCredentialRef,
    Value<int>? remoteSessionPersistence,
    Value<bool>? agentForwarding,
    Value<bool>? x11Forwarding,
    Value<String?>? startupScript,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return HostsCompanion(
      id: id ?? this.id,
      alias: alias ?? this.alias,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      connectionType: connectionType ?? this.connectionType,
      authType: authType ?? this.authType,
      localShellType: localShellType ?? this.localShellType,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      credentialRef: credentialRef ?? this.credentialRef,
      jumpHostId: jumpHostId ?? this.jumpHostId,
      kubernetesContext: kubernetesContext ?? this.kubernetesContext,
      kubernetesNamespace: kubernetesNamespace ?? this.kubernetesNamespace,
      kubernetesResource: kubernetesResource ?? this.kubernetesResource,
      kubernetesSshPort: kubernetesSshPort ?? this.kubernetesSshPort,
      kubernetesUsername: kubernetesUsername ?? this.kubernetesUsername,
      kubernetesAuthType: kubernetesAuthType ?? this.kubernetesAuthType,
      kubernetesCredentialRef:
          kubernetesCredentialRef ?? this.kubernetesCredentialRef,
      remoteSessionPersistence:
          remoteSessionPersistence ?? this.remoteSessionPersistence,
      agentForwarding: agentForwarding ?? this.agentForwarding,
      x11Forwarding: x11Forwarding ?? this.x11Forwarding,
      startupScript: startupScript ?? this.startupScript,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (hostname.present) {
      map['hostname'] = Variable<String>(hostname.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (connectionType.present) {
      map['connection_type'] = Variable<int>(connectionType.value);
    }
    if (authType.present) {
      map['auth_type'] = Variable<int>(authType.value);
    }
    if (localShellType.present) {
      map['local_shell_type'] = Variable<int>(localShellType.value);
    }
    if (workingDirectory.present) {
      map['working_directory'] = Variable<String>(workingDirectory.value);
    }
    if (credentialRef.present) {
      map['credential_ref'] = Variable<String>(credentialRef.value);
    }
    if (jumpHostId.present) {
      map['jump_host_id'] = Variable<String>(jumpHostId.value);
    }
    if (kubernetesContext.present) {
      map['kubernetes_context'] = Variable<String>(kubernetesContext.value);
    }
    if (kubernetesNamespace.present) {
      map['kubernetes_namespace'] = Variable<String>(kubernetesNamespace.value);
    }
    if (kubernetesResource.present) {
      map['kubernetes_resource'] = Variable<String>(kubernetesResource.value);
    }
    if (kubernetesSshPort.present) {
      map['kubernetes_ssh_port'] = Variable<int>(kubernetesSshPort.value);
    }
    if (kubernetesUsername.present) {
      map['kubernetes_username'] = Variable<String>(kubernetesUsername.value);
    }
    if (kubernetesAuthType.present) {
      map['kubernetes_auth_type'] = Variable<int>(kubernetesAuthType.value);
    }
    if (kubernetesCredentialRef.present) {
      map['kubernetes_credential_ref'] = Variable<String>(
        kubernetesCredentialRef.value,
      );
    }
    if (remoteSessionPersistence.present) {
      map['remote_session_persistence'] = Variable<int>(
        remoteSessionPersistence.value,
      );
    }
    if (agentForwarding.present) {
      map['agent_forwarding'] = Variable<bool>(agentForwarding.value);
    }
    if (x11Forwarding.present) {
      map['x11_forwarding'] = Variable<bool>(x11Forwarding.value);
    }
    if (startupScript.present) {
      map['startup_script'] = Variable<String>(startupScript.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostsCompanion(')
          ..write('id: $id, ')
          ..write('alias: $alias, ')
          ..write('hostname: $hostname, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('connectionType: $connectionType, ')
          ..write('authType: $authType, ')
          ..write('localShellType: $localShellType, ')
          ..write('workingDirectory: $workingDirectory, ')
          ..write('credentialRef: $credentialRef, ')
          ..write('jumpHostId: $jumpHostId, ')
          ..write('kubernetesContext: $kubernetesContext, ')
          ..write('kubernetesNamespace: $kubernetesNamespace, ')
          ..write('kubernetesResource: $kubernetesResource, ')
          ..write('kubernetesSshPort: $kubernetesSshPort, ')
          ..write('kubernetesUsername: $kubernetesUsername, ')
          ..write('kubernetesAuthType: $kubernetesAuthType, ')
          ..write('kubernetesCredentialRef: $kubernetesCredentialRef, ')
          ..write('remoteSessionPersistence: $remoteSessionPersistence, ')
          ..write('agentForwarding: $agentForwarding, ')
          ..write('x11Forwarding: $x11Forwarding, ')
          ..write('startupScript: $startupScript, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HostKeysTable extends HostKeys
    with TableInfo<$HostKeysTable, HostKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostnameMeta = const VerificationMeta(
    'hostname',
  );
  @override
  late final GeneratedColumn<String> hostname = GeneratedColumn<String>(
    'hostname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyTypeMeta = const VerificationMeta(
    'keyType',
  );
  @override
  late final GeneratedColumn<String> keyType = GeneratedColumn<String>(
    'key_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta(
    'pinnedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pinnedAt = GeneratedColumn<DateTime>(
    'pinned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hostname,
    port,
    keyType,
    fingerprint,
    pinnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'host_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostKeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hostname')) {
      context.handle(
        _hostnameMeta,
        hostname.isAcceptableOrUnknown(data['hostname']!, _hostnameMeta),
      );
    } else if (isInserting) {
      context.missing(_hostnameMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('key_type')) {
      context.handle(
        _keyTypeMeta,
        keyType.isAcceptableOrUnknown(data['key_type']!, _keyTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_keyTypeMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HostKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostKeyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hostname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hostname'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      keyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_type'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pinned_at'],
      )!,
    );
  }

  @override
  $HostKeysTable createAlias(String alias) {
    return $HostKeysTable(attachedDatabase, alias);
  }
}

class HostKeyRow extends DataClass implements Insertable<HostKeyRow> {
  final String id;
  final String hostname;
  final int port;
  final String keyType;
  final String fingerprint;
  final DateTime pinnedAt;
  const HostKeyRow({
    required this.id,
    required this.hostname,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.pinnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hostname'] = Variable<String>(hostname);
    map['port'] = Variable<int>(port);
    map['key_type'] = Variable<String>(keyType);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['pinned_at'] = Variable<DateTime>(pinnedAt);
    return map;
  }

  HostKeysCompanion toCompanion(bool nullToAbsent) {
    return HostKeysCompanion(
      id: Value(id),
      hostname: Value(hostname),
      port: Value(port),
      keyType: Value(keyType),
      fingerprint: Value(fingerprint),
      pinnedAt: Value(pinnedAt),
    );
  }

  factory HostKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostKeyRow(
      id: serializer.fromJson<String>(json['id']),
      hostname: serializer.fromJson<String>(json['hostname']),
      port: serializer.fromJson<int>(json['port']),
      keyType: serializer.fromJson<String>(json['keyType']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      pinnedAt: serializer.fromJson<DateTime>(json['pinnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hostname': serializer.toJson<String>(hostname),
      'port': serializer.toJson<int>(port),
      'keyType': serializer.toJson<String>(keyType),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'pinnedAt': serializer.toJson<DateTime>(pinnedAt),
    };
  }

  HostKeyRow copyWith({
    String? id,
    String? hostname,
    int? port,
    String? keyType,
    String? fingerprint,
    DateTime? pinnedAt,
  }) => HostKeyRow(
    id: id ?? this.id,
    hostname: hostname ?? this.hostname,
    port: port ?? this.port,
    keyType: keyType ?? this.keyType,
    fingerprint: fingerprint ?? this.fingerprint,
    pinnedAt: pinnedAt ?? this.pinnedAt,
  );
  HostKeyRow copyWithCompanion(HostKeysCompanion data) {
    return HostKeyRow(
      id: data.id.present ? data.id.value : this.id,
      hostname: data.hostname.present ? data.hostname.value : this.hostname,
      port: data.port.present ? data.port.value : this.port,
      keyType: data.keyType.present ? data.keyType.value : this.keyType,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostKeyRow(')
          ..write('id: $id, ')
          ..write('hostname: $hostname, ')
          ..write('port: $port, ')
          ..write('keyType: $keyType, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, hostname, port, keyType, fingerprint, pinnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostKeyRow &&
          other.id == this.id &&
          other.hostname == this.hostname &&
          other.port == this.port &&
          other.keyType == this.keyType &&
          other.fingerprint == this.fingerprint &&
          other.pinnedAt == this.pinnedAt);
}

class HostKeysCompanion extends UpdateCompanion<HostKeyRow> {
  final Value<String> id;
  final Value<String> hostname;
  final Value<int> port;
  final Value<String> keyType;
  final Value<String> fingerprint;
  final Value<DateTime> pinnedAt;
  final Value<int> rowid;
  const HostKeysCompanion({
    this.id = const Value.absent(),
    this.hostname = const Value.absent(),
    this.port = const Value.absent(),
    this.keyType = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostKeysCompanion.insert({
    required String id,
    required String hostname,
    required int port,
    required String keyType,
    required String fingerprint,
    required DateTime pinnedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hostname = Value(hostname),
       port = Value(port),
       keyType = Value(keyType),
       fingerprint = Value(fingerprint),
       pinnedAt = Value(pinnedAt);
  static Insertable<HostKeyRow> custom({
    Expression<String>? id,
    Expression<String>? hostname,
    Expression<int>? port,
    Expression<String>? keyType,
    Expression<String>? fingerprint,
    Expression<DateTime>? pinnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hostname != null) 'hostname': hostname,
      if (port != null) 'port': port,
      if (keyType != null) 'key_type': keyType,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostKeysCompanion copyWith({
    Value<String>? id,
    Value<String>? hostname,
    Value<int>? port,
    Value<String>? keyType,
    Value<String>? fingerprint,
    Value<DateTime>? pinnedAt,
    Value<int>? rowid,
  }) {
    return HostKeysCompanion(
      id: id ?? this.id,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      keyType: keyType ?? this.keyType,
      fingerprint: fingerprint ?? this.fingerprint,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hostname.present) {
      map['hostname'] = Variable<String>(hostname.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (keyType.present) {
      map['key_type'] = Variable<String>(keyType.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostKeysCompanion(')
          ..write('id: $id, ')
          ..write('hostname: $hostname, ')
          ..write('port: $port, ')
          ..write('keyType: $keyType, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnippetsTable extends Snippets
    with TableInfo<$SnippetsTable, SnippetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnippetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<int> scope = GeneratedColumn<int>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultRunModeMeta = const VerificationMeta(
    'defaultRunMode',
  );
  @override
  late final GeneratedColumn<int> defaultRunMode = GeneratedColumn<int>(
    'default_run_mode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    body,
    scope,
    hostId,
    defaultRunMode,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snippets';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnippetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    }
    if (data.containsKey('default_run_mode')) {
      context.handle(
        _defaultRunModeMeta,
        defaultRunMode.isAcceptableOrUnknown(
          data['default_run_mode']!,
          _defaultRunModeMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SnippetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnippetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scope'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      ),
      defaultRunMode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_run_mode'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SnippetsTable createAlias(String alias) {
    return $SnippetsTable(attachedDatabase, alias);
  }
}

class SnippetRow extends DataClass implements Insertable<SnippetRow> {
  final String id;
  final String name;
  final String body;
  final int scope;
  final String? hostId;
  final int defaultRunMode;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SnippetRow({
    required this.id,
    required this.name,
    required this.body,
    required this.scope,
    this.hostId,
    required this.defaultRunMode,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['body'] = Variable<String>(body);
    map['scope'] = Variable<int>(scope);
    if (!nullToAbsent || hostId != null) {
      map['host_id'] = Variable<String>(hostId);
    }
    map['default_run_mode'] = Variable<int>(defaultRunMode);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SnippetsCompanion toCompanion(bool nullToAbsent) {
    return SnippetsCompanion(
      id: Value(id),
      name: Value(name),
      body: Value(body),
      scope: Value(scope),
      hostId: hostId == null && nullToAbsent
          ? const Value.absent()
          : Value(hostId),
      defaultRunMode: Value(defaultRunMode),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SnippetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnippetRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      body: serializer.fromJson<String>(json['body']),
      scope: serializer.fromJson<int>(json['scope']),
      hostId: serializer.fromJson<String?>(json['hostId']),
      defaultRunMode: serializer.fromJson<int>(json['defaultRunMode']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'body': serializer.toJson<String>(body),
      'scope': serializer.toJson<int>(scope),
      'hostId': serializer.toJson<String?>(hostId),
      'defaultRunMode': serializer.toJson<int>(defaultRunMode),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SnippetRow copyWith({
    String? id,
    String? name,
    String? body,
    int? scope,
    Value<String?> hostId = const Value.absent(),
    int? defaultRunMode,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SnippetRow(
    id: id ?? this.id,
    name: name ?? this.name,
    body: body ?? this.body,
    scope: scope ?? this.scope,
    hostId: hostId.present ? hostId.value : this.hostId,
    defaultRunMode: defaultRunMode ?? this.defaultRunMode,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SnippetRow copyWithCompanion(SnippetsCompanion data) {
    return SnippetRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      body: data.body.present ? data.body.value : this.body,
      scope: data.scope.present ? data.scope.value : this.scope,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      defaultRunMode: data.defaultRunMode.present
          ? data.defaultRunMode.value
          : this.defaultRunMode,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnippetRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('body: $body, ')
          ..write('scope: $scope, ')
          ..write('hostId: $hostId, ')
          ..write('defaultRunMode: $defaultRunMode, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    body,
    scope,
    hostId,
    defaultRunMode,
    sortOrder,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnippetRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.body == this.body &&
          other.scope == this.scope &&
          other.hostId == this.hostId &&
          other.defaultRunMode == this.defaultRunMode &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SnippetsCompanion extends UpdateCompanion<SnippetRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> body;
  final Value<int> scope;
  final Value<String?> hostId;
  final Value<int> defaultRunMode;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SnippetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.body = const Value.absent(),
    this.scope = const Value.absent(),
    this.hostId = const Value.absent(),
    this.defaultRunMode = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnippetsCompanion.insert({
    required String id,
    required String name,
    required String body,
    this.scope = const Value.absent(),
    this.hostId = const Value.absent(),
    this.defaultRunMode = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       body = Value(body),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SnippetRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? body,
    Expression<int>? scope,
    Expression<String>? hostId,
    Expression<int>? defaultRunMode,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (body != null) 'body': body,
      if (scope != null) 'scope': scope,
      if (hostId != null) 'host_id': hostId,
      if (defaultRunMode != null) 'default_run_mode': defaultRunMode,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnippetsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? body,
    Value<int>? scope,
    Value<String?>? hostId,
    Value<int>? defaultRunMode,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SnippetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      body: body ?? this.body,
      scope: scope ?? this.scope,
      hostId: hostId ?? this.hostId,
      defaultRunMode: defaultRunMode ?? this.defaultRunMode,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (scope.present) {
      map['scope'] = Variable<int>(scope.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (defaultRunMode.present) {
      map['default_run_mode'] = Variable<int>(defaultRunMode.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnippetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('body: $body, ')
          ..write('scope: $scope, ')
          ..write('hostId: $hostId, ')
          ..write('defaultRunMode: $defaultRunMode, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemosTable extends Memos with TableInfo<$MemosTable, MemoRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [hostId, body, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memos';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hostId};
  @override
  MemoRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoRow(
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MemosTable createAlias(String alias) {
    return $MemosTable(attachedDatabase, alias);
  }
}

class MemoRow extends DataClass implements Insertable<MemoRow> {
  final String hostId;
  final String body;
  final DateTime updatedAt;
  const MemoRow({
    required this.hostId,
    required this.body,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host_id'] = Variable<String>(hostId);
    map['body'] = Variable<String>(body);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MemosCompanion toCompanion(bool nullToAbsent) {
    return MemosCompanion(
      hostId: Value(hostId),
      body: Value(body),
      updatedAt: Value(updatedAt),
    );
  }

  factory MemoRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoRow(
      hostId: serializer.fromJson<String>(json['hostId']),
      body: serializer.fromJson<String>(json['body']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hostId': serializer.toJson<String>(hostId),
      'body': serializer.toJson<String>(body),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MemoRow copyWith({String? hostId, String? body, DateTime? updatedAt}) =>
      MemoRow(
        hostId: hostId ?? this.hostId,
        body: body ?? this.body,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  MemoRow copyWithCompanion(MemosCompanion data) {
    return MemoRow(
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      body: data.body.present ? data.body.value : this.body,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoRow(')
          ..write('hostId: $hostId, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(hostId, body, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoRow &&
          other.hostId == this.hostId &&
          other.body == this.body &&
          other.updatedAt == this.updatedAt);
}

class MemosCompanion extends UpdateCompanion<MemoRow> {
  final Value<String> hostId;
  final Value<String> body;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MemosCompanion({
    this.hostId = const Value.absent(),
    this.body = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemosCompanion.insert({
    required String hostId,
    required String body,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : hostId = Value(hostId),
       body = Value(body),
       updatedAt = Value(updatedAt);
  static Insertable<MemoRow> custom({
    Expression<String>? hostId,
    Expression<String>? body,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hostId != null) 'host_id': hostId,
      if (body != null) 'body': body,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemosCompanion copyWith({
    Value<String>? hostId,
    Value<String>? body,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MemosCompanion(
      hostId: hostId ?? this.hostId,
      body: body ?? this.body,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemosCompanion(')
          ..write('hostId: $hostId, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionLogsTable extends SessionLogs
    with TableInfo<$SessionLogsTable, SessionLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostAliasMeta = const VerificationMeta(
    'hostAlias',
  );
  @override
  late final GeneratedColumn<String> hostAlias = GeneratedColumn<String>(
    'host_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _connectionTypeMeta = const VerificationMeta(
    'connectionType',
  );
  @override
  late final GeneratedColumn<int> connectionType = GeneratedColumn<int>(
    'connection_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endpointMeta = const VerificationMeta(
    'endpoint',
  );
  @override
  late final GeneratedColumn<String> endpoint = GeneratedColumn<String>(
    'endpoint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endReasonMeta = const VerificationMeta(
    'endReason',
  );
  @override
  late final GeneratedColumn<String> endReason = GeneratedColumn<String>(
    'end_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logPathMeta = const VerificationMeta(
    'logPath',
  );
  @override
  late final GeneratedColumn<String> logPath = GeneratedColumn<String>(
    'log_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteCountMeta = const VerificationMeta(
    'byteCount',
  );
  @override
  late final GeneratedColumn<int> byteCount = GeneratedColumn<int>(
    'byte_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lineCountMeta = const VerificationMeta(
    'lineCount',
  );
  @override
  late final GeneratedColumn<int> lineCount = GeneratedColumn<int>(
    'line_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    hostId,
    hostAlias,
    connectionType,
    endpoint,
    startedAt,
    endedAt,
    endReason,
    logPath,
    byteCount,
    lineCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('host_alias')) {
      context.handle(
        _hostAliasMeta,
        hostAlias.isAcceptableOrUnknown(data['host_alias']!, _hostAliasMeta),
      );
    } else if (isInserting) {
      context.missing(_hostAliasMeta);
    }
    if (data.containsKey('connection_type')) {
      context.handle(
        _connectionTypeMeta,
        connectionType.isAcceptableOrUnknown(
          data['connection_type']!,
          _connectionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionTypeMeta);
    }
    if (data.containsKey('endpoint')) {
      context.handle(
        _endpointMeta,
        endpoint.isAcceptableOrUnknown(data['endpoint']!, _endpointMeta),
      );
    } else if (isInserting) {
      context.missing(_endpointMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('end_reason')) {
      context.handle(
        _endReasonMeta,
        endReason.isAcceptableOrUnknown(data['end_reason']!, _endReasonMeta),
      );
    }
    if (data.containsKey('log_path')) {
      context.handle(
        _logPathMeta,
        logPath.isAcceptableOrUnknown(data['log_path']!, _logPathMeta),
      );
    } else if (isInserting) {
      context.missing(_logPathMeta);
    }
    if (data.containsKey('byte_count')) {
      context.handle(
        _byteCountMeta,
        byteCount.isAcceptableOrUnknown(data['byte_count']!, _byteCountMeta),
      );
    }
    if (data.containsKey('line_count')) {
      context.handle(
        _lineCountMeta,
        lineCount.isAcceptableOrUnknown(data['line_count']!, _lineCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      hostAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_alias'],
      )!,
      connectionType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}connection_type'],
      )!,
      endpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endpoint'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      endReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_reason'],
      ),
      logPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}log_path'],
      )!,
      byteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_count'],
      )!,
      lineCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_count'],
      )!,
    );
  }

  @override
  $SessionLogsTable createAlias(String alias) {
    return $SessionLogsTable(attachedDatabase, alias);
  }
}

class SessionLogRow extends DataClass implements Insertable<SessionLogRow> {
  final String id;
  final String sessionId;
  final String hostId;
  final String hostAlias;
  final int connectionType;
  final String endpoint;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? endReason;
  final String logPath;
  final int byteCount;
  final int lineCount;
  const SessionLogRow({
    required this.id,
    required this.sessionId,
    required this.hostId,
    required this.hostAlias,
    required this.connectionType,
    required this.endpoint,
    required this.startedAt,
    this.endedAt,
    this.endReason,
    required this.logPath,
    required this.byteCount,
    required this.lineCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['host_id'] = Variable<String>(hostId);
    map['host_alias'] = Variable<String>(hostAlias);
    map['connection_type'] = Variable<int>(connectionType);
    map['endpoint'] = Variable<String>(endpoint);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    if (!nullToAbsent || endReason != null) {
      map['end_reason'] = Variable<String>(endReason);
    }
    map['log_path'] = Variable<String>(logPath);
    map['byte_count'] = Variable<int>(byteCount);
    map['line_count'] = Variable<int>(lineCount);
    return map;
  }

  SessionLogsCompanion toCompanion(bool nullToAbsent) {
    return SessionLogsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      hostId: Value(hostId),
      hostAlias: Value(hostAlias),
      connectionType: Value(connectionType),
      endpoint: Value(endpoint),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      endReason: endReason == null && nullToAbsent
          ? const Value.absent()
          : Value(endReason),
      logPath: Value(logPath),
      byteCount: Value(byteCount),
      lineCount: Value(lineCount),
    );
  }

  factory SessionLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionLogRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      hostId: serializer.fromJson<String>(json['hostId']),
      hostAlias: serializer.fromJson<String>(json['hostAlias']),
      connectionType: serializer.fromJson<int>(json['connectionType']),
      endpoint: serializer.fromJson<String>(json['endpoint']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      endReason: serializer.fromJson<String?>(json['endReason']),
      logPath: serializer.fromJson<String>(json['logPath']),
      byteCount: serializer.fromJson<int>(json['byteCount']),
      lineCount: serializer.fromJson<int>(json['lineCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'hostId': serializer.toJson<String>(hostId),
      'hostAlias': serializer.toJson<String>(hostAlias),
      'connectionType': serializer.toJson<int>(connectionType),
      'endpoint': serializer.toJson<String>(endpoint),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'endReason': serializer.toJson<String?>(endReason),
      'logPath': serializer.toJson<String>(logPath),
      'byteCount': serializer.toJson<int>(byteCount),
      'lineCount': serializer.toJson<int>(lineCount),
    };
  }

  SessionLogRow copyWith({
    String? id,
    String? sessionId,
    String? hostId,
    String? hostAlias,
    int? connectionType,
    String? endpoint,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    Value<String?> endReason = const Value.absent(),
    String? logPath,
    int? byteCount,
    int? lineCount,
  }) => SessionLogRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    hostId: hostId ?? this.hostId,
    hostAlias: hostAlias ?? this.hostAlias,
    connectionType: connectionType ?? this.connectionType,
    endpoint: endpoint ?? this.endpoint,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    endReason: endReason.present ? endReason.value : this.endReason,
    logPath: logPath ?? this.logPath,
    byteCount: byteCount ?? this.byteCount,
    lineCount: lineCount ?? this.lineCount,
  );
  SessionLogRow copyWithCompanion(SessionLogsCompanion data) {
    return SessionLogRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      hostAlias: data.hostAlias.present ? data.hostAlias.value : this.hostAlias,
      connectionType: data.connectionType.present
          ? data.connectionType.value
          : this.connectionType,
      endpoint: data.endpoint.present ? data.endpoint.value : this.endpoint,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      endReason: data.endReason.present ? data.endReason.value : this.endReason,
      logPath: data.logPath.present ? data.logPath.value : this.logPath,
      byteCount: data.byteCount.present ? data.byteCount.value : this.byteCount,
      lineCount: data.lineCount.present ? data.lineCount.value : this.lineCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionLogRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('hostId: $hostId, ')
          ..write('hostAlias: $hostAlias, ')
          ..write('connectionType: $connectionType, ')
          ..write('endpoint: $endpoint, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endReason: $endReason, ')
          ..write('logPath: $logPath, ')
          ..write('byteCount: $byteCount, ')
          ..write('lineCount: $lineCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    hostId,
    hostAlias,
    connectionType,
    endpoint,
    startedAt,
    endedAt,
    endReason,
    logPath,
    byteCount,
    lineCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionLogRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.hostId == this.hostId &&
          other.hostAlias == this.hostAlias &&
          other.connectionType == this.connectionType &&
          other.endpoint == this.endpoint &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.endReason == this.endReason &&
          other.logPath == this.logPath &&
          other.byteCount == this.byteCount &&
          other.lineCount == this.lineCount);
}

class SessionLogsCompanion extends UpdateCompanion<SessionLogRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> hostId;
  final Value<String> hostAlias;
  final Value<int> connectionType;
  final Value<String> endpoint;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<String?> endReason;
  final Value<String> logPath;
  final Value<int> byteCount;
  final Value<int> lineCount;
  final Value<int> rowid;
  const SessionLogsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.hostId = const Value.absent(),
    this.hostAlias = const Value.absent(),
    this.connectionType = const Value.absent(),
    this.endpoint = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.endReason = const Value.absent(),
    this.logPath = const Value.absent(),
    this.byteCount = const Value.absent(),
    this.lineCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionLogsCompanion.insert({
    required String id,
    required String sessionId,
    required String hostId,
    required String hostAlias,
    required int connectionType,
    required String endpoint,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.endReason = const Value.absent(),
    required String logPath,
    this.byteCount = const Value.absent(),
    this.lineCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       hostId = Value(hostId),
       hostAlias = Value(hostAlias),
       connectionType = Value(connectionType),
       endpoint = Value(endpoint),
       startedAt = Value(startedAt),
       logPath = Value(logPath);
  static Insertable<SessionLogRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? hostId,
    Expression<String>? hostAlias,
    Expression<int>? connectionType,
    Expression<String>? endpoint,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<String>? endReason,
    Expression<String>? logPath,
    Expression<int>? byteCount,
    Expression<int>? lineCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (hostId != null) 'host_id': hostId,
      if (hostAlias != null) 'host_alias': hostAlias,
      if (connectionType != null) 'connection_type': connectionType,
      if (endpoint != null) 'endpoint': endpoint,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (endReason != null) 'end_reason': endReason,
      if (logPath != null) 'log_path': logPath,
      if (byteCount != null) 'byte_count': byteCount,
      if (lineCount != null) 'line_count': lineCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? hostId,
    Value<String>? hostAlias,
    Value<int>? connectionType,
    Value<String>? endpoint,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<String?>? endReason,
    Value<String>? logPath,
    Value<int>? byteCount,
    Value<int>? lineCount,
    Value<int>? rowid,
  }) {
    return SessionLogsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      hostId: hostId ?? this.hostId,
      hostAlias: hostAlias ?? this.hostAlias,
      connectionType: connectionType ?? this.connectionType,
      endpoint: endpoint ?? this.endpoint,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      logPath: logPath ?? this.logPath,
      byteCount: byteCount ?? this.byteCount,
      lineCount: lineCount ?? this.lineCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (hostAlias.present) {
      map['host_alias'] = Variable<String>(hostAlias.value);
    }
    if (connectionType.present) {
      map['connection_type'] = Variable<int>(connectionType.value);
    }
    if (endpoint.present) {
      map['endpoint'] = Variable<String>(endpoint.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (endReason.present) {
      map['end_reason'] = Variable<String>(endReason.value);
    }
    if (logPath.present) {
      map['log_path'] = Variable<String>(logPath.value);
    }
    if (byteCount.present) {
      map['byte_count'] = Variable<int>(byteCount.value);
    }
    if (lineCount.present) {
      map['line_count'] = Variable<int>(lineCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionLogsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('hostId: $hostId, ')
          ..write('hostAlias: $hostAlias, ')
          ..write('connectionType: $connectionType, ')
          ..write('endpoint: $endpoint, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endReason: $endReason, ')
          ..write('logPath: $logPath, ')
          ..write('byteCount: $byteCount, ')
          ..write('lineCount: $lineCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $HostsTable hosts = $HostsTable(this);
  late final $HostKeysTable hostKeys = $HostKeysTable(this);
  late final $SnippetsTable snippets = $SnippetsTable(this);
  late final $MemosTable memos = $MemosTable(this);
  late final $SessionLogsTable sessionLogs = $SessionLogsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    hosts,
    hostKeys,
    snippets,
    memos,
    sessionLogs,
  ];
}

typedef $$HostsTableCreateCompanionBuilder = HostsCompanion Function({
  required String id,
  required String alias,
  required String hostname,
  Value<int> port,
  required String username,
  Value<int> connectionType,
  Value<int> authType,
  Value<int> localShellType,
  Value<String?> workingDirectory,
  Value<String?> credentialRef,
  Value<String?> jumpHostId,
  Value<String?> kubernetesContext,
  Value<String?> kubernetesNamespace,
  Value<String?> kubernetesResource,
  Value<int> kubernetesSshPort,
  Value<String?> kubernetesUsername,
  Value<int> kubernetesAuthType,
  Value<String?> kubernetesCredentialRef,
  Value<int> remoteSessionPersistence,
  Value<bool> agentForwarding,
  Value<bool> x11Forwarding,
  Value<String?> startupScript,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$HostsTableUpdateCompanionBuilder = HostsCompanion Function({
  Value<String> id,
  Value<String> alias,
  Value<String> hostname,
  Value<int> port,
  Value<String> username,
  Value<int> connectionType,
  Value<int> authType,
  Value<int> localShellType,
  Value<String?> workingDirectory,
  Value<String?> credentialRef,
  Value<String?> jumpHostId,
  Value<String?> kubernetesContext,
  Value<String?> kubernetesNamespace,
  Value<String?> kubernetesResource,
  Value<int> kubernetesSshPort,
  Value<String?> kubernetesUsername,
  Value<int> kubernetesAuthType,
  Value<String?> kubernetesCredentialRef,
  Value<int> remoteSessionPersistence,
  Value<bool> agentForwarding,
  Value<bool> x11Forwarding,
  Value<String?> startupScript,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$HostsTableFilterComposer extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localShellType => $composableBuilder(
    column: $table.localShellType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workingDirectory => $composableBuilder(
    column: $table.workingDirectory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jumpHostId => $composableBuilder(
    column: $table.jumpHostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kubernetesContext => $composableBuilder(
    column: $table.kubernetesContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kubernetesNamespace => $composableBuilder(
    column: $table.kubernetesNamespace,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kubernetesResource => $composableBuilder(
    column: $table.kubernetesResource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kubernetesSshPort => $composableBuilder(
    column: $table.kubernetesSshPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kubernetesUsername => $composableBuilder(
    column: $table.kubernetesUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kubernetesAuthType => $composableBuilder(
    column: $table.kubernetesAuthType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kubernetesCredentialRef => $composableBuilder(
    column: $table.kubernetesCredentialRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteSessionPersistence => $composableBuilder(
    column: $table.remoteSessionPersistence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get agentForwarding => $composableBuilder(
    column: $table.agentForwarding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get x11Forwarding => $composableBuilder(
    column: $table.x11Forwarding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startupScript => $composableBuilder(
    column: $table.startupScript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HostsTableOrderingComposer
    extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localShellType => $composableBuilder(
    column: $table.localShellType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workingDirectory => $composableBuilder(
    column: $table.workingDirectory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jumpHostId => $composableBuilder(
    column: $table.jumpHostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kubernetesContext => $composableBuilder(
    column: $table.kubernetesContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kubernetesNamespace => $composableBuilder(
    column: $table.kubernetesNamespace,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kubernetesResource => $composableBuilder(
    column: $table.kubernetesResource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kubernetesSshPort => $composableBuilder(
    column: $table.kubernetesSshPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kubernetesUsername => $composableBuilder(
    column: $table.kubernetesUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kubernetesAuthType => $composableBuilder(
    column: $table.kubernetesAuthType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kubernetesCredentialRef => $composableBuilder(
    column: $table.kubernetesCredentialRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteSessionPersistence => $composableBuilder(
    column: $table.remoteSessionPersistence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get agentForwarding => $composableBuilder(
    column: $table.agentForwarding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get x11Forwarding => $composableBuilder(
    column: $table.x11Forwarding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startupScript => $composableBuilder(
    column: $table.startupScript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<String> get hostname =>
      $composableBuilder(column: $table.hostname, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<int> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get authType =>
      $composableBuilder(column: $table.authType, builder: (column) => column);

  GeneratedColumn<int> get localShellType => $composableBuilder(
    column: $table.localShellType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workingDirectory => $composableBuilder(
    column: $table.workingDirectory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jumpHostId => $composableBuilder(
    column: $table.jumpHostId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kubernetesContext => $composableBuilder(
    column: $table.kubernetesContext,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kubernetesNamespace => $composableBuilder(
    column: $table.kubernetesNamespace,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kubernetesResource => $composableBuilder(
    column: $table.kubernetesResource,
    builder: (column) => column,
  );

  GeneratedColumn<int> get kubernetesSshPort => $composableBuilder(
    column: $table.kubernetesSshPort,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kubernetesUsername => $composableBuilder(
    column: $table.kubernetesUsername,
    builder: (column) => column,
  );

  GeneratedColumn<int> get kubernetesAuthType => $composableBuilder(
    column: $table.kubernetesAuthType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kubernetesCredentialRef => $composableBuilder(
    column: $table.kubernetesCredentialRef,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remoteSessionPersistence => $composableBuilder(
    column: $table.remoteSessionPersistence,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get agentForwarding => $composableBuilder(
    column: $table.agentForwarding,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get x11Forwarding => $composableBuilder(
    column: $table.x11Forwarding,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startupScript => $composableBuilder(
    column: $table.startupScript,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$HostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HostsTable,
          HostRow,
          $$HostsTableFilterComposer,
          $$HostsTableOrderingComposer,
          $$HostsTableAnnotationComposer,
          $$HostsTableCreateCompanionBuilder,
          $$HostsTableUpdateCompanionBuilder,
          (HostRow, BaseReferences<_$AppDatabase, $HostsTable, HostRow>),
          HostRow,
          PrefetchHooks Function()
        > {
  $$HostsTableTableManager(_$AppDatabase db, $HostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<String> hostname = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<int> connectionType = const Value.absent(),
                Value<int> authType = const Value.absent(),
                Value<int> localShellType = const Value.absent(),
                Value<String?> workingDirectory = const Value.absent(),
                Value<String?> credentialRef = const Value.absent(),
                Value<String?> jumpHostId = const Value.absent(),
                Value<String?> kubernetesContext = const Value.absent(),
                Value<String?> kubernetesNamespace = const Value.absent(),
                Value<String?> kubernetesResource = const Value.absent(),
                Value<int> kubernetesSshPort = const Value.absent(),
                Value<String?> kubernetesUsername = const Value.absent(),
                Value<int> kubernetesAuthType = const Value.absent(),
                Value<String?> kubernetesCredentialRef = const Value.absent(),
                Value<int> remoteSessionPersistence = const Value.absent(),
                Value<bool> agentForwarding = const Value.absent(),
                Value<bool> x11Forwarding = const Value.absent(),
                Value<String?> startupScript = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostsCompanion(
                id: id,
                alias: alias,
                hostname: hostname,
                port: port,
                username: username,
                connectionType: connectionType,
                authType: authType,
                localShellType: localShellType,
                workingDirectory: workingDirectory,
                credentialRef: credentialRef,
                jumpHostId: jumpHostId,
                kubernetesContext: kubernetesContext,
                kubernetesNamespace: kubernetesNamespace,
                kubernetesResource: kubernetesResource,
                kubernetesSshPort: kubernetesSshPort,
                kubernetesUsername: kubernetesUsername,
                kubernetesAuthType: kubernetesAuthType,
                kubernetesCredentialRef: kubernetesCredentialRef,
                remoteSessionPersistence: remoteSessionPersistence,
                agentForwarding: agentForwarding,
                x11Forwarding: x11Forwarding,
                startupScript: startupScript,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String alias,
                required String hostname,
                Value<int> port = const Value.absent(),
                required String username,
                Value<int> connectionType = const Value.absent(),
                Value<int> authType = const Value.absent(),
                Value<int> localShellType = const Value.absent(),
                Value<String?> workingDirectory = const Value.absent(),
                Value<String?> credentialRef = const Value.absent(),
                Value<String?> jumpHostId = const Value.absent(),
                Value<String?> kubernetesContext = const Value.absent(),
                Value<String?> kubernetesNamespace = const Value.absent(),
                Value<String?> kubernetesResource = const Value.absent(),
                Value<int> kubernetesSshPort = const Value.absent(),
                Value<String?> kubernetesUsername = const Value.absent(),
                Value<int> kubernetesAuthType = const Value.absent(),
                Value<String?> kubernetesCredentialRef = const Value.absent(),
                Value<int> remoteSessionPersistence = const Value.absent(),
                Value<bool> agentForwarding = const Value.absent(),
                Value<bool> x11Forwarding = const Value.absent(),
                Value<String?> startupScript = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => HostsCompanion.insert(
                id: id,
                alias: alias,
                hostname: hostname,
                port: port,
                username: username,
                connectionType: connectionType,
                authType: authType,
                localShellType: localShellType,
                workingDirectory: workingDirectory,
                credentialRef: credentialRef,
                jumpHostId: jumpHostId,
                kubernetesContext: kubernetesContext,
                kubernetesNamespace: kubernetesNamespace,
                kubernetesResource: kubernetesResource,
                kubernetesSshPort: kubernetesSshPort,
                kubernetesUsername: kubernetesUsername,
                kubernetesAuthType: kubernetesAuthType,
                kubernetesCredentialRef: kubernetesCredentialRef,
                remoteSessionPersistence: remoteSessionPersistence,
                agentForwarding: agentForwarding,
                x11Forwarding: x11Forwarding,
                startupScript: startupScript,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HostsTable,
      HostRow,
      $$HostsTableFilterComposer,
      $$HostsTableOrderingComposer,
      $$HostsTableAnnotationComposer,
      $$HostsTableCreateCompanionBuilder,
      $$HostsTableUpdateCompanionBuilder,
      (HostRow, BaseReferences<_$AppDatabase, $HostsTable, HostRow>),
      HostRow,
      PrefetchHooks Function()
    >;
typedef $$HostKeysTableCreateCompanionBuilder = HostKeysCompanion Function({
  required String id,
  required String hostname,
  required int port,
  required String keyType,
  required String fingerprint,
  required DateTime pinnedAt,
  Value<int> rowid,
});
typedef $$HostKeysTableUpdateCompanionBuilder = HostKeysCompanion Function({
  Value<String> id,
  Value<String> hostname,
  Value<int> port,
  Value<String> keyType,
  Value<String> fingerprint,
  Value<DateTime> pinnedAt,
  Value<int> rowid,
});

class $$HostKeysTableFilterComposer
    extends Composer<_$AppDatabase, $HostKeysTable> {
  $$HostKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyType => $composableBuilder(
    column: $table.keyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HostKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $HostKeysTable> {
  $$HostKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyType => $composableBuilder(
    column: $table.keyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $HostKeysTable> {
  $$HostKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hostname =>
      $composableBuilder(column: $table.hostname, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get keyType =>
      $composableBuilder(column: $table.keyType, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);
}

class $$HostKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HostKeysTable,
          HostKeyRow,
          $$HostKeysTableFilterComposer,
          $$HostKeysTableOrderingComposer,
          $$HostKeysTableAnnotationComposer,
          $$HostKeysTableCreateCompanionBuilder,
          $$HostKeysTableUpdateCompanionBuilder,
          (
            HostKeyRow,
            BaseReferences<_$AppDatabase, $HostKeysTable, HostKeyRow>,
          ),
          HostKeyRow,
          PrefetchHooks Function()
        > {
  $$HostKeysTableTableManager(_$AppDatabase db, $HostKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hostname = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> keyType = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<DateTime> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostKeysCompanion(
                id: id,
                hostname: hostname,
                port: port,
                keyType: keyType,
                fingerprint: fingerprint,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hostname,
                required int port,
                required String keyType,
                required String fingerprint,
                required DateTime pinnedAt,
                Value<int> rowid = const Value.absent(),
              }) => HostKeysCompanion.insert(
                id: id,
                hostname: hostname,
                port: port,
                keyType: keyType,
                fingerprint: fingerprint,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HostKeysTable,
      HostKeyRow,
      $$HostKeysTableFilterComposer,
      $$HostKeysTableOrderingComposer,
      $$HostKeysTableAnnotationComposer,
      $$HostKeysTableCreateCompanionBuilder,
      $$HostKeysTableUpdateCompanionBuilder,
      (HostKeyRow, BaseReferences<_$AppDatabase, $HostKeysTable, HostKeyRow>),
      HostKeyRow,
      PrefetchHooks Function()
    >;
typedef $$SnippetsTableCreateCompanionBuilder = SnippetsCompanion Function({
  required String id,
  required String name,
  required String body,
  Value<int> scope,
  Value<String?> hostId,
  Value<int> defaultRunMode,
  Value<int> sortOrder,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SnippetsTableUpdateCompanionBuilder = SnippetsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> body,
  Value<int> scope,
  Value<String?> hostId,
  Value<int> defaultRunMode,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SnippetsTableFilterComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultRunMode => $composableBuilder(
    column: $table.defaultRunMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SnippetsTableOrderingComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultRunMode => $composableBuilder(
    column: $table.defaultRunMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SnippetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<int> get defaultRunMode => $composableBuilder(
    column: $table.defaultRunMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SnippetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SnippetsTable,
          SnippetRow,
          $$SnippetsTableFilterComposer,
          $$SnippetsTableOrderingComposer,
          $$SnippetsTableAnnotationComposer,
          $$SnippetsTableCreateCompanionBuilder,
          $$SnippetsTableUpdateCompanionBuilder,
          (
            SnippetRow,
            BaseReferences<_$AppDatabase, $SnippetsTable, SnippetRow>,
          ),
          SnippetRow,
          PrefetchHooks Function()
        > {
  $$SnippetsTableTableManager(_$AppDatabase db, $SnippetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnippetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnippetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnippetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> scope = const Value.absent(),
                Value<String?> hostId = const Value.absent(),
                Value<int> defaultRunMode = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion(
                id: id,
                name: name,
                body: body,
                scope: scope,
                hostId: hostId,
                defaultRunMode: defaultRunMode,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String body,
                Value<int> scope = const Value.absent(),
                Value<String?> hostId = const Value.absent(),
                Value<int> defaultRunMode = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion.insert(
                id: id,
                name: name,
                body: body,
                scope: scope,
                hostId: hostId,
                defaultRunMode: defaultRunMode,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SnippetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SnippetsTable,
      SnippetRow,
      $$SnippetsTableFilterComposer,
      $$SnippetsTableOrderingComposer,
      $$SnippetsTableAnnotationComposer,
      $$SnippetsTableCreateCompanionBuilder,
      $$SnippetsTableUpdateCompanionBuilder,
      (SnippetRow, BaseReferences<_$AppDatabase, $SnippetsTable, SnippetRow>),
      SnippetRow,
      PrefetchHooks Function()
    >;
typedef $$MemosTableCreateCompanionBuilder = MemosCompanion Function({
  required String hostId,
  required String body,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$MemosTableUpdateCompanionBuilder = MemosCompanion Function({
  Value<String> hostId,
  Value<String> body,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$MemosTableFilterComposer extends Composer<_$AppDatabase, $MemosTable> {
  $$MemosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemosTableOrderingComposer
    extends Composer<_$AppDatabase, $MemosTable> {
  $$MemosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemosTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemosTable> {
  $$MemosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MemosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemosTable,
          MemoRow,
          $$MemosTableFilterComposer,
          $$MemosTableOrderingComposer,
          $$MemosTableAnnotationComposer,
          $$MemosTableCreateCompanionBuilder,
          $$MemosTableUpdateCompanionBuilder,
          (MemoRow, BaseReferences<_$AppDatabase, $MemosTable, MemoRow>),
          MemoRow,
          PrefetchHooks Function()
        > {
  $$MemosTableTableManager(_$AppDatabase db, $MemosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hostId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemosCompanion(
                hostId: hostId,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hostId,
                required String body,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => MemosCompanion.insert(
                hostId: hostId,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemosTable,
      MemoRow,
      $$MemosTableFilterComposer,
      $$MemosTableOrderingComposer,
      $$MemosTableAnnotationComposer,
      $$MemosTableCreateCompanionBuilder,
      $$MemosTableUpdateCompanionBuilder,
      (MemoRow, BaseReferences<_$AppDatabase, $MemosTable, MemoRow>),
      MemoRow,
      PrefetchHooks Function()
    >;
typedef $$SessionLogsTableCreateCompanionBuilder =
    SessionLogsCompanion Function({
      required String id,
      required String sessionId,
      required String hostId,
      required String hostAlias,
      required int connectionType,
      required String endpoint,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<String?> endReason,
      required String logPath,
      Value<int> byteCount,
      Value<int> lineCount,
      Value<int> rowid,
    });
typedef $$SessionLogsTableUpdateCompanionBuilder =
    SessionLogsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> hostId,
      Value<String> hostAlias,
      Value<int> connectionType,
      Value<String> endpoint,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<String?> endReason,
      Value<String> logPath,
      Value<int> byteCount,
      Value<int> lineCount,
      Value<int> rowid,
    });

class $$SessionLogsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionLogsTable> {
  $$SessionLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostAlias => $composableBuilder(
    column: $table.hostAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logPath => $composableBuilder(
    column: $table.logPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineCount => $composableBuilder(
    column: $table.lineCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionLogsTable> {
  $$SessionLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostAlias => $composableBuilder(
    column: $table.hostAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logPath => $composableBuilder(
    column: $table.logPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteCount => $composableBuilder(
    column: $table.byteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineCount => $composableBuilder(
    column: $table.lineCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionLogsTable> {
  $$SessionLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get hostAlias =>
      $composableBuilder(column: $table.hostAlias, builder: (column) => column);

  GeneratedColumn<int> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get endpoint =>
      $composableBuilder(column: $table.endpoint, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get endReason =>
      $composableBuilder(column: $table.endReason, builder: (column) => column);

  GeneratedColumn<String> get logPath =>
      $composableBuilder(column: $table.logPath, builder: (column) => column);

  GeneratedColumn<int> get byteCount =>
      $composableBuilder(column: $table.byteCount, builder: (column) => column);

  GeneratedColumn<int> get lineCount =>
      $composableBuilder(column: $table.lineCount, builder: (column) => column);
}

class $$SessionLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionLogsTable,
          SessionLogRow,
          $$SessionLogsTableFilterComposer,
          $$SessionLogsTableOrderingComposer,
          $$SessionLogsTableAnnotationComposer,
          $$SessionLogsTableCreateCompanionBuilder,
          $$SessionLogsTableUpdateCompanionBuilder,
          (
            SessionLogRow,
            BaseReferences<_$AppDatabase, $SessionLogsTable, SessionLogRow>,
          ),
          SessionLogRow,
          PrefetchHooks Function()
        > {
  $$SessionLogsTableTableManager(_$AppDatabase db, $SessionLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> hostId = const Value.absent(),
                Value<String> hostAlias = const Value.absent(),
                Value<int> connectionType = const Value.absent(),
                Value<String> endpoint = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<String?> endReason = const Value.absent(),
                Value<String> logPath = const Value.absent(),
                Value<int> byteCount = const Value.absent(),
                Value<int> lineCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionLogsCompanion(
                id: id,
                sessionId: sessionId,
                hostId: hostId,
                hostAlias: hostAlias,
                connectionType: connectionType,
                endpoint: endpoint,
                startedAt: startedAt,
                endedAt: endedAt,
                endReason: endReason,
                logPath: logPath,
                byteCount: byteCount,
                lineCount: lineCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String hostId,
                required String hostAlias,
                required int connectionType,
                required String endpoint,
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<String?> endReason = const Value.absent(),
                required String logPath,
                Value<int> byteCount = const Value.absent(),
                Value<int> lineCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionLogsCompanion.insert(
                id: id,
                sessionId: sessionId,
                hostId: hostId,
                hostAlias: hostAlias,
                connectionType: connectionType,
                endpoint: endpoint,
                startedAt: startedAt,
                endedAt: endedAt,
                endReason: endReason,
                logPath: logPath,
                byteCount: byteCount,
                lineCount: lineCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionLogsTable,
      SessionLogRow,
      $$SessionLogsTableFilterComposer,
      $$SessionLogsTableOrderingComposer,
      $$SessionLogsTableAnnotationComposer,
      $$SessionLogsTableCreateCompanionBuilder,
      $$SessionLogsTableUpdateCompanionBuilder,
      (
        SessionLogRow,
        BaseReferences<_$AppDatabase, $SessionLogsTable, SessionLogRow>,
      ),
      SessionLogRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db, _db.hosts);
  $$HostKeysTableTableManager get hostKeys =>
      $$HostKeysTableTableManager(_db, _db.hostKeys);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db, _db.snippets);
  $$MemosTableTableManager get memos =>
      $$MemosTableTableManager(_db, _db.memos);
  $$SessionLogsTableTableManager get sessionLogs =>
      $$SessionLogsTableTableManager(_db, _db.sessionLogs);
}
