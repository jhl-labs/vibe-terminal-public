import 'dart:async';

import 'package:clock/clock.dart';

import '../core/korean_particle.dart';
import '../ai/ai_chat_service.dart';
import 'agent_capability_classifier.dart';
import 'agent_mailbox.dart';
import 'agent_models.dart';
import 'agent_prompts.dart';
import 'agent_schedule.dart';
import 'agent_session_role.dart';
import 'agent_session_inspector.dart';
import 'quiescence_detector.dart';
import 'risk_classifier.dart';
import 'session_port.dart';
import 'session_intervention.dart';
import 'terminal_screen_delta.dart';
import 'terminal_runtime_issue_detector.dart';

/// 오케스트레이터가 LLM을 호출하는 방식. AiChatService.complete를 감싸 주입한다.
typedef CompletionFn =
    Future<String> Function({
      required String system,
      required List<AiChatMessage> messages,
      AiCancelToken? cancelToken,
    });

/// loop 실행 결과.
class AgentRunResult {
  const AgentRunResult({
    required this.outcome,
    required this.summary,
    required this.steps,
  });

  final AgentLoopOutcome outcome;
  final String summary;
  final int steps;
}

/// Agent Chat의 Loop Engineering 상태 기계 구동자.
///
/// UI/Riverpod을 모른다. 세션 접근은 [SessionPortRegistry], LLM 호출은
/// [CompletionFn], 이벤트/상태 반영은 콜백으로 주입받는다. pause/stop/feedback/
/// approval/answer는 외부(Notifier)가 메서드로 밀어 넣는다.
class AgentOrchestrator {
  AgentOrchestrator({
    required this.registry,
    required this.completion,
    required this.linesPerSession,
    required this.emit,
    required this.onStatus,
    required this.onSessionTasks,
    required this.onApproval,
    required this.onQuestion,
    this.maxSteps = AgentLoopState.defaultMaxSteps,
    this.maxActionsPerStep = 8,
    this._classifier = const RiskClassifier(),
    this._runtimeIssueDetector = const TerminalRuntimeIssueDetector(),
    QuiescenceDetector Function()? detectorFactory,
    Future<void> Function(Duration)? sleep,
    Future<void> Function(Duration)? submitSleep,
    String Function(String)? keyNormalizer,
    this.pollInterval = const Duration(milliseconds: 750),
    this.quiescenceTimeout = const Duration(seconds: 180),
    this.settleDelay = const Duration(milliseconds: 650),
    this.submitDelay = const Duration(milliseconds: 120),
    this.completionTimeout = const Duration(seconds: 130),
  }) : _detectorFactory = detectorFactory ?? QuiescenceDetector.new,
       _sleep = sleep ?? _realSleep,
       // 루프 페이싱 sleep과 분리한다. 테스트가 주입하는 [sleep]은 관찰 단계의
       // 진행을 제어하려는 것이라, 전송 내부의 짧은 대기까지 그리로 보내면
       // 그 테스트들의 의도가 깨진다.
       _submitSleep = submitSleep ?? _realSleep,
       _keyNormalizer = keyNormalizer ?? _identity;

  final SessionPortRegistry registry;
  final CompletionFn completion;
  final int linesPerSession;
  final void Function(AgentEvent) emit;
  final void Function(
    AgentLoopStatus status, {
    int? step,
    AgentPauseReason? pauseReason,
    String? pauseMessage,
  })
  onStatus;
  final void Function(Map<String, SessionTaskView>) onSessionTasks;
  final void Function(PendingApproval?) onApproval;
  final void Function(String?) onQuestion;

  /// 우편함의 미배달 메시지가 바뀔 때마다 전체 목록을 받는다.
  ///
  /// 생성자 인자가 아니라 필드인 이유: 기존 생성 훅(테스트의 factory)을 깨지
  /// 않고 뒤에서 붙일 수 있게 하려는 것이다. null이면 알리지 않는다.
  void Function(List<AgentMessage> pending)? onMailbox;

  /// 플래너의 `schedule` 액션을 실제 예약으로 바꾸는 콜백. null이면 액션을
  /// 거절한다(예약 기능이 없는 환경).
  Future<AgentScheduledTask?> Function(AgentScheduleRequest request)?
  onSchedule;

  /// 한 실행에서 플래너가 등록할 수 있는 후속 예약 수. 폭주 방지.
  static const maxSchedulesPerRun = 3;

  /// 후속 예약은 이보다 먼 미래로 잡을 수 없다.
  static const maxScheduleHorizon = Duration(hours: 24);

  int maxSteps;
  final int maxActionsPerStep;
  final RiskClassifier _classifier;
  final TerminalRuntimeIssueDetector _runtimeIssueDetector;
  final QuiescenceDetector Function() _detectorFactory;
  final Future<void> Function(Duration) _sleep;
  final Future<void> Function(Duration) _submitSleep;
  final String Function(String) _keyNormalizer;
  final Duration pollInterval;
  final Duration quiescenceTimeout;
  final Duration settleDelay;

  /// 프롬프트 본문을 보낸 뒤 Enter를 보내기까지 기다리는 시간.
  ///
  /// 인라인 TUI가 본문을 입력창에 반영할 틈을 준다. 0으로 두면 본문과 Enter가
  /// 한 번에 도착해 붙여넣기로 처리되고, 개행이 제출 대신 줄바꿈이 된다.
  final Duration submitDelay;

  /// 서비스 구현이 자체 timeout/취소 계약을 지키지 않아도 모델 대기를 끝낸다.
  final Duration completionTimeout;

  final AiCancelToken _cancelToken = AiCancelToken();
  final List<String> _feedbackQueue = [];
  final Map<String, String> _agentHints = {};

  /// 세션별로 지금까지 얻은 최고 확신도. 힌트를 되돌리지 않기 위한 기준.
  final Map<String, AgentDetectionConfidence> _agentHintConfidence = {};

  /// 화면에서 감지한 모델 라벨(세션별 최고 확신도, CLI 무관).
  final Map<String, String> _modelHints = {};
  final Map<String, AgentDetectionConfidence> _modelHintConfidence = {};
  final Map<String, SessionTaskView> _tasks = {};
  final Map<String, Object> _interventionConnections = {};
  final _interventionDetector = const SessionInterventionDetector();

  /// 세션 간 메시지 큐. loop 하나가 소유하고 배달까지 책임진다.
  final AgentMailbox _mailbox = AgentMailbox();

  /// await:false로 내보내 아직 관찰이 끝나지 않은 세션들.
  final Map<String, Future<_ActionOutcome>> _background = {};

  /// 배경 관찰이 끝났지만 아직 어느 step에도 회수되지 않은 결과들.
  final List<_ActionOutcome> _backgroundResults = [];

  Map<String, AgentSessionRole> _sessionRoles = const {};

  /// 세션별 최근 인계 기록. 세션당 2개, 전체 12개까지만 유지한다.
  final List<AgentHandoff> _handoffs = [];

  /// 이번 실행에서 설계 세션(architect/lead)의 인계가 한 번이라도 기록됐는지.
  ///
  /// [_handoffs]는 상한(세션당·전체)으로 오래된 항목을 버리므로, 세션이 많으면
  /// 초기 설계 인계가 밀려난다. 순서 강제 게이트가 그 리스트만 보면 이미 구현
  /// 중인 세션을 뒤늦게 막게 되어 별도 플래그로 기억한다.
  bool _designHandoffSeen = false;
  static const _maxHandoffsPerSession = 2;
  static const _maxHandoffs = 12;

  /// 역할 정책 거부 횟수. 키는 `세션id|capability`.
  ///
  /// 같은 조합으로 2번 거부한 뒤에도 또 시도하면 사용자에게 예외 승인을 묻는다.
  final Map<String, int> _rolePolicyRejections = {};

  /// 사용자가 예외 승인을 거부한 `세션id|capability`. 이번 실행 동안 다시 묻지
  /// 않고 조용히 거부한다.
  final Set<String> _rolePolicyDenied = {};
  late AgentGoalSpec _goal;
  int _scheduledCount = 0;

  /// 현재 목표 계약. 마감 연장 뒤 Notifier가 상태에 반영할 때 읽는다.
  AgentGoalSpec get goal => _goal;

  /// 지금까지 쌓인 인계 기록(세션당 2개·전체 12개로 다듬어진 뒤).
  List<AgentHandoff> get handoffs => List.unmodifiable(_handoffs);

  bool _stopped = false;
  int _controlRevision = 0;

  /// loop가 결과를 내고 끝났는지. 남아 있던 배경 관찰이 종료된 타임라인에
  /// 뒤늦게 이벤트를 붙이지 못하게 막는다.
  bool _finished = false;
  bool _paused = false;
  AgentLoopStatus _currentStatus = AgentLoopStatus.planning;
  AgentLoopStatus _resumeStatus = AgentLoopStatus.planning;
  int _currentStep = 0;
  AgentPauseReason? _pauseReason;
  String? _pauseMessage;
  final Completer<void> _stopCompleter = Completer<void>();
  Completer<void> _pauseSignal = Completer<void>();
  Completer<void>? _resumeCompleter;
  Completer<bool>? _approvalCompleter;
  Completer<String>? _answerCompleter;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);
  static String _identity(String s) => s;

  // --- 외부 제어 API ---

  void requestStop() {
    if (_stopped) return;
    _stopped = true;
    _controlRevision++;
    _cancelToken.cancel();
    if (!_stopCompleter.isCompleted) _stopCompleter.complete();
    final resume = _resumeCompleter;
    if (resume != null && !resume.isCompleted) resume.complete();
    final approval = _approvalCompleter;
    if (approval != null && !approval.isCompleted) approval.complete(false);
    final answer = _answerCompleter;
    if (answer != null && !answer.isCompleted) answer.complete('');
  }

  void requestPause() {
    _controlRevision++;
    if (_stopped || _paused || !_canPause(_currentStatus)) return;
    _paused = true;
    _pauseReason = AgentPauseReason.user;
    _pauseMessage = '사용자가 loop를 일시정지했습니다.';
    _resumeStatus = _currentStatus;
    _resumeCompleter = Completer<void>();
    if (!_pauseSignal.isCompleted) _pauseSignal.complete();
    _transition(
      AgentLoopStatus.paused,
      step: _currentStep,
      pauseReason: _pauseReason,
      pauseMessage: _pauseMessage,
    );
  }

  void requestResume() {
    if (!_paused) return;
    // 예산·마감은 그 값을 늘려야만 이어진다. 그냥 재개하면 같은 자리에서
    // 곧바로 다시 멈춘다.
    if (_pauseReason == AgentPauseReason.budgetExhausted) return;
    if (_pauseReason == AgentPauseReason.deadlineReached) return;
    _paused = false;
    _pauseReason = null;
    _pauseMessage = null;
    _pauseSignal = Completer<void>();
    _transition(_resumeStatus, step: _currentStep);
    final completer = _resumeCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    _resumeCompleter = null;
  }

  void extendBudget([int by = 10]) {
    if (_stopped || by <= 0) return;
    maxSteps += by;
    if (_paused && _pauseReason == AgentPauseReason.budgetExhausted) {
      _paused = false;
      _pauseReason = null;
      _pauseMessage = null;
      _pauseSignal = Completer<void>();
      _transition(_resumeStatus, step: _currentStep);
      final completer = _resumeCompleter;
      if (completer != null && !completer.isCompleted) completer.complete();
      _resumeCompleter = null;
    }
  }

  /// 마감을 [by]만큼 뒤로 미룬다. 마감 도달로 멈춰 있었다면 이어서 실행한다.
  ///
  /// 마감이 이미 지났으면 지금 시각부터 [by]를 더한다. 지난 마감에 더하면
  /// 연장해도 여전히 과거라 곧바로 다시 멈춘다.
  void extendDeadline(Duration by) {
    if (_stopped || by <= Duration.zero) return;
    final now = _now();
    final base = _goal.deadline;
    final target = base == null || base.isBefore(now)
        ? now.add(by)
        : base.add(by);
    _goal = _goal.withDeadline(target);
    if (_paused && _pauseReason == AgentPauseReason.deadlineReached) {
      _paused = false;
      _pauseReason = null;
      _pauseMessage = null;
      _pauseSignal = Completer<void>();
      _transition(_resumeStatus, step: _currentStep);
      final completer = _resumeCompleter;
      if (completer != null && !completer.isCompleted) completer.complete();
      _resumeCompleter = null;
    }
  }

  /// 이전 실행에서 배달되지 못한 메시지를 우편함에 되살린다. [run] 전에 부른다.
  void seedMailbox(Iterable<AgentMessage> messages) {
    _mailbox.seed(messages);
  }

  /// 사용자가 특정 세션의 우편함에 직접 메시지를 넣는다.
  ///
  /// 피드백(submitFeedback)이 오케스트레이터에게 하는 말이라면, 이것은 세션
  /// 안의 에이전트에게 하는 말이다. 다음 send_prompt에 [INBOX]로 실려 간다.
  /// 스코프 밖 세션이거나 loop가 끝났으면 false.
  bool postUserMessage({required String sessionId, required String body}) {
    final trimmed = body.trim();
    if (trimmed.isEmpty || _stopped || _finished) return false;
    if (!_tasks.containsKey(sessionId)) return false;
    _mailbox.post(
      from: AgentMessage.user,
      to: sessionId,
      body: trimmed,
      at: _now(),
    );
    emit(
      MessagePostedEvent(
        _now(),
        from: AgentMessage.user,
        to: sessionId,
        body: trimmed,
      ),
    );
    _publishTasks();
    return true;
  }

  /// 아직 배달되지 않은 우편함 메시지를 거둬들인다. 성공하면 true.
  bool withdrawMessage(int id) {
    if (_stopped || _finished) return false;
    final removed = _mailbox.withdraw(id);
    if (removed == null) return false;
    emit(
      MessageWithdrawnEvent(
        _now(),
        from: removed.from,
        to: removed.to,
        body: removed.body,
      ),
    );
    _publishTasks();
    return true;
  }

  void submitFeedback(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _feedbackQueue.add(trimmed);
    emit(UserFeedbackEvent(_now(), text: trimmed));
  }

  void answerQuestion(String text) {
    final completer = _answerCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(text.trim());
    }
    _answerCompleter = null;
  }

  void resolveApproval(bool approved) {
    final completer = _approvalCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    }
    _approvalCompleter = null;
  }

  // --- 실행 ---

  Future<AgentRunResult> run({
    required String goal,
    required List<String> allowedIds,
    required String scopeLabel,
    AgentGoalSpec? goalSpec,
    Map<String, AgentSessionRole> sessionRoles = const {},
    List<AgentHandoff> seedHandoffs = const [],
  }) async {
    final startedAt = _now();
    // 실행마다 역할 상태를 초기화한다. 이전 실행의 인계·거부가 남으면 순서
    // 강제와 예외 승인 판단이 어긋난다.
    _handoffs.clear();
    _designHandoffSeen = false;
    _rolePolicyRejections.clear();
    _rolePolicyDenied.clear();
    _modelHints.clear();
    _goal = (goalSpec ?? AgentGoalSpec(objective: goal)).normalized(
      objectiveOverride: goal,
    );
    _sessionRoles = Map.unmodifiable({
      for (final entry in sessionRoles.entries)
        if (allowedIds.contains(entry.key) && !entry.value.isEmpty)
          entry.key: entry.value,
    });
    // "같은 목표 이어가기"는 지난 실행을 이어받는다. 인계 기록을 버리면 새
    // 실행의 첫 스텝이 설계 결과를 모른 채 시작하고, 순서 강제도 설계 인계가
    // 없다고 보아 구현 세션을 막는다. 상한은 그대로 지킨다.
    for (final handoff in seedHandoffs) {
      if (!allowedIds.contains(handoff.sessionId)) continue;
      _noteDesignHandoff(handoff);
      final capped = appendHandoffWithCaps(
        _handoffs,
        handoff,
        perSession: _maxHandoffsPerSession,
        total: _maxHandoffs,
      );
      _handoffs
        ..clear()
        ..addAll(capped);
    }
    emit(
      LoopStartedEvent(
        startedAt,
        goal: _goal.objective,
        scope: scopeLabel,
        goalSpec: _goal,
      ),
    );
    _refreshTasks(allowedIds);

    final transcript = <String>[];
    var stuckStreak = 0;
    var currentStep = 0;

    try {
      var step = 1;
      while (true) {
        for (; step <= maxSteps; step++) {
          currentStep = step;
          _currentStep = step;
          if (_stopped) {
            return _finish(
              AgentLoopOutcome.stopped,
              '사용자가 loop를 중단했습니다.',
              step - 1,
              startedAt,
            );
          }
          await _awaitResumeIfPaused();
          if (_stopped) {
            return _finish(
              AgentLoopOutcome.stopped,
              '사용자가 loop를 중단했습니다.',
              step - 1,
              startedAt,
            );
          }

          // 마감은 step 경계에서 확인한다. 관찰 도중에 끊으면 세션에 이미 들어간
          // 지시의 결과를 잃는다. 연장하면 같은 step부터 이어간다.
          if (_deadlinePassed()) {
            final resumed = await _pauseForDeadline(step - 1);
            if (!resumed) return _finishStopped(step - 1, startedAt);
          }

          _transition(AgentLoopStatus.planning, step: step);
          final sessions = _allowedSessions(allowedIds);
          if (sessions.where((session) => session.isConnected).isEmpty) {
            return _finish(
              AgentLoopOutcome.blocked,
              '허용된 세션이 모두 사라져 loop를 종료합니다.',
              step,
              startedAt,
            );
          }
          _refreshTasks(allowedIds);

          // 지난 step에 배경으로 돌린 작업 중 끝난 것을 회수한다. 계획 전에
          // 넣어야 플래너가 이번 step에서 결과를 보고 판단할 수 있다.
          final carried = _drainBackgroundResults();
          for (final outcome in carried) {
            transcript.add('step $step background: ${outcome.log}');
          }

          late AgentDecision decision;
          while (true) {
            final planned = await _plan(
              step: step,
              allowedIds: allowedIds,
              transcript: transcript,
              scopeLabel: scopeLabel,
            );
            await _awaitResumeIfPaused();
            if (_stopped) return _finishStopped(step - 1, startedAt);
            if (planned != null) {
              decision = planned;
              break;
            }
            final resumed = await _pauseForRecoverableError(
              '계획 응답을 JSON으로 해석하지 못했습니다. 모델 설정을 확인한 뒤 재개하세요.',
              resumeStatus: AgentLoopStatus.planning,
            );
            if (!resumed) return _finishStopped(step - 1, startedAt);
          }

          if (decision.thought.isNotEmpty) {
            emit(ThoughtEvent(_now(), step: step, text: decision.thought));
            transcript.add('step $step thought: ${decision.thought}');
          }

          final controlActions = decision.actions
              .where(
                (action) =>
                    action.tool == 'finish' || action.tool == 'ask_user',
              )
              .toList(growable: false);
          if (controlActions.isNotEmpty && decision.actions.length != 1) {
            final message =
                'finish와 ask_user는 다른 액션과 같은 step에 실행할 수 없습니다. '
                '안전하게 전체 계획을 보류하고 다시 계획합니다.';
            emit(LoopErrorEvent(_now(), message: message));
            transcript.add('step $step: $message');
            continue;
          }
          if (decision.actions.length > maxActionsPerStep) {
            final skipped = decision.actions.length - maxActionsPerStep;
            final message =
                'step당 액션 상한 $maxActionsPerStep개를 초과해 마지막 $skipped개를 '
                '실행하지 않습니다.';
            emit(LoopErrorEvent(_now(), message: message));
            transcript.add('step $step: $message');
          }

          final finish = decision.finishAction;
          if (finish != null) {
            final outcome = _outcomeFromStatus(finish.status);
            if (outcome != AgentLoopOutcome.achieved) {
              return _finish(
                outcome,
                finish.summary ?? decision.thought,
                step,
                startedAt,
              );
            }
            _transition(AgentLoopStatus.evaluating, step: step);
            // 배경 작업이 아직 도는 채로 완료를 판정하면 평가자가 볼 증거가
            // 없다. 남은 관찰을 끝내고 그 결과까지 넘긴다.
            final settled = await _awaitBackgroundObservations();
            if (_stopped) return _finishStopped(step, startedAt);
            for (final outcome in settled) {
              transcript.add('step $step background: ${outcome.log}');
            }
            final verification = await _verifyForCompletion(
              step: step,
              allowedIds: allowedIds,
              actionResults: [
                'planner requested achieved: ${finish.summary ?? decision.thought}',
                for (final outcome in settled) 'background: ${outcome.log}',
              ],
            );
            if (verification == null) return _finishStopped(step, startedAt);
            emit(
              VerifiedEvent(
                _now(),
                verdict: verification.verdict,
                summary: verification.summary,
              ),
            );
            transcript.add(
              'step $step final verify: ${verification.verdict} - '
              '${verification.summary}',
            );
            if (verification.goalMet) {
              return _finish(
                AgentLoopOutcome.achieved,
                verification.summary,
                step,
                startedAt,
              );
            }
            if (!verification.continueLoop) {
              return _finish(
                AgentLoopOutcome.partial,
                verification.summary,
                step,
                startedAt,
              );
            }
            emit(
              LoopErrorEvent(
                _now(),
                message: '완료 선언을 평가자가 반려했습니다: ${verification.summary}',
              ),
            );
            continue;
          }

          final ask = decision.askUserAction;
          if (ask != null) {
            final answer = await _askUser(ask.question ?? '진행 방향을 알려주세요.');
            if (_stopped) {
              return _finish(
                AgentLoopOutcome.stopped,
                '사용자가 loop를 중단했습니다.',
                step,
                startedAt,
              );
            }
            transcript.add('step $step ask_user: ${ask.question} -> $answer');
            continue;
          }

          if (decision.actions.isEmpty) {
            return _finish(
              AgentLoopOutcome.partial,
              decision.thought.isEmpty
                  ? '다음 실행할 도구가 없어 멈췄습니다.'
                  : decision.thought,
              step,
              startedAt,
            );
          }

          // DISPATCH + OBSERVE
          _transition(AgentLoopStatus.dispatching, step: step);
          final actionResults = <String>[
            for (final outcome in carried) 'background: ${outcome.log}',
          ];
          final runtimeBlockers = <_RuntimeBlocker>[
            for (final outcome in carried) ...outcome.runtimeBlockers,
          ];
          final pendingObservations = <_PendingObservation>[];
          // 회수한 배경 결과도 검증 대상이다. 이번 step에 새 전송이 없더라도
          // 평가자가 그 결과를 판정해야 한다.
          var sentSomething = carried.any((outcome) => outcome.sent);
          final dispatchedSessionIds = <String>{};
          for (final action in decision.actions.take(maxActionsPerStep)) {
            await _awaitResumeIfPaused();
            if (_stopped) break;
            if (_isSendAction(action)) {
              final targetId = action.sessionId;
              if (targetId != null && dispatchedSessionIds.contains(targetId)) {
                final message = '같은 step에서 $targetId 세션으로 두 번째 입력을 보내지 않았습니다.';
                emit(LoopErrorEvent(_now(), message: message));
                actionResults.add('send rejected: duplicate session $targetId');
                transcript.add('step $step: $message');
                continue;
              }
              if (targetId != null && _background.containsKey(targetId)) {
                final message =
                    '$targetId 세션은 아직 배경 작업이 끝나지 않아 새 입력을 보내지 않았습니다.';
                emit(LoopErrorEvent(_now(), message: message));
                actionResults.add(
                  'send rejected: background task still running on $targetId',
                );
                transcript.add('step $step: $message');
                continue;
              }
              final dispatch = await _dispatchSend(action, allowedIds);
              await _awaitResumeIfPaused();
              final pending = dispatch.pendingObservation;
              if (pending != null) {
                dispatchedSessionIds.add(pending.sessionId);
                if (action.isBackgroundSend) {
                  _startBackgroundObservation(pending);
                  final log =
                      'sent to ${pending.sessionId} in background '
                      '(await:false, result arrives in a later step)';
                  actionResults.add(log);
                  transcript.add('step $step: $log');
                } else {
                  pendingObservations.add(pending);
                  sentSomething = true;
                }
              } else {
                final result = dispatch.outcome;
                if (result != null) {
                  actionResults.add(result.log);
                  transcript.add('step $step: ${result.log}');
                  runtimeBlockers.addAll(result.runtimeBlockers);
                }
              }
            } else {
              final result = await _executeAction(action, allowedIds);
              await _awaitResumeIfPaused();
              actionResults.add(result.log);
              transcript.add('step $step: ${result.log}');
              runtimeBlockers.addAll(result.runtimeBlockers);
              if (result.sent) sentSomething = true;
            }
          }
          if (_stopped) {
            return _finish(
              AgentLoopOutcome.stopped,
              '사용자가 loop를 중단했습니다.',
              step,
              startedAt,
            );
          }
          if (pendingObservations.isNotEmpty) {
            _transition(AgentLoopStatus.observing, step: step);
            final observedResults = await Future.wait(
              pendingObservations.map(_observeDispatchedSend),
            );
            await _awaitResumeIfPaused();
            if (_stopped) return _finishStopped(step, startedAt);
            for (final result in observedResults) {
              actionResults.add(result.log);
              transcript.add('step $step: ${result.log}');
              runtimeBlockers.addAll(result.runtimeBlockers);
            }
          }

          if (runtimeBlockers.isNotEmpty) {
            final blocker = runtimeBlockers.reduce(
              (current, candidate) =>
                  candidate.issue.priority > current.issue.priority
                  ? candidate
                  : current,
            );
            final resumed = await _pauseForRuntimeBlocker(blocker);
            if (!resumed) return _finishStopped(step, startedAt);
            transcript.add(
              'step $step: 런타임 오류 처리 후 현재 화면을 다시 확인했습니다. '
              '이전 입력은 자동 재전송하지 않았습니다. 새 계획으로 복구를 진행하세요.',
            );
            continue;
          }

          if (await _waitForSessionInput(allowedIds)) {
            if (_stopped) return _finishStopped(step, startedAt);
            transcript.add(
              'step $step: 사용자가 CLI의 승인·입력 대기를 처리했습니다. '
              '이전 지시를 다시 보내지 말고 현재 화면으로 새 계획을 세우세요.',
            );
            continue;
          }
          if (_stopped) return _finishStopped(step, startedAt);

          // EVALUATE (send류 액션이 있었을 때만)
          if (sentSomething) {
            if (_stopped) return _finishStopped(step, startedAt);
            _transition(AgentLoopStatus.evaluating, step: step);
            final verification = await _verifyForCompletion(
              step: step,
              allowedIds: allowedIds,
              actionResults: actionResults,
            );
            if (_stopped) return _finishStopped(step, startedAt);
            if (verification == null) return _finishStopped(step, startedAt);
            emit(
              VerifiedEvent(
                _now(),
                verdict: verification.verdict,
                summary: verification.summary,
              ),
            );
            transcript.add(
              'step $step verify: ${verification.verdict} - ${verification.summary}',
            );

            if (verification.goalMet) {
              return _finish(
                AgentLoopOutcome.achieved,
                verification.summary,
                step,
                startedAt,
              );
            }
            if (verification.verdict == 'stuck') {
              stuckStreak++;
              if (stuckStreak >= 2) {
                final answer = await _askUser(
                  'loop가 같은 상태에서 진전이 없습니다. 어떻게 진행할까요?',
                );
                stuckStreak = 0;
                if (_stopped) {
                  return _finish(
                    AgentLoopOutcome.stopped,
                    '사용자가 loop를 중단했습니다.',
                    step,
                    startedAt,
                  );
                }
                transcript.add('step $step stuck ask_user -> $answer');
                continue;
              }
            } else {
              stuckStreak = 0;
            }
            if (!verification.continueLoop) {
              return _finish(
                AgentLoopOutcome.partial,
                verification.summary,
                step,
                startedAt,
              );
            }
          }

          if (!sentSomething && !decision.continueLoop) {
            return _finish(
              AgentLoopOutcome.partial,
              actionResults.isEmpty ? '계획된 작업을 마쳤습니다.' : actionResults.last,
              step,
              startedAt,
            );
          }
        }
        final continued = await _pauseForBudgetExtension(step - 1);
        if (!continued) return _finishStopped(step - 1, startedAt);
      }
    } on _UnsubmittedInput catch (error) {
      return _finish(
        _stopped ? AgentLoopOutcome.stopped : AgentLoopOutcome.partial,
        error.message,
        currentStep,
        startedAt,
      );
    } on AiChatCancelledException {
      return _finishStopped(currentStep, startedAt);
    } catch (e) {
      emit(LoopErrorEvent(_now(), message: e.toString()));
      return _finish(
        AgentLoopOutcome.failed,
        '오류로 loop를 종료했습니다: $e',
        currentStep,
        startedAt,
      );
    }
  }

  // --- PLAN ---

  Future<AgentDecision?> _plan({
    required int step,
    required List<String> allowedIds,
    required List<String> transcript,
    required String scopeLabel,
  }) async {
    final pendingFeedback = <String>[];
    var accepted = false;
    try {
      final result = await _completeWithRecovery<AgentDecision?>(
        phase: AgentLoopStatus.planning,
        allowedIds: allowedIds,
        attempt: (token) async {
          pendingFeedback.addAll(_feedbackQueue);
          _feedbackQueue.clear();
          final inventory = AgentPrompts.sessionInventory(
            sessions: _allowedSessions(allowedIds),
            linesPerSession: linesPerSession,
            agentHints: _agentHints,
            sessionRoles: _sessionRoles,
            tasks: _tasks,
            unreadCounts: _mailbox.unreadCounts(),
            backgroundSessionIds: _background.keys.toSet(),
            modelHints: _confirmedModelHints(),
          );
          final system =
              '${AgentPrompts.orchestratorSystem(scopeLabel: scopeLabel, allowedIds: allowedIds, sessionRoles: _sessionRoles)}\n\n'
              'Current session snapshots:\n$inventory';
          final userPrompt = AgentPrompts.stepPrompt(
            goal: _goal,
            step: step,
            maxSteps: maxSteps,
            allowedIds: allowedIds,
            transcript: transcript,
            pendingFeedback: pendingFeedback,
            now: _now(),
            schedulesLeft: onSchedule == null
                ? 0
                : maxSchedulesPerRun - _scheduledCount,
            handoffs: _handoffs,
          );
          final messages = [
            AiChatMessage(
              role: AiChatRole.user,
              content: userPrompt,
              createdAt: _now(),
            ),
          ];
          final raw = await _callCompletion(
            token: token,
            system: system,
            messages: messages,
          );
          final decision = AgentDecision.tryParse(raw);
          if (decision != null) return decision;
          // JSON 파싱 실패 시 repair로 1회 재요청.
          final repaired = await _callCompletion(
            token: token,
            system: system,
            messages: [
              AiChatMessage(
                role: AiChatRole.user,
                content: AgentPrompts.repairPrompt(raw),
                createdAt: _now(),
              ),
            ],
          );
          return AgentDecision.tryParse(repaired);
        },
      );
      accepted = result != null;
      return result;
    } finally {
      if (!accepted && !_stopped) _feedbackQueue.insertAll(0, pendingFeedback);
    }
  }

  // --- 액션 실행 ---

  Future<_ActionOutcome> _executeAction(
    AgentAction action,
    List<String> allowedIds,
  ) async {
    switch (action.tool) {
      case 'read_sessions':
      case 'read_session':
        return _readSessions(action, allowedIds);

      case 'wait':
        final seconds = (action.seconds ?? 3).clamp(1, 30);
        await _delayWithControl(Duration(seconds: seconds));
        if (_stopped) {
          return const _ActionOutcome('wait cancelled by user');
        }
        return _ActionOutcome('waited ${seconds}s: ${action.reason ?? ''}');

      case 'report':
        final md = action.markdown ?? action.summary ?? '';
        if (md.trim().isNotEmpty) emit(ReportEvent(_now(), markdown: md));
        return const _ActionOutcome('report posted');

      case 'post_message':
        return _postMessage(action, allowedIds);

      case 'broadcast':
        return _broadcast(action, allowedIds);

      case 'read_inbox':
        return _readInbox(action, allowedIds);

      case 'schedule':
        return _scheduleFollowUp(action, allowedIds);

      case 'send_prompt':
      case 'send_keys':
        final dispatch = await _dispatchSend(action, allowedIds);
        final pending = dispatch.pendingObservation;
        if (pending == null) {
          return dispatch.outcome ??
              const _ActionOutcome('send rejected: unknown error');
        }
        return _observeDispatchedSend(pending);

      default:
        return _ActionOutcome('tool rejected: unsupported `${action.tool}`');
    }
  }

  bool _isSendAction(AgentAction action) =>
      action.tool == 'send_prompt' || action.tool == 'send_keys';

  /// 발신자 id를 정규화한다. 스코프 밖이면 오케스트레이터 자신으로 본다.
  String _senderOf(AgentAction action, List<String> allowedIds) {
    final from = action.fromSessionId;
    if (from != null && allowedIds.contains(from)) return from;
    return AgentMessage.orchestrator;
  }

  _ActionOutcome _postMessage(AgentAction action, List<String> allowedIds) {
    final to = action.toSessionId ?? action.sessionId;
    if (to == null || !allowedIds.contains(to)) {
      return _ActionOutcome(
        'post_message rejected: recipient ${to ?? '(missing)'} outside scope',
      );
    }
    final body = action.body ?? action.prompt ?? action.markdown;
    if (body == null || body.trim().isEmpty) {
      return const _ActionOutcome('post_message rejected: empty body');
    }
    final from = _senderOf(action, allowedIds);
    _mailbox.post(from: from, to: to, body: body.trim(), at: _now());
    emit(MessagePostedEvent(_now(), from: from, to: to, body: body.trim()));
    _publishTasks();
    return _ActionOutcome(
      'post_message queued $from -> $to '
      '(delivered with the next send_prompt to $to)',
    );
  }

  _ActionOutcome _broadcast(AgentAction action, List<String> allowedIds) {
    final body = action.body ?? action.prompt ?? action.markdown;
    if (body == null || body.trim().isEmpty) {
      return const _ActionOutcome('broadcast rejected: empty body');
    }
    final requested = action.sessionIds.isEmpty
        ? allowedIds
        : action.sessionIds;
    final recipients = requested.where(allowedIds.contains).toSet();
    if (recipients.isEmpty) {
      return const _ActionOutcome(
        'broadcast rejected: no recipient inside scope',
      );
    }
    final from = _senderOf(action, allowedIds);
    final posted = _mailbox.broadcast(
      from: from,
      to: recipients,
      body: body.trim(),
      at: _now(),
    );
    for (final message in posted) {
      emit(
        MessagePostedEvent(
          _now(),
          from: message.from,
          to: message.to,
          body: message.body,
        ),
      );
    }
    if (posted.isEmpty) {
      return const _ActionOutcome(
        'broadcast rejected: sender was the only recipient',
      );
    }
    _publishTasks();
    return _ActionOutcome(
      'broadcast queued from $from to ${posted.map((m) => m.to).join(', ')}',
    );
  }

  /// 플래너가 요청한 후속 작업을 예약한다.
  ///
  /// 긴 `wait` 대신 "20분 뒤 다시 확인"처럼 시간을 두고 돌아오게 한다. 예약은
  /// 스케줄러가 소유하므로 이 loop가 끝나도 살아남고, 사용자는 목록에서 취소할
  /// 수 있다. 실행당 [maxSchedulesPerRun]건, [maxScheduleHorizon] 이내로 제한해
  /// 플래너가 예약을 남발하지 못하게 한다.
  Future<_ActionOutcome> _scheduleFollowUp(
    AgentAction action,
    List<String> allowedIds,
  ) async {
    final handler = onSchedule;
    if (handler == null) {
      return const _ActionOutcome(
        'schedule rejected: scheduling is not available in this run',
      );
    }
    if (_scheduledCount >= maxSchedulesPerRun) {
      return const _ActionOutcome(
        'schedule rejected: at most $maxSchedulesPerRun follow-ups per run',
      );
    }
    final now = _now();
    var runAt = action.at;
    if (runAt == null) {
      final minutes = action.inMinutes;
      if (minutes == null) {
        return const _ActionOutcome(
          'schedule rejected: give in_minutes (1..1440) or at (ISO time)',
        );
      }
      if (minutes < 1 || minutes > maxScheduleHorizon.inMinutes) {
        return _ActionOutcome(
          'schedule rejected: in_minutes must be 1..${maxScheduleHorizon.inMinutes}',
        );
      }
      runAt = now.add(Duration(minutes: minutes));
    }
    if (!runAt.isAfter(now)) {
      return const _ActionOutcome('schedule rejected: at is not in the future');
    }
    if (runAt.difference(now) > maxScheduleHorizon) {
      return _ActionOutcome(
        'schedule rejected: at must be within ${maxScheduleHorizon.inHours} hours',
      );
    }

    // 목표를 새로 주면 그 목표로, 없으면 현재 목표를 이어간다. 제약은 안전
    // 규칙이므로 항상 물려준다. 완료 조건은 새 목표에 맞지 않을 수 있어 새
    // 목표일 때는 물려주지 않는다.
    final followUpObjective = action.goal;
    final context = [
      '이전 loop "${_goal.objective}"에서 예약한 후속 작업.',
      if (action.reason case final reason? when reason.trim().isNotEmpty)
        '예약 이유: ${reason.trim()}',
    ].join(' ');
    final goal = followUpObjective == null
        ? _goal.withDeadline(null)
        : AgentGoalSpec(
            objective: followUpObjective,
            constraints: _goal.constraints,
            continuationContext: context,
          ).normalized();

    final task = await handler(
      AgentScheduleRequest(
        goal: goal,
        runAt: runAt,
        allowedSessionIds: List.unmodifiable(allowedIds),
        sessionRoles: _sessionRoles,
        reason: action.reason,
      ),
    );
    if (task == null) {
      return const _ActionOutcome('schedule rejected: scheduler declined');
    }
    _scheduledCount++;
    emit(
      ScheduleRequestedEvent(
        _now(),
        taskId: task.id,
        title: task.title,
        runAt: runAt,
        reason: action.reason,
      ),
    );
    return _ActionOutcome(
      'scheduled follow-up "${task.title}" at '
      '${AgentScheduleTrigger.formatDateTime(runAt)} '
      '(${maxSchedulesPerRun - _scheduledCount} left this run)',
    );
  }

  /// 미배달 메시지를 계획자에게 보여준다. 배달로 치지 않는다.
  _ActionOutcome _readInbox(AgentAction action, List<String> allowedIds) {
    final requested = action.sessionIds.isEmpty
        ? allowedIds
        : action.sessionIds;
    final ids = requested.where(allowedIds.contains).toSet();
    if (ids.isEmpty) {
      return const _ActionOutcome(
        'read_inbox rejected: no requested session is inside scope',
      );
    }
    final logs = <String>[];
    for (final id in ids) {
      final pending = _mailbox.pendingFor(id);
      if (pending.isEmpty) {
        logs.add('read_inbox $id: (no undelivered message)');
        continue;
      }
      final lines = pending
          .map((m) => '  - from ${m.from}: ${_truncateForLog(m.body)}')
          .join('\n');
      logs.add('read_inbox $id: ${pending.length} undelivered\n$lines');
    }
    return _ActionOutcome(logs.join('\n'));
  }

  _ActionOutcome _readSessions(AgentAction action, List<String> allowedIds) {
    final requestedIds = action.sessionIds.isEmpty
        ? allowedIds
        : action.sessionIds;
    final ids = requestedIds.where(allowedIds.contains).toSet();
    if (ids.isEmpty) {
      return const _ActionOutcome(
        'read_sessions rejected: no requested session is inside scope',
      );
    }

    final logs = <String>[];
    final runtimeBlockers = <_RuntimeBlocker>[];
    var tasksChanged = false;
    for (final id in ids) {
      final session = registry.byId(id);
      if (session == null) {
        logs.add('read_sessions: session $id not found');
        continue;
      }
      final screen = session.readScreen(maxLines: linesPerSession);
      final snapshot = screen.trim().isEmpty ? '(화면 내용 없음)' : screen.trim();
      final hint = _rememberAgentHint(id, screen);
      final runtimeIssue = _runtimeIssueDetector.detectBlocking(
        screen,
        now: _now(),
      );
      final existing = _tasks[id];
      if (existing != null) {
        _tasks[id] = existing.copyWith(
          agentHint: hint,
          phase: !session.isConnected || runtimeIssue != null
              ? SessionTaskPhase.error
              : existing.phase,
        );
        tasksChanged = true;
      }
      final stillWorking =
          session.isBusy ||
          QuiescenceDetector.hasWorkingIndicator(screen) ||
          existing?.phase == SessionTaskPhase.working;
      emit(
        ObservedEvent(
          _now(),
          sessionId: id,
          sessionName: session.displayName,
          delta: snapshot,
          quiescent:
              session.isConnected &&
              !stillWorking &&
              _sessionInputReason(session, screen) == null,
          isSnapshot: true,
        ),
      );
      logs.add(
        'read_sessions snapshot $id (${stillWorking ? 'working / completion unconfirmed' : 'idle'}): '
        '${_truncateForLog(snapshot)}',
      );
      if (runtimeIssue != null) {
        runtimeBlockers.add(
          _recordRuntimeIssue(
            runtimeIssue,
            sessionId: id,
            sessionName: session.displayName,
          ),
        );
      }
    }
    if (tasksChanged) {
      _publishTasks();
    }
    return _ActionOutcome(logs.join('\n'), runtimeBlockers: runtimeBlockers);
  }

  Future<_DispatchOutcome> _dispatchSend(
    AgentAction action,
    List<String> allowedIds,
  ) async {
    final sessionId = action.sessionId;
    if (sessionId == null || !allowedIds.contains(sessionId)) {
      return _DispatchOutcome.outcome(
        _ActionOutcome(
          'send rejected: session ${sessionId ?? '(missing)'} outside scope',
        ),
      );
    }
    final session = registry.byId(sessionId);
    if (session == null) {
      return _DispatchOutcome.outcome(
        _ActionOutcome('send rejected: session $sessionId not found'),
      );
    }
    if (!session.isConnected) {
      return _DispatchOutcome.outcome(
        _ActionOutcome('send rejected: session $sessionId is disconnected'),
      );
    }
    final connectionIdentity = session.connectionIdentity;

    final isPrompt = action.tool == 'send_prompt';
    final payload = isPrompt ? (action.prompt ?? '') : (action.input ?? '');
    if (payload.isEmpty) {
      return _DispatchOutcome.outcome(
        _ActionOutcome('send rejected: empty payload for $sessionId'),
      );
    }

    var beforeScreen = session.readScreen(maxLines: linesPerSession);
    if (isPrompt) {
      if (session.isBusy ||
          QuiescenceDetector.hasWorkingIndicator(beforeScreen)) {
        return _rejectDispatch(
          '${session.displayName}은 작업 중이므로 다음 지시를 보내지 않았습니다.',
        );
      }
      // 관찰 제한 시간은 완료가 아니다. 이전 전송이 working인 채로 끝났다면
      // 다시 관찰하여 완료를 확인해야만 다음 지시를 보낼 수 있다.
      if (_tasks[sessionId]?.phase == SessionTaskPhase.working) {
        final observation = await _observeUntilQuiescent(
          session,
          timeout: quiescenceTimeout,
          connectionIdentity: connectionIdentity,
        );
        beforeScreen = observation.screen;
        if (!observation.quiescent) {
          return _rejectDispatch(
            '${session.displayName}의 이전 작업 완료가 확인되지 않아 다음 지시를 보내지 않았습니다.',
          );
        }
      }
    }

    // 역할 정책(ACL) 게이트. 확신 있는 분류에 한해 강제한다.
    if (isPrompt) {
      final gate = await _checkRolePolicy(
        sessionId: sessionId,
        sessionName: session.displayName,
        action: action,
        payload: payload,
        screenContext: beforeScreen,
      );
      if (gate != null) return gate;
    }

    // 우편함에 쌓인 메시지를 이 프롬프트 앞머리에 실어 보낸다. send_keys는
    // 메뉴 조작·인터럽트용이라 붙이지 않는다. 배달 표시는 전송이 확정된 뒤에
    // 하므로, 승인 거부로 무산되면 메시지는 큐에 그대로 남는다.
    final deliveries = isPrompt
        ? _mailbox.pendingFor(sessionId)
        : const <AgentMessage>[];
    final outgoing = deliveries.isEmpty
        ? payload
        : '${AgentMailbox.formatBlock(deliveries)}$payload';

    // 입력 전 화면을 승인 판단과 이후 delta 계산의 동일한 기준점으로 사용한다.
    final existingRuntimeIssue = _runtimeIssueDetector.detectBlocking(
      beforeScreen,
      now: _now(),
    );
    if (existingRuntimeIssue != null) {
      _setTaskPhase(sessionId, SessionTaskPhase.error);
      return _DispatchOutcome.outcome(
        _ActionOutcome(
          'send paused: runtime blocker already visible in $sessionId',
          runtimeBlockers: [
            _recordRuntimeIssue(
              existingRuntimeIssue,
              sessionId: sessionId,
              sessionName: session.displayName,
            ),
          ],
        ),
      );
    }
    if (_sessionInputReason(session, beforeScreen) != null) {
      _setTaskPhase(sessionId, SessionTaskPhase.waitingInput);
      return _rejectDispatch(
        '${session.displayName}의 CLI가 승인·입력을 기다리고 있어 새 지시로 덮어쓰지 않았습니다.',
      );
    }

    // 위험 분류 → 승인 게이트. 실제로 세션에 들어가는 문자열 전체를 본다.
    // 우편함으로 옮겨온 남의 출력에 파괴적 명령이 섞여 있을 수 있다.
    final ruleVerdict = _classifier.classify(
      outgoing,
      screenContext: beforeScreen,
    );
    if (ruleVerdict.destructive || action.selfReportedDestructive) {
      final reason = ruleVerdict.reason ?? 'LLM이 destructive로 신고함';
      final approved = await _requestApproval(
        sessionId: sessionId,
        sessionName: session.displayName,
        description: outgoing,
        reason: reason,
        screenContext: beforeScreen,
      );
      if (!approved) {
        return _DispatchOutcome.outcome(
          _ActionOutcome(
            'send rejected by user ($sessionId): $reason',
            sent: false,
          ),
        );
      }
      // 승인 화면에 표시한 대상/문맥이 바뀌면 과거 승인으로 실행하지 않는다.
      if (!_sameConnection(sessionId, connectionIdentity) ||
          session.readScreen(maxLines: linesPerSession) != beforeScreen) {
        return _rejectDispatch('승인 이후 세션 연결 또는 화면이 바뀌었습니다. 다시 계획하고 승인받아야 합니다.');
      }
    }

    if (_stopped ||
        _finished ||
        _paused ||
        _deadlinePassed() ||
        !_sameConnection(sessionId, connectionIdentity) ||
        !_batchStillPending(sessionId, deliveries)) {
      return _rejectDispatch('전송 전에 제어 상태·연결·우편함이 바뀌어 지시를 보내지 않았습니다.');
    }
    if (isPrompt &&
        (session.isBusy ||
            QuiescenceDetector.hasWorkingIndicator(
              session.readScreen(maxLines: linesPerSession),
            ))) {
      return _rejectDispatch('전송 직전 작업 중 상태가 확인되어 다음 지시를 보내지 않았습니다.');
    }
    final controlRevision = _controlRevision;
    if (isPrompt) {
      session.sendText(_withoutTrailingSubmit(outgoing));
      // 본문과 Enter를 나눠 보낸다.
      //
      // 둘을 연달아 보내면 PTY에 한 덩어리로 들어가는데, codex·claude 같은
      // 인라인 TUI는 사람이 칠 수 없는 속도로 도착한 입력을 붙여넣기로 보고
      // 끝의 개행을 "제출"이 아니라 입력창의 줄바꿈으로 넣는다. 그래서 메시지는
      // 채워지는데 전송이 되지 않는다. 짧게 끊어 별개의 키 입력으로 보이게 한다.
      await Future.any<void>([
        _submitSleep(submitDelay),
        _stopCompleter.future,
        _pauseSignal.future,
      ]);
      if (_stopped ||
          _finished ||
          _paused ||
          _deadlinePassed() ||
          controlRevision != _controlRevision ||
          !_sameConnection(sessionId, connectionIdentity) ||
          !_batchStillPending(sessionId, deliveries)) {
        const message =
            '입력됨·미제출: 본문 입력 뒤 중단·일시정지·연결 또는 우편함 변경이 감지되어 Enter를 보내지 않았습니다. '
            '터미널에 남은 입력을 확인하고 정리한 뒤 같은 목표 이어가기를 선택하세요. 자동 재전송하지 않습니다.';
        emit(LoopErrorEvent(_now(), message: message));
        throw const _UnsubmittedInput(message);
      }
      session.submit();
    } else {
      session.sendText(_keyNormalizer(payload));
    }
    if (deliveries.isNotEmpty) {
      final delivered = _mailbox.markInjected(
        sessionId,
        deliveries.map((message) => message.id),
      );
      onMailbox?.call(_mailbox.allPending());
      emit(
        MessageDeliveredEvent(
          _now(),
          sessionId: sessionId,
          sessionName: session.displayName,
          senders: [for (final message in delivered) message.from],
        ),
      );
    }
    _setTaskPhase(
      sessionId,
      SessionTaskPhase.working,
      instruction: isPrompt ? payload : 'keys: $payload',
    );
    emit(
      DispatchedEvent(
        _now(),
        sessionId: sessionId,
        sessionName: session.displayName,
        kind: isPrompt ? 'prompt' : 'keys',
        payload: payload,
        reason: action.reason,
        capability:
            action.capability ?? AgentCapabilityClassifier.classify(payload),
      ),
    );

    return _DispatchOutcome.pending(
      _PendingObservation(
        action: action,
        session: session,
        sessionId: sessionId,
        sessionName: session.displayName,
        before: beforeScreen,
        connectionIdentity: connectionIdentity,
        timeout: Duration(
          seconds:
              (action.timeoutSeconds ??
                      _sessionRoles[sessionId]?.effectiveTimeoutSeconds ??
                      quiescenceTimeout.inSeconds)
                  .clamp(5, 600),
        ),
      ),
    );
  }

  /// 역할이 맡지 않는 작업이면 전송을 막는다.
  ///
  /// 통과하면 null. 같은 세션·같은 capability로 3번째 시도부터는 사용자에게
  /// "이번만 허용" 승인을 묻는다(설계 §4).
  Future<_DispatchOutcome?> _checkRolePolicy({
    required String sessionId,
    required String sessionName,
    required AgentAction action,
    required String payload,
    required String screenContext,
  }) async {
    final role = _sessionRoles[sessionId];
    if (role == null || role.capabilities.isEmpty) return null;
    final capability =
        action.capability ?? AgentCapabilityClassifier.classify(payload);
    if (capability == null) return null;
    if (!role.capabilities.contains(capability)) {
      return _rejectRolePolicy(
        sessionId: sessionId,
        sessionName: sessionName,
        role: role,
        capability: capability,
        payload: payload,
        screenContext: screenContext,
        reason:
            'role policy: $sessionName(${AgentSessionRole.kindLabel(role.kind)})은 '
            '${withObjectParticle(AgentSessionRole.capabilityLabel(capability))} '
            '맡지 않습니다 — 다른 세션에 배정하세요',
      );
    }
    // 순서 강제: 설계 인계가 없는 구현 세션에는 구현을 맡기지 않는다(설계 §4).
    if (capability == AgentCapability.implement &&
        role.kind == AgentRoleKind.implementer &&
        _teamHasDesignRole() &&
        !_hasDesignHandoff()) {
      return _rejectRolePolicy(
        sessionId: sessionId,
        sessionName: sessionName,
        role: role,
        capability: capability,
        // 순서 강제는 "역할이 못 맡는 작업"과 원인이 다르다. 카운터를 나눠
        // 두지 않으면 capability 불일치 시도가 순서 게이트의 예외 승인까지
        // 앞당겨 띄운다.
        keySuffix: '|order',
        payload: payload,
        screenContext: screenContext,
        reason:
            'role policy: 설계 인계(handoff)가 아직 없습니다 — '
            '설계 세션(architect/lead)의 작업을 먼저 끝내세요',
      );
    }
    return null;
  }

  /// 팀에 설계를 맡는 세션(architect/lead)이 있는지.
  bool _teamHasDesignRole() => _sessionRoles.values.any(
    (role) =>
        role.kind == AgentRoleKind.architect || role.kind == AgentRoleKind.lead,
  );

  /// 이번 실행에서 설계 세션의 인계가 한 번이라도 기록됐는지.
  bool _hasDesignHandoff() => _designHandoffSeen;

  void _noteDesignHandoff(AgentHandoff handoff) {
    if (handoff.roleKind == AgentRoleKind.architect ||
        handoff.roleKind == AgentRoleKind.lead) {
      _designHandoffSeen = true;
    }
  }

  /// 역할 정책 거부 공통 처리.
  ///
  /// 같은 세션·같은 capability로 3번째 시도부터는 사용자에게 "이번만 허용"
  /// 승인을 묻는다(설계 §4). 사용자가 한 번 거부하면 이번 실행 내내 조용히
  /// 거부하고 다시 묻지 않는다. 거부 카드는 [RolePolicyRejectedEvent] 하나로
  /// 끝내고 [LoopErrorEvent]를 중복 발행하지 않는다.
  Future<_DispatchOutcome?> _rejectRolePolicy({
    required String sessionId,
    required String sessionName,
    required AgentSessionRole role,
    required AgentCapability capability,
    required String payload,
    required String screenContext,
    required String reason,
    String keySuffix = '',
  }) async {
    final wire = AgentSessionRole.capabilityLabel(capability);
    final key = '$sessionId|$wire$keySuffix';
    final rejected = _rolePolicyRejections[key] ?? 0;
    final denied = _rolePolicyDenied.contains(key);
    if (rejected < 2 || denied) {
      // 이미 사용자가 거부한 키는 더 세지 않는다. 세어 봐야 쓰는 곳이 없고,
      // 승인을 다시 묻지 않기로 한 뒤에도 값이 끝없이 커진다.
      if (!denied) _rolePolicyRejections[key] = rejected + 1;
      emit(
        RolePolicyRejectedEvent(
          _now(),
          sessionId: sessionId,
          sessionName: sessionName,
          roleKind: role.kind,
          capability: capability,
          reason: reason,
        ),
      );
      return _DispatchOutcome.outcome(_ActionOutcome('send rejected: $reason'));
    }
    final approved = await _requestApproval(
      sessionId: sessionId,
      sessionName: sessionName,
      description: payload,
      reason:
          '역할 정책 예외: $sessionName(${AgentSessionRole.kindLabel(role.kind)})은 '
          '$wire을 맡지 않지만 플래너가 반복해서 시도합니다. 이번만 허용할까요?',
      screenContext: screenContext,
      kind: PendingApprovalKind.rolePolicy,
      capability: capability,
    );
    if (!approved) {
      // 사용자가 거부했으면 남은 실행 동안 다시 묻지 않는다.
      _rolePolicyDenied.add(key);
      emit(
        RolePolicyRejectedEvent(
          _now(),
          sessionId: sessionId,
          sessionName: sessionName,
          roleKind: role.kind,
          capability: capability,
          reason: reason,
        ),
      );
      return _DispatchOutcome.outcome(_ActionOutcome('send rejected: $reason'));
    }
    _rolePolicyRejections.remove(key);
    _rolePolicyDenied.remove(key);
    return null;
  }

  bool _sameConnection(String sessionId, Object identity) {
    final current = registry.byId(sessionId);
    return current != null &&
        current.isConnected &&
        current.connectionIdentity == identity;
  }

  bool _batchStillPending(String sessionId, List<AgentMessage> batch) {
    final pendingIds = _mailbox
        .pendingFor(sessionId)
        .map((message) => message.id)
        .toSet();
    return batch.every((message) => pendingIds.contains(message.id));
  }

  _DispatchOutcome _rejectDispatch(String message) {
    emit(LoopErrorEvent(_now(), message: message));
    return _DispatchOutcome.outcome(_ActionOutcome('send rejected: $message'));
  }

  /// await:false 전송을 배경 관찰로 넘긴다.
  ///
  /// loop는 결과를 기다리지 않고 다음 계획으로 넘어가고, 완료된 결과는 이후
  /// step이 [_drainBackgroundResults]로 회수한다. 이게 없으면 한 세션의 긴
  /// 빌드가 라운드 전체의 wall-clock을 잡아먹는다.
  void _startBackgroundObservation(_PendingObservation pending) {
    final future = _observeDispatchedSend(pending);
    _background[pending.sessionId] = future;
    _publishTasks();
    unawaited(() async {
      _ActionOutcome outcome;
      try {
        outcome = await future;
      } catch (error) {
        outcome = _ActionOutcome(
          'background observation failed for ${pending.sessionId}: $error',
          sent: true,
        );
      }
      _background.remove(pending.sessionId);
      if (_finished || _stopped) return;
      _backgroundResults.add(outcome);
      _publishTasks();
    }());
  }

  /// 완료된 배경 관찰 결과만 회수한다. 아직 도는 것은 건드리지 않는다.
  List<_ActionOutcome> _drainBackgroundResults() {
    if (_backgroundResults.isEmpty) return const [];
    final drained = List<_ActionOutcome>.from(_backgroundResults);
    _backgroundResults.clear();
    return drained;
  }

  /// 남은 배경 관찰이 모두 끝날 때까지 기다렸다가 회수한다.
  ///
  /// 완료 선언 직전에 부른다. 빌드가 아직 도는 채로 achieved를 선언하면
  /// 평가자가 볼 증거가 없다.
  Future<List<_ActionOutcome>> _awaitBackgroundObservations() async {
    while (_background.isNotEmpty) {
      await Future.wait(_background.values.toList(growable: false));
      // 완료 콜백이 맵에서 자기를 지우는 건 한 틱 뒤다. 그 틱을 양보한다.
      await Future<void>.delayed(Duration.zero);
    }
    return _drainBackgroundResults();
  }

  Future<_ActionOutcome> _observeDispatchedSend(
    _PendingObservation pending,
  ) async {
    var observed = await _observeUntilQuiescent(
      pending.session,
      timeout: pending.timeout,
      connectionIdentity: pending.connectionIdentity,
    );
    if (_stopped || _finished) {
      return const _ActionOutcome('observation cancelled by user', sent: true);
    }
    // CLI 에이전트가 provider 오류나 무응답으로 멈췄으면 사람이 "계속해"를
    // 치는 대신 여기서 다시 지시한다. 각 재지시는 새 관찰 기준점을 가진다.
    var before = pending.before;
    final continuation = <String>[];
    var providerRetries = 0;
    var silentRetries = 0;
    while (!_stopped && !_finished) {
      final stall = _detectAgentStall(pending, before, observed);
      if (stall == null) break;
      final isProvider = stall.kind == _AgentStallKind.providerFailure;
      final attempt = isProvider ? providerRetries + 1 : silentRetries + 1;
      final limit = isProvider ? maxProviderRetries : maxSilentRetries;
      if (attempt > limit) {
        continuation.add(
          'auto-continue exhausted after ${attempt - 1} attempts (${stall.reason})',
        );
        break;
      }
      if (isProvider) {
        providerRetries = attempt;
      } else {
        silentRetries = attempt;
      }
      final delay = isProvider
          ? sessionRetryBackoff(attempt)
          : const Duration(seconds: 3);
      await _delayWithControl(delay);
      if (_stopped || _finished) break;
      if (!_sameConnection(pending.sessionId, pending.connectionIdentity)) {
        break;
      }
      final current = pending.session.readScreen(maxLines: linesPerSession);
      if (pending.session.isBusy ||
          QuiescenceDetector.hasWorkingIndicator(current) ||
          _sessionInputReason(pending.session, current) != null) {
        // 대기 중에 스스로 재개했거나 사람이 개입해야 한다. 재지시하지 않는다.
        observed = await _observeUntilQuiescent(
          pending.session,
          timeout: pending.timeout,
          connectionIdentity: pending.connectionIdentity,
        );
        continue;
      }
      emit(
        SessionRetryEvent(
          _now(),
          sessionId: pending.sessionId,
          sessionName: pending.sessionName,
          attempt: attempt,
          reason: stall.reason,
          evidence: stall.evidence,
        ),
      );
      continuation.add('auto-continue #$attempt: ${stall.reason}');
      before = current;
      // 무응답 1회차는 제출이 안 된 입력일 가능성이 커서 Enter만 다시 보낸다.
      final resendPrompt = isProvider || attempt > 1;
      if (resendPrompt) {
        pending.session.sendText(
          AgentPrompts.continuationPrompt(
            original: pending.action.prompt ?? '',
            reason: stall.reason,
          ),
        );
        await _submitSleep(submitDelay);
        if (_stopped || _finished) break;
        if (!_sameConnection(pending.sessionId, pending.connectionIdentity)) {
          break;
        }
      }
      pending.session.submit();
      _setTaskPhase(pending.sessionId, SessionTaskPhase.working);
      observed = await _observeUntilQuiescent(
        pending.session,
        timeout: pending.timeout,
        connectionIdentity: pending.connectionIdentity,
      );
    }
    if (_stopped || _finished) {
      return const _ActionOutcome('observation cancelled by user', sent: true);
    }
    final disconnected = !_sameConnection(
      pending.sessionId,
      pending.connectionIdentity,
    );
    final rawDelta = TerminalScreenDelta.compute(before, observed.screen);
    final delta = disconnected ? '(세션 연결 끊김)\n$rawDelta' : rawDelta;
    final sessionId = pending.sessionId;
    final exhaustedProvider =
        !disconnected &&
        providerRetries >= maxProviderRetries &&
        _runtimeIssueDetector.detect(rawDelta, now: _now())?.kind ==
            TerminalRuntimeIssueKind.providerFailure;
    final runtimeIssue = disconnected
        ? null
        : exhaustedProvider
        ? TerminalRuntimeIssue(
            kind: TerminalRuntimeIssueKind.providerFailure,
            message:
                'CLI 에이전트가 LLM 서버 오류로 $maxProviderRetries회 자동 재지시에도 '
                '계속 실패했습니다. 터미널에서 에이전트 상태·네트워크를 확인한 뒤 '
                '재개하세요. 현재 목표와 loop 상태는 유지됩니다.',
            evidence:
                _runtimeIssueDetector.detect(rawDelta, now: _now())?.evidence ??
                '',
          )
        : _runtimeIssueDetector.detectBlocking(rawDelta, now: _now());
    final needsInput =
        !disconnected &&
        _sessionInputReason(pending.session, observed.screen) != null;
    _rememberAgentHint(sessionId, observed.screen);
    _setTaskPhase(
      sessionId,
      disconnected || runtimeIssue != null
          ? SessionTaskPhase.error
          : needsInput
          ? SessionTaskPhase.waitingInput
          : observed.quiescent
          ? SessionTaskPhase.done
          : SessionTaskPhase.working,
    );
    final quiescentForHandoff =
        observed.quiescent && !disconnected && !needsInput;
    emit(
      ObservedEvent(
        _now(),
        sessionId: sessionId,
        sessionName: pending.sessionName,
        delta: delta,
        quiescent: quiescentForHandoff,
      ),
    );
    if (quiescentForHandoff && pending.action.tool == 'send_prompt') {
      _recordHandoff(pending, rawDelta);
    }
    final runtimeBlockers = runtimeIssue == null
        ? const <_RuntimeBlocker>[]
        : [
            _recordRuntimeIssue(
              runtimeIssue,
              sessionId: sessionId,
              sessionName: pending.sessionName,
            ),
          ];
    return _ActionOutcome(
      'sent to $sessionId (${disconnected
          ? 'disconnected'
          : needsInput
          ? 'waiting for human input'
          : observed.quiescent
          ? 'quiescent'
          : 'timeout'}): '
      '${pending.action.reason ?? ''}'
      '${continuation.isEmpty ? '' : '\n${continuation.join('\n')}'}'
      '\nobserved delta:\n${_truncateForLog(delta)}',
      sent: true,
      runtimeBlockers: runtimeBlockers,
    );
  }

  /// 잠잠해진 send_prompt 관찰에서 인계 요약을 만들어 남긴다.
  ///
  /// 요약이 비어 있으면(프롬프트 글리프만 남거나 출력이 전혀 없으면) 기록하지
  /// 않는다. 다음 스텝 프롬프트가 이 세션이 방금 뭘 했는지 알 수 있게 하는
  /// 것이 목적이라, 알맹이 없는 인계는 오히려 잡음이다.
  void _recordHandoff(_PendingObservation pending, String rawDelta) {
    final normalized = QuiescenceDetector.normalize(rawDelta);
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !_promptGlyphOnly.hasMatch(line))
        .toList();
    if (lines.isEmpty) return;
    final tail = lines.length <= 12 ? lines : lines.sublist(lines.length - 12);
    final summary = _clampHandoffSummary(
      tail.map(_truncateHandoffLine).join('\n'),
    );
    final rawInstruction = pending.action.prompt ?? '';
    final instruction = rawInstruction.length <= 200
        ? rawInstruction
        : '${rawInstruction.substring(0, 200)}...';
    final handoff = AgentHandoff(
      sessionId: pending.sessionId,
      sessionName: pending.sessionName,
      roleKind: _sessionRoles[pending.sessionId]?.kind ?? AgentRoleKind.custom,
      instruction: instruction,
      summary: summary,
      at: _now(),
    );
    _noteDesignHandoff(handoff);
    final capped = appendHandoffWithCaps(
      _handoffs,
      handoff,
      perSession: _maxHandoffsPerSession,
      total: _maxHandoffs,
    );
    _handoffs
      ..clear()
      ..addAll(capped);
    emit(HandoffRecordedEvent(_now(), handoff: handoff));
  }

  /// 인계 요약 한 줄 상한(180자). 긴 로그 한 줄이 프롬프트를 삼키는 걸 막는다.
  static const _handoffLineLimit = 180;

  /// 인계 요약 전체 상한(1200자).
  static const _handoffSummaryLimit = 1200;

  static String _truncateHandoffLine(String line) =>
      line.length <= _handoffLineLimit
      ? line
      : '${line.substring(0, _handoffLineLimit)}…';

  static String _clampHandoffSummary(String summary) =>
      summary.length <= _handoffSummaryLimit
      ? summary
      : '${summary.substring(0, _handoffSummaryLimit - 1)}…';

  static final RegExp _promptGlyphOnly = RegExp(r'^[❯➜\$#>\s]+$');

  /// provider 오류 n번째(1부터) 자동 재지시 전 대기. 5s→15s→30s→60s 고정.
  static Duration sessionRetryBackoff(int attempt) {
    const steps = [5, 15, 30, 60];
    final index = attempt.clamp(1, steps.length) - 1;
    return Duration(seconds: steps[index]);
  }

  /// 한 번의 send_prompt에 대해 provider 오류로 자동 재지시하는 최대 횟수.
  static const maxProviderRetries = 5;

  /// 한 번의 send_prompt에 대해 무응답으로 자동 재지시하는 최대 횟수.
  /// 1회차는 Enter 재전송, 2회차는 "이어서 계속" 프롬프트.
  static const maxSilentRetries = 2;

  /// 지시를 받은 CLI 에이전트가 일을 하지 않고 멈췄는지 판단한다.
  ///
  /// send_prompt에만 적용한다. 화면이 조용해졌는데 (a) 마지막 줄들에 provider·
  /// 네트워크 오류가 있거나 (b) 지시 본문 외에 아무 출력도 없으면 멈춘 것이다.
  /// 승인·입력 대기나 연결 끊김은 다른 경로가 처리하므로 여기서는 제외한다.
  _AgentStall? _detectAgentStall(
    _PendingObservation pending,
    String before,
    _Observation observed,
  ) {
    if (pending.action.tool != 'send_prompt') return null;
    if (!observed.quiescent) return null;
    if (!_sameConnection(pending.sessionId, pending.connectionIdentity)) {
      return null;
    }
    if (_sessionInputReason(pending.session, observed.screen) != null) {
      return null;
    }
    final delta = TerminalScreenDelta.compute(before, observed.screen);
    final issue = _runtimeIssueDetector.detect(delta, now: _now());
    if (issue != null) {
      if (!issue.isBlocking) {
        return _AgentStall(
          _AgentStallKind.providerFailure,
          reason: 'LLM 서버·네트워크 오류로 에이전트가 턴을 중단함',
          evidence: issue.evidence,
        );
      }
      return null;
    }
    final hint = _agentHints[pending.sessionId];
    if (hint == null || hint == 'unknown') return null;
    if (!_isSilentResponse(delta, pending.action.prompt ?? '')) return null;
    // 새 출력이 없는데 화면 꼬리에 provider 오류가 남아 있으면, TUI가 같은
    // 오류를 같은 자리에 다시 그린 것이다. 무응답이 아니라 provider 오류다.
    final tail = _tailLines(observed.screen, 6);
    final lingering = _runtimeIssueDetector.detect(tail, now: _now());
    if (lingering != null && !lingering.isBlocking) {
      return _AgentStall(
        _AgentStallKind.providerFailure,
        reason: 'LLM 서버·네트워크 오류로 에이전트가 턴을 중단함',
        evidence: lingering.evidence,
      );
    }
    return const _AgentStall(
      _AgentStallKind.silent,
      reason: '지시 후 에이전트 출력이 없음',
      evidence: '',
    );
  }

  static String _tailLines(String screen, int count) {
    final lines = screen
        .replaceAll('\r', '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    return lines
        .skip(lines.length > count ? lines.length - count : 0)
        .join('\n');
  }

  /// delta에 지시 본문의 메아리와 프롬프트 장식 외에 아무것도 없는지.
  static bool _isSilentResponse(String delta, String prompt) {
    if (delta == '(변화 없음)' || delta.trim().isEmpty) return true;
    if (delta == '(화면이 갱신됨)' || delta == '(화면이 비워짐)') return false;
    final promptLines = prompt
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
    final decoration = RegExp(
      r'^[\s❯›➜>$#│─╭╮╰╯┌┐└┘├┤┬┴┼═║╔╗╚╝╠╣╦╩╬━┃┏┓┗┛┣┫┳┻╋•·.…\-_=|\[\]()]*$',
    );
    for (final raw in QuiescenceDetector.normalize(delta).split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || decoration.hasMatch(line)) continue;
      final stripped = line.replaceFirst(RegExp(r'^[❯›➜>$#]\s*'), '').trim();
      if (promptLines.contains(stripped)) continue;
      if (promptLines.any((p) => p.length >= 12 && stripped.contains(p))) {
        continue;
      }
      return false;
    }
    return true;
  }

  Future<_Observation> _observeUntilQuiescent(
    SessionPort session, {
    required Duration timeout,
    Object? connectionIdentity,
  }) async {
    final detector = _detectorFactory();
    var elapsed = Duration.zero;
    var screen = session.readScreen(maxLines: linesPerSession);
    if (_sessionInputReason(session, screen) != null) {
      return _Observation(screen, false);
    }
    detector.pushSnapshot(screen, busy: session.isBusy);
    // 첫 입력 반영을 위한 짧은 settle.
    await _delayWithControl(settleDelay);
    if (_stopped) return _Observation(screen, false);
    while (elapsed < timeout) {
      await _delayWithControl(pollInterval);
      if (_stopped) break;
      if (!session.isConnected ||
          (connectionIdentity != null &&
              !_sameConnection(session.id, connectionIdentity))) {
        screen = session.readScreen(maxLines: linesPerSession);
        return _Observation(screen, false);
      }
      elapsed += pollInterval;
      screen = session.readScreen(maxLines: linesPerSession);
      if (_sessionInputReason(session, screen) != null) {
        return _Observation(screen, false);
      }
      detector.pushSnapshot(screen, busy: session.isBusy);
      if (detector.isQuiescent) {
        return _Observation(screen, true);
      }
    }
    return _Observation(screen, false);
  }

  // --- EVALUATE ---

  Future<AgentVerification?> _verify({
    required int step,
    required List<String> allowedIds,
    required List<String> actionResults,
  }) async {
    return _completeWithRecovery<AgentVerification?>(
      phase: AgentLoopStatus.evaluating,
      allowedIds: allowedIds,
      attempt: (token) async {
        final sessions = _allowedSessions(allowedIds);
        final inventory = AgentPrompts.sessionInventory(
          sessions: sessions,
          linesPerSession: linesPerSession,
          agentHints: _agentHints,
          sessionRoles: _sessionRoles,
          tasks: _tasks,
          unreadCounts: _mailbox.unreadCounts(),
          backgroundSessionIds: _background.keys.toSet(),
          modelHints: _confirmedModelHints(),
        );
        final system =
            '${AgentPrompts.verifierSystem(allowedIds: allowedIds)}\n\n'
            'Current session snapshots:\n$inventory';
        final raw = await _callCompletion(
          token: token,
          system: system,
          messages: [
            AiChatMessage(
              role: AiChatRole.user,
              content: AgentPrompts.verifierPrompt(
                goal: _goal,
                step: step,
                maxSteps: maxSteps,
                actionResults: actionResults,
              ),
              createdAt: _now(),
            ),
          ],
        );
        final verification = AgentVerification.tryParse(raw);
        if (verification != null) return verification;
        final repaired = await _callCompletion(
          token: token,
          system: system,
          messages: [
            AiChatMessage(
              role: AiChatRole.user,
              content: AgentPrompts.repairPrompt(raw),
              createdAt: _now(),
            ),
          ],
        );
        return AgentVerification.tryParse(repaired);
      },
    );
  }

  /// 플래너 finish와 일반 평가가 공유하는 성공 게이트.
  /// 일반 중간 평가는 병렬성을 유지하고, 성공 후보일 때만 미수집 관찰을 모아 재평가한다.
  Future<AgentVerification?> _verifyForCompletion({
    required int step,
    required List<String> allowedIds,
    required List<String> actionResults,
  }) async {
    var verification = await _verifyUntilValid(
      step: step,
      allowedIds: allowedIds,
      actionResults: actionResults,
    );
    if (verification == null || !verification.goalMet) return verification;
    if (_background.isNotEmpty || _backgroundResults.isNotEmpty) {
      final settled = await _awaitBackgroundObservations();
      if (_stopped) return null;
      verification = await _verifyUntilValid(
        step: step,
        allowedIds: allowedIds,
        actionResults: [
          ...actionResults,
          for (final result in settled) 'background: ${result.log}',
        ],
      );
      if (verification == null) return null;
    }
    if (await _waitForSessionInput(allowedIds)) {
      if (_stopped) return null;
      return const AgentVerification(
        verdict: 'uncertain',
        summary: 'CLI 승인·입력 처리 후 최신 화면으로 다시 계획합니다.',
        goalMet: false,
        continueLoop: true,
      );
    }
    final blocked =
        _stopped ||
        _paused ||
        _approvalCompleter != null ||
        _background.isNotEmpty ||
        _backgroundResults.isNotEmpty ||
        allowedIds.any((id) {
          final session = registry.byId(id);
          return session == null || !session.isConnected || session.isBusy;
        }) ||
        _tasks.values.any(
          (task) =>
              task.phase == SessionTaskPhase.working ||
              task.phase == SessionTaskPhase.waitingInput ||
              task.phase == SessionTaskPhase.error,
        );
    if (verification.goalMet && (verification.verdict != 'ok' || blocked)) {
      return AgentVerification(
        verdict: 'uncertain',
        summary:
            '완료 보류: 미확인 작업·연결·승인 상태 또는 평가 모순을 먼저 확인해야 합니다. ${verification.summary}',
        goalMet: false,
        continueLoop: verification.continueLoop,
      );
    }
    return verification;
  }

  Future<AgentVerification?> _verifyUntilValid({
    required int step,
    required List<String> allowedIds,
    required List<String> actionResults,
  }) async {
    while (!_stopped) {
      if (_feedbackQueue.isNotEmpty) {
        return const AgentVerification(
          verdict: 'uncertain',
          summary: '대기 중 도착한 사용자 피드백을 다음 계획에 먼저 반영합니다.',
          goalMet: false,
          continueLoop: true,
        );
      }
      final verification = await _verify(
        step: step,
        allowedIds: allowedIds,
        actionResults: actionResults,
      );
      await _awaitResumeIfPaused();
      if (_stopped) return null;
      // 모델 대기/재시도 중 새 지시가 왔다면 그 지시를 못 본 완료 판정은 버린다.
      if (_feedbackQueue.isNotEmpty) continue;
      if (verification != null) return verification;
      final resumed = await _pauseForRecoverableError(
        '평가 응답을 JSON으로 해석하지 못했습니다. 모델 설정을 확인한 뒤 재개하세요.',
        resumeStatus: AgentLoopStatus.evaluating,
      );
      if (!resumed) return null;
    }
    return null;
  }

  Future<String> _callCompletion({
    required AiCancelToken token,
    required String system,
    required List<AiChatMessage> messages,
  }) async {
    token.throwIfCancelled();
    final result = await completion(
      system: system,
      messages: messages,
      cancelToken: token,
    );
    token.throwIfCancelled();
    return result;
  }

  Future<T> _completeWithRecovery<T>({
    required Future<T> Function(AiCancelToken) attempt,
    required AgentLoopStatus phase,
    required List<String> allowedIds,
  }) async {
    var automaticRetries = 0;
    while (true) {
      await _awaitResumeIfPaused();
      if (_stopped) throw AiChatCancelledException();
      await _waitForSessionInput(allowedIds);
      if (_stopped) throw AiChatCancelledException();
      final token = AiCancelToken();
      final unregister = _cancelToken.onCancel(token.cancel);
      final revision = _controlRevision;
      try {
        final result = await Future.any<T>([
          Future<T>.sync(() => attempt(token)),
          _stopCompleter.future.then<T>(
            (_) => throw AiChatCancelledException(),
          ),
          _pauseSignal.future.then<T>(
            (_) => throw const _RebuildModelRequest(),
          ),
        ]).timeout(completionTimeout);
        if (_stopped) throw AiChatCancelledException();
        if (_paused || revision != _controlRevision) {
          throw const _RebuildModelRequest();
        }
        return result;
      } on _RebuildModelRequest {
        token.cancel();
        await _awaitResumeIfPaused();
        if (_stopped) throw AiChatCancelledException();
        // 대기 중 바뀐 화면·피드백으로 새 요청을 만든다. 늦은 이전 응답은 버린다.
        automaticRetries = 0;
      } on AiChatCancelledException {
        rethrow;
      } catch (failure) {
        token.cancel();
        final error = failure is TimeoutException
            ? AiChatException(
                'AI 서버 응답 시간이 초과되었습니다.',
                kind: AiChatFailureKind.timeout,
              )
            : failure;
        if (error is! AiChatException) rethrow;
        if (!_isRecoverableAiError(error)) rethrow;
        await _awaitResumeIfPaused();
        if (_stopped) throw AiChatCancelledException();
        if (_isTransientAiError(error)) {
          // 서버 불안정은 사용자가 고칠 일이 아니다. 멈추지 않고 백오프로 계속
          // 두드린다. 중단·일시정지는 sleep 중에도 즉시 반영된다.
          automaticRetries++;
          final delay = retryBackoff(automaticRetries);
          emit(
            LoopRetryEvent(
              _now(),
              attempt: automaticRetries,
              delay: delay,
              message: error.message,
            ),
          );
          await _delayWithControl(delay);
          if (_stopped) throw AiChatCancelledException();
          continue;
        }
        final resumed = await _pauseForRecoverableError(
          '${error.message} 설정이나 네트워크를 확인한 뒤 재개하세요.',
          resumeStatus: phase,
        );
        if (!resumed) throw AiChatCancelledException();
        automaticRetries = 0;
      } finally {
        unregister();
        token.cancel();
      }
    }
  }

  /// n번째(1부터) 연속 재시도 전 대기. 1s→2s→5s→10s→20s→30s→60s에서 고정.
  static Duration retryBackoff(int attempt) {
    const steps = [1, 2, 5, 10, 20, 30, 60];
    final index = attempt.clamp(1, steps.length) - 1;
    return Duration(seconds: steps[index]);
  }

  bool _isRecoverableAiError(AiChatException error) {
    return error.kind != AiChatFailureKind.unknown ||
        _isTransientAiError(error);
  }

  bool _isTransientAiError(AiChatException error) {
    if (error.kind != AiChatFailureKind.unknown) {
      return switch (error.kind) {
        AiChatFailureKind.timeout ||
        AiChatFailureKind.connection ||
        AiChatFailureKind.rateLimited ||
        AiChatFailureKind.server => true,
        _ => false,
      };
    }
    final message = error.message.toLowerCase();
    return message.contains('시간이 초과') ||
        message.contains('연결할 수 없습니다') ||
        message.contains('연결을 끊었습니다') ||
        RegExp(r'서버 오류 (429|5\d\d)').hasMatch(message);
  }

  // --- 게이트 ---

  String? _sessionInputReason(SessionPort session, String screen) {
    // 사용량·인증 등의 런타임 오류는 기존 복구 경로에서 따로 안내한다.
    if (_runtimeIssueDetector.detectBlocking(screen, now: _now()) != null) {
      return null;
    }
    return _interventionDetector.inspect(session, screen);
  }

  /// 사용자 개입은 의도된 대기다. 타임아웃/자동 승인으로 통과시키지 않고,
  /// 명시적 재개 때 현재 화면과 연결을 다시 확인한다.
  Future<bool> _waitForSessionInput(List<String> allowedIds) async {
    final returnStatus = _currentStatus;
    var waited = false;
    while (!_stopped && !_finished) {
      final blocked = <String>[];
      for (final id in allowedIds) {
        final session = registry.byId(id);
        if (session == null || !session.isConnected) {
          if (_interventionConnections.remove(id) != null) {
            _setTaskPhase(id, SessionTaskPhase.error);
          }
          continue;
        }
        var screen = session.readScreen(maxLines: linesPerSession);
        var reason = _sessionInputReason(session, screen);
        if (reason == null && _interventionConnections.containsKey(id)) {
          final identity = _interventionConnections[id];
          if (session.connectionIdentity != identity) {
            _interventionConnections.remove(id);
            _setTaskPhase(id, SessionTaskPhase.error);
            continue;
          }
          // 이미 제출한 지시는 다시 보내지 않고 관찰만 이어간다.
          if (_tasks[id]?.lastInstruction != null) {
            final observation = await _observeUntilQuiescent(
              session,
              timeout: quiescenceTimeout,
              connectionIdentity: identity,
            );
            if (_stopped) return true;
            if (!_sameConnection(id, identity!)) {
              _interventionConnections.remove(id);
              _setTaskPhase(id, SessionTaskPhase.error);
              continue;
            }
            screen = observation.screen;
            reason = _sessionInputReason(session, screen);
            if (reason == null) {
              final runtime = _runtimeIssueDetector.detectBlocking(
                screen,
                now: _now(),
              );
              _setTaskPhase(
                id,
                !session.isConnected || runtime != null
                    ? SessionTaskPhase.error
                    : observation.quiescent
                    ? SessionTaskPhase.done
                    : SessionTaskPhase.working,
              );
            }
          } else {
            _setTaskPhase(id, SessionTaskPhase.idle);
          }
          if (reason == null) {
            _interventionConnections.remove(id);
            emit(
              ObservedEvent(
                _now(),
                sessionId: id,
                sessionName: session.displayName,
                delta: screen,
                quiescent:
                    !session.isBusy &&
                    (_tasks[id]?.phase == SessionTaskPhase.done ||
                        _tasks[id]?.phase == SessionTaskPhase.idle),
                isSnapshot: true,
              ),
            );
          }
        }
        if (reason == null) continue;
        if (!_interventionConnections.containsKey(id)) {
          _interventionConnections[id] = session.connectionIdentity;
          emit(
            ObservedEvent(
              _now(),
              sessionId: id,
              sessionName: session.displayName,
              delta: screen,
              quiescent: false,
              isSnapshot: true,
            ),
          );
        }
        _setTaskPhase(id, SessionTaskPhase.waitingInput);
        blocked.add('${session.displayName}: $reason');
      }
      if (blocked.isEmpty) {
        if (waited) _transition(returnStatus, step: _currentStep);
        return waited;
      }
      waited = true;
      final resumed = await _pauseUntilResumed(
        reason: AgentPauseReason.sessionInput,
        message:
            '${blocked.join("\n")}\n해당 터미널에서 직접 처리한 뒤 재개하세요. 자동으로 승인하거나 Enter를 보내지 않습니다.',
        resumeStatus: returnStatus,
        step: _currentStep,
      );
      if (!resumed) return true;
    }
    return waited;
  }

  Future<bool> _requestApproval({
    required String sessionId,
    required String sessionName,
    required String description,
    required String reason,
    required String screenContext,
    PendingApprovalKind kind = PendingApprovalKind.destructive,
    AgentCapability? capability,
  }) async {
    final returnStatus = _currentStatus;
    final approval = PendingApproval(
      sessionId: sessionId,
      sessionName: sessionName,
      description: description,
      reason: reason,
      screenContext: screenContext,
      kind: kind,
      capability: capability,
    );
    final completer = Completer<bool>();
    _approvalCompleter = completer;
    _transition(AgentLoopStatus.waitingApproval, step: _currentStep);
    onApproval(approval);
    emit(ApprovalRequestedEvent(_now(), approval: approval));
    if (_stopped && !completer.isCompleted) completer.complete(false);
    final approved = await completer.future;
    if (identical(_approvalCompleter, completer)) _approvalCompleter = null;
    onApproval(null);
    emit(
      ApprovalResolvedEvent(
        _now(),
        approved: approved,
        description: description,
      ),
    );
    if (!_stopped) _transition(returnStatus, step: _currentStep);
    return approved && !_stopped;
  }

  Future<String> _askUser(String question) async {
    final completer = Completer<String>();
    _answerCompleter = completer;
    _transition(AgentLoopStatus.waitingUser, step: _currentStep);
    onQuestion(question);
    emit(AskUserEvent(_now(), question: question));
    if (_stopped && !completer.isCompleted) completer.complete('');
    final answer = await completer.future;
    if (identical(_answerCompleter, completer)) _answerCompleter = null;
    onQuestion(null);
    if (answer.trim().isNotEmpty) {
      _feedbackQueue.add(answer.trim());
      emit(UserFeedbackEvent(_now(), text: answer.trim()));
    }
    if (!_stopped) _transition(AgentLoopStatus.planning, step: _currentStep);
    return answer;
  }

  Future<void> _awaitResumeIfPaused() async {
    while (_paused && !_stopped) {
      final resume = _resumeCompleter;
      if (resume == null) return;
      await Future.any<void>([resume.future, _stopCompleter.future]);
    }
  }

  Future<bool> _pauseForBudgetExtension(int completedSteps) async {
    return _pauseUntilResumed(
      reason: AgentPauseReason.budgetExhausted,
      message: 'step 예산 $maxSteps개를 모두 사용했습니다. 예산을 늘리면 이어서 실행합니다.',
      resumeStatus: AgentLoopStatus.planning,
      step: completedSteps,
    );
  }

  bool _deadlinePassed() {
    final deadline = _goal.deadline;
    return deadline != null && !_now().isBefore(deadline);
  }

  Future<bool> _pauseForDeadline(int completedSteps) async {
    final deadline = _goal.deadline!;
    final now = _now();
    emit(
      DeadlineReachedEvent(
        now,
        deadline: deadline,
        overrun: now.difference(deadline),
      ),
    );
    return _pauseUntilResumed(
      reason: AgentPauseReason.deadlineReached,
      message:
          '마감 ${AgentScheduleTrigger.formatDateTime(deadline)}을 지났습니다. '
          '마감을 연장하면 이어서 실행하고, 아니면 중단하세요.',
      resumeStatus: AgentLoopStatus.planning,
      step: completedSteps,
    );
  }

  Future<bool> _pauseForRecoverableError(
    String message, {
    required AgentLoopStatus resumeStatus,
  }) async {
    emit(LoopErrorEvent(_now(), message: message));
    return _pauseUntilResumed(
      reason: AgentPauseReason.recoverableError,
      message: message,
      resumeStatus: resumeStatus,
      step: _currentStep,
    );
  }

  Future<bool> _pauseForRuntimeBlocker(_RuntimeBlocker blocker) async {
    var issue = blocker.issue;
    while (!_stopped) {
      final resumed = await _pauseUntilResumed(
        reason: AgentPauseReason.runtimeBlocked,
        message:
            '${blocker.sessionName}: ${issue.message}\n터미널에서 문제를 처리한 뒤 재개하세요. 현재 화면을 다시 확인합니다.',
        resumeStatus: AgentLoopStatus.observing,
        step: _currentStep,
      );
      if (!resumed) return false;
      final session = registry.byId(blocker.sessionId);
      if (session == null || !session.isConnected) return true;
      final screen = session.readScreen(maxLines: linesPerSession);
      final currentIssue = _runtimeIssueDetector.detectBlocking(
        screen,
        now: _now(),
      );
      if (currentIssue != null) {
        issue = currentIssue;
        continue;
      }
      // 오류가 사라진 것은 복구의 근거이지 이전 작업 완료의 근거는 아니다.
      _setTaskPhase(blocker.sessionId, SessionTaskPhase.idle);
      emit(
        ObservedEvent(
          _now(),
          sessionId: blocker.sessionId,
          sessionName: session.displayName,
          delta: screen,
          quiescent: false,
          isSnapshot: true,
        ),
      );
      return true;
    }
    return false;
  }

  Future<bool> _pauseUntilResumed({
    required AgentPauseReason reason,
    required String message,
    required AgentLoopStatus resumeStatus,
    required int step,
  }) async {
    if (_stopped) return false;
    _paused = true;
    _pauseReason = reason;
    _pauseMessage = message;
    _resumeStatus = resumeStatus;
    _resumeCompleter = Completer<void>();
    if (!_pauseSignal.isCompleted) _pauseSignal.complete();
    _transition(
      AgentLoopStatus.paused,
      step: step,
      pauseReason: reason,
      pauseMessage: message,
    );
    await _awaitResumeIfPaused();
    return !_stopped;
  }

  Future<bool> _delayWithControl(Duration duration) async {
    var remaining = duration;
    while (remaining > Duration.zero) {
      await _awaitResumeIfPaused();
      if (_stopped || _finished) return false;
      final pauseSignal = _pauseSignal.future;
      final stopwatch = Stopwatch()..start();
      final result = await Future.any<int>([
        _sleep(remaining).then((_) => 0),
        _stopCompleter.future.then((_) => 1),
        pauseSignal.then((_) => 2),
      ]);
      stopwatch.stop();
      if (result == 0) return true;
      if (result == 1) return false;
      final elapsed = stopwatch.elapsed;
      remaining = elapsed >= remaining ? Duration.zero : remaining - elapsed;
    }
    await _awaitResumeIfPaused();
    return !_stopped;
  }

  bool _canPause(AgentLoopStatus status) => switch (status) {
    AgentLoopStatus.planning ||
    AgentLoopStatus.dispatching ||
    AgentLoopStatus.observing ||
    AgentLoopStatus.evaluating => true,
    _ => false,
  };

  void _transition(
    AgentLoopStatus status, {
    int? step,
    AgentPauseReason? pauseReason,
    String? pauseMessage,
  }) {
    _currentStatus = status;
    if (step != null) _currentStep = step;
    onStatus(
      status,
      step: step,
      pauseReason: pauseReason,
      pauseMessage: pauseMessage,
    );
  }

  // --- 헬퍼 ---

  AgentRunResult _finish(
    AgentLoopOutcome outcome,
    String summary,
    int steps,
    DateTime startedAt,
  ) {
    onApproval(null);
    onQuestion(null);
    // 아직 도는 배경 관찰을 깨워서 끝낸다. 두지 않으면 종료된 loop의 세션을
    // 최대 timeout까지 계속 폴링한다.
    _finished = true;
    if (!_stopCompleter.isCompleted) _stopCompleter.complete();
    // Notifier가 finished 상태에서 outcome을 찾을 수 있도록 이벤트를 먼저 emit한다.
    emit(
      LoopFinishedEvent(
        _now(),
        outcome: outcome,
        summary: summary.trim().isEmpty ? 'loop가 종료되었습니다.' : summary.trim(),
        steps: steps,
        elapsed: _now().difference(startedAt),
      ),
    );
    _transition(AgentLoopStatus.finished, step: steps);
    return AgentRunResult(outcome: outcome, summary: summary, steps: steps);
  }

  AgentRunResult _finishStopped(int steps, DateTime startedAt) =>
      _finish(AgentLoopOutcome.stopped, '사용자가 loop를 중단했습니다.', steps, startedAt);

  List<SessionPort> _allowedSessions(List<String> allowedIds) => [
    for (final session in registry.sessions())
      if (allowedIds.contains(session.id)) session,
  ];

  /// 화면에서 얻은 agent 판별 결과를 기록하고, 지금 쓸 힌트를 돌려준다.
  ///
  /// 한 번 알아낸 값을 `unknown`으로 되돌리지 않는 것이 핵심이다. agent의 시작
  /// 배너는 대화가 길어지면 화면 밖으로 밀려나는데, 그때마다 힌트를 지우면
  /// 세션 인벤토리가 `unknown`이 되고 플래너는 그 세션을 AI agent로 다루지
  /// 못해 일을 배정하지 않는다. 더 확실한 판별이 나올 때만 교체한다.
  String _rememberAgentHint(String sessionId, String screen) {
    final inspection = AgentSessionInspector.inspect(
      screen,
      // 역할에 선언된 모델 이름도 패밀리 단어로 쳐준다. 내장 목록에 없는
      // 사내·자체 호스팅 모델을 쓰면 감지가 늘 비어 불일치 배지가 죽는다.
      extraFamilies: _declaredModelFamilies(),
    );
    final previous = _agentHintConfidence[sessionId];
    final isBetter =
        previous == null || inspection.confidence.index >= previous.index;
    if (inspection.confidence != AgentDetectionConfidence.none && isBetter) {
      _agentHints[sessionId] = inspection.agentHint;
      _agentHintConfidence[sessionId] = inspection.confidence;
    }
    final modelHint = inspection.modelHint;
    final previousModelConfidence = _modelHintConfidence[sessionId];
    final isModelBetter =
        previousModelConfidence == null ||
        inspection.modelConfidence.index >= previousModelConfidence.index;
    if (modelHint != null &&
        inspection.modelConfidence != AgentDetectionConfidence.none &&
        isModelBetter) {
      _modelHints[sessionId] = modelHint;
      _modelHintConfidence[sessionId] = inspection.modelConfidence;
    }
    return _agentHints[sessionId] ?? inspection.agentHint;
  }

  /// 이번 실행의 역할에 선언된 모델에서 뽑은 패밀리 단어들.
  Set<String> _declaredModelFamilies() =>
      AgentSessionInspector.familyWordsFrom([
        for (final role in _sessionRoles.values)
          if (role.declaredModel != null &&
              role.declaredModel!.trim().isNotEmpty)
            role.declaredModel!.trim(),
      ]);

  /// confirmed로 감지된 모델 라벨만 인벤토리·UI에 노출한다.
  String? _confirmedModelHint(String sessionId) {
    if (_modelHintConfidence[sessionId] != AgentDetectionConfidence.confirmed) {
      return null;
    }
    return _modelHints[sessionId];
  }

  /// 세션별로 confirmed 확신도인 모델 라벨만 모은 맵. 인벤토리 프롬프트에 넘긴다.
  Map<String, String> _confirmedModelHints() => {
    for (final entry in _modelHints.entries)
      if (_modelHintConfidence[entry.key] == AgentDetectionConfidence.confirmed)
        entry.key: entry.value,
  };

  void _refreshTasks(List<String> allowedIds) {
    final sessions = _allowedSessions(allowedIds);
    final next = <String, SessionTaskView>{};
    for (final session in sessions) {
      final screen = session.readScreen(maxLines: linesPerSession);
      final hint = _rememberAgentHint(session.id, screen);
      final existing = _tasks[session.id];
      next[session.id] = SessionTaskView(
        sessionId: session.id,
        displayName: session.displayName,
        agentHint: hint,
        role: _sessionRoles[session.id],
        phase: !session.isConnected
            ? SessionTaskPhase.error
            : existing?.phase ?? SessionTaskPhase.idle,
        lastInstruction: existing?.lastInstruction,
        detectedModel: _confirmedModelHint(session.id),
      );
    }
    _tasks
      ..clear()
      ..addAll(next);
    _publishTasks();
  }

  /// 세션 상태를 UI로 내보낸다.
  ///
  /// 우편함 미배달 건수와 배경 작업 여부는 터미널 화면에 아무 흔적이 없다.
  /// 여기서 붙여주지 않으면 사용자는 왜 다음 지시에 다른 세션 이야기가 붙는지,
  /// 왜 멀쩡해 보이는 세션에 지시가 안 나가는지 알 수 없다.
  void _publishTasks() {
    onSessionTasks({
      for (final entry in _tasks.entries)
        entry.key: entry.value.copyWith(
          unreadMessages: _mailbox.unreadCount(entry.key),
          backgroundRunning: _background.containsKey(entry.key),
        ),
    });
    onMailbox?.call(_mailbox.allPending());
  }

  void _setTaskPhase(String id, SessionTaskPhase phase, {String? instruction}) {
    final existing = _tasks[id];
    if (existing == null) return;
    _tasks[id] = existing.copyWith(
      phase: phase,
      lastInstruction: instruction ?? existing.lastInstruction,
    );
    _publishTasks();
  }

  _RuntimeBlocker _recordRuntimeIssue(
    TerminalRuntimeIssue issue, {
    required String sessionId,
    required String sessionName,
  }) {
    emit(
      TerminalRuntimeIssueEvent(
        _now(),
        code: issue.code,
        sessionId: sessionId,
        sessionName: sessionName,
        message: issue.message,
        evidence: issue.evidence,
      ),
    );
    return _RuntimeBlocker(
      issue: issue,
      sessionId: sessionId,
      sessionName: sessionName,
    );
  }

  AgentLoopOutcome _outcomeFromStatus(String? status) => switch (status) {
    'achieved' => AgentLoopOutcome.achieved,
    'blocked' => AgentLoopOutcome.blocked,
    'partial' => AgentLoopOutcome.partial,
    _ => AgentLoopOutcome.partial,
  };

  String _withoutTrailingSubmit(String input) {
    return input.endsWith('\r\n')
        ? input.substring(0, input.length - 2)
        : input.endsWith('\r') || input.endsWith('\n')
        ? input.substring(0, input.length - 1)
        : input;
  }

  String _truncateForLog(String value) {
    const maxCharacters = 2400;
    if (value.length <= maxCharacters) return value;
    return '${value.substring(0, maxCharacters)}\n...(truncated)';
  }

  DateTime _now() => clock.now();
}

class _ActionOutcome {
  const _ActionOutcome(
    this.log, {
    this.sent = false,
    this.runtimeBlockers = const [],
  });
  final String log;
  final bool sent;
  final List<_RuntimeBlocker> runtimeBlockers;
}

class _UnsubmittedInput implements Exception {
  const _UnsubmittedInput(this.message);
  final String message;
}

class _RebuildModelRequest implements Exception {
  const _RebuildModelRequest();
}

class _RuntimeBlocker {
  const _RuntimeBlocker({
    required this.issue,
    required this.sessionId,
    required this.sessionName,
  });

  final TerminalRuntimeIssue issue;
  final String sessionId;
  final String sessionName;
}

class _DispatchOutcome {
  const _DispatchOutcome._({this.outcome, this.pendingObservation});

  factory _DispatchOutcome.outcome(_ActionOutcome outcome) =>
      _DispatchOutcome._(outcome: outcome);

  factory _DispatchOutcome.pending(_PendingObservation pendingObservation) =>
      _DispatchOutcome._(pendingObservation: pendingObservation);

  final _ActionOutcome? outcome;
  final _PendingObservation? pendingObservation;
}

class _PendingObservation {
  const _PendingObservation({
    required this.action,
    required this.session,
    required this.sessionId,
    required this.sessionName,
    required this.before,
    required this.connectionIdentity,
    required this.timeout,
  });

  final AgentAction action;
  final SessionPort session;
  final String sessionId;
  final String sessionName;
  final String before;
  final Object connectionIdentity;
  final Duration timeout;
}

class _Observation {
  const _Observation(this.screen, this.quiescent);
  final String screen;
  final bool quiescent;
}

enum _AgentStallKind { providerFailure, silent }

class _AgentStall {
  const _AgentStall(this.kind, {required this.reason, required this.evidence});
  final _AgentStallKind kind;
  final String reason;
  final String evidence;
}
