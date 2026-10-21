import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session.dart';
import '../state/providers.dart';
import 'agent_chat_notifier.dart';
import 'agent_models.dart';
import 'agent_schedule.dart';
import '../ai/routines/ai_chat_routine_runner.dart';
import 'agent_session_role.dart';
import 'agent_schedule_store.dart';
import 'agent_schedule_claim_store.dart';
import 'agent_scheduler.dart';

/// 테스트에서 실제 [Timer] 대신 가짜 타이머를 꽂기 위한 provider.
/// null이면 [AgentScheduler]의 기본 타이머를 쓴다.
final agentScheduleTimerFactoryProvider = Provider<AgentTimerFactory?>(
  (ref) => null,
);

/// Agent Chat 예약 목록을 소유하고, 시각이 되면 loop를 시작시키는 Notifier.
///
/// 앱 수준 provider라 패널을 닫아도 타이머가 산다. 예약이 실제로 loop가 되는
/// 조건(AI 설정, 세션 연결, 현재 loop 유무)은 여기서 판단하고, 시각 계산과
/// 타이머는 [AgentScheduler]에 맡긴다.
///
/// [AgentChatNotifier]와의 관계: 이 Notifier가 만들어질 때 chat Notifier에
/// `scheduleHandler`를 꽂아 플래너의 `schedule` 액션이 여기로 오게 한다. 반대로
/// chat 상태를 구독해 loop가 끝나는 순간 미뤄둔 예약을 다시 묻는다.
class AgentScheduleStorageStatus extends Notifier<String?> {
  @override
  String? build() => null;
  void report(String? error) => state = error;
}

final agentScheduleStorageStatusProvider =
    NotifierProvider<AgentScheduleStorageStatus, String?>(
      AgentScheduleStorageStatus.new,
    );

class AgentScheduleNotifier extends Notifier<List<AgentScheduledTask>> {
  Future<void> _lastSave = Future.value();
  late AgentScheduleStore _store;
  late AgentScheduler _scheduler;
  Future<void>? _restoreFuture;
  bool _disposed = false;
  Object? _restoreError;
  final Map<String, String> _manualOccurrences = {};
  int _manualSequence = 0;

  @override
  List<AgentScheduledTask> build() {
    _store = ref.read(agentScheduleStoreProvider);
    _scheduler = AgentScheduler(
      onDue: _handleDue,
      onChanged: _onChanged,
      timerFactory: ref.read(agentScheduleTimerFactoryProvider),
    );
    ref.onDispose(() {
      _disposed = true;
      _scheduler.dispose();
    });
    // loop가 끝나면 예약으로 시작한 실행이면 결과를 예약에 남기고, '대기'
    // 정책으로 미뤄둔 예약을 곧바로 다시 묻는다.
    ref.listen<AgentLoopState>(agentChatProvider, (previous, next) {
      final wasRunning = previous?.isRunning == true;
      if (wasRunning && !next.isRunning) {
        _recordActiveRunResult(next);
        if (next.canStart) unawaited(_scheduler.tick());
      } else if (previous?.canStart != true && next.canStart) {
        unawaited(_scheduler.tick());
      } else if (!wasRunning && next.isRunning) {
        // loop가 새로 시작되면 "loop 실행 대기" 중이던 메시지 예약을 바로 넣는다.
        unawaited(_scheduler.tick());
      }
    });
    ref.read(agentChatProvider.notifier).scheduleHandler = addFromRequest;
    _restoreFuture = _restore();
    return const [];
  }

  AgentScheduler get scheduler => _scheduler;

  /// 사용자가 패널에서 예약을 등록한다.
  Future<AgentScheduledTask> add({
    required AgentGoalSpec goalSpec,
    required List<String> allowedSessionIds,
    required AgentScheduleTrigger trigger,
    Map<String, AgentSessionRole> sessionRoles = const {},
    AgentScheduleConflictPolicy conflictPolicy =
        AgentScheduleConflictPolicy.wait,
    Duration? timeBudget,
    AgentScheduleOrigin origin = AgentScheduleOrigin.user,
    String? reason,
  }) async {
    final bindings = _captureBindings(allowedSessionIds);
    await _restoreFuture;
    if (_restoreError != null) {
      throw StateError('예약 파일을 먼저 복구해 주세요: $_restoreError');
    }
    final now = clock.now();
    final task = AgentScheduledTask(
      id: _scheduler.newId(),
      goalSpec: goalSpec.withDeadline(null).normalized(),
      allowedSessionIds: List.unmodifiable(allowedSessionIds),
      sessionBindings: bindings,
      sessionRoles: Map.unmodifiable(sessionRoles),
      trigger: trigger,
      conflictPolicy: conflictPolicy,
      origin: origin,
      createdAt: now,
      timeBudget: timeBudget,
      reason: reason,
    );
    final added = _scheduler.add(task);
    await _lastSave;
    return added;
  }

  /// 플래너의 `schedule` 액션. 1회 예약으로 등록한다.
  Future<AgentScheduledTask?> addFromRequest(
    AgentScheduleRequest request,
  ) async {
    if (_disposed || request.allowedSessionIds.isEmpty) return null;
    return add(
      goalSpec: request.goal,
      allowedSessionIds: request.allowedSessionIds,
      sessionRoles: request.sessionRoles,
      trigger: AgentScheduleTrigger.once(request.runAt),
      timeBudget: request.timeBudget,
      origin: AgentScheduleOrigin.orchestrator,
      reason: request.reason,
    );
  }

  bool remove(String id) => _scheduler.remove(id);

  bool setEnabled(String id, bool enabled) =>
      _scheduler.setEnabled(id, enabled);

  /// 기존 예약의 목표·세션·트리거를 바꾼다. 실행 이력은 유지된다.
  Future<bool> update(
    String id, {
    required AgentGoalSpec goalSpec,
    required List<String> allowedSessionIds,
    required AgentScheduleTrigger trigger,
    Map<String, AgentSessionRole> sessionRoles = const {},
    AgentScheduleConflictPolicy conflictPolicy =
        AgentScheduleConflictPolicy.wait,
    Duration? timeBudget,
  }) async {
    final bindings = _captureBindings(allowedSessionIds);
    await _restoreFuture;
    if (_restoreError != null) {
      throw StateError('예약 파일을 먼저 복구해 주세요: $_restoreError');
    }
    final existing = _scheduler.byId(id);
    if (existing == null) return false;
    final replaced = _scheduler.replace(
      existing.copyWith(
        goalSpec: goalSpec.withDeadline(null).normalized(),
        allowedSessionIds: List.unmodifiable(allowedSessionIds),
        sessionBindings: bindings,
        sessionRoles: Map.unmodifiable(sessionRoles),
        trigger: trigger,
        conflictPolicy: conflictPolicy,
        timeBudget: timeBudget,
        enabled: true,
      ),
    );
    await _lastSave;
    return replaced;
  }

  /// 예약 시각을 기다리지 않고 지금 실행을 시도한다.
  Future<AgentScheduleDueResult?> runNow(String id) async {
    await _restoreFuture;
    if (_restoreError != null) {
      throw StateError('예약 파일을 먼저 복구해 주세요: $_restoreError');
    }
    if (_manualOccurrences.containsKey(id)) {
      return AgentScheduleDueResult.deferred;
    }
    _manualOccurrences[id] =
        'manual:${DateTime.now().toUtc().microsecondsSinceEpoch}:${_manualSequence++}';
    try {
      return await _scheduler.runNow(id);
    } finally {
      _manualOccurrences.remove(id);
    }
  }

  /// 시각이 된 예약을 지금 확인한다. 테스트와 수동 새로고침용.
  Future<void> tick() => _scheduler.tick();

  /// 예약이 시작시킨 현재 loop의 예약 id. 끝나면 결과를 그 예약에 남긴다.
  String? _activeTaskId;

  void _recordActiveRunResult(AgentLoopState finished) {
    final id = _activeTaskId;
    if (id == null) return;
    _activeTaskId = null;
    final outcome = finished.outcome;
    final outcomeLabel = switch (outcome) {
      AgentLoopOutcome.achieved => '달성',
      AgentLoopOutcome.partial => '부분 완료',
      AgentLoopOutcome.blocked => '차단',
      AgentLoopOutcome.stopped => '중단됨',
      AgentLoopOutcome.failed => '실패',
      null => '종료',
    };
    String? summary;
    for (final event in finished.events.reversed) {
      if (event is LoopFinishedEvent) {
        summary = event.summary;
        break;
      }
    }
    final now = clock.now();
    final at = AgentScheduleTrigger.formatDateTime(now);
    final trimmed = summary?.trim() ?? '';
    _scheduler.recordRun(
      id,
      AgentScheduleRunRecord(
        startedAt: finished.startedAt ?? now,
        finishedAt: now,
        outcome: outcome?.name ?? 'finished',
        summary: trimmed,
        steps: finished.step,
        runId: _activeRunId,
      ),
      summary: trimmed.isEmpty
          ? '$at $outcomeLabel'
          : '$at $outcomeLabel · $trimmed',
    );
    _activeRunId = null;
  }

  /// 예약이 시작한 loop의 실행 기록 id. 결과 기록에 붙여 타임라인을 찾게 한다.
  String? _activeRunId;

  /// 세션 우편함에 메시지를 넣는 예약을 등록한다.
  Future<AgentScheduledTask> addMessage({
    required String sessionId,
    required String body,
    required AgentScheduleTrigger trigger,
  }) async {
    final bindings = _captureBindings([sessionId]);
    await _restoreFuture;
    if (_restoreError != null) {
      throw StateError('예약 파일을 먼저 복구해 주세요: $_restoreError');
    }
    final now = clock.now();
    final added = _scheduler.add(
      AgentScheduledTask(
        id: _scheduler.newId(),
        kind: AgentScheduleTaskKind.message,
        messageBody: body.trim(),
        goalSpec: AgentGoalSpec(objective: body.trim()),
        allowedSessionIds: List.unmodifiable([sessionId]),
        sessionBindings: bindings,
        trigger: trigger,
        createdAt: now,
      ),
    );
    await _lastSave;
    return added;
  }

  /// AI Chat 루틴을 등록한다. 세션 하나에 저장한 프롬프트로 AI Chat 턴을
  /// 예약 시각마다 헤드리스로 돌린다.
  Future<AgentScheduledTask> addAiChatRoutine({
    required String sessionId,
    required String prompt,
    required AgentScheduleTrigger trigger,
    bool terminalToolCall = false,
  }) async {
    final bindings = _captureBindings([sessionId]);
    await _restoreFuture;
    if (_restoreError != null) {
      throw StateError('예약 파일을 먼저 복구해 주세요: $_restoreError');
    }
    final body = prompt.trim();
    final added = _scheduler.add(
      AgentScheduledTask(
        id: _scheduler.newId(),
        kind: AgentScheduleTaskKind.aiChat,
        messageBody: body,
        terminalToolCall: terminalToolCall,
        goalSpec: AgentGoalSpec(objective: body),
        allowedSessionIds: List.unmodifiable([sessionId]),
        sessionBindings: bindings,
        trigger: trigger,
        createdAt: clock.now(),
      ),
    );
    await _lastSave;
    return added;
  }

  /// AI Chat 루틴의 세션·프롬프트·트리거·터미널 입력 허용 여부를 바꾼다.
  Future<bool> updateAiChatRoutine(
    String id, {
    required String sessionId,
    required String prompt,
    required AgentScheduleTrigger trigger,
    required bool terminalToolCall,
  }) async {
    final bindings = _captureBindings([sessionId]);
    await _restoreFuture;
    if (_restoreError != null) {
      throw StateError('예약 파일을 먼저 복구해 주세요: $_restoreError');
    }
    final existing = _scheduler.byId(id);
    if (existing == null || !existing.isAiChat) return false;
    final body = prompt.trim();
    final replaced = _scheduler.replace(
      existing.copyWith(
        messageBody: body,
        terminalToolCall: terminalToolCall,
        goalSpec: AgentGoalSpec(objective: body),
        allowedSessionIds: List.unmodifiable([sessionId]),
        sessionBindings: bindings,
        trigger: trigger,
        enabled: true,
      ),
    );
    await _lastSave;
    return replaced;
  }

  /// AI Chat 루틴을 실행한다. 건너뜀 사유는 실행 전에 확인하고, 실제 턴은
  /// 스케줄러 tick을 잡아 두지 않도록 뒤에서 돌린 뒤 결과를 기록한다.
  Future<void> _runAiChatRoutine(
    AgentScheduledTask task,
    AiChatRoutineRunner runner,
  ) async {
    final startedAt = clock.now();
    AiChatRoutineResult result;
    try {
      result = await runner.run(task);
    } catch (error) {
      result = AiChatRoutineResult.failed('$error');
    }
    if (_disposed) return;
    final now = clock.now();
    final at = AgentScheduleTrigger.formatDateTime(now);
    _scheduler.recordRun(
      task.id,
      AgentScheduleRunRecord(
        startedAt: startedAt,
        finishedAt: now,
        outcome: result.outcome,
        summary: result.summary,
        steps: 1,
      ),
      summary: '$at ${result.failed ? '실패' : '실행'} · ${result.summary}',
    );
  }

  /// 메시지 예약의 수신 세션·본문·트리거를 바꾼다.
  Future<bool> updateMessage(
    String id, {
    required String sessionId,
    required String body,
    required AgentScheduleTrigger trigger,
  }) async {
    final bindings = _captureBindings([sessionId]);
    await _restoreFuture;
    if (_restoreError != null) {
      throw StateError('예약 파일을 먼저 복구해 주세요: $_restoreError');
    }
    final existing = _scheduler.byId(id);
    if (existing == null || !existing.isMessage) return false;
    final replaced = _scheduler.replace(
      existing.copyWith(
        messageBody: body.trim(),
        goalSpec: AgentGoalSpec(objective: body.trim()),
        allowedSessionIds: List.unmodifiable([sessionId]),
        sessionBindings: bindings,
        trigger: trigger,
        enabled: true,
      ),
    );
    await _lastSave;
    return replaced;
  }

  /// 메시지 예약을 처리한다. 수신 세션을 포함한 loop가 돌고 있을 때만 넣고,
  /// 아니면 그런 loop가 시작될 때까지 미룬다(상태 구독이 시작 순간 다시 묻는다).
  AgentScheduleDueResult _deliverScheduledMessage(AgentScheduledTask task) {
    final sessionId = task.messageSessionId;
    final body = task.messageBody?.trim() ?? '';
    if (sessionId == null || body.isEmpty) {
      return const AgentScheduleDueResult.skipped('수신 세션이나 본문이 없어 건너뜀');
    }
    final loop = ref.read(agentChatProvider);
    if (!loop.isRunning || !loop.sessionTasks.containsKey(sessionId)) {
      return AgentScheduleDueResult.deferred;
    }
    final posted = ref
        .read(agentChatProvider.notifier)
        .postInboxMessage(sessionId: sessionId, body: body);
    if (!posted) return AgentScheduleDueResult.deferred;
    final now = clock.now();
    _scheduler.recordRun(
      task.id,
      AgentScheduleRunRecord(
        startedAt: now,
        finishedAt: now,
        outcome: 'delivered',
        summary:
            '${loop.sessionTasks[sessionId]?.displayName ?? sessionId} 우편함에 넣음',
        steps: loop.step,
      ),
    );
    return AgentScheduleDueResult.started;
  }

  Future<void> _restore() async {
    try {
      final tasks = await _store.load();
      if (_disposed) return;
      _restoreError = null;
      _scheduler.load([
        for (final task in tasks)
          task.allowedSessionIds.every(task.sessionBindings.containsKey)
              ? task
              : task.copyWith(
                  enabled: false,
                  lastResult: '보안 업데이트: 예약 대상 세션을 다시 선택하세요.',
                ),
      ]);
    } catch (error) {
      _restoreError = error;
      if (!_disposed) {
        ref
            .read(agentScheduleStorageStatusProvider.notifier)
            .report('예약 복구 실패: $error');
      }
    }
  }

  void _onChanged(List<AgentScheduledTask> tasks) {
    if (_disposed) return;
    state = tasks;
    _lastSave = _store.save(tasks);
    unawaited(
      _lastSave.then(
        (_) {
          if (!_disposed) {
            ref.read(agentScheduleStorageStatusProvider.notifier).report(null);
          }
        },
        onError: (Object error) {
          if (!_disposed) {
            ref
                .read(agentScheduleStorageStatusProvider.notifier)
                .report('예약 저장 실패: $error');
          }
        },
      ),
    );
  }

  Future<void> retrySave() async {
    if (_restoreError != null) {
      await _restore();
      if (_restoreError != null) throw StateError('예약 복구 실패: $_restoreError');
    } else {
      _onChanged(state);
    }
    await _lastSave;
  }

  Future<AgentScheduleDueResult?> _claim(AgentScheduledTask task) async {
    final store = _store;
    if (store is! AgentScheduleClaimStore) return null;
    final occurrence =
        _manualOccurrences[task.id] ??
        task.nextRunAt?.toUtc().toIso8601String();
    if (occurrence == null) {
      return const AgentScheduleDueResult.skipped('실행 회차를 확인할 수 없습니다');
    }
    try {
      final claimed = await (store as AgentScheduleClaimStore).claimOccurrence(
        '${task.id}:$occurrence',
      );
      return claimed
          ? null
          : const AgentScheduleDueResult.skipped(
              '이미 시작을 기록한 회차입니다. 이전 실행 결과를 확인한 뒤 필요하면 지금 실행하세요.',
            );
    } catch (error) {
      if (!_disposed) {
        ref
            .read(agentScheduleStorageStatusProvider.notifier)
            .report('예약 실행 기록 저장 실패: $error');
      }
      return AgentScheduleDueResult.deferred;
    }
  }

  String _binding(SessionInfo session) =>
      jsonEncode([session.host.id, session.authorizationId]);

  Map<String, String> _captureBindings(List<String> ids) {
    final sessions = {
      for (final s in ref.read(sessionManagerProvider)) s.id: s,
    };
    return Map.unmodifiable({
      for (final id in ids)
        id: sessions[id] == null
            ? throw StateError('예약할 세션을 다시 선택하세요: $id')
            : _binding(sessions[id]!),
    });
  }

  bool _bindingsMatch(AgentScheduledTask task) {
    final sessions = {
      for (final s in ref.read(sessionManagerProvider)) s.id: s,
    };
    return task.allowedSessionIds.every(
      (id) =>
          task.sessionBindings.containsKey(id) &&
          (sessions[id] == null ||
              task.sessionBindings[id] == _binding(sessions[id]!)),
    );
  }

  bool _sameConnections(Map<String, SessionInfo> before) {
    final current = {for (final s in ref.read(sessionManagerProvider)) s.id: s};
    return before.entries.every(
      (e) =>
          current[e.key] != null &&
          identical(e.value.engine, current[e.key]!.engine) &&
          e.value.connectedAt == current[e.key]!.connectedAt &&
          e.value.status == current[e.key]!.status &&
          _binding(e.value) == _binding(current[e.key]!),
    );
  }

  Future<AgentScheduleDueResult> _handleDue(AgentScheduledTask task) async {
    try {
      await _lastSave;
    } catch (_) {
      return AgentScheduleDueResult.deferred;
    }
    if (_disposed) return AgentScheduleDueResult.deferred;
    if (!_bindingsMatch(task)) {
      return const AgentScheduleDueResult.skipped(
        '예약 대상 권한이 달라졌습니다. 세션을 다시 선택하세요.',
      );
    }
    final connections = {
      for (final s in ref.read(sessionManagerProvider))
        if (task.allowedSessionIds.contains(s.id)) s.id: s,
    };

    if (ref.read(agentChatProvider).resetInProgress) {
      return AgentScheduleDueResult.deferred;
    }
    if (task.isMessage) {
      final loop = ref.read(agentChatProvider);
      if (!loop.isRunning ||
          !loop.sessionTasks.containsKey(task.messageSessionId)) {
        return AgentScheduleDueResult.deferred;
      }
      final claimed = await _claim(task);
      if (claimed != null) return claimed;
      if (_disposed ||
          !_bindingsMatch(task) ||
          !_sameConnections(connections)) {
        return const AgentScheduleDueResult.skipped('예약 대상 연결이 변경되었습니다.');
      }
      return _deliverScheduledMessage(task);
    }
    if (task.isAiChat) {
      final runner = ref.read(aiChatRoutineRunnerProvider);
      final reason = runner.skipReason(task);
      if (reason != null) return AgentScheduleDueResult.skipped(reason);
      final claimed = await _claim(task);
      if (claimed != null) return claimed;
      if (_disposed ||
          !_bindingsMatch(task) ||
          !_sameConnections(connections)) {
        return const AgentScheduleDueResult.skipped('예약 대상 연결이 변경되었습니다.');
      }
      if (_disposed) return AgentScheduleDueResult.deferred;
      unawaited(_runAiChatRoutine(task, runner));
      return AgentScheduleDueResult.started;
    }
    final settings = ref.read(appSettingsProvider).ai;
    if (!settings.isConfigured) {
      return const AgentScheduleDueResult.skipped('AI 설정이 없어 건너뜀');
    }
    final connected = {
      for (final session in ref.read(sessionManagerProvider))
        if (session.status == SessionStatus.connected) session.id,
    };
    final sessionIds = [
      for (final id in task.allowedSessionIds)
        if (connected.contains(id)) id,
    ];
    if (sessionIds.isEmpty) {
      return const AgentScheduleDueResult.skipped('예약한 세션이 연결되어 있지 않아 건너뜀');
    }

    if (!ref.read(agentChatProvider).canStart &&
        task.conflictPolicy == AgentScheduleConflictPolicy.wait) {
      return AgentScheduleDueResult.deferred;
    }
    final claimed = await _claim(task);
    if (claimed != null) return claimed;
    if (_disposed || !_bindingsMatch(task) || !_sameConnections(connections)) {
      return const AgentScheduleDueResult.skipped('예약 대상 연결이 변경되었습니다.');
    }
    if (_disposed) return AgentScheduleDueResult.deferred;
    final chat = ref.read(agentChatProvider.notifier);
    String? interruptedGoal;
    if (!ref.read(agentChatProvider).canStart) {
      switch (task.conflictPolicy) {
        case AgentScheduleConflictPolicy.wait:
          return AgentScheduleDueResult.deferred;
        case AgentScheduleConflictPolicy.interrupt:
          interruptedGoal = ref.read(agentChatProvider).goal;
          // 중단되는 loop도 예약이 시작한 것이면 그 사실을 남긴다. 상태 구독이
          // finished를 보고 결과를 적기 전에 어느 예약이었는지 잊지 않게 한다.
          await chat.stopAndWait();
          if (ref.read(agentChatProvider).resetInProgress) {
            return AgentScheduleDueResult.deferred;
          }
          if (_disposed) return AgentScheduleDueResult.deferred;
      }
    }

    if (!_bindingsMatch(task) || !_sameConnections(connections)) {
      return const AgentScheduleDueResult.skipped('예약 대상 연결이 변경되었습니다.');
    }
    final now = clock.now();
    final budget = task.timeBudget;
    final goal = task.goalSpec.withDeadline(
      budget == null ? null : now.add(budget),
    );
    final started = chat.start(
      goal: goal.objective,
      allowedSessionIds: sessionIds,
      goalSpec: goal,
      sessionRoles: {
        for (final entry in task.sessionRoles.entries)
          if (sessionIds.contains(entry.key)) entry.key: entry.value,
      },
      scheduledStart: AgentScheduledStart(
        taskId: task.id,
        title: task.title,
        triggerLabel: task.trigger.label,
        interruptedGoal: interruptedGoal,
      ),
    );
    if (started) {
      _activeTaskId = task.id;
      _activeRunId = chat.currentRunId;
    }
    return started
        ? AgentScheduleDueResult.started
        : const AgentScheduleDueResult.skipped('loop를 시작하지 못해 건너뜀');
  }
}

final agentScheduleProvider =
    NotifierProvider<AgentScheduleNotifier, List<AgentScheduledTask>>(
      AgentScheduleNotifier.new,
    );
