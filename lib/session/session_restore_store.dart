import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../agent/agent_launcher.dart';
import '../core/atomic_file.dart';
import '../data/models/host.dart';
import 'session_group.dart';

class RestoredSessionEntry {
  const RestoredSessionEntry({
    required this.id,
    required this.hostId,
    this.title,
    this.terminalText,
    this.currentWorkingDirectory,
    this.localShellType,
    this.sessionLogId,
    this.groupId = defaultSessionGroupId,
    this.historyPromptDismissed = false,
    this.historyPromptCompleted = false,
    this.pathPromptDismissed = false,
    this.pathPromptCompleted = false,
    this.remoteSessionId,
    this.agentWorkspace,
  });

  final String id;
  final String hostId;
  final String? title;
  final String? terminalText;
  final String? currentWorkingDirectory;
  final LocalShellType? localShellType;
  final String? sessionLogId;
  final String groupId;
  final bool historyPromptDismissed;
  final bool historyPromptCompleted;
  final bool pathPromptDismissed;
  final bool pathPromptCompleted;
  final String? remoteSessionId;
  final AgentWorkspaceContext? agentWorkspace;

  Map<String, Object?> toJson() => {
    'id': id,
    'hostId': hostId,
    if (title != null) 'title': title,
    if (terminalText != null && terminalText!.isNotEmpty)
      'terminalText': terminalText,
    if (currentWorkingDirectory != null && currentWorkingDirectory!.isNotEmpty)
      'currentWorkingDirectory': currentWorkingDirectory,
    if (localShellType != null) 'localShellType': localShellType!.name,
    if (sessionLogId != null && sessionLogId!.isNotEmpty)
      'sessionLogId': sessionLogId,
    if (groupId != defaultSessionGroupId) 'groupId': groupId,
    if (historyPromptDismissed) 'historyPromptDismissed': true,
    if (historyPromptCompleted) 'historyPromptCompleted': true,
    if (pathPromptDismissed) 'pathPromptDismissed': true,
    if (pathPromptCompleted) 'pathPromptCompleted': true,
    if (remoteSessionId != null && remoteSessionId!.isNotEmpty)
      'remoteSessionId': remoteSessionId,
    if (agentWorkspace != null) 'agentWorkspace': agentWorkspace!.toJson(),
  };

  static RestoredSessionEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final hostId = value['hostId'];
    if (id is! String || id.isEmpty || hostId is! String || hostId.isEmpty) {
      return null;
    }
    final title = value['title'];
    final terminalText = value['terminalText'];
    final currentWorkingDirectory = value['currentWorkingDirectory'];
    final localShellType = _localShellTypeFromJson(value['localShellType']);
    final sessionLogId = value['sessionLogId'];
    final groupId = value['groupId'];
    final remoteSessionId = value['remoteSessionId'];
    final agentWorkspace = AgentWorkspaceContext.fromJson(
      value['agentWorkspace'],
    );
    return RestoredSessionEntry(
      id: id,
      hostId: hostId,
      title: title is String ? title : null,
      terminalText: terminalText is String ? terminalText : null,
      currentWorkingDirectory: currentWorkingDirectory is String
          ? currentWorkingDirectory
          : null,
      localShellType: localShellType,
      sessionLogId: sessionLogId is String ? sessionLogId : null,
      groupId: groupId is String && groupId.trim().isNotEmpty
          ? groupId.trim()
          : defaultSessionGroupId,
      historyPromptDismissed: value['historyPromptDismissed'] == true,
      historyPromptCompleted: value['historyPromptCompleted'] == true,
      pathPromptDismissed: value['pathPromptDismissed'] == true,
      pathPromptCompleted: value['pathPromptCompleted'] == true,
      remoteSessionId: remoteSessionId is String && remoteSessionId.isNotEmpty
          ? remoteSessionId
          : null,
      agentWorkspace: agentWorkspace,
    );
  }

  static LocalShellType? _localShellTypeFromJson(Object? value) {
    if (value is! String) return null;
    for (final type in LocalShellType.values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

class SessionRestoreSnapshot {
  const SessionRestoreSnapshot({
    required this.sessions,
    this.activeId,
    this.groups = const [SessionGroup.defaultGroup],
    this.activeGroupId = defaultSessionGroupId,
  });

  static const empty = SessionRestoreSnapshot(sessions: []);

  final List<RestoredSessionEntry> sessions;
  final String? activeId;
  final List<SessionGroup> groups;
  final String activeGroupId;

  SessionRestoreSnapshot copyWith({
    List<RestoredSessionEntry>? sessions,
    Object? activeId = _unchanged,
    List<SessionGroup>? groups,
    String? activeGroupId,
  }) => SessionRestoreSnapshot(
    sessions: sessions ?? this.sessions,
    activeId: identical(activeId, _unchanged)
        ? this.activeId
        : activeId as String?,
    groups: groups ?? this.groups,
    activeGroupId: activeGroupId ?? this.activeGroupId,
  );

  static const Object _unchanged = Object();

  Map<String, Object?> toJson() => {
    'version': 5,
    'activeId': activeId,
    'activeGroupId': activeGroupId,
    'groups': [for (final group in groups) group.toJson()],
    'sessions': [for (final session in sessions) session.toJson()],
  };

  static SessionRestoreSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawSessions = value['sessions'];
    if (rawSessions is! List) return null;
    final sessions = rawSessions
        .map(RestoredSessionEntry.fromJson)
        .whereType<RestoredSessionEntry>()
        .toList();
    final activeId = value['activeId'];
    final rawGroups = value['groups'];
    final groups = normalizeSessionGroups(
      rawGroups is List
          ? rawGroups.map(SessionGroup.fromJson).whereType<SessionGroup>()
          : const <SessionGroup>[],
      requiredIds: sessions.map((session) => session.groupId),
    );
    final activeGroupId = value['activeGroupId'];
    return SessionRestoreSnapshot(
      sessions: sessions,
      activeId: activeId is String && activeId.isNotEmpty ? activeId : null,
      groups: groups,
      activeGroupId:
          activeGroupId is String &&
              groups.any((group) => group.id == activeGroupId)
          ? activeGroupId
          : defaultSessionGroupId,
    );
  }
}

class SessionRestoreStore {
  Future<void> _pendingWrite = Future<void>.value();

  Future<File> _snapshotFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}sessions.json');
  }

  Future<SessionRestoreSnapshot?> load() async {
    try {
      final file = await _snapshotFile();
      if (!file.existsSync()) return null;
      return SessionRestoreSnapshot.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SessionRestoreSnapshot snapshot) {
    _pendingWrite = _pendingWrite.then(
      (_) => _write(snapshot),
      onError: (_) => _write(snapshot),
    );
    return _pendingWrite;
  }

  Future<void> saveActiveId(String? activeId) async {
    try {
      await _pendingWrite;
    } catch (_) {
      // 다음 load/save로 복구를 시도한다.
    }
    final current = await load() ?? SessionRestoreSnapshot.empty;
    await save(current.copyWith(activeId: activeId));
  }

  Future<void> saveGroupState(
    List<SessionGroup> groups,
    String activeGroupId,
  ) async {
    try {
      await _pendingWrite;
    } catch (_) {
      // 다음 load/save로 복구를 시도한다.
    }
    final current = await load() ?? SessionRestoreSnapshot.empty;
    await save(current.copyWith(groups: groups, activeGroupId: activeGroupId));
  }

  Future<void> _write(SessionRestoreSnapshot snapshot) async {
    try {
      final file = await _snapshotFile();
      final hasDefaultGroupState =
          snapshot.groups.length == 1 &&
          snapshot.groups.single.id == defaultSessionGroupId &&
          snapshot.activeGroupId == defaultSessionGroupId;
      if (snapshot.sessions.isEmpty &&
          snapshot.activeId == null &&
          hasDefaultGroupState) {
        if (file.existsSync()) await file.delete();
        return;
      }
      // 원자적으로 바꾼다. 앱이 쓰는 도중 종료돼도 다음 실행에서 잘린
      // 스냅샷을 읽어 세션 복원이 통째로 실패하는 일이 없게 한다.
      await writeFileAtomically(
        file,
        const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      );
    } catch (_) {
      // 세션 복원 정보는 보조 기능이다. 실패해도 런타임 세션은 계속 동작한다.
    }
  }
}
