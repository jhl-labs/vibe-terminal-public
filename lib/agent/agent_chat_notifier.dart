import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_chat_service.dart';
import '../settings/app_settings.dart';
import '../state/providers.dart';
import '../terminal/terminal_input_codec.dart';
import 'agent_chat_draft_notifier.dart';
import 'agent_mailbox.dart';
import 'agent_models.dart';
import 'agent_orchestrator.dart';
import 'agent_run_store.dart';
import 'agent_run_transcript.dart';
import 'agent_schedule.dart';
import 'agent_session_role.dart';
import 'session_manager_port.dart';
import 'session_port.dart';

/// 플래너의 `schedule` 액션을 실제 예약으로 바꾸는 훅.
typedef AgentScheduleRequestHandler =
    Future<AgentScheduledTask?> Function(AgentScheduleRequest request);

/// Agent Chat loop를 소유하는 앱 수준 Notifier.
///
/// 패널 위젯이 아니라 provider가 loop를 소유하므로 패널을 닫아도 loop는 계속
/// 실행된다. UI는 [state]를 구독해 타임라인을 그리고, 제어 명령을 이 Notifier로
/// 보낸다. 실제 loop 구동은 [AgentOrchestrator]에 위임한다.
class AgentChatNotifier extends Notifier<AgentLoopState> {
  AgentOrchestrator? _orchestrator;
  late AgentRunStore _runStore;
  String? _runId;
  bool _disposed = false;
  Future<void>? _driveFuture;
  Future<void>? _resetFuture;
  late Future<AgentRunSnapshot?> _startupSnapshot;
  int _restoreEpoch = 0;
  int _runGeneration = 0;

  @override
  AgentLoopState build() {
    _runStore = ref.read(agentRunStoreProvider);
    ref.onDispose(() {
      _disposed = true;
      _orchestrator?.requestStop();
    });
    _startupSnapshot = _runStore.loadCurrent();
    unawaited(_restoreLatestRun());
    return AgentLoopState.idle;
  }

  /// 테스트에서 오케스트레이터 생성을 가로채기 위한 훅. null이면 기본 구현.
  AgentOrchestrator Function({
    required SessionPortRegistry registry,
    required CompletionFn completion,
    required int linesPerSession,
    required int maxSteps,
    required void Function(AgentEvent) emit,
    required void Function(
      AgentLoopStatus, {
      int? step,
      AgentPauseReason? pauseReason,
      String? pauseMessage,
    })
    onStatus,
    required void Function(Map<String, SessionTaskView>) onSessionTasks,
    required void Function(PendingApproval?) onApproval,
    required void Function(String?) onQuestion,
  })?
  orchestratorFactory;

  /// 플래너가 후속 작업을 예약할 때 쓰는 훅. 예약 Notifier가 만들어질 때 꽂는다.
  /// null이면 `schedule` 액션이 거절된다.
  AgentScheduleRequestHandler? scheduleHandler;

  bool get isRunning => state.isRunning;

  /// 현재(또는 마지막) 실행의 기록 id. `agent_chat/history/<id>.jsonl`.
  String? get currentRunId => _runId;

  /// [start]가 false를 돌려줄 이유를 사용자에게 보여줄 문장으로 만든다.
  /// 시작할 수 있으면 null. [start]와 같은 순서로 같은 조건을 검사한다.
  String? describeStartRefusal({
    required String goal,
    required List<String> allowedSessionIds,
  }) {
    if (_disposed) return 'Agent Chat이 종료되어 시작할 수 없습니다.';
    if (_resetFuture != null) return '초기화가 진행 중입니다. 잠시 후 다시 시도하세요.';
    if (!state.canStart) {
      return state.isRunning
          ? '이미 실행 중인 목표가 있습니다. 먼저 중지하거나 완료를 기다리세요.'
          : '지금 상태에서는 새 목표를 시작할 수 없습니다.';
    }
    if (goal.trim().isEmpty) return '목표를 입력하세요.';
    if (allowedSessionIds.isEmpty) return '오케스트레이션할 세션을 하나 이상 선택하세요.';
    if (!ref.read(appSettingsProvider).ai.isConfigured) {
      return 'AI 설정에서 provider, model, API token을 먼저 입력하세요.';
    }
    return null;
  }

  /// 새 Goal loop를 시작한다. 이미 실행 중이면 무시하고 false 반환.
  ///
  /// [scheduledStart]가 있으면 예약이 시작시킨 loop다. 타임라인 첫머리에 그
  /// 사실을 남겨 사용자가 누르지 않은 loop가 왜 도는지 설명한다.
  /// [seedMessages]는 이전 실행에서 배달되지 못한 우편함 메시지로, "같은 목표
  /// 이어가기"에서 넘긴다.
  bool start({
    required String goal,
    required List<String> allowedSessionIds,
    AgentGoalSpec? goalSpec,
    Map<String, AgentSessionRole> sessionRoles = const {},
    AgentScheduledStart? scheduledStart,
    List<AgentMessage> seedMessages = const [],
    List<AgentHandoff> seedHandoffs = const [],
  }) {
    if (_disposed || _resetFuture != null || !state.canStart) return false;
    final trimmedGoal = goal.trim();
    if (trimmedGoal.isEmpty || allowedSessionIds.isEmpty) return false;

    final settings = ref.read(appSettingsProvider).ai;
    if (!settings.isConfigured) return false;

    final scopeLabel = allowedSessionIds.length == 1
        ? '단일 세션'
        : '${allowedSessionIds.length}개 세션';
    final effectiveGoal = (goalSpec ?? AgentGoalSpec(objective: trimmedGoal))
        .normalized(objectiveOverride: trimmedGoal);
    final undelivered = List<AgentMessage>.unmodifiable([
      for (final message in seedMessages)
        if (!message.delivered && allowedSessionIds.contains(message.to))
          message,
    ]);
    final seededHandoffs = <AgentHandoff>[
      for (final handoff in seedHandoffs)
        if (allowedSessionIds.contains(handoff.sessionId)) handoff,
    ];

    _restoreEpoch++;
    final generation = ++_runGeneration;
    _runId = 'agent-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    _storeFailureReported = false;
    _setState(
      AgentLoopState(
        status: AgentLoopStatus.planning,
        goal: trimmedGoal,
        goalSpec: effectiveGoal,
        step: 0,
        startedAt: DateTime.now(),
        allowedSessionIds: List.unmodifiable(allowedSessionIds),
        sessionRoles: Map.unmodifiable({
          for (final entry in sessionRoles.entries)
            if (allowedSessionIds.contains(entry.key) && !entry.value.isEmpty)
              entry.key: entry.value,
        }),
        events: const [],
        sessionTasks: const {},
        undeliveredMessages: undelivered,
        // 이어가기는 지난 실행의 인계 기록을 그대로 물려받는다.
        handoffs: List.unmodifiable(seededHandoffs),
      ),
    );
    if (scheduledStart != null) {
      _emit(
        ScheduleTriggeredEvent(
          DateTime.now(),
          taskId: scheduledStart.taskId,
          title: scheduledStart.title,
          triggerLabel: scheduledStart.triggerLabel,
          interruptedGoal: scheduledStart.interruptedGoal,
        ),
      );
    }

    final orchestrator = _buildOrchestrator(settings)
      ..onMailbox = (pending) {
        if (_acceptCallback(generation)) _onMailbox(pending);
      }
      ..onSchedule = scheduleHandler
      ..seedMailbox(undelivered);
    _orchestrator = orchestrator;
    final drive = _drive(
      orchestrator,
      trimmedGoal,
      allowedSessionIds,
      scopeLabel,
      effectiveGoal,
      state.sessionRoles,
      seededHandoffs,
    );
    _driveFuture = drive;
    unawaited(drive);
    return true;
  }

  Future<void> _drive(
    AgentOrchestrator orchestrator,
    String goal,
    List<String> allowedIds,
    String scopeLabel,
    AgentGoalSpec goalSpec,
    Map<String, AgentSessionRole> sessionRoles,
    List<AgentHandoff> seedHandoffs,
  ) async {
    try {
      await orchestrator.run(
        goal: goal,
        allowedIds: allowedIds,
        scopeLabel: scopeLabel,
        goalSpec: goalSpec,
        sessionRoles: sessionRoles,
        seedHandoffs: seedHandoffs,
      );
    } finally {
      if (identical(_orchestrator, orchestrator)) _orchestrator = null;
    }
  }

  AgentOrchestrator _buildOrchestrator(AiSettings settings) {
    final generation = _runGeneration;
    final registry = SessionManagerPort(ref);
    final service = ref.read(aiChatServiceProvider);
    final linesPerSession = settings.maxContextLines.clamp(20, 120).toInt();

    Future<String> completion({
      required String system,
      required List<AiChatMessage> messages,
      AiCancelToken? cancelToken,
    }) => service.complete(
      settings: ref.read(appSettingsProvider).ai,
      sessionLabel: 'Agent Chat',
      terminalContext: '',
      messages: messages,
      cancelToken: cancelToken,
      systemPromptOverride: system,
    );

    void emit(AgentEvent event) {
      if (_acceptCallback(generation)) _emit(event);
    }

    void onStatus(
      AgentLoopStatus status, {
      int? step,
      AgentPauseReason? pauseReason,
      String? pauseMessage,
    }) {
      if (_acceptCallback(generation)) {
        _onStatus(
          status,
          step: step,
          pauseReason: pauseReason,
          pauseMessage: pauseMessage,
        );
      }
    }

    void onSessionTasks(Map<String, SessionTaskView> tasks) {
      if (_acceptCallback(generation)) _onSessionTasks(tasks);
    }

    void onApproval(PendingApproval? approval) {
      if (_acceptCallback(generation)) _onApproval(approval);
    }

    void onQuestion(String? question) {
      if (_acceptCallback(generation)) _onQuestion(question);
    }

    final factory = orchestratorFactory;
    if (factory != null) {
      return factory(
        registry: registry,
        completion: completion,
        linesPerSession: linesPerSession,
        maxSteps: state.maxSteps,
        emit: emit,
        onStatus: onStatus,
        onSessionTasks: onSessionTasks,
        onApproval: onApproval,
        onQuestion: onQuestion,
      );
    }

    return AgentOrchestrator(
      registry: registry,
      completion: completion,
      linesPerSession: linesPerSession,
      maxSteps: state.maxSteps,
      emit: emit,
      onStatus: onStatus,
      onSessionTasks: onSessionTasks,
      onApproval: onApproval,
      onQuestion: onQuestion,
      keyNormalizer: _normalizeKeys,
    );
  }

  bool _acceptCallback(int generation) =>
      !_disposed &&
      generation == _runGeneration &&
      state.status != AgentLoopStatus.finished;

  static String _normalizeKeys(String input) {
    final decoded = TerminalInputCodec.decode(input);
    return decoded.text;
  }

  // --- 제어 명령 ---

  void pause() {
    if (!state.isRunning || state.resetInProgress) return;
    _orchestrator?.requestPause();
  }

  void resume() {
    if (state.resetInProgress) return;
    _orchestrator?.requestResume();
  }

  void stop() {
    _orchestrator?.requestStop();
  }

  /// 중단을 요청하고 loop가 완전히 끝날 때까지 기다린다.
  ///
  /// 예약의 '전환' 정책처럼 곧바로 다른 loop를 시작해야 할 때 쓴다. [stop]만
  /// 부르고 바로 [start]하면 아직 finished가 아니라 거절된다.
  Future<void> stopAndWait() async {
    if (!state.isRunning) return;
    _orchestrator?.requestStop();
    final pending = _driveFuture;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // 중단 과정의 오류가 다음 loop 시작을 막지 않게 한다.
    }
  }

  void submitFeedback(String text) {
    if (state.resetInProgress) return;
    if (text.trim().isEmpty) return;
    _orchestrator?.submitFeedback(text);
  }

  /// 특정 세션의 우편함에 사용자 메시지를 넣는다. 다음 지시에 [INBOX]로 실린다.
  bool postInboxMessage({required String sessionId, required String body}) {
    if (state.resetInProgress) return false;
    final orchestrator = _orchestrator;
    if (orchestrator == null || !state.isRunning) return false;
    return orchestrator.postUserMessage(sessionId: sessionId, body: body);
  }

  /// 아직 배달되지 않은 우편함 메시지를 거둬들인다.
  ///
  /// loop가 끝난 뒤에는 오케스트레이터가 없으므로 스냅샷의 목록에서만 뺀다.
  /// 그러면 "같은 목표 이어가기"에 실려 가지 않는다.
  bool withdrawInboxMessage(int id) {
    if (state.resetInProgress) return false;
    final orchestrator = _orchestrator;
    if (orchestrator != null && state.isRunning) {
      return orchestrator.withdrawMessage(id);
    }
    final remaining = [
      for (final message in state.undeliveredMessages)
        if (message.id != id) message,
    ];
    if (remaining.length == state.undeliveredMessages.length) return false;
    _setState(
      state.copyWith(undeliveredMessages: List.unmodifiable(remaining)),
    );
    return true;
  }

  /// 마감을 [by]만큼 연장한다. 마감 도달로 멈춰 있었다면 이어서 실행한다.
  void extendDeadline([Duration by = const Duration(minutes: 30)]) {
    if (state.resetInProgress) return;
    final orchestrator = _orchestrator;
    if (orchestrator == null || !state.isRunning) return;
    orchestrator.extendDeadline(by);
    _setState(state.copyWith(goalSpec: orchestrator.goal));
  }

  void answerAskUser(String text) {
    if (state.resetInProgress) return;
    _orchestrator?.answerQuestion(text);
  }

  void resolveApproval(bool approved) {
    if (state.resetInProgress) return;
    _orchestrator?.resolveApproval(approved);
  }

  void extendBudget([int by = 10]) {
    if (state.resetInProgress) return;
    final orchestrator = _orchestrator;
    if (orchestrator == null) return;
    orchestrator.extendBudget(by);
    _setState(state.copyWith(maxSteps: orchestrator.maxSteps));
  }

  /// 히스토리 화면용 전체 이벤트. 메모리의 500개 제한 때문에 접힌 앞부분도
  /// 디스크에서 다시 읽는다. 저장이 실패했으면 메모리 이벤트를 그대로 준다.
  Future<List<AgentEvent>> loadCurrentRunEvents() async {
    final runId = _runId;
    if (runId == null) return state.events;
    try {
      final stored = await _runStore.loadEvents(runId);
      return stored.length >= state.events.length ? stored : state.events;
    } catch (_) {
      return state.events;
    }
  }

  Future<String?> exportCurrentRunTranscript() async {
    if (state.status == AgentLoopStatus.idle) return null;
    final snapshot = state;
    final runId = _runId;
    final storedEvents = runId == null
        ? const <AgentEvent>[]
        : await _runStore.loadEvents(runId);
    final events = storedEvents.isEmpty ? snapshot.events : storedEvents;
    return AgentRunTranscript.format(snapshot, events);
  }

  /// 종료된 loop의 현재 스냅샷만 비운다. 기존 호출자의 이력 보존 계약을 유지한다.
  /// 대화와 디스크 이력을 함께 삭제하려면 [reset]을 사용한다.
  void clear() {
    if (state.isRunning || state.resetInProgress) return;
    _restoreEpoch++;
    final generation = ++_runGeneration;
    _runId = null;
    _driveFuture = null;
    // idle 공개가 새 실행을 유발할 수 있으므로 삭제를 새 스냅샷 쓰기보다 먼저 큐에 넣는다.
    final clearing = _runStore.clearCurrent();
    state = AgentLoopState.idle;
    unawaited(
      clearing.catchError((Object error) {
        if (!_disposed && generation == _runGeneration) {
          _emit(
            LoopErrorEvent(DateTime.now(), message: '저장된 대화 삭제 실패: $error'),
          );
        }
      }),
    );
  }

  /// 대화창과 loop를 초기화한다. 실행 중이면 먼저 중단한다.
  ///
  /// 중단 직후에도 오케스트레이터는 마지막 이벤트를 emit하므로, drive가 끝날
  /// 때까지 기다린 뒤에 비운다. 기다리지 않으면 늦게 도착한 이벤트가 방금
  /// 비운 타임라인을 되살린다.
  Future<void> reset() {
    if (_disposed) return Future<void>.value();
    final existing = _resetFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _resetFuture = completion.future;
    _restoreEpoch++;
    final runId = _runId;
    final pending = _driveFuture;
    state = state.copyWith(resetInProgress: true);
    _orchestrator?.requestStop();
    unawaited(
      _performReset(runId, pending).then(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack),
      ),
    );
    return completion.future;
  }

  Future<void> _performReset(String? runId, Future<void>? pending) async {
    try {
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // 중단 과정에서 난 오류가 초기화를 막지 않도록 삼킨다.
        }
      }
      // 복원이 아직 도착하지 않았다면 삭제 대상 id만 읽고 UI에는 복원하지 않는다.
      final targetId = runId ?? (await _startupSnapshot)?.runId;
      _runGeneration++;
      if (targetId == null) {
        await _runStore.clearCurrent();
      } else {
        await _runStore.clearRun(targetId);
      }
      if (_disposed) return;
      _orchestrator = null;
      _driveFuture = null;
      _runId = null;
      ref.read(agentChatDraftProvider.notifier).clear();
      // idle 공개 전에 잠금을 풀어, 완료를 기다리던 예약이 안전하게 시작하도록 한다.
      _resetFuture = null;
      state = AgentLoopState.idle;
    } catch (_) {
      if (!_disposed) {
        _resetFuture = null;
        state = state.copyWith(resetInProgress: false);
      }
      rethrow;
    }
  }

  // --- 오케스트레이터 콜백 → state 반영 ---

  /// 실행당 한 번만 저장 실패를 알린다. 알림 자체도 이벤트라 다시 저장을
  /// 시도하므로, 플래그 없이는 실패 → 알림 → 실패가 끝없이 이어진다.
  bool _storeFailureReported = false;

  void _reportStoreFailure(String what, Object error) {
    if (_disposed || _storeFailureReported) return;
    _storeFailureReported = true;
    _emit(
      LoopErrorEvent(
        DateTime.now(),
        message:
            '$what 저장 실패: $error — 실행은 계속되지만 앱을 다시 열면 이 실행이 '
            '복원되지 않을 수 있습니다.',
      ),
    );
  }

  void _emit(AgentEvent event) {
    final runId = _runId;
    if (runId != null) {
      unawaited(
        _runStore
            .appendEvent(runId, event)
            .then((_) {}, onError: (Object e) => _reportStoreFailure('이벤트', e)),
      );
    }
    if (event is HandoffRecordedEvent) {
      _setState(state.copyWith(handoffs: _appendHandoff(event.handoff)));
    }
    final events = [...state.events, event];
    // 요약 행을 포함해 정확히 500개 이하를 유지한다.
    if (events.length > AgentLoopState.maxEvents) {
      final keepCount = AgentLoopState.maxEvents - 1;
      final splitAt = events.length - keepCount;
      var collapsedCount = 0;
      for (final removed in events.take(splitAt)) {
        collapsedCount += removed is CollapsedEvent ? removed.count : 1;
      }
      final collapsed = <AgentEvent>[
        CollapsedEvent(event.at, count: collapsedCount),
        ...events.sublist(splitAt),
      ];
      _setState(state.copyWith(events: collapsed));
      return;
    }
    _setState(state.copyWith(events: events));
  }

  /// 오케스트레이터가 이미 세션당 2개·전체 12개로 다듬어 보내지만, state.handoffs는
  /// 이벤트 스트림을 그대로 따라가며 누적하는 별도 리스트라 같은 상한을 다시 건다.
  static const _maxHandoffsPerSession = 2;
  static const _maxHandoffs = 12;

  List<AgentHandoff> _appendHandoff(AgentHandoff handoff) =>
      appendHandoffWithCaps(
        state.handoffs,
        handoff,
        perSession: _maxHandoffsPerSession,
        total: _maxHandoffs,
      );

  void _onStatus(
    AgentLoopStatus status, {
    int? step,
    AgentPauseReason? pauseReason,
    String? pauseMessage,
  }) {
    AgentLoopOutcome? outcome = state.outcome;
    if (status == AgentLoopStatus.finished) {
      outcome = _lastOutcome() ?? outcome;
    }
    _setState(
      state.copyWith(
        status: status,
        step: step,
        outcome: outcome,
        pauseReason: status == AgentLoopStatus.paused ? pauseReason : null,
        pauseMessage: status == AgentLoopStatus.paused ? pauseMessage : null,
      ),
    );
  }

  AgentLoopOutcome? _lastOutcome() {
    for (final event in state.events.reversed) {
      if (event is LoopFinishedEvent) return event.outcome;
    }
    return null;
  }

  void _onSessionTasks(Map<String, SessionTaskView> tasks) {
    _setState(state.copyWith(sessionTasks: tasks));
  }

  void _onApproval(PendingApproval? approval) {
    _setState(state.copyWith(pendingApproval: approval));
  }

  void _onQuestion(String? question) {
    _setState(state.copyWith(pendingQuestion: question));
  }

  void _onMailbox(List<AgentMessage> pending) {
    _setState(state.copyWith(undeliveredMessages: List.unmodifiable(pending)));
  }

  Future<void> _restoreLatestRun() async {
    final epoch = _restoreEpoch;
    AgentRunSnapshot? snapshot;
    try {
      snapshot = await _startupSnapshot;
    } catch (_) {
      return;
    }
    if (_disposed ||
        epoch != _restoreEpoch ||
        snapshot == null ||
        state.status != AgentLoopStatus.idle) {
      return;
    }
    _runId = snapshot.runId;
    final restored = snapshot.state;
    if (!restored.isRunning) {
      state = restored;
      return;
    }

    final now = DateTime.now();
    final startedAt = restored.startedAt ?? snapshot.savedAt;
    final rawElapsed = now.difference(startedAt);
    final finished = LoopFinishedEvent(
      now,
      outcome: AgentLoopOutcome.partial,
      summary:
          '앱이 종료되어 실행 중이던 loop가 중단되었습니다. '
          '현재 상태를 확인한 뒤 같은 목표 이어가기로 계속할 수 있습니다.',
      steps: restored.step,
      elapsed: rawElapsed.isNegative ? Duration.zero : rawElapsed,
    );
    unawaited(
      _runStore
          .appendEvent(snapshot.runId, finished)
          .then((_) {}, onError: (Object e) => _reportStoreFailure('이벤트', e)),
    );
    _setState(
      restored.copyWith(
        status: AgentLoopStatus.finished,
        events: _cappedEvents([...restored.events, finished]),
        pendingApproval: null,
        pendingQuestion: null,
        pauseReason: null,
        pauseMessage: null,
        outcome: AgentLoopOutcome.partial,
      ),
    );
  }

  List<AgentEvent> _cappedEvents(List<AgentEvent> events) {
    if (events.length <= AgentLoopState.maxEvents) return events;
    final keepCount = AgentLoopState.maxEvents - 1;
    final splitAt = events.length - keepCount;
    var omittedCount = 0;
    for (final removed in events.take(splitAt)) {
      omittedCount += removed is CollapsedEvent ? removed.count : 1;
    }
    return [
      CollapsedEvent(events[splitAt].at, count: omittedCount),
      ...events.sublist(splitAt),
    ];
  }

  void _setState(AgentLoopState next) {
    state = next;
    final runId = _runId;
    if (runId == null || next.status == AgentLoopStatus.idle) return;
    unawaited(
      _runStore
          .saveCurrent(
            AgentRunSnapshot(
              runId: runId,
              savedAt: DateTime.now(),
              state: next,
            ),
          )
          .then((_) {}, onError: (Object e) => _reportStoreFailure('스냅샷', e)),
    );
  }
}

final agentChatProvider = NotifierProvider<AgentChatNotifier, AgentLoopState>(
  AgentChatNotifier.new,
);
