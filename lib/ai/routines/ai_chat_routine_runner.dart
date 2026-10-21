/// AI Chat 루틴 실행기.
///
/// 예약 시각이 되면 [AgentScheduleNotifier]가 [AgentScheduleTaskKind.aiChat]
/// 작업을 여기로 넘긴다. 사용자가 AI Chat에 직접 친 것과 같은 턴을 헤드리스로
/// 돌리고(선택적으로 터미널 tool call까지), 결과를 그 세션의 AI Chat 대화에
/// 남긴 뒤 사용자가 보고 있지 않으면 알린다. Agent Chat loop와는 무관하다.
library;

import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_schedule.dart';
import '../../agent/agent_attention.dart';
import '../../session/session.dart';
import '../../session/session_activity.dart';
import '../../session/session_attention.dart';
import '../../state/providers.dart';
import '../ai_chat_service.dart';
import '../terminal_tool_call.dart';
import '../../session/session_notification_mute.dart';

class AiChatRoutineResult {
  const AiChatRoutineResult._({
    required this.outcome,
    required this.summary,
    this.skipReason,
  });

  const AiChatRoutineResult.skipped(String reason)
    : this._(outcome: 'skipped', summary: reason, skipReason: reason);
  const AiChatRoutineResult.delivered(String summary)
    : this._(outcome: 'delivered', summary: summary);
  const AiChatRoutineResult.failed(String summary)
    : this._(outcome: 'failed', summary: summary);

  /// 예약 실행 기록의 outcome 값: delivered | failed | skipped.
  final String outcome;
  final String summary;
  final String? skipReason;

  bool get skipped => outcome == 'skipped';
  bool get failed => outcome == 'failed';
}

class AiChatRoutineRunner {
  AiChatRoutineRunner(this.ref, {this.historyLimit = 12});

  final Ref ref;

  /// 요청에 붙이는 이전 대화 수. 루틴이 쌓은 결과와 사용자의 조정을 이어 준다.
  final int historyLimit;
  final Set<String> _runningSessions = {};

  /// 말풍선 아래 안내와 알림에 붙는 출처 표시.
  static const noteLabel = '예약 루틴';

  /// 실행 전에 알 수 있는 건너뜀 사유. null이면 실행할 수 있다.
  String? skipReason(AgentScheduledTask task) {
    final sessionId = task.aiChatSessionId;
    final prompt = task.messageBody?.trim() ?? '';
    if (sessionId == null || prompt.isEmpty) return '세션이나 프롬프트가 없어 건너뜀';
    if (_runningSessions.contains(sessionId)) return '이 세션의 이전 루틴이 실행 중이라 건너뜀';
    final session = _session(sessionId);
    if (session == null) return '세션이 닫혀 건너뜀';
    if (task.sessionBindings[sessionId] !=
        jsonEncode([session.host.id, session.authorizationId])) {
      return '예약 대상 권한이 달라져 건너뜀. 세션을 다시 선택하세요.';
    }
    if (session.status != SessionStatus.connected) {
      return '세션이 연결되어 있지 않아 건너뜀';
    }
    if (!ref.read(appSettingsProvider).ai.isConfigured) return 'AI 설정이 없어 건너뜀';
    return null;
  }

  Future<AiChatRoutineResult> run(AgentScheduledTask task) async {
    final reason = skipReason(task);
    if (reason != null) return AiChatRoutineResult.skipped(reason);
    final sessionId = task.aiChatSessionId!;
    _runningSessions.add(sessionId);
    try {
      return await _run(task);
    } finally {
      _runningSessions.remove(sessionId);
    }
  }

  Future<AiChatRoutineResult> _run(AgentScheduledTask task) async {
    final sessionId = task.aiChatSessionId!;
    final prompt = task.messageBody!.trim();
    final session = _session(sessionId)!;
    final settings = ref.read(appSettingsProvider).ai;
    final chat = ref.read(aiChatMessagesProvider(sessionId).notifier);
    final note = '$noteLabel · ${task.title} · ${task.trigger.label}';
    final userMessage = AiChatMessage(
      role: AiChatRole.user,
      content: prompt,
      createdAt: clock.now(),
      contextNote: note,
    );
    final history = ref
        .read(aiChatMessagesProvider(sessionId))
        .where((message) => !message.isError)
        .toList();
    final recent = history.length > historyLimit
        ? history.sublist(history.length - historyLimit)
        : history;
    final requestMessages = [...recent, userMessage];
    chat.add(userMessage);

    try {
      final service = ref.read(aiChatServiceProvider);
      String reply;
      if (task.terminalToolCall) {
        // 헤드리스에서는 파괴적 입력을 보내지 않고 제안으로 남긴다. 코드 블록의
        // OK 버튼이 기존 경로로 전송해 주므로 사용자가 확인한 뒤 실행할 수 있다.
        String? proposal;
        final executor = TerminalToolExecutor(
          sessions: () => ref.read(sessionManagerProvider),
          inputBlockReason: (live) {
            if (!ref.mounted) return '예약 실행기가 종료됨';
            if (ref.read(sessionActivityProvider.notifier).isBusy(live.id)) {
              return '출력 진행 중';
            }
            if (ref.read(sessionAttentionProvider)[live.id]?.state ==
                    SessionAttentionState.blocked ||
                const AgentAttentionClassifier(requireAgent: false)
                    .inspect(live.engine.recentPlainText(maxLines: 60))
                    .needsInput) {
              return '승인·입력 대기 중';
            }
            return null;
          },
          approveRisky: (session, input, verdict) async {
            proposal = input;
            return false;
          },
        );
        reply =
            await TerminalToolCallRunner(
              service: service,
              executor: executor,
            ).run(
              settings: settings,
              session: session,
              userGoal: prompt,
              requestMessages: requestMessages,
            );
        if (reply.startsWith('터미널 tool call을 실행했습니다')) {
          ref
              .read(sessionActivityProvider.notifier)
              .markTaskSubmitted(sessionId);
        }
        if (proposal case final input?) {
          reply =
              '$reply\n\n'
              '파괴적일 수 있는 명령이라 자동으로 보내지 않았습니다. '
              '직접 확인한 뒤 OK를 누르면 전송됩니다.\n\n'
              '```terminal\n$input\n```';
        }
      } else {
        reply = await service.complete(
          settings: settings,
          sessionLabel: session.displayName,
          terminalContext: session.engine.recentPlainText(
            maxLines: settings.maxContextLines,
          ),
          messages: requestMessages,
        );
      }
      chat.add(
        AiChatMessage(
          role: AiChatRole.assistant,
          content: reply,
          createdAt: clock.now(),
          contextNote: note,
        ),
      );
      final summary = summarize(reply);
      await _notifyIfAway(
        sessionId,
        title: '루틴 실행: ${task.title}',
        body: summary,
      );
      return AiChatRoutineResult.delivered(summary);
    } catch (error) {
      final message = error is AiChatException ? error.message : '$error';
      chat.add(
        AiChatMessage(
          role: AiChatRole.assistant,
          content: message,
          createdAt: clock.now(),
          isError: true,
          contextNote: note,
        ),
      );
      await _notifyIfAway(
        sessionId,
        title: '루틴 실패: ${task.title}',
        body: message,
      );
      return AiChatRoutineResult.failed(summarize(message));
    }
  }

  /// 답변의 첫 의미 있는 줄을 160자로 자른 요약. 목록·알림에 쓴다.
  static String summarize(String reply) {
    var inFence = false;
    for (final raw in reply.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence || line.isEmpty) continue;
      return line.length <= 160 ? line : '${line.substring(0, 160)}…';
    }
    return '(빈 답변)';
  }

  SessionInfo? _session(String sessionId) {
    for (final session in ref.read(sessionManagerProvider)) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  /// 사용자가 그 세션을 보고 있지 않을 때만 알린다.
  Future<void> _notifyIfAway(
    String sessionId, {
    required String title,
    required String body,
  }) async {
    if (ref.read(appForegroundProvider) &&
        ref.read(activeSessionIdProvider) == sessionId) {
      return;
    }
    if (ref.read(sessionNotificationMuteProvider).contains(sessionId)) return;
    await ref
        .read(notificationServiceProvider)
        .showAgentAttention(title: title, body: body);
  }
}

final aiChatRoutineRunnerProvider = Provider<AiChatRoutineRunner>(
  AiChatRoutineRunner.new,
);
