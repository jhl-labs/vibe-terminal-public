import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../agent/agent_chat_notifier.dart';
import '../../agent/agent_chat_draft_notifier.dart';
import '../../agent/agent_mailbox.dart';
import '../../agent/agent_models.dart';
import '../../agent/agent_schedule.dart';
import '../../agent/agent_schedule_notifier.dart';
import '../../agent/agent_scheduler.dart';
import '../../agent/agent_session_inspector.dart';
import '../../agent/agent_session_role.dart';
import '../../app/theme.dart';
import 'ai_data_consent.dart';
import '../../session/session.dart';
import '../../settings/app_settings.dart';
import '../../state/providers.dart';
import 'agent_chat/role_badges.dart';
import 'agent_chat/role_editor.dart';
import 'agent_chat/role_pipeline_strip.dart';
import 'agent_history_dialog.dart';
import 'agent_inbox_dialog.dart';
import '../../ai/routines/ai_chat_routine_dialog.dart';
import 'agent_schedule_dialog.dart';
import 'ai_message_renderer.dart';

/// 다중 세션 오케스트레이션 Agent Chat 패널.
///
/// loop는 [agentChatProvider]가 소유하므로 이 위젯은 상태를 구독해 타임라인을
/// 그리고 제어 명령만 전달한다. 패널을 닫아도 loop는 계속 실행된다.
class AgentChatPanel extends ConsumerStatefulWidget {
  const AgentChatPanel({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends ConsumerState<AgentChatPanel> {
  late final TextEditingController _inputController;
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _ticker;
  int _lastEventCount = 0;
  bool _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(
      text: ref.read(agentChatDraftProvider),
    );
    _inputController.addListener(_persistDraft);
    _scrollController.addListener(_handleTimelineScroll);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _inputController.removeListener(_persistDraft);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.removeListener(_handleTimelineScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _persistDraft() {
    ref.read(agentChatDraftProvider.notifier).set(_inputController.text);
  }

  void _ensureTicker(bool running) {
    if (running && _ticker == null) {
      // 경과 시간 표시를 위해 1초마다 rebuild.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  void _scrollToEndSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;
      await _animateToTimelineEnd();
    });
  }

  bool get _isNearTimelineEnd =>
      !_scrollController.hasClients ||
      _scrollController.position.extentAfter < 80;

  void _handleTimelineScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.position.extentAfter >= 120;
    if (shouldShow == _showJumpToLatest || !mounted) return;
    setState(() => _showJumpToLatest = shouldShow);
  }

  Future<void> _jumpToLatest() async {
    if (!_scrollController.hasClients) return;
    await _animateToTimelineEnd();
  }

  Future<void> _animateToTimelineEnd() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!_scrollController.hasClients ||
          _scrollController.position.extentAfter < 1) {
        return;
      }
    }
  }

  Future<void> _onSubmit(AgentLoopState loop) async {
    final text = _inputController.text.trim();
    final notifier = ref.read(agentChatProvider.notifier);

    switch (loop.status) {
      case AgentLoopStatus.idle:
      case AgentLoopStatus.finished:
        if (text.isEmpty) return;
        await _startLoop(text);
      case AgentLoopStatus.waitingUser:
        if (text.isEmpty) return;
        notifier.answerAskUser(text);
        _inputController.clear();
      case AgentLoopStatus.waitingApproval:
        return; // 승인 카드 버튼을 사용.
      default:
        if (text.isEmpty) return;
        notifier.submitFeedback(text);
        _inputController.clear();
    }
  }

  Future<void> _startLoop(
    String goal, {
    AgentGoalSpec? initialGoal,
    List<String>? initialSessionIds,
    Map<String, AgentSessionRole> initialSessionRoles = const {},
    List<AgentMessage> seedMessages = const [],
    List<AgentHandoff> seedHandoffs = const [],
  }) async {
    final settings = ref.read(appSettingsProvider).ai;
    if (!settings.isConfigured) {
      _snack('AI 설정에서 provider, model, API token을 먼저 입력하세요.');
      return;
    }
    if (!await AiDataConsent(
      store: ref.read(aiConsentStoreProvider),
    ).request(context, settings)) {
      return;
    }
    if (!mounted ||
        AiDataConsent.destinationKey(settings) !=
            AiDataConsent.destinationKey(ref.read(appSettingsProvider).ai)) {
      return;
    }
    final sessions = _activeGroupSessions();
    final connected = sessions
        .where((s) => s.status == SessionStatus.connected)
        .toList();
    if (connected.isEmpty) {
      _snack('현재 workspace에 오케스트레이션할 연결된 세션이 없습니다.');
      return;
    }
    final selection = await showDialog<_AgentSessionScopeSelection>(
      context: context,
      builder: (_) => _SessionScopeDialog(
        sessions: sessions,
        initialGoal: initialGoal ?? AgentGoalSpec(objective: goal),
        initialSessionIds: initialSessionIds,
        initialSessionRoles: initialSessionRoles,
      ),
    );
    if (selection == null || selection.sessionIds.isEmpty || !mounted) return;

    final timing = selection.timing;
    if (!timing.valid) return;
    final trigger = timing.trigger;
    if (trigger != null) {
      // 지금 시작하지 않고 예약만 남긴다. 시각이 되면 예약 Notifier가 시작한다.
      final task = await ref
          .read(agentScheduleProvider.notifier)
          .add(
            goalSpec: selection.goalSpec,
            allowedSessionIds: selection.sessionIds,
            sessionRoles: selection.roles,
            trigger: trigger,
            conflictPolicy: timing.conflictPolicy,
            timeBudget: timing.timeBudget,
          );
      if (!mounted) return;
      _inputController.clear();
      final next = task.nextRunAt;
      _snack(
        next == null
            ? '예약을 등록했습니다: ${task.trigger.label}'
            : '예약을 등록했습니다: ${task.trigger.label} · 다음 실행 '
                  '${AgentScheduleTrigger.formatDateTime(next)}',
      );
      return;
    }

    final started = ref
        .read(agentChatProvider.notifier)
        .start(
          goal: selection.goalSpec.objective,
          allowedSessionIds: selection.sessionIds,
          goalSpec: selection.goalSpec.withDeadline(timing.deadline),
          sessionRoles: selection.roles,
          seedMessages: seedMessages,
          seedHandoffs: seedHandoffs,
        );
    if (started) {
      _inputController.clear();
    } else {
      final reason = ref
          .read(agentChatProvider.notifier)
          .describeStartRefusal(
            goal: selection.goalSpec.objective,
            allowedSessionIds: selection.sessionIds,
          );
      _snack(reason ?? 'loop를 시작하지 못했습니다. 설정과 세션을 확인하세요.');
    }
  }

  /// 빈 화면의 예시 목표를 입력창에 채운다. 바로 시작하지는 않는다.
  void _fillDraft(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.collapsed(offset: text.length);
    ref.read(agentChatDraftProvider.notifier).set(text);
  }

  Future<void> _showSchedules() => showDialog<void>(
    context: context,
    builder: (_) => AgentScheduleListDialog(
      sessionNames: _sessionNames(),
      onAdd: () => unawaited(_openScheduleEditor()),
      onEdit: (task) => unawaited(
        task.isAiChat
            ? _openAiChatRoutineEditor(task)
            : task.isMessage
            ? _openMessageScheduler(existing: task)
            : _openScheduleEditor(existing: task),
      ),
      onRunNow: (task) => unawaited(_runScheduleNow(task)),
    ),
  );

  /// AI Chat 루틴은 AI Chat 쪽 편집기로 보낸다. 세션 이름은 목록과 같은 표를 쓴다.
  Future<void> _openAiChatRoutineEditor(AgentScheduledTask task) async {
    final sessionId = task.aiChatSessionId;
    if (sessionId == null) return;
    await showAiChatRoutineEditor(
      context,
      ref,
      sessionId: sessionId,
      sessionName: _sessionNames()[sessionId] ?? sessionId,
      existing: task,
    );
  }

  /// 현재 활성화된 세션 그룹(workspace)에 속한 세션만 고른다.
  ///
  /// Agent 작업공간은 각자 세션 그룹을 만들어 그 안에 세션을 띄우므로, 세션
  /// 선택 화면에 모든 그룹의 세션을 늘어놓으면 다른 작업공간의 세션까지 섞인다.
  List<SessionInfo> _activeGroupSessions() {
    final activeGroupId = ref.read(sessionGroupProvider).activeGroupId;
    return [
      for (final session in ref.read(sessionManagerProvider))
        if (session.groupId == activeGroupId) session,
    ];
  }

  /// 세션 id → 표시 이름. 실행 중인 loop의 세션과 열린 세션을 합친다.
  Map<String, String> _sessionNames() => {
    for (final session in ref.read(sessionManagerProvider))
      session.id: session.displayName,
    for (final task in ref.read(agentChatProvider).sessionTasks.values)
      task.sessionId: task.displayName,
  };

  /// 시각을 정해 세션 우편함에 넣을 메시지를 등록하거나 고친다.
  ///
  /// 대상 세션은 loop가 돌고 있으면 그 범위, 아니면 연결된 세션 전체다.
  Future<void> _openMessageScheduler({AgentScheduledTask? existing}) async {
    final loop = ref.read(agentChatProvider);
    final candidates = loop.isRunning
        ? [
            for (final task in loop.sessionTasks.values)
              (task.sessionId, task.displayName),
          ]
        : [
            for (final session in _activeGroupSessions())
              if (session.status == SessionStatus.connected)
                (session.id, session.displayName),
          ];
    if (candidates.isEmpty) {
      _snack('현재 workspace에 메시지를 받을 세션이 없습니다.');
      return;
    }
    final result = await showDialog<AgentScheduledMessageResult>(
      context: context,
      builder: (_) => AgentScheduledMessageDialog(
        sessions: candidates,
        initialSessionId: existing?.messageSessionId,
        initialBody: existing?.messageBody,
        initialTrigger: existing?.trigger,
      ),
    );
    if (result == null || !mounted) return;
    final notifier = ref.read(agentScheduleProvider.notifier);
    if (existing == null) {
      await notifier.addMessage(
        sessionId: result.sessionId,
        body: result.body,
        trigger: result.trigger,
      );
      if (!mounted) return;
      _snack('예약 메시지를 등록했습니다: ${result.trigger.label}');
    } else {
      final updated = await notifier.updateMessage(
        existing.id,
        sessionId: result.sessionId,
        body: result.body,
        trigger: result.trigger,
      );
      if (!mounted) return;
      _snack(updated ? '예약 메시지를 수정했습니다.' : '예약을 찾지 못했습니다.');
    }
  }

  /// 예약을 새로 만들거나 고친다. loop가 실행 중이어도 쓸 수 있다.
  ///
  /// Loop 실행 설정 다이얼로그를 예약 전용 모드로 연다. 목표 계약·세션 범위·
  /// 실행 시점을 같은 화면에서 고르되 "지금 실행"은 고를 수 없다.
  Future<void> _openScheduleEditor({AgentScheduledTask? existing}) async {
    final sessions = _activeGroupSessions();
    if (sessions.every((s) => s.status != SessionStatus.connected)) {
      _snack('현재 workspace에 예약할 연결된 세션이 없습니다.');
      return;
    }
    final initialTiming = existing == null
        ? AgentTimingSelection(
            trigger: AgentScheduleTrigger.once(
              DateTime.now().add(const Duration(hours: 1)),
            ),
          )
        : AgentTimingSelection(
            trigger: existing.trigger,
            conflictPolicy: existing.conflictPolicy,
            timeBudget: existing.timeBudget,
          );
    final selection = await showDialog<_AgentSessionScopeSelection>(
      context: context,
      builder: (_) => _SessionScopeDialog(
        sessions: sessions,
        initialGoal: existing?.goalSpec ?? const AgentGoalSpec(objective: ''),
        initialSessionIds: existing?.allowedSessionIds,
        initialSessionRoles: existing?.sessionRoles ?? const {},
        initialTiming: initialTiming,
        scheduleOnly: true,
      ),
    );
    final trigger = selection?.timing.trigger;
    if (selection == null || trigger == null || !mounted) return;
    final notifier = ref.read(agentScheduleProvider.notifier);
    if (existing == null) {
      final task = await notifier.add(
        goalSpec: selection.goalSpec,
        allowedSessionIds: selection.sessionIds,
        sessionRoles: selection.roles,
        trigger: trigger,
        conflictPolicy: selection.timing.conflictPolicy,
        timeBudget: selection.timing.timeBudget,
      );
      if (!mounted) return;
      _snack('예약을 등록했습니다: ${task.trigger.label}');
    } else {
      final updated = await notifier.update(
        existing.id,
        goalSpec: selection.goalSpec,
        allowedSessionIds: selection.sessionIds,
        sessionRoles: selection.roles,
        trigger: trigger,
        conflictPolicy: selection.timing.conflictPolicy,
        timeBudget: selection.timing.timeBudget,
      );
      if (!mounted) return;
      _snack(updated ? '예약을 수정했습니다: ${trigger.label}' : '예약을 찾지 못했습니다.');
    }
  }

  Future<void> _runScheduleNow(AgentScheduledTask task) async {
    final result = await ref
        .read(agentScheduleProvider.notifier)
        .runNow(task.id);
    if (!mounted) return;
    _snack(switch (result?.outcome) {
      AgentScheduleDueOutcome.started => '"${task.title}" 실행을 시작했습니다.',
      AgentScheduleDueOutcome.deferred => '실행 중인 loop가 있어 지금은 시작하지 못했습니다.',
      AgentScheduleDueOutcome.skipped => result?.detail ?? '지금은 실행할 수 없습니다.',
      null => '예약을 찾지 못했습니다.',
    });
  }

  /// 오케스트레이터가 무엇을 지시했고 각 세션이 무엇을 했는지 한눈에 본다.
  Future<void> _showHistory() => showDialog<void>(
    context: context,
    builder: (_) => AgentHistoryDialog(onOpenSession: _openSession),
  );

  Future<void> _showInbox({String? sessionId}) => showDialog<void>(
    context: context,
    builder: (_) => AgentInboxDialog(
      filterSessionId: sessionId,
      onCompose: (target) {
        final task = ref.read(agentChatProvider).sessionTasks[target];
        if (task != null) unawaited(_postInbox(task));
      },
      onScheduleMessage: () => unawaited(_openMessageScheduler()),
    ),
  );

  /// 세션 우편함에 사용자 메시지를 넣는다. 다음 지시에 [INBOX]로 실린다.
  Future<void> _postInbox(SessionTaskView task) async {
    final body = await showDialog<String>(
      context: context,
      builder: (_) => AgentInboxComposeDialog(sessionName: task.displayName),
    );
    if (body == null || body.trim().isEmpty || !mounted) return;
    final posted = ref
        .read(agentChatProvider.notifier)
        .postInboxMessage(sessionId: task.sessionId, body: body);
    _snack(
      posted
          ? '${task.displayName} 우편함에 넣었습니다. 다음 지시에 함께 전달됩니다.'
          : '지금은 메시지를 넣을 수 없습니다. loop가 실행 중인지 확인하세요.',
    );
  }

  String? _lastLoopSummary(AgentLoopState loop) {
    for (final event in loop.events.reversed) {
      if (event is LoopFinishedEvent) return event.summary;
    }
    return null;
  }

  Future<void> _continueLoop(AgentLoopState loop) async {
    final objective = loop.goal?.trim();
    if (objective == null || objective.isEmpty) return;
    final previous = loop.goalSpec ?? AgentGoalSpec(objective: objective);
    final continuedGoal = AgentGoalSpec(
      objective: previous.objective,
      successCriteria: previous.successCriteria,
      verificationSteps: previous.verificationSteps,
      constraints: previous.constraints,
      continuationContext:
          _lastLoopSummary(loop) ?? previous.continuationContext,
    );
    await _startLoop(
      objective,
      initialGoal: continuedGoal,
      initialSessionIds: loop.allowedSessionIds,
      initialSessionRoles: loop.sessionRoles,
      // 지난 실행에서 배달되지 못한 우편함 메시지를 그대로 넘긴다.
      seedMessages: loop.undeliveredMessages,
      // 인계 기록도 넘긴다. 없으면 이어받은 실행이 설계 결과를 모른 채
      // 시작하고, 순서 강제가 구현 세션을 다시 막는다.
      seedHandoffs: loop.handoffs,
    );
  }

  void _focusNewGoal() {
    _inputController.clear();
    _inputFocusNode.requestFocus();
  }

  Future<void> _confirmStop(AgentLoopState loop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Loop 중단'),
        content: Text(
          '"${loop.goal ?? '현재 목표'}" 오케스트레이션을 중단합니다. '
          '세션에서 이미 시작된 작업은 계속될 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('agent-confirm-stop'),
            style: FilledButton.styleFrom(
              backgroundColor: VibeColors.statusError,
              foregroundColor: VibeColors.onSurface,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Loop 중단'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(agentChatProvider.notifier).stop();
    }
  }

  /// 타임라인·목표·입력 초안을 비우고 새 목표를 받을 수 있는 상태로 되돌린다.
  Future<void> _confirmReset(AgentLoopState loop) async {
    final running = loop.isRunning;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('대화 초기화'),
        content: Text(
          running
              ? '실행 중인 loop를 중단하고 대화 기록과 목표를 모두 지웁니다. '
                    '세션에서 이미 시작된 작업은 계속될 수 있습니다.'
              : '대화 기록과 목표를 지우고 새 목표를 입력할 수 있는 상태로 되돌립니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('agent-confirm-reset'),
            style: FilledButton.styleFrom(
              backgroundColor: VibeColors.statusError,
              foregroundColor: VibeColors.onSurface,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(agentChatProvider.notifier).reset();
    } catch (_) {
      _snack('대화 기록을 삭제하지 못했습니다. 저장 공간·권한을 확인한 뒤 다시 초기화하세요.');
      return;
    }
    if (!mounted) return;
    // 초안은 Notifier가 삭제 성공 시 비운다. 새 실행의 초안을 여기서 다시 지우지 않는다.
    _inputFocusNode.requestFocus();
    _snack('Agent Chat 대화를 초기화했습니다.');
  }

  Future<void> _showGoalContract(AgentGoalSpec goal) => showDialog<void>(
    context: context,
    builder: (context) => _GoalContractDialog(goal: goal),
  );

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSession(String sessionId) {
    ref.read(activeSessionIdProvider.notifier).set(sessionId);
  }

  Future<void> _copyRunHistory() async {
    final transcript = await ref
        .read(agentChatProvider.notifier)
        .exportCurrentRunTranscript();
    if (!mounted) return;
    if (transcript == null || transcript.isEmpty) {
      _snack('복사할 실행 기록이 없습니다.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: transcript));
    _snack('전체 실행 기록을 클립보드에 복사했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final loop = ref.watch(agentChatProvider);
    ref.listen<String>(agentChatDraftProvider, (_, next) {
      if (_inputController.text != next) _inputController.text = next;
    });
    final settings = ref.watch(appSettingsProvider).ai;
    final scheduledCount = ref.watch(
      agentScheduleProvider.select(
        (tasks) => tasks.where((task) => task.enabled).length,
      ),
    );
    _ensureTicker(loop.isRunning);

    if (loop.events.length != _lastEventCount) {
      final shouldFollow = _lastEventCount == 0 || _isNearTimelineEnd;
      _lastEventCount = loop.events.length;
      if (shouldFollow) _scrollToEndSoon();
    }

    return ColoredBox(
      color: VibeColors.surface,
      child: Column(
        children: [
          _AgentHeader(
            loop: loop,
            onPause: () => ref.read(agentChatProvider.notifier).pause(),
            onResume: () => ref.read(agentChatProvider.notifier).resume(),
            onStop: () => _confirmStop(loop),
            onExtend: () => ref.read(agentChatProvider.notifier).extendBudget(),
            onExtendDeadline: () =>
                ref.read(agentChatProvider.notifier).extendDeadline(),
            onSchedules: _showSchedules,
            scheduledCount: scheduledCount,
            onInbox: () => _showInbox(),
            undeliveredCount: loop.undeliveredMessages.length,
            onContinue: () => _continueLoop(loop),
            onNew: _focusNewGoal,
            onCopyHistory: loop.events.isEmpty
                ? null
                : () => unawaited(_copyRunHistory()),
            onHistory: loop.events.isEmpty ? null : _showHistory,
            onReset:
                loop.resetInProgress ||
                    (loop.status == AgentLoopStatus.idle && loop.events.isEmpty)
                ? null
                : () => unawaited(_confirmReset(loop)),
            onShowGoalContract: loop.goalSpec == null
                ? null
                : () => _showGoalContract(loop.goalSpec!),
            onOpenSettings: widget.onOpenSettings,
          ),
          if (loop.resetInProgress)
            const _AgentNotice(
              icon: Icons.hourglass_top,
              text: '대화 초기화 중… 실행 중단과 저장된 기록 삭제를 기다리고 있습니다.',
            ),
          if (!settings.isConfigured)
            _AgentNotice(
              icon: Icons.key_off_outlined,
              text: 'AI 설정에서 provider, model, API token을 입력하세요.',
              actionLabel: widget.onOpenSettings == null ? null : '설정',
              onAction: widget.onOpenSettings,
            ),
          if (loop.status == AgentLoopStatus.paused &&
              loop.pauseMessage != null)
            _AgentNotice(
              icon: switch (loop.pauseReason) {
                AgentPauseReason.budgetExhausted =>
                  Icons.hourglass_bottom_outlined,
                AgentPauseReason.deadlineReached => Icons.timer_off_outlined,
                AgentPauseReason.recoverableError => Icons.cloud_off_outlined,
                AgentPauseReason.runtimeBlocked => Icons.build_circle_outlined,
                AgentPauseReason.sessionInput => Icons.pan_tool_outlined,
                _ => Icons.pause_circle_outline,
              },
              text: loop.pauseMessage!,
              actionLabel: switch (loop.pauseReason) {
                AgentPauseReason.budgetExhausted => '계속 +10',
                AgentPauseReason.deadlineReached => '마감 +30분',
                _ => '재개',
              },
              onAction: switch (loop.pauseReason) {
                AgentPauseReason.budgetExhausted =>
                  () => ref.read(agentChatProvider.notifier).extendBudget(),
                AgentPauseReason.deadlineReached =>
                  () => ref.read(agentChatProvider.notifier).extendDeadline(),
                _ => () => ref.read(agentChatProvider.notifier).resume(),
              },
            ),
          if (loop.sessionTasks.isNotEmpty &&
              RolePipelineStrip.hasRoles(loop.sessionTasks))
            RolePipelineStrip(tasks: loop.sessionTasks),
          if (loop.sessionTasks.isNotEmpty)
            _SessionTaskBoard(
              tasks: loop.sessionTasks.values.toList(),
              onTapSession: _openSession,
              onPostMessage: loop.isRunning ? _postInbox : null,
              onOpenInbox: (sessionId) => _showInbox(sessionId: sessionId),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: loop.events.isEmpty
                      ? _AgentEmptyState(onPickExample: _fillDraft)
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 54),
                          itemCount: loop.events.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _EventCard(
                            key: ObjectKey(loop.events[index]),
                            event: loop.events[index],
                            eventIndex: index,
                            settings: settings,
                            onTapSession: _openSession,
                            onApprove: () => ref
                                .read(agentChatProvider.notifier)
                                .resolveApproval(true),
                            onReject: () => ref
                                .read(agentChatProvider.notifier)
                                .resolveApproval(false),
                            pendingApproval: loop.pendingApproval,
                            tasks: loop.sessionTasks,
                          ),
                        ),
                ),
                if (_showJumpToLatest && loop.events.isNotEmpty)
                  Positioned(
                    right: 14,
                    bottom: 10,
                    child: FloatingActionButton.small(
                      key: const ValueKey('agent-jump-to-latest'),
                      heroTag: null,
                      tooltip: '최신 이벤트로 이동',
                      onPressed: () => unawaited(_jumpToLatest()),
                      backgroundColor: VibeColors.surfaceHigh,
                      foregroundColor: VibeColors.accent,
                      child: const Icon(Icons.arrow_downward, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          _AgentInputBar(
            controller: _inputController,
            focusNode: _inputFocusNode,
            loop: loop,
            onSubmit: () => _onSubmit(loop),
          ),
        ],
      ),
    );
  }
}

// --- 헤더 ---

class _AgentHeader extends StatelessWidget {
  const _AgentHeader({
    required this.loop,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onExtend,
    required this.onExtendDeadline,
    required this.onSchedules,
    required this.scheduledCount,
    required this.onInbox,
    required this.undeliveredCount,
    required this.onContinue,
    required this.onNew,
    required this.onCopyHistory,
    required this.onHistory,
    required this.onReset,
    required this.onShowGoalContract,
    required this.onOpenSettings,
  });

  final AgentLoopState loop;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onExtend;
  final VoidCallback onExtendDeadline;
  final VoidCallback onSchedules;
  final int scheduledCount;
  final VoidCallback onInbox;
  final int undeliveredCount;
  final VoidCallback onContinue;
  final VoidCallback onNew;
  final VoidCallback? onCopyHistory;
  final VoidCallback? onHistory;
  final VoidCallback? onReset;
  final VoidCallback? onShowGoalContract;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final running = loop.isRunning;
    final paused = loop.status == AgentLoopStatus.paused;
    final budgetPaused =
        paused && loop.pauseReason == AgentPauseReason.budgetExhausted;
    final deadlinePaused =
        paused && loop.pauseReason == AgentPauseReason.deadlineReached;
    final waitingForHuman =
        loop.status == AgentLoopStatus.waitingApproval ||
        loop.status == AgentLoopStatus.waitingUser;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.hub_outlined,
                color: VibeColors.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              // 좁은 폭·큰 글자에서 제목이 줄바꿈되면 헤더가 커져 타임라인
              // 공간을 잃는다. 제목은 한 줄로 고정한다.
              const Expanded(
                child: Text(
                  'Agent Chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (loop.status == AgentLoopStatus.finished &&
                  !loop.resetInProgress) ...[
                _HeaderIconButton(
                  tooltip: '같은 목표 이어가기',
                  icon: const Icon(Icons.replay, size: 18),
                  onPressed: onContinue,
                ),
                _HeaderIconButton(
                  tooltip: '새 목표',
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  onPressed: onNew,
                ),
              ],
              if (running || undeliveredCount > 0)
                _HeaderIconButton(
                  key: const ValueKey('agent-inbox'),
                  tooltip: undeliveredCount == 0
                      ? '세션 우편함'
                      : '세션 우편함 · 배달 대기 $undeliveredCount건',
                  icon: Badge(
                    isLabelVisible: undeliveredCount > 0,
                    label: Text('$undeliveredCount'),
                    child: const Icon(Icons.mail_outline, size: 18),
                  ),
                  onPressed: onInbox,
                ),
              _HeaderIconButton(
                key: const ValueKey('agent-schedules'),
                tooltip: scheduledCount == 0
                    ? '예약된 실행'
                    : '예약된 실행 $scheduledCount건',
                icon: Badge(
                  isLabelVisible: scheduledCount > 0,
                  label: Text('$scheduledCount'),
                  child: const Icon(Icons.schedule_outlined, size: 18),
                ),
                onPressed: onSchedules,
              ),
              if (onHistory != null)
                _HeaderIconButton(
                  key: const ValueKey('agent-history'),
                  tooltip: '실행 히스토리 · 지시와 세션별 진행 내역',
                  icon: const Icon(Icons.history, size: 18),
                  onPressed: onHistory,
                ),
              if (onCopyHistory != null)
                _HeaderIconButton(
                  tooltip: '전체 실행 기록 복사',
                  icon: const Icon(Icons.content_copy_outlined, size: 17),
                  onPressed: onCopyHistory,
                ),
              if (onReset != null)
                _HeaderIconButton(
                  key: const ValueKey('agent-reset'),
                  tooltip: '대화 초기화',
                  icon: const Icon(Icons.restart_alt, size: 18),
                  onPressed: onReset,
                ),
              if (onOpenSettings != null)
                _HeaderIconButton(
                  tooltip: 'AI 설정',
                  icon: const Icon(Icons.tune, size: 18),
                  onPressed: onOpenSettings,
                ),
            ],
          ),
          if (loop.goal != null) ...[
            const SizedBox(height: 6),
            Text(
              loop.goal!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
            if (loop.goalSpec?.hasContract == true) ...[
              const SizedBox(height: 5),
              _GoalContractMeta(
                goal: loop.goalSpec!,
                onTap: onShowGoalContract,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _PhaseChip(loop: loop),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _progressLabel(loop),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (running) ...[
                  if (budgetPaused)
                    _HeaderIconButton(
                      tooltip: '예산 +10 후 계속',
                      icon: const Icon(Icons.playlist_add, size: 18),
                      onPressed: onExtend,
                    )
                  else if (deadlinePaused)
                    _HeaderIconButton(
                      key: const ValueKey('agent-extend-deadline'),
                      tooltip: '마감 +30분 후 계속',
                      icon: const Icon(Icons.more_time, size: 18),
                      onPressed: onExtendDeadline,
                    )
                  else ...[
                    if (!waitingForHuman)
                      _HeaderIconButton(
                        tooltip: paused ? '재개' : '일시정지',
                        icon: Icon(
                          paused ? Icons.play_arrow : Icons.pause,
                          size: 18,
                        ),
                        onPressed: paused ? onResume : onPause,
                      ),
                    _HeaderIconButton(
                      tooltip: '예산 +10',
                      icon: const Icon(Icons.add_task, size: 17),
                      onPressed: onExtend,
                    ),
                  ],
                  _HeaderIconButton(
                    tooltip: '중단',
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    onPressed: onStop,
                  ),
                ],
              ],
            ),
            if (_narration(loop) case final narration?) ...[
              const SizedBox(height: 5),
              Text(
                narration,
                key: const ValueKey('agent-narration'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// "지금 무엇을 하고 있고, 무엇을 기다리는가"를 한 줄로 말해준다.
  ///
  /// 상태 칩만으로는 '관찰'이 어느 세션을 얼마나 기다리는 것인지 알 수 없다.
  /// 오래 걸리는 구간에서 사용자가 멈춘 것으로 오해하지 않게 한다.
  String? _narration(AgentLoopState loop) {
    if (!loop.isRunning) return null;
    final tasks = loop.sessionTasks.values;
    final waitingOn = [
      for (final task in tasks)
        if (task.phase == SessionTaskPhase.working ||
            task.phase == SessionTaskPhase.dispatched)
          task.displayName,
    ];
    final backgroundCount = tasks.where((t) => t.backgroundRunning).length;
    final unread = tasks.fold<int>(0, (sum, t) => sum + t.unreadMessages);

    final headline = switch (loop.status) {
      AgentLoopStatus.planning => '다음에 무엇을 시킬지 계획하는 중',
      AgentLoopStatus.dispatching => '세션에 지시를 보내는 중',
      AgentLoopStatus.observing =>
        waitingOn.isEmpty
            ? '세션 응답을 기다리는 중'
            : '${waitingOn.join(', ')} 응답을 기다리는 중',
      AgentLoopStatus.evaluating => '결과가 목표에 맞는지 검증하는 중',
      AgentLoopStatus.waitingApproval => '위험한 명령이라 승인을 기다리는 중',
      AgentLoopStatus.waitingUser => '사용자 답변을 기다리는 중',
      // 일시정지 사유는 별도 배너가 이미 설명한다.
      _ => null,
    };
    if (headline == null) return null;
    return [
      headline,
      if (backgroundCount > 0) '배경 작업 $backgroundCount건 진행 중',
      if (unread > 0) '전달 대기 메시지 $unread건',
    ].join(' · ');
  }

  String _progressLabel(AgentLoopState loop) {
    final step = 'step ${loop.step}/${loop.maxSteps}';
    final started = loop.startedAt;
    if (started == null) return step;
    final elapsed = loop.status == AgentLoopStatus.finished
        ? _finishedElapsed(loop) ?? DateTime.now().difference(started)
        : DateTime.now().difference(started);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final deadline = loop.goalSpec?.deadline;
    if (deadline == null || !loop.isRunning) return '$step · $mm:$ss';
    // 마감까지 남은 시간을 함께 보여준다. 지나면 초과로 표시한다.
    final remaining = deadline.difference(DateTime.now());
    final deadlineLabel = remaining.isNegative
        ? '마감 ${AgentScheduleTrigger.formatDuration(-remaining)} 초과'
        : '마감까지 ${AgentScheduleTrigger.formatDuration(remaining)}';
    return '$step · $mm:$ss · $deadlineLabel';
  }

  Duration? _finishedElapsed(AgentLoopState loop) {
    for (final event in loop.events.reversed) {
      if (event is LoopFinishedEvent) return event.elapsed;
    }
    return null;
  }
}

class _GoalContractMeta extends StatelessWidget {
  const _GoalContractMeta({required this.goal, required this.onTap});

  final AgentGoalSpec goal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (goal.successCriteria.isNotEmpty) '완료 ${goal.successCriteria.length}',
      if (goal.verificationSteps.isNotEmpty)
        '검증 ${goal.verificationSteps.length}',
      if (goal.constraints.isNotEmpty) '제약 ${goal.constraints.length}',
      if (goal.deadline case final deadline?)
        '마감 ${AgentScheduleTrigger.formatDateTime(deadline).substring(5)}',
      if (goal.continuationContext != null) '이전 loop 연결',
    ];
    return Tooltip(
      message: '목표 계약 보기',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                size: 13,
                color: VibeColors.secondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  parts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 14,
                color: VibeColors.onSurfaceDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalContractDialog extends StatelessWidget {
  const _GoalContractDialog({required this.goal});

  final AgentGoalSpec goal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(
            Icons.fact_check_outlined,
            size: 19,
            color: VibeColors.secondary,
          ),
          SizedBox(width: 8),
          Text('목표 계약'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GoalContractSection(label: '목표', items: [goal.objective]),
              if (goal.successCriteria.isNotEmpty)
                _GoalContractSection(
                  label: '완료 조건',
                  items: goal.successCriteria,
                ),
              if (goal.verificationSteps.isNotEmpty)
                _GoalContractSection(
                  label: '필수 검증',
                  items: goal.verificationSteps,
                ),
              if (goal.constraints.isNotEmpty)
                _GoalContractSection(label: '제약 조건', items: goal.constraints),
              if (goal.deadline case final deadline?)
                _GoalContractSection(
                  label: '마감',
                  items: [AgentScheduleTrigger.formatDateTime(deadline)],
                ),
              if (goal.continuationContext case final context?
                  when context.trim().isNotEmpty)
                _GoalContractSection(label: '이전 loop 요약', items: [context]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class _GoalContractSection extends StatelessWidget {
  const _GoalContractSection({required this.label, required this.items});

  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: VibeColors.secondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == items.length - 1 ? 0 : 4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.length > 1) ...[
                    Text(
                      '${index + 1}.',
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: SelectableText(
                      items[index],
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.loop});
  final AgentLoopState loop;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _describe(loop);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (String, Color) _describe(AgentLoopState loop) {
    if (loop.status == AgentLoopStatus.finished) {
      return switch (loop.outcome) {
        AgentLoopOutcome.achieved => ('달성', VibeColors.statusConnected),
        AgentLoopOutcome.partial => ('부분 완료', VibeColors.warning),
        AgentLoopOutcome.blocked => ('차단', VibeColors.warning),
        AgentLoopOutcome.stopped => ('중단됨', VibeColors.onSurfaceDim),
        AgentLoopOutcome.failed => ('실패', VibeColors.statusError),
        null => ('완료', VibeColors.onSurfaceDim),
      };
    }
    return switch (loop.status) {
      AgentLoopStatus.planning => ('계획', VibeColors.secondary),
      AgentLoopStatus.dispatching => ('지시', VibeColors.accent),
      AgentLoopStatus.observing => ('관찰', VibeColors.accent),
      AgentLoopStatus.evaluating => ('평가', VibeColors.secondary),
      AgentLoopStatus.waitingApproval => ('승인 대기', VibeColors.warning),
      AgentLoopStatus.waitingUser => ('질문 대기', VibeColors.warning),
      AgentLoopStatus.paused => switch (loop.pauseReason) {
        AgentPauseReason.budgetExhausted => ('예산 소진', VibeColors.warning),
        AgentPauseReason.deadlineReached => ('마감 도달', VibeColors.warning),
        AgentPauseReason.recoverableError => ('복구 대기', VibeColors.warning),
        AgentPauseReason.runtimeBlocked => ('터미널 복구', VibeColors.warning),
        AgentPauseReason.sessionInput => ('CLI 입력 대기', VibeColors.warning),
        _ => ('일시정지', VibeColors.onSurfaceDim),
      },
      _ => ('대기', VibeColors.onSurfaceDim),
    };
  }
}

// --- 세션 보드 ---

class _SessionTaskBoard extends StatelessWidget {
  const _SessionTaskBoard({
    required this.tasks,
    required this.onTapSession,
    this.onPostMessage,
    this.onOpenInbox,
  });

  final List<SessionTaskView> tasks;
  final ValueChanged<String> onTapSession;

  /// 세션 우편함에 사용자 메시지를 넣는다. null이면 버튼을 숨긴다(loop 없음).
  final ValueChanged<SessionTaskView>? onPostMessage;

  /// 미배달 배지를 눌렀을 때 그 세션의 우편함 목록을 연다.
  final ValueChanged<String>? onOpenInbox;

  /// 세션이 많아도 이벤트 목록을 다 밀어내지 않도록 보드가 차지하는 높이의
  /// 상한(패널 높이 대비). 그 안에서는 세로로 스크롤한다.
  static const _maxHeightFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight * _maxHeightFraction
            : double.infinity;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: VibeColors.borderSoft),
                bottom: BorderSide(color: VibeColors.borderSoft),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) => _SessionTaskCard(
                task: tasks[index],
                onTap: () => onTapSession(tasks[index].sessionId),
                onPostMessage: onPostMessage,
                onOpenInbox: onOpenInbox,
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _miniBadge({
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required String tooltip,
  }) {
    return Tooltip(
      key: key,
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _phaseDot(SessionTaskPhase phase) {
    final color = switch (phase) {
      SessionTaskPhase.idle => VibeColors.onSurfaceDim,
      SessionTaskPhase.dispatched => VibeColors.secondary,
      SessionTaskPhase.working => VibeColors.accent,
      SessionTaskPhase.done => VibeColors.statusConnected,
      SessionTaskPhase.error => VibeColors.statusError,
      SessionTaskPhase.waitingInput => VibeColors.warning,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  static String _phaseLabel(SessionTaskPhase phase) => switch (phase) {
    SessionTaskPhase.idle => '대기',
    SessionTaskPhase.dispatched => '전송됨',
    SessionTaskPhase.working => '작업 중',
    SessionTaskPhase.done => '완료',
    SessionTaskPhase.error => '오류',
    SessionTaskPhase.waitingInput => '승인·입력 필요',
  };
}

// --- 이벤트 카드 ---

class _EventCard extends StatelessWidget {
  const _EventCard({
    super.key,
    required this.event,
    required this.eventIndex,
    required this.settings,
    required this.onTapSession,
    required this.onApprove,
    required this.onReject,
    required this.pendingApproval,
    this.tasks = const {},
  });

  final AgentEvent event;

  /// 타임라인 안의 위치. 시각만으로는 겹칠 수 있는 카드 key에 쓴다.
  final int eventIndex;
  final AiSettings settings;
  final ValueChanged<String> onTapSession;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final PendingApproval? pendingApproval;

  /// 세션별 현재 상태. 지시 카드에 역할을 덧붙이는 데만 쓴다.
  final Map<String, SessionTaskView> tasks;

  @override
  Widget build(BuildContext context) {
    return switch (event) {
      LoopStartedEvent(:final goal, :final scope) => _line(
        Icons.flag_outlined,
        VibeColors.accent,
        '목표 시작 · $scope',
        goal,
      ),
      LoopFinishedEvent(
        :final outcome,
        :final summary,
        :final steps,
        :final elapsed,
      ) =>
        _finishedCard(outcome, summary, steps, elapsed),
      ThoughtEvent(:final step, :final text) => _thoughtCard(step, text),
      DispatchedEvent(
        :final sessionId,
        :final sessionName,
        :final kind,
        :final payload,
        :final reason,
        :final capability,
      ) =>
        _dispatchCard(
          sessionId,
          sessionName,
          kind,
          payload,
          reason,
          capability,
        ),
      ObservedEvent() => _ObservedCard(
        event: event as ObservedEvent,
        onTapSession: onTapSession,
      ),
      VerifiedEvent(:final verdict, :final summary) => _verifiedCard(
        verdict,
        summary,
      ),
      ReportEvent(:final markdown) => _reportCard(markdown),
      UserFeedbackEvent(:final text) => _feedbackBubble(text),
      ApprovalRequestedEvent(:final approval) => _approvalCard(approval),
      ApprovalResolvedEvent(:final approved, :final description) => _line(
        approved ? Icons.check_circle_outline : Icons.block,
        approved ? VibeColors.statusConnected : VibeColors.statusError,
        approved ? '승인됨' : '거부됨',
        description,
      ),
      AskUserEvent(:final question) => _line(
        Icons.help_outline,
        VibeColors.warning,
        '질문',
        question,
      ),
      MessagePostedEvent(:final from, :final to, :final body) => _line(
        Icons.forward_to_inbox_outlined,
        VibeColors.secondary,
        '메시지 · $from → $to',
        body,
        sessionId: to,
        sessionName: to,
      ),
      MessageWithdrawnEvent(:final from, :final to, :final body) => _line(
        Icons.undo,
        VibeColors.onSurfaceDim,
        '메시지 회수 · $from → $to',
        body,
        sessionId: to,
        sessionName: to,
      ),
      MessageDeliveredEvent(
        :final sessionId,
        :final sessionName,
        :final senders,
      ) =>
        _line(
          Icons.mark_email_read_outlined,
          VibeColors.secondary,
          '$sessionName · 메시지 ${senders.length}건 전달',
          '발신: ${senders.join(', ')}',
          sessionId: sessionId,
          sessionName: sessionName,
        ),
      RolePolicyRejectedEvent(
        :final sessionId,
        :final sessionName,
        :final roleKind,
        :final capability,
        :final reason,
      ) =>
        _line(
          Icons.block_outlined,
          VibeColors.warning,
          '역할 정책 거부 · $sessionName '
          '[${AgentSessionRole.kindLabel(roleKind)} · '
          '${AgentSessionRole.capabilityLabel(capability)}]',
          reason,
          sessionId: sessionId,
          sessionName: sessionName,
        ),
      HandoffRecordedEvent(:final handoff) => _handoffCard(handoff, eventIndex),
      LoopErrorEvent(:final message) => _line(
        Icons.error_outline,
        VibeColors.statusError,
        '오류',
        message,
      ),
      LoopRetryEvent(:final attempt, :final delay, :final message) => _line(
        Icons.sync_problem_outlined,
        VibeColors.warning,
        'LLM 재시도 · $attempt회',
        '$message\n${delay.inSeconds}초 후 다시 시도합니다. loop는 계속됩니다.',
      ),
      SessionRetryEvent(
        :final sessionId,
        :final sessionName,
        :final attempt,
        :final reason,
        :final evidence,
      ) =>
        _line(
          Icons.replay_circle_filled_outlined,
          VibeColors.warning,
          '$sessionName · 작업 속행 재지시 · $attempt회',
          evidence.trim().isEmpty ? reason : '$reason\n$evidence',
          sessionId: sessionId,
          sessionName: sessionName,
        ),
      TerminalRuntimeIssueEvent(
        :final sessionId,
        :final sessionName,
        :final message,
        :final evidence,
      ) =>
        _line(
          Icons.build_circle_outlined,
          VibeColors.warning,
          '복구 필요 · $sessionName',
          evidence.trim().isEmpty ? message : '$message\n$evidence',
          sessionId: sessionId,
          sessionName: sessionName,
        ),
      DeadlineReachedEvent(:final deadline, :final overrun) => _line(
        Icons.timer_off_outlined,
        VibeColors.warning,
        '마감 도달',
        '마감 ${AgentScheduleTrigger.formatDateTime(deadline)} · '
            '${AgentScheduleTrigger.formatDuration(overrun)} 초과. '
            '마감을 연장하면 이어서 실행합니다.',
      ),
      ScheduleTriggeredEvent(
        :final title,
        :final triggerLabel,
        :final interruptedGoal,
      ) =>
        _line(
          Icons.schedule_outlined,
          VibeColors.secondary,
          '예약 실행 · $triggerLabel',
          interruptedGoal == null
              ? title
              : '$title\n직전 목표를 중단하고 전환: $interruptedGoal',
        ),
      ScheduleRequestedEvent(:final title, :final runAt, :final reason) =>
        _line(
          Icons.more_time,
          VibeColors.secondary,
          '후속 작업 예약 · ${AgentScheduleTrigger.formatDateTime(runAt)}',
          reason == null || reason.trim().isEmpty ? title : '$title\n$reason',
        ),
      CollapsedEvent(:final count) => Center(
        child: Text(
          '이전 $count개 이벤트 생략됨',
          style: const TextStyle(color: VibeColors.onSurfaceDim, fontSize: 11),
        ),
      ),
    };
  }

  Widget _line(
    IconData icon,
    Color color,
    String title,
    String body, {
    String? sessionId,
    String? sessionName,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (body.trim().isNotEmpty)
                Text(
                  body,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
            ],
          ),
        ),
        if (sessionId != null && sessionName != null)
          _openSessionButton(sessionId, sessionName),
      ],
    );
  }

  Widget _bubble(IconData icon, String text, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: VibeColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  /// 인계 기록 카드. 요약은 접어 두고 제목·지시만 먼저 보여 준다.
  /// [index]는 타임라인 안의 위치다. 같은 세션이 같은 마이크로초에 두 번
  /// 인계되면 시각만으로는 key가 겹친다.
  Widget _handoffCard(AgentHandoff handoff, int index) {
    return Material(
      color: VibeColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: VibeColors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
          brightness: Brightness.dark,
        ),
        child: ExpansionTile(
          key: ValueKey('agent-handoff-${handoff.sessionId}-$index'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          dense: true,
          leading: const Icon(
            Icons.forward_outlined,
            color: VibeColors.secondary,
            size: 16,
          ),
          title: Text(
            '인계 기록 · ${handoff.sessionName} '
            '[${AgentSessionRole.kindLabel(handoff.roleKind)}]',
            style: const TextStyle(
              color: VibeColors.secondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            handoff.instruction,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VibeColors.onSurfaceMuted,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
          trailing: _openSessionButton(handoff.sessionId, handoff.sessionName),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                handoff.summary,
                style: const TextStyle(
                  color: VibeColors.onSurfaceMuted,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dispatchCard(
    String sessionId,
    String sessionName,
    String kind,
    String payload,
    String? reason,
    AgentCapability? capability,
  ) {
    final label = kind == 'prompt' ? '지시' : '키 입력';
    // 역할이 붙은 세션이면 "누가 무슨 일로" 받았는지 제목에서 바로 읽히게 한다.
    final roleKind = tasks[sessionId]?.role?.kind;
    final suffix = roleKind == null || roleKind == AgentRoleKind.custom
        ? ''
        : ' [${AgentSessionRole.kindLabel(roleKind)}'
              '${capability == null ? '' : ' · ${AgentSessionRole.capabilityLabel(capability)}'}]';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_arrow, color: VibeColors.accent, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$sessionName · $label$suffix',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _openSessionButton(sessionId, sessionName),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            payload,
            style: const TextStyle(
              color: VibeColors.onSurface,
              fontFamily: kMonoFontFamily,
              fontFamilyFallback: kMonoFontFallback,
              fontSize: 12,
            ),
          ),
          if (reason != null && reason.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            // 지시 본문과 같은 톤으로 두면 근거인지 지시의 일부인지 구분되지
            // 않는다. "왜"라고 못박아 판단 근거임을 드러낸다.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '왜',
                  style: TextStyle(
                    color: VibeColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 계획 판단 앞에 step 구분선을 둔다.
  ///
  /// 타임라인이 한 줄로 이어지면 "계획 → 지시 → 관찰 → 평가"라는 loop의 리듬이
  /// 보이지 않는다. 어디서 새 판단이 시작됐는지 눈으로 끊어 읽게 한다.
  Widget _thoughtCard(int step, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'STEP $step',
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Divider(color: VibeColors.borderSoft)),
          ],
        ),
        const SizedBox(height: 6),
        _bubble(Icons.psychology_outlined, text, VibeColors.onSurfaceMuted),
      ],
    );
  }

  Widget _verifiedCard(String verdict, String summary) {
    // 모델이 뱉는 판정어(progress/ok/mistake/stuck/uncertain)를 그대로 노출하면
    // 사용자는 loop가 왜 계속되는지/멈추는지를 읽어낼 수 없다. 뜻을 함께 적는다.
    final (label, meaning, problem) = switch (verdict) {
      'ok' => ('정상', '직전 행동이 의도대로 반영됐습니다.', false),
      'progress' => ('진행', '목표에 가까워졌습니다. loop를 계속합니다.', false),
      'mistake' => ('잘못된 행동', '의도한 변화가 없거나 엉뚱한 곳에 반영됐습니다.', true),
      'stuck' => ('정체', '같은 상태가 반복돼 진전이 없습니다.', true),
      'uncertain' => ('판단 보류', '화면만으로는 결과를 확신할 수 없습니다.', true),
      _ => (verdict, '', false),
    };
    final color = problem ? VibeColors.warning : VibeColors.statusConnected;
    return _line(
      problem ? Icons.warning_amber_outlined : Icons.check_circle_outline,
      color,
      '평가 · $label',
      meaning.isEmpty ? summary : '$summary\n$meaning',
    );
  }

  Widget _reportCard(String markdown) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VibeColors.border),
      ),
      child: AiMessageRenderer(
        markdown: markdown,
        isAssistant: true,
        isError: false,
        onSubmitTerminalInput: (_) {},
        fontFamily: settings.chatFontFamily,
        fontFallback: settings.fontFallback,
        fontSize: settings.chatFontSize,
      ),
    );
  }

  Widget _feedbackBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: VibeColors.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: const TextStyle(color: VibeColors.onSurface, fontSize: 12.5),
        ),
      ),
    );
  }

  Widget _approvalCard(PendingApproval approval) {
    // 반복된 동일 명령의 과거 카드가 현재 승인을 처리하지 못하게 한다.
    final active = identical(pendingApproval, approval);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: VibeColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VibeColors.warning.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: VibeColors.warning,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  approval.kind == PendingApprovalKind.rolePolicy
                      ? '역할 정책 예외 승인 · ${approval.sessionName}'
                            '${approval.capability == null ? '' : ' [${AgentSessionRole.capabilityLabel(approval.capability!)}]'}'
                      : '승인 요청 · ${approval.sessionName}',
                  style: const TextStyle(
                    color: VibeColors.warning,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _openSessionButton(approval.sessionId, approval.sessionName),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            approval.reason,
            style: const TextStyle(
              color: VibeColors.onSurfaceMuted,
              fontSize: 11,
            ),
          ),
          if (approval.screenContext.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '현재 터미널',
              style: TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            _terminalBlock(_terminalExcerpt(approval.screenContext)),
          ],
          const SizedBox(height: 8),
          const Text(
            '보낼 입력',
            style: TextStyle(
              color: VibeColors.onSurfaceDim,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          _terminalBlock(approval.description, emphasize: true),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                key: const ValueKey('agent-approve-action'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VibeColors.warning,
                  side: BorderSide(
                    color: VibeColors.warning.withValues(alpha: 0.7),
                  ),
                ),
                onPressed: active ? onApprove : null,
                child: const Text('승인'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                key: const ValueKey('agent-reject-action'),
                autofocus: active,
                style: FilledButton.styleFrom(
                  backgroundColor: VibeColors.accentSoft,
                  foregroundColor: VibeColors.onSurface,
                ),
                onPressed: active ? onReject : null,
                child: const Text('거부'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _openSessionButton(String sessionId, String sessionName) {
    return IconButton(
      key: ValueKey('agent-open-session-$sessionId'),
      tooltip: '$sessionName 세션 열기',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      onPressed: () => onTapSession(sessionId),
      icon: const Icon(
        Icons.open_in_new,
        size: 14,
        color: VibeColors.onSurfaceDim,
      ),
    );
  }

  Widget _terminalBlock(String text, {bool emphasize = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: VibeColors.terminal,
        borderRadius: BorderRadius.circular(6),
        border: emphasize
            ? Border.all(color: VibeColors.warning.withValues(alpha: 0.35))
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: emphasize ? VibeColors.onSurface : VibeColors.onSurfaceMuted,
          fontFamily: kMonoFontFamily,
          fontFamilyFallback: kMonoFontFallback,
          fontSize: emphasize ? 11.5 : 10.5,
          height: 1.3,
        ),
      ),
    );
  }

  String _terminalExcerpt(String screen) {
    final lines = screen
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return '(화면 내용 없음)';
    const maxLines = 6;
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(start).join('\n');
  }

  Widget _finishedCard(
    AgentLoopOutcome outcome,
    String summary,
    int steps,
    Duration elapsed,
  ) {
    final color = switch (outcome) {
      AgentLoopOutcome.achieved => VibeColors.statusConnected,
      AgentLoopOutcome.failed => VibeColors.statusError,
      _ => VibeColors.warning,
    };
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_circle_outlined, color: color, size: 17),
              const SizedBox(width: 6),
              Text(
                'loop 종료 · ${_outcomeLabel(outcome)}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '$steps step · $mm:$ss',
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            summary,
            style: const TextStyle(
              color: VibeColors.onSurface,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  String _outcomeLabel(AgentLoopOutcome outcome) => switch (outcome) {
    AgentLoopOutcome.achieved => '목표 달성',
    AgentLoopOutcome.partial => '부분 완료',
    AgentLoopOutcome.blocked => '차단',
    AgentLoopOutcome.stopped => '중단됨',
    AgentLoopOutcome.failed => '실패',
  };
}

/// 관찰 화면 델타 — 기본 접힘, 탭하면 펼침.
class _ObservedCard extends StatefulWidget {
  const _ObservedCard({required this.event, required this.onTapSession});
  final ObservedEvent event;
  final ValueChanged<String> onTapSession;

  @override
  State<_ObservedCard> createState() => _ObservedCardState();
}

class _ObservedCardState extends State<_ObservedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final lines = event.delta.split('\n');
    final preview = lines.take(3).join('\n');
    final hasMore = lines.length > 3;
    return InkWell(
      onTap: hasMore ? () => setState(() => _expanded = !_expanded) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: VibeColors.terminal,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VibeColors.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  event.isSnapshot
                      ? Icons.visibility_outlined
                      : event.quiescent
                      ? Icons.tv_outlined
                      : Icons.hourglass_empty,
                  color: VibeColors.onSurfaceDim,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event.isSnapshot
                        ? '${event.sessionName} 화면 확인'
                        : '${event.sessionName} 관찰'
                              '${event.quiescent ? '' : ' (타임아웃)'}',
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('agent-open-session-${event.sessionId}'),
                  tooltip: '${event.sessionName} 세션 열기',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.onTapSession(event.sessionId),
                  icon: const Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: VibeColors.onSurfaceDim,
                  ),
                ),
                if (hasMore)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: VibeColors.onSurfaceDim,
                    size: 16,
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              _expanded ? event.delta : preview,
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 입력바 ---

class _AgentInputBar extends StatelessWidget {
  const _AgentInputBar({
    required this.controller,
    required this.focusNode,
    required this.loop,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AgentLoopState loop;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final enabled =
        !loop.resetInProgress && loop.status != AgentLoopStatus.waitingApproval;
    final (hint, actionIcon, actionTooltip) = _describe(loop);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final canSubmit = enabled && value.text.trim().isNotEmpty;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: VibeColors.borderSoft)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: canSubmit ? (_) => onSubmit() : null,
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 12.5,
                    ),
                    filled: true,
                    fillColor: VibeColors.surfaceHigh,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('agent-submit'),
                onPressed: canSubmit ? onSubmit : null,
                icon: Icon(actionIcon),
                color: VibeColors.accent,
                tooltip: actionTooltip,
              ),
            ],
          ),
        );
      },
    );
  }

  (String, IconData, String) _describe(AgentLoopState loop) =>
      switch (loop.status) {
        AgentLoopStatus.idle => ('목표 입력', Icons.play_arrow, '목표 설정'),
        AgentLoopStatus.finished => ('새 목표 입력', Icons.play_arrow, '새 목표 설정'),
        AgentLoopStatus.waitingUser => ('답변 입력', Icons.send, '답변 보내기'),
        AgentLoopStatus.waitingApproval => (
          '승인 카드에서 선택',
          Icons.lock,
          '승인 카드에서 선택',
        ),
        AgentLoopStatus.paused => switch (loop.pauseReason) {
          AgentPauseReason.budgetExhausted => (
            '계속하기 전에 반영할 추가 지시',
            Icons.send,
            '피드백 저장',
          ),
          AgentPauseReason.deadlineReached => (
            '마감 연장 전에 반영할 추가 지시',
            Icons.send,
            '피드백 저장',
          ),
          AgentPauseReason.recoverableError => (
            '재개 전에 반영할 추가 지시',
            Icons.send,
            '피드백 저장',
          ),
          AgentPauseReason.runtimeBlocked => (
            '재개 전에 반영할 추가 지시',
            Icons.send,
            '피드백 저장',
          ),
          _ => ('재개 전에 반영할 피드백', Icons.send, '피드백 저장'),
        },
        _ => ('다음 계획에 반영할 피드백', Icons.send, '피드백 보내기'),
      };
}

// --- 세션 스코프 선택 다이얼로그 ---

class _AgentSessionScopeSelection {
  const _AgentSessionScopeSelection({
    required this.goalSpec,
    required this.sessionIds,
    required this.roles,
    this.timing = AgentTimingSelection.now,
  });

  final AgentGoalSpec goalSpec;
  final List<String> sessionIds;
  final Map<String, AgentSessionRole> roles;

  /// 지금 시작할지, 예약할지, 마감은 언제인지.
  final AgentTimingSelection timing;
}

class _SessionScopeDialog extends StatefulWidget {
  const _SessionScopeDialog({
    required this.sessions,
    required this.initialGoal,
    this.initialSessionIds,
    this.initialSessionRoles = const {},
    this.initialTiming = AgentTimingSelection.now,
    this.scheduleOnly = false,
  });
  final List<SessionInfo> sessions;
  final AgentGoalSpec initialGoal;
  final List<String>? initialSessionIds;
  final Map<String, AgentSessionRole> initialSessionRoles;
  final AgentTimingSelection initialTiming;

  /// 예약 등록/편집 전용. "지금 실행"을 고를 수 없고 버튼 문구가 예약이 된다.
  final bool scheduleOnly;

  @override
  State<_SessionScopeDialog> createState() => _SessionScopeDialogState();
}

class _SessionScopeDialogState extends State<_SessionScopeDialog> {
  late final List<_AgentSessionCandidate> _candidates;
  late final TextEditingController _objectiveController;
  late final TextEditingController _successController;
  late final TextEditingController _verificationController;
  late final TextEditingController _constraintsController;
  final Set<String> _selected = {};
  final Map<String, AgentSessionRole> _roles = {};
  bool _acknowledgedRisk = false;
  bool _goalExpanded = true;
  late AgentTimingSelection _timing = widget.initialTiming;
  int _unavailableInitialSessionCount = 0;

  @override
  void initState() {
    super.initState();
    _objectiveController = TextEditingController(
      text: widget.initialGoal.objective,
    );
    _successController = TextEditingController(
      text: widget.initialGoal.successCriteria.join('\n'),
    );
    _verificationController = TextEditingController(
      text: widget.initialGoal.verificationSteps.join('\n'),
    );
    _constraintsController = TextEditingController(
      text: widget.initialGoal.constraints.join('\n'),
    );
    _candidates = widget.sessions
        .map(_AgentSessionCandidate.fromSession)
        .toList(growable: false);
    final initialSessionIds = widget.initialSessionIds;
    if (initialSessionIds == null) {
      _selected.addAll(
        _candidates
            .where(
              (candidate) =>
                  candidate.isConnected &&
                  candidate.inspection.isConfirmedAgent &&
                  !candidate.isSensitive,
            )
            .map((candidate) => candidate.session.id),
      );
    } else {
      final requested = initialSessionIds.toSet();
      final available = _candidates
          .where(
            (candidate) =>
                candidate.isConnected &&
                requested.contains(candidate.session.id),
          )
          .map((candidate) => candidate.session.id)
          .toSet();
      _selected.addAll(available);
      _unavailableInitialSessionCount = requested.length - available.length;
      _roles.addAll({
        for (final entry in widget.initialSessionRoles.entries)
          if (available.contains(entry.key) && !entry.value.isEmpty)
            entry.key: entry.value,
      });
    }
  }

  @override
  void dispose() {
    _objectiveController.dispose();
    _successController.dispose();
    _verificationController.dispose();
    _constraintsController.dispose();
    super.dispose();
  }

  List<_AgentSessionCandidate> get _selectedCandidates => _candidates
      .where((candidate) => _selected.contains(candidate.session.id))
      .toList(growable: false);

  bool get _requiresRiskAcknowledgement => _selectedCandidates.any(
    (candidate) =>
        !candidate.inspection.isConfirmedAgent || candidate.isSensitive,
  );

  bool get _canStart =>
      _objectiveController.text.trim().isNotEmpty &&
      _selected.isNotEmpty &&
      (!_requiresRiskAcknowledgement || _acknowledgedRisk) &&
      _timingIsValid;

  /// 1회 예약은 미래 시각이어야 한다. 지난 시각은 등록 즉시 놓친 예약이 된다.
  bool get _timingIsValid {
    if (!_timing.valid) return false;
    final trigger = _timing.trigger;
    if (trigger == null || trigger.kind != AgentScheduleKind.once) return true;
    return trigger.at?.isAfter(DateTime.now()) ?? false;
  }

  /// 이 세션에 현재 배정된 역할. 없으면 빈 사용자 정의 역할을 보여 준다.
  AgentSessionRole _roleOf(String sessionId) =>
      _roles[sessionId] ??
      const AgentSessionRole(kind: AgentRoleKind.custom, capabilities: {});

  /// 역할 편집기에서 올라온 변경을 반영한다. 빈 역할은 저장하지 않는다.
  void _updateRole(String sessionId, AgentSessionRole role) {
    setState(() {
      if (role.isEmpty) {
        _roles.remove(sessionId);
      } else {
        _roles[sessionId] = role;
      }
    });
  }

  /// 선택된 세션에 4단 팀 역할을 표시 순서대로 배정한다.
  ///
  /// 5번째부터는 프리셋에 자리가 없으므로 사용자 정의로 둔다. 이미 적어 둔
  /// 모델 라벨과 메모는 유지한다.
  void _applyTeamPreset() {
    setState(() {
      var index = 0;
      for (final candidate in _candidates) {
        final id = candidate.session.id;
        if (!_selected.contains(id)) continue;
        final existing = _roles[id];
        final kind = index < AgentSessionRole.teamPresetOrder.length
            ? AgentSessionRole.teamPresetOrder[index]
            : AgentRoleKind.custom;
        index++;
        _roles[id] = AgentSessionRole.preset(
          kind,
          declaredModel: existing?.declaredModel,
          note: existing?.note ?? '',
        );
      }
    });
  }

  /// 프리셋 버튼 툴팁. 네 역할이 각각 뭘 맡는지 그대로 설명한다.
  String get _teamPresetTooltip => [
    '선택한 세션에 순서대로 배정합니다.',
    for (final kind in AgentSessionRole.teamPresetOrder)
      '${AgentSessionRole.kindLabel(kind)}: '
          '${AgentSessionRole.kindDescription(kind)}',
  ].join('\n');

  void _toggle(_AgentSessionCandidate candidate, bool selected) {
    if (!candidate.isConnected) return;
    setState(() {
      if (selected) {
        _selected.add(candidate.session.id);
      } else {
        _selected.remove(candidate.session.id);
      }
      _acknowledgedRisk = false;
    });
  }

  void _submit() {
    if (!_canStart) return;
    Navigator.of(context).pop(
      _AgentSessionScopeSelection(
        goalSpec: AgentGoalSpec(
          objective: _objectiveController.text,
          successCriteria: AgentGoalSpec.parseLines(_successController.text),
          verificationSteps: AgentGoalSpec.parseLines(
            _verificationController.text,
          ),
          constraints: AgentGoalSpec.parseLines(_constraintsController.text),
          continuationContext: widget.initialGoal.continuationContext,
        ).normalized(),
        sessionIds: [
          for (final candidate in _candidates)
            if (_selected.contains(candidate.session.id)) candidate.session.id,
        ],
        roles: {
          for (final entry in _roles.entries)
            if (_selected.contains(entry.key) && !entry.value.isEmpty)
              entry.key: entry.value,
        },
        timing: _timing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaHeight = MediaQuery.sizeOf(context).height;
    final contentHeight = math.max(300.0, math.min(540.0, mediaHeight - 220));
    final confirmedCount = _candidates
        .where(
          (candidate) =>
              candidate.isConnected && candidate.inspection.isConfirmedAgent,
        )
        .length;
    final requiresAcknowledgement = _requiresRiskAcknowledgement;
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.scheduleOnly ? Icons.schedule_outlined : Icons.hub_outlined,
            size: 20,
            color: VibeColors.accent,
          ),
          const SizedBox(width: 9),
          Text(widget.scheduleOnly ? '예약 설정' : 'Loop 실행 설정'),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: contentHeight,
        child: Column(
          children: [
            _GoalContractEditor(
              objectiveController: _objectiveController,
              successController: _successController,
              verificationController: _verificationController,
              constraintsController: _constraintsController,
              continuationContext: widget.initialGoal.continuationContext,
              expanded: _goalExpanded,
              onToggle: () => setState(() => _goalExpanded = !_goalExpanded),
              onObjectiveChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (_unavailableInitialSessionCount > 0) ...[
              Container(
                key: const ValueKey('agent-continuation-scope-warning'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: VibeColors.warning.withValues(alpha: 0.09),
                  border: Border.all(
                    color: VibeColors.warning.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.link_off_outlined,
                      size: 16,
                      color: VibeColors.warning,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '이전 범위의 세션 $_unavailableInitialSessionCount개가 '
                        '현재 연결되지 않았습니다. 다른 세션을 자동으로 추가하지 않았습니다.',
                        style: const TextStyle(
                          color: VibeColors.warning,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: VibeColors.surfaceHigh,
                border: Border.all(color: VibeColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    confirmedCount > 0
                        ? Icons.verified_outlined
                        : Icons.search_off_outlined,
                    size: 16,
                    color: confirmedCount > 0
                        ? VibeColors.statusConnected
                        : VibeColors.warning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      confirmedCount > 0
                          ? '화면에서 CLI agent $confirmedCount개 확인'
                          : '화면에서 확인된 CLI agent가 없습니다',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurfaceMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${_selected.length}개 선택',
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 실행 시점은 별도 다이얼로그에서 고른다. 여기 펼치면 세션
                  // 목록 높이를 잡아먹어 세션이 화면 밖으로 밀린다.
                  AgentTimingButton(
                    value: _timing,
                    allowNow: !widget.scheduleOnly,
                    onChanged: (value) => setState(() => _timing = value),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: _teamPresetTooltip,
                    child: OutlinedButton.icon(
                      key: const ValueKey('agent-scope-team-preset'),
                      onPressed: _selected.isEmpty ? null : _applyTeamPreset,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: const Size(0, 28),
                        foregroundColor: VibeColors.secondary,
                        side: const BorderSide(color: VibeColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.groups_outlined, size: 15),
                      label: const Text(
                        '4단 팀 프리셋',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: _candidates.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final candidate = _candidates[index];
                  final selected = _selected.contains(candidate.session.id);
                  return _AgentSessionTile(
                    candidate: candidate,
                    selected: selected,
                    role: _roleOf(candidate.session.id),
                    onSelected: (value) => _toggle(candidate, value),
                    onRoleChanged: (value) =>
                        _updateRole(candidate.session.id, value),
                  );
                },
              ),
            ),
            if (requiresAcknowledgement) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () =>
                    setState(() => _acknowledgedRisk = !_acknowledgedRisk),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 5, 9, 5),
                  decoration: BoxDecoration(
                    color: VibeColors.warning.withValues(alpha: 0.09),
                    border: Border.all(
                      color: VibeColors.warning.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _acknowledgedRisk,
                        onChanged: (value) =>
                            setState(() => _acknowledgedRisk = value ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'Agent 미확인 또는 운영 주의 세션의 화면을 확인했습니다.',
                          style: TextStyle(
                            color: VibeColors.warning,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          key: const ValueKey('agent-scope-submit'),
          onPressed: _canStart ? _submit : null,
          icon: Icon(
            _timing.isScheduled ? Icons.schedule_outlined : Icons.play_arrow,
            size: 17,
          ),
          label: Text(
            _timing.isScheduled
                ? '${_selected.length}개 세션으로 예약'
                : '${_selected.length}개 세션으로 시작',
          ),
        ),
      ],
    );
  }
}

class _GoalContractEditor extends StatelessWidget {
  const _GoalContractEditor({
    required this.objectiveController,
    required this.successController,
    required this.verificationController,
    required this.constraintsController,
    required this.continuationContext,
    required this.expanded,
    required this.onToggle,
    required this.onObjectiveChanged,
  });

  final TextEditingController objectiveController;
  final TextEditingController successController;
  final TextEditingController verificationController;
  final TextEditingController constraintsController;
  final String? continuationContext;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onObjectiveChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: VibeColors.accent.withValues(alpha: 0.055),
        border: Border.all(color: VibeColors.accent.withValues(alpha: 0.38)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.track_changes_outlined,
                    size: 16,
                    color: VibeColors.accent,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      '목표 계약',
                      style: TextStyle(
                        color: VibeColors.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 17,
                    color: VibeColors.onSurfaceDim,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(9, 0, 9, expanded ? 9 : 8),
            child: Column(
              children: [
                _GoalField(
                  fieldKey: const ValueKey('agent-goal-objective'),
                  controller: objectiveController,
                  label: '목표',
                  hint: '달성할 결과',
                  onChanged: onObjectiveChanged,
                ),
                if (expanded) ...[
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _GoalField(
                          fieldKey: const ValueKey('agent-goal-success'),
                          controller: successController,
                          label: '완료 조건',
                          hint: '한 줄에 하나',
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _GoalField(
                          fieldKey: const ValueKey('agent-goal-verification'),
                          controller: verificationController,
                          label: '필수 검증',
                          hint: '테스트·확인 명령',
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  _GoalField(
                    fieldKey: const ValueKey('agent-goal-constraints'),
                    controller: constraintsController,
                    label: '제약 조건',
                    hint: '금지하거나 반드시 지킬 사항',
                    maxLines: 2,
                  ),
                  if (continuationContext != null &&
                      continuationContext!.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    const Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 13,
                          color: VibeColors.secondary,
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '직전 loop 요약을 다음 계획에 포함합니다.',
                            style: TextStyle(
                              color: VibeColors.onSurfaceDim,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalField extends StatelessWidget {
  const _GoalField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: VibeColors.onSurface, fontSize: 11.5),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: VibeColors.onSurfaceMuted,
          fontSize: 10.5,
        ),
        hintStyle: const TextStyle(
          color: VibeColors.onSurfaceDim,
          fontSize: 10.5,
        ),
        filled: true,
        fillColor: VibeColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: VibeColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: VibeColors.border),
        ),
      ),
    );
  }
}

class _AgentSessionCandidate {
  const _AgentSessionCandidate({
    required this.session,
    required this.inspection,
    required this.isSensitive,
  });

  factory _AgentSessionCandidate.fromSession(SessionInfo session) {
    final screen = session.engine.recentPlainText(maxLines: 24);
    final searchable = [
      session.displayName,
      session.host.alias,
      session.host.hostname,
      session.host.username,
    ].join(' ').toLowerCase();
    final productionName = RegExp(
      r'(^|[\s._-])(prod|production|live)([\s._-]|$)',
    ).hasMatch(searchable);
    final isSensitive =
        productionName ||
        searchable.contains('운영') ||
        session.host.username.toLowerCase() == 'root';
    return _AgentSessionCandidate(
      session: session,
      // 최근 24줄에는 배너가 없을 수 있다. TUI가 쓴 터미널 제목을 합쳐
      // 화면에 우연히 지나간 단어보다 지금 떠 있는 Agent를 우선 본다.
      inspection: AgentSessionInspector.inspect(
        screen,
        title: session.engine.title,
      ),
      isSensitive: isSensitive,
    );
  }

  final SessionInfo session;
  final AgentSessionInspection inspection;
  final bool isSensitive;

  bool get isConnected => session.status == SessionStatus.connected;
  bool get isRemote => !session.host.isLocalShell;
}

class _AgentSessionTile extends StatelessWidget {
  const _AgentSessionTile({
    required this.candidate,
    required this.selected,
    required this.role,
    required this.onSelected,
    required this.onRoleChanged,
  });

  final _AgentSessionCandidate candidate;
  final bool selected;
  final AgentSessionRole role;
  final ValueChanged<bool> onSelected;
  final ValueChanged<AgentSessionRole> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final session = candidate.session;
    final enabled = candidate.isConnected;
    return Material(
      color: selected
          ? VibeColors.accent.withValues(alpha: 0.07)
          : VibeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected
              ? VibeColors.accent.withValues(alpha: 0.55)
              : VibeColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => onSelected(!selected) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 10, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: enabled
                    ? (value) => onSelected(value ?? false)
                    : null,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: enabled
                                  ? VibeColors.onSurface
                                  : VibeColors.onSurfaceDim,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!enabled)
                          _SessionBadge(
                            label: session.status.label,
                            color: VibeColors.statusError,
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _agentBadge(candidate.inspection),
                        _SessionBadge(
                          label: candidate.isRemote ? 'SSH' : 'Local',
                          color: candidate.isRemote
                              ? VibeColors.secondary
                              : VibeColors.onSurfaceDim,
                        ),
                        if (candidate.isSensitive)
                          const _SessionBadge(
                            label: '운영 주의',
                            color: VibeColors.warning,
                            icon: Icons.shield_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      session.host.endpointLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontFamily: kMonoFontFamily,
                        fontFamilyFallback: kMonoFontFallback,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: VibeColors.terminal,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        candidate.inspection.preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VibeColors.onSurfaceDim,
                          fontFamily: kMonoFontFamily,
                          fontFamilyFallback: kMonoFontFallback,
                          fontSize: 10,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 7),
                      AgentRoleEditor(
                        sessionId: session.id,
                        role: role,
                        detectedModel: candidate.inspection.modelHint,
                        onChanged: onRoleChanged,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentBadge(AgentSessionInspection inspection) {
    return switch (inspection.confidence) {
      AgentDetectionConfidence.confirmed => _SessionBadge(
        label: inspection.agentHint,
        color: VibeColors.statusConnected,
        icon: Icons.smart_toy_outlined,
      ),
      AgentDetectionConfidence.possible => _SessionBadge(
        label: '${inspection.agentHint} 추정',
        color: VibeColors.warning,
        icon: Icons.help_outline,
      ),
      AgentDetectionConfidence.none => const _SessionBadge(
        label: 'agent 미확인',
        color: VibeColors.onSurfaceDim,
        icon: Icons.help_outline,
      ),
    };
  }
}

class _SessionBadge extends StatelessWidget {
  const _SessionBadge({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 공용 소품 ---

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AgentNotice extends StatelessWidget {
  const _AgentNotice({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: VibeColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 12,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _AgentEmptyState extends StatelessWidget {
  const _AgentEmptyState({required this.onPickExample});

  final ValueChanged<String> onPickExample;

  /// (칩 라벨, 입력창에 채울 전체 목표)
  static const _examples = [
    ('실패한 테스트 원인 정리', '연결된 세션에서 실패한 테스트를 찾아 원인을 정리하고 수정 계획을 세워줘.'),
    ('서버 자원 점검', '서버 세션의 디스크·메모리 사용량을 점검하고 위험한 항목을 보고해줘.'),
    ('빌드 실행 후 오류 분석', '개발 세션에서 빌드를 실행하고 오류가 나면 로그를 분석해줘.'),
  ];

  @override
  Widget build(BuildContext context) {
    // 일시정지 배너·작업 보드가 공간을 차지하면 세로가 모자랄 수 있어 스크롤로 감싼다.
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hub_outlined,
                color: VibeColors.accent,
                size: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                '진행 중인 목표 없음',
                style: TextStyle(
                  color: VibeColors.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '목표를 입력하면 연결된 세션 중 범위를 고르고, Agent가 세션마다 '
                '작업을 나눠 진행합니다. 예시를 눌러 시작해 보세요.',
                style: TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontSize: 12,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, goal) in _examples)
                    ActionChip(
                      key: ValueKey('agent-example:$label'),
                      label: Text(
                        label,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onPressed: () => onPickExample(goal),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 세션 보드의 카드 한 장. 위에서 아래로 쌓이므로 가로 폭 전체를 쓴다.
class _SessionTaskCard extends StatelessWidget {
  const _SessionTaskCard({
    required this.task,
    required this.onTap,
    this.onPostMessage,
    this.onOpenInbox,
  });

  final SessionTaskView task;
  final VoidCallback onTap;
  final ValueChanged<SessionTaskView>? onPostMessage;
  final ValueChanged<String>? onOpenInbox;

  @override
  Widget build(BuildContext context) {
    final role = task.role;
    final note = role?.note.trim() ?? '';
    final detail = [
      _SessionTaskBoard._phaseLabel(task.phase),
      if (note.isNotEmpty) note,
      ?task.lastInstruction,
    ].join(' · ');
    return InkWell(
      key: ValueKey('agent-task-${task.sessionId}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: VibeColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VibeColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SessionTaskBoard._phaseDot(task.phase),
                const SizedBox(width: 6),
                if (role != null) ...[
                  AgentRoleKindIcon(kind: role.kind),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    task.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibeColors.onSurface,
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: Text(
                    task.agentHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibeColors.accent,
                      fontSize: 10,
                      height: 1.15,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                    ),
                  ),
                ),
                if (task.declaredModel != null ||
                    task.detectedModel != null) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: AgentModelBadge(
                      sessionId: task.sessionId,
                      declared: task.declaredModel,
                      detected: task.detectedModel,
                      mismatch: task.modelMismatch,
                    ),
                  ),
                ],
                // 화면에 흔적이 없는 상태를 먼저 보여준다. 이게 없으면
                // 왜 이 세션에 지시가 안 나가는지 알 수 없다.
                if (task.backgroundRunning) ...[
                  const SizedBox(width: 4),
                  _SessionTaskBoard._miniBadge(
                    key: ValueKey('agent-task-background-${task.sessionId}'),
                    icon: Icons.hourglass_top,
                    label: '배경',
                    color: VibeColors.accent,
                    tooltip: '결과를 기다리지 않고 배경에서 돌고 있는 작업이 있습니다.',
                  ),
                ],
                if (task.unreadMessages > 0) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onOpenInbox == null
                        ? null
                        : () => onOpenInbox!(task.sessionId),
                    child: _SessionTaskBoard._miniBadge(
                      key: ValueKey('agent-task-inbox-${task.sessionId}'),
                      icon: Icons.mail_outline,
                      label: '${task.unreadMessages}',
                      color: VibeColors.secondary,
                      tooltip:
                          '배달 대기 메시지 ${task.unreadMessages}건이 다음 지시에 '
                          '실려 전달됩니다. 눌러서 내용을 봅니다.',
                    ),
                  ),
                ],
                if (onPostMessage != null) ...[
                  const SizedBox(width: 6),
                  SizedBox.square(
                    dimension: 16,
                    child: InkWell(
                      key: ValueKey('agent-task-post-${task.sessionId}'),
                      onTap: () => onPostMessage!(task),
                      borderRadius: BorderRadius.circular(3),
                      child: const Tooltip(
                        message: '이 세션 우편함에 메시지 넣기',
                        child: Icon(
                          Icons.forward_to_inbox_outlined,
                          size: 14,
                          color: VibeColors.secondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            _WorkingDirectoryLine(
              sessionId: task.sessionId,
              // 지시가 바뀌면 에이전트가 다른 폴더로 옮겨갔을 수 있으니 다시 읽는다.
              revision: '${task.phase.name}|${task.lastInstruction ?? ''}',
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (role != null && role.capabilities.isNotEmpty) ...[
                  Flexible(
                    child: AgentCapabilityChips(
                      capabilities: role.capabilities,
                      max: 3,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 10.5,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 세션이 지금 작업 중인 폴더. 세션 관리자가 아는 값(로컬은 OS, 원격은 셸
/// 통합/tmux)을 읽으며, 모르면 줄 자체를 숨긴다.
class _WorkingDirectoryLine extends ConsumerStatefulWidget {
  const _WorkingDirectoryLine({
    required this.sessionId,
    required this.revision,
  });

  final String sessionId;

  /// 값이 바뀌면 경로를 다시 읽는다.
  final String revision;

  @override
  ConsumerState<_WorkingDirectoryLine> createState() =>
      _WorkingDirectoryLineState();
}

class _WorkingDirectoryLineState extends ConsumerState<_WorkingDirectoryLine> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _WorkingDirectoryLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.revision != widget.revision) {
      _load();
    }
  }

  Future<void> _load() async {
    final path = await ref
        .read(sessionManagerProvider.notifier)
        .currentWorkingDirectoryOf(widget.sessionId);
    if (!mounted || path == _path) return;
    setState(() => _path = path);
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: ValueKey('agent-task-path-${widget.sessionId}'),
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          const Icon(
            Icons.folder_outlined,
            size: 11,
            color: VibeColors.onSurfaceDim,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 10.5,
                height: 1.15,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
