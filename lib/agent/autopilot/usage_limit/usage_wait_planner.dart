import '../autopilot_state.dart';
import '../autopilot_timing.dart';
import 'usage_limit_parser.dart';

/// 한도 문구를 본 뒤 무엇을 할지. 게이트·타이머·입력은 컨트롤러가 맡는다.
sealed class UsageWaitDecision {
  const UsageWaitDecision();
}

/// 대기 시작부터 [AutopilotTiming.usageMaxWait]를 넘는다. 포기하고 알린다.
final class UsageGiveUp extends UsageWaitDecision {
  const UsageGiveUp();
}

/// 알림만 모드. [notify]면 이번 감지를 알린다(같은 대기에서는 한 번만).
final class UsageNotifyOnly extends UsageWaitDecision {
  const UsageNotifyOnly({required this.wakeAt, required this.notify});

  final DateTime wakeAt;
  final bool notify;
}

/// [wakeAt]에 재개한다. [startedAt]은 대기 연장 체인의 시작 시각.
/// [notifyStart]면 새 대기의 시작이라 사람에게 알린다.
final class UsageWait extends UsageWaitDecision {
  const UsageWait({
    required this.wakeAt,
    required this.startedAt,
    required this.notifyStart,
  });

  final DateTime wakeAt;
  final DateTime startedAt;
  final bool notifyStart;
}

/// 사용량 한도 대기 계획(§6.3). 순수 함수.
///
/// 재개 시각 = 리셋 시각 + 여유, 모르면 now + 재시도 간격. 재개 뒤 다시 한도면
/// [AutopilotState.usageWaitStartedAt]을 유지해 같은 대기의 연장으로 센다.
class UsageWaitPlanner {
  const UsageWaitPlanner();

  UsageWaitDecision plan(
    AutopilotState state,
    UsageLimitHit hit,
    DateTime now,
    AutopilotTiming timing,
  ) {
    final startedAt = state.usageWaitStartedAt ?? now;
    final wakeAt =
        hit.resetAt?.add(timing.usageResetMargin) ??
        now.add(timing.usageRetryInterval);
    if (wakeAt.difference(startedAt) > timing.usageMaxWait) {
      return const UsageGiveUp();
    }
    if (state.notifyOnly) {
      return UsageNotifyOnly(
        wakeAt: wakeAt,
        notify: state.usageResetAt == null,
      );
    }
    return UsageWait(
      wakeAt: wakeAt,
      startedAt: startedAt,
      notifyStart: state.usageWaitStartedAt == null,
    );
  }
}
