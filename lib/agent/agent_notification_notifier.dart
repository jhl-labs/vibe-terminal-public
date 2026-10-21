import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'agent_chat_notifier.dart';
import 'agent_models.dart';

/// Agent Chat loop가 사람을 기다리거나 끝났을 때 시스템 알림을 보낸다.
///
/// 패널의 배지는 앱을 보고 있을 때만 의미가 있다. 예약으로 시작한 loop는 사용자가
/// 자리에 없을 가능성이 크고, 수동으로 시작했어도 앱이 백그라운드면 승인 대기를
/// 알 길이 없다. 그래서 다음 조건에서만 알린다:
/// - 설정에서 Agent Chat 알림이 켜져 있고,
/// - loop가 예약으로 시작됐거나 앱이 백그라운드이며,
/// - 상태가 승인 대기·답변 대기·(사용자 일시정지가 아닌) 일시정지·종료로 **바뀐**
///   순간(같은 상태가 이어지는 동안은 다시 알리지 않는다).
///
/// 상태값 [state]는 지금까지 보낸 알림 수다. 테스트와 디버깅용.
class AgentNotificationNotifier extends Notifier<int> {
  @override
  int build() {
    ref.listen<AgentLoopState>(agentChatProvider, _onLoopChanged);
    return 0;
  }

  void _onLoopChanged(AgentLoopState? previous, AgentLoopState next) {
    if (previous == null) return;
    if (!_transitioned(previous, next)) return;
    if (!ref.read(appSettingsProvider).notifications.canShowAgentAttention) {
      return;
    }
    final scheduled = next.events.any(
      (event) => event is ScheduleTriggeredEvent,
    );
    final foreground = ref.read(appForegroundProvider);
    if (!scheduled && foreground) return;

    final message = describe(next);
    if (message == null) return;
    state = state + 1;
    unawaited(
      ref
          .read(notificationServiceProvider)
          .showAgentAttention(title: message.$1, body: message.$2),
    );
  }

  /// 알릴 만한 상태로 새로 들어섰는지. 같은 사유의 일시정지가 이어지면 false.
  static bool _transitioned(AgentLoopState previous, AgentLoopState next) {
    if (previous.status == next.status &&
        previous.pauseReason == next.pauseReason) {
      return false;
    }
    return switch (next.status) {
      AgentLoopStatus.waitingApproval ||
      AgentLoopStatus.waitingUser ||
      AgentLoopStatus.finished => true,
      AgentLoopStatus.paused => next.pauseReason != AgentPauseReason.user,
      _ => false,
    };
  }

  /// 상태를 (제목, 본문)으로 옮긴다. 알릴 상태가 아니면 null.
  static (String, String)? describe(AgentLoopState loop) {
    final goal = loop.goal?.trim();
    final goalLabel = goal == null || goal.isEmpty
        ? 'Agent Chat'
        : goal.length <= 40
        ? goal
        : '${goal.substring(0, 40)}…';
    switch (loop.status) {
      case AgentLoopStatus.waitingApproval:
        final approval = loop.pendingApproval;
        return (
          '승인 필요 · $goalLabel',
          approval == null
              ? '위험한 명령이 승인을 기다립니다.'
              : '${approval.sessionName}: ${approval.reason}',
        );
      case AgentLoopStatus.waitingUser:
        return (
          '답변 필요 · $goalLabel',
          loop.pendingQuestion ?? '오케스트레이터가 질문했습니다.',
        );
      case AgentLoopStatus.paused:
        final title = switch (loop.pauseReason) {
          AgentPauseReason.budgetExhausted => '예산 추가 필요',
          AgentPauseReason.deadlineReached => '마감 연장 필요',
          AgentPauseReason.recoverableError => '복구 후 재개 필요',
          AgentPauseReason.runtimeBlocked => '터미널 복구 필요',
          AgentPauseReason.sessionInput => 'CLI 승인·입력 필요',
          AgentPauseReason.user || null => null,
        };
        if (title == null) return null;
        return ('$title · $goalLabel', loop.pauseMessage ?? 'loop가 멈췄습니다.');
      case AgentLoopStatus.finished:
        final outcome = switch (loop.outcome) {
          AgentLoopOutcome.achieved => '달성',
          AgentLoopOutcome.partial => '부분 완료',
          AgentLoopOutcome.blocked => '차단',
          AgentLoopOutcome.stopped => '중단됨',
          AgentLoopOutcome.failed => '실패',
          null => '종료',
        };
        String? summary;
        for (final event in loop.events.reversed) {
          if (event is LoopFinishedEvent) {
            summary = event.summary;
            break;
          }
        }
        return (
          'Loop $outcome · $goalLabel',
          summary == null || summary.trim().isEmpty
              ? '${loop.step} step'
              : summary,
        );
      case AgentLoopStatus.idle ||
          AgentLoopStatus.planning ||
          AgentLoopStatus.dispatching ||
          AgentLoopStatus.observing ||
          AgentLoopStatus.evaluating:
        return null;
    }
  }
}

final agentNotificationProvider =
    NotifierProvider<AgentNotificationNotifier, int>(
      AgentNotificationNotifier.new,
    );
