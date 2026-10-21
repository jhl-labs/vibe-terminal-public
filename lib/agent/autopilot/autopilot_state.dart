import '../agent_launcher.dart';

/// 자율사용 컨트롤러가 세션 하나에 대해 지금 무엇을 하고 있는지.
enum AutopilotPhase {
  /// 켜져 있지만 개입할 일이 없다.
  idle,

  /// idle 전이를 봤고, 정상 턴 종료와 구분하려고 안정화 시간을 기다린다.
  settling,

  /// 로컬·LLM 판정 중.
  judging,

  /// 중단으로 판정했고 백오프 뒤 재개한다.
  waitingBackoff,

  /// 재개 명령을 보내는 중(TUI 준비 대기 포함).
  resuming,

  /// 승인 키를 보내고 프롬프트가 사라졌는지 확인하는 중.
  approving,

  /// 사용량 한도 리셋을 기다린다. [AutopilotState.usageResetAt]에 재개한다.
  waitingUsageReset,

  /// 이번 작업에서 재개 한도에 도달했다. 사용자가 새 프롬프트를 제출하면 풀린다.
  exhausted,
}

/// 판정 결과의 종류. `interrupted`만 재개 대상이다.
enum ResumeStatus { completed, interrupted, waitingUser, working, unknown }

/// Agent 프로세스가 아직 TUI로 살아 있는지, 셸로 돌아갔는지.
enum ResumeProcess { tuiAlive, exited, unknown }

/// 판정이 어디서 나왔는지. 진단 로그와 UI 툴팁에 쓴다.
enum ResumeVerdictSource { local, llm, error }

extension ResumeVerdictSourceLabel on ResumeVerdictSource {
  String get label => switch (this) {
    ResumeVerdictSource.local => '오류 문구',
    ResumeVerdictSource.llm => 'LLM',
    ResumeVerdictSource.error => '판정 실패',
  };
}

class ResumeVerdict {
  const ResumeVerdict({
    required this.status,
    required this.confidence,
    required this.process,
    required this.reason,
    required this.evidence,
    required this.source,
    required this.at,
  });

  final ResumeStatus status;

  /// 0.0–1.0. 로컬 판정은 1.0.
  final double confidence;
  final ResumeProcess process;
  final String reason;

  /// 화면에서 그대로 인용한 근거 줄. LLM 판정은 실제 화면에 존재해야 한다.
  final String evidence;
  final ResumeVerdictSource source;
  final DateTime at;

  bool get isInterrupted => status == ResumeStatus.interrupted;

  ResumeVerdict copyWith({ResumeProcess? process}) => ResumeVerdict(
    status: status,
    confidence: confidence,
    process: process ?? this.process,
    reason: reason,
    evidence: evidence,
    source: source,
    at: at,
  );

  @override
  String toString() =>
      '${status.name} (${(confidence * 100).round()}%, ${process.name}, '
      '${source.name}): $reason';
}

/// 세션 하나의 자율사용 상태. [enabled]가 false면 나머지는 무시된다.
class AutopilotState {
  const AutopilotState({
    this.enabled = false,
    this.notifyOnly = false,
    this.cli,
    this.resumeAttempt = 0,
    this.phase = AutopilotPhase.idle,
    this.cooldownUntil,
    this.lastJudgedAt,
    this.lastVerdict,
    this.approvalCount = 0,
    this.usageResetAt,
    this.usageWaitStartedAt,
    this.lastAction,
  });

  final bool enabled;

  /// 판정은 하되 재개하지 않고 알림만 보낸다(오탐률을 실사용에서 보는 모드).
  final bool notifyOnly;

  /// 켤 때 확정한 CLI. 재개 명령 구성에 쓴다.
  final AgentCli? cli;

  /// 현재 작업에서 재개한 횟수. 사용자가 새 프롬프트를 제출하면 0으로 돌아간다.
  final int resumeAttempt;
  final AutopilotPhase phase;

  /// 이 시각 전에는 판정하지 않는다(백오프·판정 실패 쿨다운).
  final DateTime? cooldownUntil;
  final DateTime? lastJudgedAt;
  final ResumeVerdict? lastVerdict;

  /// 현재 작업에서 자동 승인한 횟수. 새 프롬프트 제출로 0.
  final int approvalCount;

  /// 한도 대기 중 재개 예정 시각.
  final DateTime? usageResetAt;

  /// 이번 한도 대기를 시작한 시각(최대 대기 계산용). 재개 후 다시 한도면 유지된다.
  final DateTime? usageWaitStartedAt;

  /// 마지막으로 한 일(배지 확장 영역 한 줄).
  final String? lastAction;

  bool get isActive =>
      phase == AutopilotPhase.judging ||
      phase == AutopilotPhase.waitingBackoff ||
      phase == AutopilotPhase.resuming ||
      phase == AutopilotPhase.approving ||
      phase == AutopilotPhase.waitingUsageReset;

  /// 세션 타일 배지 툴팁용 한 줄.
  String get statusLabel {
    final mode = notifyOnly ? '알림만' : '자율';
    final phaseText = switch (phase) {
      AutopilotPhase.idle => '대기',
      AutopilotPhase.settling => '안정화 대기',
      AutopilotPhase.judging => '판정 중',
      AutopilotPhase.waitingBackoff => '재개 대기 #$resumeAttempt',
      AutopilotPhase.resuming => '재개 중 #$resumeAttempt',
      AutopilotPhase.approving => '승인 중',
      AutopilotPhase.waitingUsageReset => '한도 대기 · ${_hhmm(usageResetAt)} 재개',
      AutopilotPhase.exhausted => '한도 도달',
    };
    return [
      mode,
      phaseText,
      if (phase != AutopilotPhase.waitingUsageReset && approvalCount > 0)
        '승인 $approvalCount회',
      if (phase == AutopilotPhase.idle && resumeAttempt > 0)
        '재개 $resumeAttempt회',
    ].join(' · ');
  }

  static String _hhmm(DateTime? at) => at == null
      ? '?'
      : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  AutopilotState copyWith({
    bool? enabled,
    bool? notifyOnly,
    AgentCli? cli,
    int? resumeAttempt,
    AutopilotPhase? phase,
    Object? cooldownUntil = _unchanged,
    Object? lastJudgedAt = _unchanged,
    Object? lastVerdict = _unchanged,
    int? approvalCount,
    Object? usageResetAt = _unchanged,
    Object? usageWaitStartedAt = _unchanged,
    Object? lastAction = _unchanged,
  }) => AutopilotState(
    enabled: enabled ?? this.enabled,
    notifyOnly: notifyOnly ?? this.notifyOnly,
    cli: cli ?? this.cli,
    resumeAttempt: resumeAttempt ?? this.resumeAttempt,
    phase: phase ?? this.phase,
    cooldownUntil: identical(cooldownUntil, _unchanged)
        ? this.cooldownUntil
        : cooldownUntil as DateTime?,
    lastJudgedAt: identical(lastJudgedAt, _unchanged)
        ? this.lastJudgedAt
        : lastJudgedAt as DateTime?,
    lastVerdict: identical(lastVerdict, _unchanged)
        ? this.lastVerdict
        : lastVerdict as ResumeVerdict?,
    approvalCount: approvalCount ?? this.approvalCount,
    usageResetAt: identical(usageResetAt, _unchanged)
        ? this.usageResetAt
        : usageResetAt as DateTime?,
    usageWaitStartedAt: identical(usageWaitStartedAt, _unchanged)
        ? this.usageWaitStartedAt
        : usageWaitStartedAt as DateTime?,
    lastAction: identical(lastAction, _unchanged)
        ? this.lastAction
        : lastAction as String?,
  );

  static const _unchanged = Object();
}
