import '../agent/agent_launcher.dart';
import '../core/result.dart';
import '../data/models/host.dart';
import '../terminal/terminal_engine.dart';
import 'session_group.dart';

enum SessionStatus { connecting, connected, disconnected, error }

const Object _unchanged = Object();

extension SessionStatusLabel on SessionStatus {
  String get label => switch (this) {
    SessionStatus.connecting => '연결 중',
    SessionStatus.connected => '연결됨',
    SessionStatus.disconnected => '연결 끊김',
    SessionStatus.error => '오류',
  };
}

class RestoredSessionContext {
  const RestoredSessionContext({
    this.logId,
    this.workingDirectory,
    this.summaryPromptDismissed = false,
    this.summaryPromptCompleted = false,
    this.pathPromptDismissed = false,
    this.pathPromptCompleted = false,
  });

  final String? logId;
  final String? workingDirectory;
  final bool summaryPromptDismissed;
  final bool summaryPromptCompleted;
  final bool pathPromptDismissed;
  final bool pathPromptCompleted;

  bool get hasLog => logId != null && logId!.trim().isNotEmpty;

  bool get hasWorkingDirectory =>
      workingDirectory != null && workingDirectory!.trim().isNotEmpty;

  bool get shouldOfferSummary =>
      hasLog && !summaryPromptDismissed && !summaryPromptCompleted;

  bool get shouldOfferPathRestore =>
      hasWorkingDirectory &&
      summaryPromptCompleted &&
      !pathPromptDismissed &&
      !pathPromptCompleted;

  RestoredSessionContext copyWith({
    Object? logId = _unchanged,
    Object? workingDirectory = _unchanged,
    bool? summaryPromptDismissed,
    bool? summaryPromptCompleted,
    bool? pathPromptDismissed,
    bool? pathPromptCompleted,
  }) => RestoredSessionContext(
    logId: identical(logId, _unchanged) ? this.logId : logId as String?,
    workingDirectory: identical(workingDirectory, _unchanged)
        ? this.workingDirectory
        : workingDirectory as String?,
    summaryPromptDismissed:
        summaryPromptDismissed ?? this.summaryPromptDismissed,
    summaryPromptCompleted:
        summaryPromptCompleted ?? this.summaryPromptCompleted,
    pathPromptDismissed: pathPromptDismissed ?? this.pathPromptDismissed,
    pathPromptCompleted: pathPromptCompleted ?? this.pathPromptCompleted,
  );
}

/// 활성 SSH 세션 하나의 런타임 상태.
class SessionInfo {
  SessionInfo({
    required this.id,
    required this.host,
    required this.engine,
    this.status = SessionStatus.connecting,
    this.error,
    this.failure,
    this.title,
    this.connectedAt,
    this.restoredContext,
    this.groupId = defaultSessionGroupId,
    this.remoteSessionId,
    this.fellBackToDirectSsh = false,
    this.agentWorkspace,
  });

  final String id;
  final Host host;
  final TerminalEngine engine;
  final SessionStatus status;
  final String? error;
  final Failure? failure;
  final String? title;

  /// 가장 최근에 connected 상태가 된 시각. 연결 지속 시간(uptime) 계산에 사용.
  /// 재연결 시 갱신되며, connected가 아니면 null일 수 있다.
  final DateTime? connectedAt;
  final RestoredSessionContext? restoredContext;
  final String groupId;

  /// 앱 재시작 뒤에도 같은 원격 tmux 세션을 찾기 위한 영속 식별자.
  /// 살아 있는 SSH/PTY 핸들이 아니라 복원 스냅샷에 저장 가능한 문자열이다.
  final String? remoteSessionId;

  /// 작업 이어가기를 요청했지만 서버에 tmux가 없어 이번 연결만 일반 SSH로
  /// 동작하는 상태. 호스트 설정이 아니라 현재 연결의 실제 기능 상태다.
  final bool fellBackToDirectSsh;

  /// 앱에서 시작한 Agent와 격리 worktree의 복원 가능한 실행 메타데이터.
  final AgentWorkspaceContext? agentWorkspace;

  String get displayName {
    final cleaned = title?.trim();
    if (cleaned != null && cleaned.isNotEmpty) return cleaned;
    return host.alias;
  }

  SessionInfo copyWith({
    SessionStatus? status,
    Object? error = _unchanged,
    Failure? failure,
    Object? title = _unchanged,
    Object? connectedAt = _unchanged,
    Object? restoredContext = _unchanged,
    String? groupId,
    Object? remoteSessionId = _unchanged,
    bool? fellBackToDirectSsh,
    Object? agentWorkspace = _unchanged,
  }) => SessionInfo(
    id: id,
    host: host,
    engine: engine,
    status: status ?? this.status,
    error: identical(error, _unchanged) ? this.error : error as String?,
    failure: failure ?? this.failure,
    title: identical(title, _unchanged) ? this.title : title as String?,
    connectedAt: identical(connectedAt, _unchanged)
        ? this.connectedAt
        : connectedAt as DateTime?,
    restoredContext: identical(restoredContext, _unchanged)
        ? this.restoredContext
        : restoredContext as RestoredSessionContext?,
    groupId: groupId ?? this.groupId,
    remoteSessionId: identical(remoteSessionId, _unchanged)
        ? this.remoteSessionId
        : remoteSessionId as String?,
    fellBackToDirectSsh: fellBackToDirectSsh ?? this.fellBackToDirectSsh,
    agentWorkspace: identical(agentWorkspace, _unchanged)
        ? this.agentWorkspace
        : agentWorkspace as AgentWorkspaceContext?,
  );
}
