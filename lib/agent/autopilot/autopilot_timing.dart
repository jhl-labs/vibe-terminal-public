/// 자동 재개의 시간 상수. 테스트에서 짧게 바꿔 끼운다.
class AutopilotTiming {
  const AutopilotTiming({
    this.settleDelay = const Duration(seconds: 15),
    this.minJudgeInterval = const Duration(seconds: 60),
    this.userInputGrace = const Duration(seconds: 20),
    this.tuiReadyTimeout = const Duration(seconds: 30),
    this.tuiReadyPoll = const Duration(milliseconds: 500),
    this.submitDelay = const Duration(milliseconds: 300),
    this.errorCooldown = const Duration(seconds: 60),
    this.maxAttempts = 3,
    this.approvalSettle = const Duration(milliseconds: 1500),
    this.approvalVerify = const Duration(seconds: 2),
    this.approvalFailureCooldown = const Duration(minutes: 5),
    this.maxApprovals = 50,
    this.usageResetMargin = const Duration(minutes: 1),
    this.usageRetryInterval = const Duration(minutes: 30),
    this.usageMaxWait = const Duration(hours: 12),
  });

  /// idle 전이 뒤 이만큼 더 조용해야 판정한다. 정상 턴 종료 직후 사용자가 다음
  /// 지시를 치는 흐름과 겹치지 않게 하고 LLM 호출 수를 줄인다.
  final Duration settleDelay;

  /// 같은 세션에 대한 LLM 판정 최소 간격.
  final Duration minJudgeInterval;

  /// 사용자가 이 세션에 키를 친 뒤 이만큼은 개입하지 않는다.
  final Duration userInputGrace;

  /// 재실행 뒤 TUI 입력창이 뜨기를 기다리는 최대 시간.
  final Duration tuiReadyTimeout;
  final Duration tuiReadyPoll;

  /// 텍스트를 넣고 Enter를 치기까지의 간격(TUI가 붙여넣기를 처리할 시간).
  final Duration submitDelay;

  /// 판정 LLM 호출이 실패했을 때 다음 판정까지의 쿨다운.
  final Duration errorCooldown;

  /// 한 작업(사용자 프롬프트 제출 사이)에서 재개하는 최대 횟수.
  final int maxAttempts;

  /// 화면이 멈춘 뒤 승인 프롬프트를 해석하기까지 기다리는 시간. 안정화는 이
  /// 시간을 포함하므로 [settleDelay]보다 길 수 없다(컨트롤러가 assert).
  final Duration approvalSettle;

  /// 승인 키를 보낸 뒤 프롬프트가 사라졌는지 확인하는 시간.
  final Duration approvalVerify;

  /// 승인 키가 먹히지 않았을 때 그 세션의 자동 승인을 쉬는 시간.
  final Duration approvalFailureCooldown;

  /// 한 작업에서 자동 승인하는 최대 횟수.
  final int maxApprovals;

  /// 한도 리셋 시각 뒤 여유.
  final Duration usageResetMargin;

  /// 리셋 시각을 못 읽었을 때 재시도 간격.
  final Duration usageRetryInterval;

  /// 한도 대기를 포기하기까지의 최대 시간.
  final Duration usageMaxWait;

  /// 재개 전 백오프. 오케스트레이터의 provider 재시도와 같은 단계다.
  Duration backoff(int attempt) {
    const steps = [5, 15, 30, 60];
    return Duration(seconds: steps[attempt.clamp(1, steps.length) - 1]);
  }
}
