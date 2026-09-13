import 'agent_launcher.dart';

enum AgentWorktreeLifecycle { provisioning, active, stranded, missing }

enum AgentWorktreeGitState { unknown, cleanUnmerged, dirty, merged }

class AgentWorktreeRecord {
  const AgentWorktreeRecord({
    required this.id,
    required this.hostId,
    required this.hostAlias,
    required this.groupId,
    required this.cli,
    required this.arguments,
    required this.branchName,
    required this.baseRef,
    required this.repositoryRoot,
    required this.worktreePath,
    required this.createdAt,
    required this.lifecycle,
    this.gitState = AgentWorktreeGitState.unknown,
    this.sessionId,
    this.lastInspectedAt,
    this.lastError,
  });

  final String id;
  final String hostId;
  final String hostAlias;
  final String groupId;
  final AgentCli cli;
  final List<String> arguments;
  final String branchName;
  final String baseRef;
  final String repositoryRoot;
  final String worktreePath;
  final DateTime createdAt;
  final AgentWorktreeLifecycle lifecycle;
  final AgentWorktreeGitState gitState;
  final String? sessionId;
  final DateTime? lastInspectedAt;
  final String? lastError;

  bool get canSafelyRemove =>
      lifecycle != AgentWorktreeLifecycle.active &&
      (lifecycle == AgentWorktreeLifecycle.missing ||
          gitState == AgentWorktreeGitState.merged);

  AgentWorkspaceContext toWorkspaceContext() => AgentWorkspaceContext(
    cli: cli,
    isolatedWorktree: true,
    branchName: branchName,
    arguments: List.unmodifiable(arguments),
    workspaceId: id,
    repositoryRoot: repositoryRoot,
    worktreePath: worktreePath,
    baseRef: baseRef,
  );

  AgentWorktreeRecord copyWith({
    AgentWorktreeLifecycle? lifecycle,
    AgentWorktreeGitState? gitState,
    Object? sessionId = _unchanged,
    Object? lastInspectedAt = _unchanged,
    Object? lastError = _unchanged,
  }) => AgentWorktreeRecord(
    id: id,
    hostId: hostId,
    hostAlias: hostAlias,
    groupId: groupId,
    cli: cli,
    arguments: arguments,
    branchName: branchName,
    baseRef: baseRef,
    repositoryRoot: repositoryRoot,
    worktreePath: worktreePath,
    createdAt: createdAt,
    lifecycle: lifecycle ?? this.lifecycle,
    gitState: gitState ?? this.gitState,
    sessionId: identical(sessionId, _unchanged)
        ? this.sessionId
        : sessionId as String?,
    lastInspectedAt: identical(lastInspectedAt, _unchanged)
        ? this.lastInspectedAt
        : lastInspectedAt as DateTime?,
    lastError: identical(lastError, _unchanged)
        ? this.lastError
        : lastError as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'hostId': hostId,
    'hostAlias': hostAlias,
    'groupId': groupId,
    'cli': cli.name,
    if (arguments.isNotEmpty) 'arguments': arguments,
    'branchName': branchName,
    'baseRef': baseRef,
    'repositoryRoot': repositoryRoot,
    'worktreePath': worktreePath,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lifecycle': lifecycle.name,
    'gitState': gitState.name,
    if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
    if (lastInspectedAt != null)
      'lastInspectedAt': lastInspectedAt!.toUtc().toIso8601String(),
    if (lastError != null && lastError!.isNotEmpty) 'lastError': lastError,
  };

  static AgentWorktreeRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final hostId = value['hostId'];
    final hostAlias = value['hostAlias'];
    final groupId = value['groupId'];
    final branchName = value['branchName'];
    final baseRef = value['baseRef'];
    final repositoryRoot = value['repositoryRoot'];
    final worktreePath = value['worktreePath'];
    final createdAt = value['createdAt'];
    final cli = _enumByName(AgentCli.values, value['cli']);
    final lifecycle = _enumByName(
      AgentWorktreeLifecycle.values,
      value['lifecycle'],
    );
    final gitState = _enumByName(
      AgentWorktreeGitState.values,
      value['gitState'],
    );
    final parsedCreatedAt = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    if (id is! String ||
        id.isEmpty ||
        hostId is! String ||
        hostId.isEmpty ||
        hostAlias is! String ||
        groupId is! String ||
        groupId.isEmpty ||
        branchName is! String ||
        branchName.isEmpty ||
        baseRef is! String ||
        baseRef.isEmpty ||
        repositoryRoot is! String ||
        repositoryRoot.isEmpty ||
        worktreePath is! String ||
        worktreePath.isEmpty ||
        parsedCreatedAt == null ||
        cli == null ||
        lifecycle == null) {
      return null;
    }
    final rawArguments = value['arguments'];
    final lastInspectedAt = value['lastInspectedAt'];
    final lastError = value['lastError'];
    final sessionId = value['sessionId'];
    return AgentWorktreeRecord(
      id: id,
      hostId: hostId,
      hostAlias: hostAlias,
      groupId: groupId,
      cli: cli,
      arguments: rawArguments is List
          ? [
              for (final item in rawArguments)
                if (item is String) item,
            ]
          : const [],
      branchName: branchName,
      baseRef: baseRef,
      repositoryRoot: repositoryRoot,
      worktreePath: worktreePath,
      createdAt: parsedCreatedAt,
      lifecycle: lifecycle,
      gitState: gitState ?? AgentWorktreeGitState.unknown,
      sessionId: sessionId is String && sessionId.isNotEmpty ? sessionId : null,
      lastInspectedAt: lastInspectedAt is String
          ? DateTime.tryParse(lastInspectedAt)
          : null,
      lastError: lastError is String && lastError.isNotEmpty ? lastError : null,
    );
  }

  static T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static const Object _unchanged = Object();
}
