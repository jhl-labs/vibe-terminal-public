import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../agent/agent_launcher.dart';
import '../core/atomic_file.dart';
import '../data/models/host.dart';
import 'session_group.dart';
import 'session_tab_group.dart';
import '../settings/terminal_preferences.dart';

class RestoredSessionEntry {
  const RestoredSessionEntry({
    required this.id,
    required this.hostId,
    this.authorizationId,
    this.title,
    this.terminalText,
    this.currentWorkingDirectory,
    this.localShellType,
    this.sessionLogId,
    this.groupId = defaultSessionGroupId,
    this.tabGroupId,
    this.historyPromptDismissed = false,
    this.historyPromptCompleted = false,
    this.pathPromptDismissed = false,
    this.pathPromptCompleted = false,
    this.remoteSessionId,
    this.localSessionId,
    this.agentWorkspace,
    this.terminalPreferences,
    this.terminalDefaults,
  });

  final TerminalPreferences? terminalPreferences;
  final TerminalPreferences? terminalDefaults;
  final String id;
  final String hostId;
  final String? authorizationId;
  final String? title;
  final String? terminalText;
  final String? currentWorkingDirectory;
  final LocalShellType? localShellType;
  final String? sessionLogId;
  final String groupId;

  /// 작업공간 안 탭 그룹 id. 없으면 그룹 없는 탭. 이전 버전 스냅샷에는 없다.
  final String? tabGroupId;
  final bool historyPromptDismissed;
  final bool historyPromptCompleted;
  final bool pathPromptDismissed;
  final bool pathPromptCompleted;
  final String? remoteSessionId;
  final String? localSessionId;
  final AgentWorkspaceContext? agentWorkspace;

  Map<String, Object?> toJson() => {
    'id': id,
    'hostId': hostId,
    if (authorizationId != null) 'authorizationId': authorizationId,
    if (terminalPreferences != null)
      'terminalPreferences': terminalPreferences!.toJson(),
    if (terminalDefaults != null)
      'terminalDefaults': terminalDefaults!.toJson(),
    if (localSessionId != null) 'localSessionId': localSessionId,
    if (title != null) 'title': title,
    if (terminalText != null && terminalText!.isNotEmpty)
      'terminalText': terminalText,
    if (currentWorkingDirectory != null && currentWorkingDirectory!.isNotEmpty)
      'currentWorkingDirectory': currentWorkingDirectory,
    if (localShellType != null) 'localShellType': localShellType!.name,
    if (sessionLogId != null && sessionLogId!.isNotEmpty)
      'sessionLogId': sessionLogId,
    if (groupId != defaultSessionGroupId) 'groupId': groupId,
    if (tabGroupId != null) 'tabGroupId': tabGroupId,
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
    final tabGroupId = value['tabGroupId'];
    final remoteSessionId = value['remoteSessionId'];
    final agentWorkspace = AgentWorkspaceContext.fromJson(
      value['agentWorkspace'],
    );
    return RestoredSessionEntry(
      id: id,
      hostId: hostId,
      authorizationId:
          value['authorizationId'] is String &&
              RegExp(
                r'^[A-Za-z0-9_-]{22}==$',
              ).hasMatch(value['authorizationId'] as String)
          ? value['authorizationId'] as String
          : null,
      localSessionId: value['localSessionId'] is String
          ? value['localSessionId'] as String
          : null,
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
      tabGroupId: tabGroupId is String && tabGroupId.trim().isNotEmpty
          ? tabGroupId.trim()
          : null,
      historyPromptDismissed: value['historyPromptDismissed'] == true,
      historyPromptCompleted: value['historyPromptCompleted'] == true,
      pathPromptDismissed: value['pathPromptDismissed'] == true,
      pathPromptCompleted: value['pathPromptCompleted'] == true,
      remoteSessionId: remoteSessionId is String && remoteSessionId.isNotEmpty
          ? remoteSessionId
          : null,
      agentWorkspace: agentWorkspace,
      terminalPreferences: value['terminalPreferences'] is Map
          ? TerminalPreferences.fromJson(value['terminalPreferences'])
          : null,
      terminalDefaults: value['terminalDefaults'] is Map
          ? TerminalPreferences.fromJson(value['terminalDefaults'])
          : null,
    );
  }

  /// 탭 그룹 소속만 지운 정확한 사본. 스냅샷을 읽을 때 유효하지 않은 소속을
  /// 지운다. 저장 형식을 거치지 않으므로 값이 정규화되거나 빠지지 않는다.
  ///
  /// 필드를 추가하면 이 생성자 호출에도 넣어야 한다. 모든 필드가 그대로
  /// 복사되는지는 테스트(`withoutTabGroup은 소속 외 모든 필드를…`)가 확인한다.
  RestoredSessionEntry withoutTabGroup() => RestoredSessionEntry(
    id: id,
    hostId: hostId,
    authorizationId: authorizationId,
    title: title,
    terminalText: terminalText,
    currentWorkingDirectory: currentWorkingDirectory,
    localShellType: localShellType,
    sessionLogId: sessionLogId,
    groupId: groupId,
    historyPromptDismissed: historyPromptDismissed,
    historyPromptCompleted: historyPromptCompleted,
    pathPromptDismissed: pathPromptDismissed,
    pathPromptCompleted: pathPromptCompleted,
    remoteSessionId: remoteSessionId,
    localSessionId: localSessionId,
    agentWorkspace: agentWorkspace,
    terminalPreferences: terminalPreferences,
    terminalDefaults: terminalDefaults,
  );

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
    this.tabGroups = const [],
  });

  static const empty = SessionRestoreSnapshot(sessions: []);

  final List<RestoredSessionEntry> sessions;
  final String? activeId;
  final List<SessionGroup> groups;
  final String activeGroupId;

  /// 작업공간 안의 탭 그룹(이름·색·접힘). 소속은 각 세션 항목의 tabGroupId.
  final List<SessionTabGroup> tabGroups;

  SessionRestoreSnapshot copyWith({
    List<RestoredSessionEntry>? sessions,
    Object? activeId = _unchanged,
    List<SessionGroup>? groups,
    String? activeGroupId,
    List<SessionTabGroup>? tabGroups,
  }) => SessionRestoreSnapshot(
    sessions: sessions ?? this.sessions,
    activeId: identical(activeId, _unchanged)
        ? this.activeId
        : activeId as String?,
    groups: groups ?? this.groups,
    activeGroupId: activeGroupId ?? this.activeGroupId,
    tabGroups: tabGroups ?? this.tabGroups,
  );

  static const Object _unchanged = Object();

  Map<String, Object?> toJson() => {
    'version': 6,
    'activeId': activeId,
    'activeGroupId': activeGroupId,
    'groups': [for (final group in groups) group.toJson()],
    if (tabGroups.isNotEmpty)
      'tabGroups': [for (final group in tabGroups) group.toJson()],
    'sessions': [for (final session in sessions) session.toJson()],
  };

  static SessionRestoreSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawSessions = value['sessions'];
    if (rawSessions is! List) return null;
    final rawTabGroups = value['tabGroups'];
    final (sessions, tabGroups) = _validTabGroups(
      rawSessions
          .map(RestoredSessionEntry.fromJson)
          .whereType<RestoredSessionEntry>()
          .toList(),
      rawTabGroups is List
          ? normalizeSessionTabGroups(
              rawTabGroups
                  .map(SessionTabGroup.fromJson)
                  .whereType<SessionTabGroup>(),
            )
          : const <SessionTabGroup>[],
    );
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
      tabGroups: tabGroups,
    );
  }

  /// 세션의 탭 그룹 소속은 같은 작업공간의 저장된 그룹을 가리킬 때만 남긴다.
  /// 멤버가 없는 탭 그룹은 버린다. 이전 버전 스냅샷(필드 없음)은 그대로
  /// "그룹 없음"이 된다.
  static (List<RestoredSessionEntry>, List<SessionTabGroup>) _validTabGroups(
    List<RestoredSessionEntry> sessions,
    List<SessionTabGroup> tabGroups,
  ) {
    final byId = {for (final group in tabGroups) group.id: group};
    final usedIds = <String>{};
    final validSessions = <RestoredSessionEntry>[];
    for (final session in sessions) {
      final id = session.tabGroupId;
      if (id == null) {
        validSessions.add(session);
      } else if (byId[id]?.workspaceGroupId == session.groupId) {
        usedIds.add(id);
        validSessions.add(session);
      } else {
        validSessions.add(session.withoutTabGroup());
      }
    }
    return (
      validSessions,
      [
        for (final group in tabGroups)
          if (usedIds.contains(group.id)) group,
      ],
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
