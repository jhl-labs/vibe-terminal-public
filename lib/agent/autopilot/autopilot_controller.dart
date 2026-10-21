import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../ai/ai_chat_service.dart';
import '../../session/session_activity.dart';
import '../../session/session_attention.dart';
import '../../state/providers.dart';
import '../agent_chat_notifier.dart';
import '../agent_launcher.dart';
import '../session_manager_port.dart';
import '../session_port.dart';
import '../../session/session_notification_mute.dart';
import 'approval/approval_flow.dart';
import 'approval/approval_policy.dart';
import 'approval/approval_prompt_parser.dart';
import 'autopilot_gate.dart';
import 'autopilot_prefs_binding.dart';
import 'autopilot_prefs_store.dart';
import 'autopilot_prefs_sync.dart';
import 'autopilot_runtime.dart';
import 'autopilot_state.dart';
import 'autopilot_timing.dart';
import 'resume/resume_flow.dart';
import 'resume/resume_judge.dart';
import 'usage_limit/usage_limit_flow.dart';
import 'usage_limit/usage_limit_parser.dart';
import 'usage_limit/usage_wait_planner.dart';

part 'autopilot_controller_runtime.dart';

/// 세션 단위 Agent 자율사용: 끊김 재개, 사용량 한도 대기, 권한 요청 자동 승인.
///
/// [SessionActivityTracker]의 busy→idle 전이를 구독해, 켜진 세션이 조용해지면
/// 게이트(승인 대기·작업 중·사용자 조작 중·오케스트레이터 관찰 중 등)를 거친 뒤
/// [ResumeJudge]로 비정상 중단인지 판정하고, 맞으면 백오프 뒤 재개 지시를
/// 보낸다. 판정 LLM은 Agent 자신의 LLM이 아닌 앱 AI 설정의 provider다.
///
/// 이 컨트롤러는 공개 API·활동 구독·흐름 분기(승인 → 한도 → 재개)를 맡는다.
/// 토글 저장·복원은 [AutopilotPrefsBinding]이, 각 흐름은 [ApprovalFlow]·
/// [UsageLimitFlow]·[ResumeFlow]가, 개입 가능 여부는 [AutopilotGate]가 맡는다. 흐름은 provider를 직접 읽지 않고
/// [AutopilotRuntime]만 거친다. 그 구현(`_ControllerRuntime`, part 파일)은 이
/// 컨트롤러의 비공개 기본 동작을 써서 공개 API를 넓히지 않는다.
class AutopilotController extends Notifier<Map<String, AutopilotState>> {
  AutopilotController({
    ResumeJudge? judge,
    this.timing = const AutopilotTiming(),
    SessionPortRegistry? ports,
    this.approvalParser = const ApprovalPromptParser(),
    this.approvalPolicy = const ApprovalPolicy(),
    this.usageLimitParser = const UsageLimitParser(),
    this.usageWaitPlanner = const UsageWaitPlanner(),
  }) : assert(
         timing.settleDelay >= timing.approvalSettle,
         'settleDelay는 approvalSettle보다 짧을 수 없다(승인 확인 뒤 남은 시간만큼 안정화).',
       ),
       _judgeOverride = judge,
       _portsOverride = ports;

  /// 1차 릴리스에서 토글을 제공하는 CLI.
  static const supportedClis = {
    AgentCli.claude,
    AgentCli.codex,
    AgentCli.opencode,
  };

  final AutopilotTiming timing;
  final ApprovalPromptParser approvalParser;
  final ApprovalPolicy approvalPolicy;
  final UsageLimitParser usageLimitParser;
  final UsageWaitPlanner usageWaitPlanner;
  final ResumeJudge? _judgeOverride;
  final SessionPortRegistry? _portsOverride;

  final Map<String, DateTime> _idleSince = {};
  final Map<String, DateTime> _lastUserInputAt = {};

  /// 흐름·게이트가 쓰는 실행 환경. 타이머·작업 토큰·주입 표시·기록을 가진다.
  late final _ControllerRuntime _runtime = _ControllerRuntime(this);

  /// 토글 저장과 재시작 뒤 복원.
  late AutopilotPrefsBinding _prefs;

  late final AutopilotGate _gate = AutopilotGate(
    _runtime,
    supportedClis: supportedClis,
    approvalParser: approvalParser,
    approvalCooldownUntil: (id) => _approval.cooldownUntil(id),
  );

  late final ApprovalFlow _approval = ApprovalFlow(
    _runtime,
    _gate,
    parser: approvalParser,
    policy: approvalPolicy,
  );

  late final UsageLimitFlow _usage = UsageLimitFlow(
    _runtime,
    _gate,
    parser: usageLimitParser,
    planner: usageWaitPlanner,
  );

  late final ResumeFlow _resume = ResumeFlow(
    _runtime,
    _gate,
    judge: () => _judge,
    workspaceIdOf: _workspaceIdOf,
    findWorktree: (workspaceId) =>
        ref.read(agentWorktreeStoreProvider).find(workspaceId),
  );

  @override
  Map<String, AutopilotState> build() {
    // sessionManagerProvider를 listen하면 SessionManager(onInput)→이 컨트롤러
    // 읽기와 순환이 되므로, 세션 종료는 활동 추적기의 키 제거로 알아챈다.
    ref.listen<Map<String, bool>>(sessionActivityProvider, _onActivity);
    ref.onDispose(_runtime._cancelAllTimers);
    _prefs = AutopilotPrefsBinding(
      AutopilotPrefsSync(ref.read(autopilotPrefsStoreProvider)),
      states: () => state,
      sessionHosts: () => {
        for (final s in ref.read(sessionManagerProvider)) s.id: s.host.id,
      },
      wasRestored: (id) =>
          ref.read(sessionManagerProvider.notifier).wasRestoredSession(id),
      hasPort: (id) => _ports.byId(id) != null,
      restore: (id, prefs) {
        setEnabled(id, true);
        if (prefs.notifyOnly) setNotifyOnly(id, true);
      },
      record: _runtime.record,
      mounted: () => ref.mounted,
    );
    unawaited(_prefs.load());
    return const {};
  }

  ResumeJudge get _judge =>
      _judgeOverride ??
      ResumeJudge(
        complete: ({required system, required user}) => ref
            .read(aiChatServiceProvider)
            .complete(
              settings: ref.read(appSettingsProvider).ai,
              sessionLabel: 'Agent Autopilot',
              terminalContext: '',
              systemPromptOverride: system,
              messages: [
                AiChatMessage(
                  role: AiChatRole.user,
                  content: user,
                  createdAt: clock.now(),
                ),
              ],
            ),
      );

  String? _workspaceIdOf(String id) {
    for (final session in ref.read(sessionManagerProvider)) {
      if (session.id == id) return session.agentWorkspace?.workspaceId;
    }
    return null;
  }

  SessionPortRegistry get _ports =>
      _portsOverride ?? ref.read(sessionPortRegistryProvider);

  // ---------------------------------------------------------------------------
  // 공개 API (UI)
  // ---------------------------------------------------------------------------

  AutopilotState stateOf(String sessionId) =>
      state[sessionId] ?? const AutopilotState();

  bool isEnabled(String sessionId) => stateOf(sessionId).enabled;

  /// 판정 LLM(앱 AI 설정)이 준비됐는지. 아니면 조용한 멈춤 판정만 건너뛴다.
  bool get aiConfigured => ref.read(appSettingsProvider).ai.isConfigured;

  /// 세션에서 감지된 CLI. 화면·제목 판별 결과를 우선하고, 없으면 작업공간 정보.
  AgentCli? cliFor(String sessionId) {
    final hint = ref.read(sessionAttentionProvider)[sessionId]?.agentHint;
    for (final cli in AgentCli.values) {
      if (cli.name == hint) return cli;
    }
    for (final session in ref.read(sessionManagerProvider)) {
      if (session.id == sessionId) return session.agentWorkspace?.cli;
    }
    return null;
  }

  /// 컨텍스트 메뉴에 토글을 보일지. 연결된 세션에서 지원 CLI가 보일 때만.
  bool isAvailableFor(String sessionId) {
    final port = _ports.byId(sessionId);
    if (port == null || !port.isConnected) return false;
    final cli = cliFor(sessionId);
    return cli != null && supportedClis.contains(cli);
  }

  void setEnabled(String sessionId, bool enabled) {
    _invalidate(sessionId);
    if (!enabled) {
      _cancelTimer(sessionId);
      // 끈 뒤에는 idle·입력을 보지 않으므로 우리가 올린 표시를 지금 내린다.
      _releaseBlock(sessionId);
      if (!state.containsKey(sessionId)) return;
      _set(
        sessionId,
        stateOf(sessionId).copyWith(
          enabled: false,
          phase: AutopilotPhase.idle,
          usageResetAt: null,
          usageWaitStartedAt: null,
        ),
      );
      _runtime.record(sessionId, '자율사용 끔');
      _prefs.persist();
      return;
    }
    final cli = cliFor(sessionId);
    _approval.forgetFailures(sessionId);
    _set(
      sessionId,
      stateOf(sessionId).copyWith(
        enabled: true,
        cli: cli,
        resumeAttempt: 0,
        phase: AutopilotPhase.idle,
        cooldownUntil: null,
        usageResetAt: null,
        usageWaitStartedAt: null,
      ),
    );
    _runtime.record(sessionId, '자율사용 켬 (${cli?.label ?? '?'})');
    // 이미 조용한 세션이면 idle 전이가 다시 오지 않으므로 지금 평가한다.
    if (!ref.read(sessionActivityProvider.notifier).isBusy(sessionId)) {
      _idleSince[sessionId] ??= clock.now();
      _onIdle(sessionId);
    }
    _prefs.persist();
  }

  void toggle(String sessionId) => setEnabled(sessionId, !isEnabled(sessionId));

  void setNotifyOnly(String sessionId, bool notifyOnly) {
    _invalidate(sessionId);
    _set(
      sessionId,
      stateOf(sessionId).copyWith(
        notifyOnly: notifyOnly,
        usageResetAt: null,
        usageWaitStartedAt: null,
      ),
    );
    _runtime.record(sessionId, notifyOnly ? '알림만 모드' : '자동 실행 모드');
    _prefs.persist();
    // 알림만으로 보류한 승인 화면·한도 공지는 출력을 더 내지 않아 idle 전이가
    // 다시 오지 않는다. 자동 모드로 바꾼 지금 다시 평가한다.
    if (!notifyOnly &&
        stateOf(sessionId).enabled &&
        !ref.read(sessionActivityProvider.notifier).isBusy(sessionId)) {
      _idleSince[sessionId] ??= clock.now();
      _onIdle(sessionId);
    }
  }

  /// 세션 진단용 최근 기록(최신이 마지막).
  List<String> logFor(String sessionId) =>
      List.unmodifiable(_runtime._log[sessionId] ?? const []);

  /// 사용자가 이 세션에 키를 쳤다. Enter 제출은 새 작업의 경계라 재개 횟수를 되돌린다.
  void noteUserInput(String sessionId, {required bool submitted}) {
    if (_runtime._injecting.contains(sessionId)) return;
    _lastUserInputAt[sessionId] = clock.now();
    if (submitted) _usage.rememberSubmittedNotice(sessionId);
    final current = state[sessionId];
    if (current == null || !current.enabled) return;
    // 판정·재실행·Enter 대기·한도 대기 중의 사람 입력도 이전 작업을 무효화한다.
    _invalidate(sessionId);
    _usage.clearWait(sessionId, endWait: submitted);
    if (submitted &&
        (current.resumeAttempt > 0 ||
            current.approvalCount > 0 ||
            current.phase == AutopilotPhase.exhausted)) {
      _set(
        sessionId,
        stateOf(sessionId).copyWith(
          resumeAttempt: 0,
          approvalCount: 0,
          phase: AutopilotPhase.idle,
          cooldownUntil: null,
        ),
      );
      _releaseBlock(sessionId);
      _approval.forgetFailures(sessionId);
      _runtime.record(sessionId, '사용자가 새 프롬프트 제출 → 재개·승인 횟수 초기화');
    }
  }

  void remove(String sessionId) {
    _runtime._operations.remove(sessionId);
    _cancelTimer(sessionId);
    _idleSince.remove(sessionId);
    _lastUserInputAt.remove(sessionId);
    _runtime._log.remove(sessionId);
    _runtime._injecting.remove(sessionId);
    _releaseBlock(sessionId);
    _approval.forgetFailures(sessionId);
    _usage.forget(sessionId);
    final hadState = state.containsKey(sessionId);
    if (hadState) state = {...state}..remove(sessionId);
    _prefs.forget(sessionId, stateRemoved: hadState);
  }

  // ---------------------------------------------------------------------------
  // 활동 구독
  // ---------------------------------------------------------------------------

  void _onActivity(Map<String, bool>? previous, Map<String, bool> next) {
    if (previous != null) {
      for (final id in previous.keys) {
        if (!next.containsKey(id) &&
            (state.containsKey(id) || _prefs.isPending(id))) {
          remove(id);
        }
      }
    }
    _prefs.reconcile();
    for (final entry in next.entries) {
      final id = entry.key;
      final wasBusy = previous?[id] ?? false;
      if (wasBusy && !entry.value) {
        _idleSince[id] = clock.now();
        _onIdle(id);
      } else if (!wasBusy && entry.value) {
        _idleSince.remove(id);
        final current = state[id];
        // 다시 출력이 나오면 정상 진행 중이다. 예약된 승인 해석·안정화 대기는
        // 접는다. 승인 확인·백오프·한도 대기의 타이머는 그대로 둔다.
        if (current != null && current.phase == AutopilotPhase.idle) {
          _cancelTimer(id);
        } else if (current != null &&
            current.phase == AutopilotPhase.settling) {
          _cancelTimer(id);
          _set(id, current.copyWith(phase: AutopilotPhase.idle));
        }
      }
    }
  }

  void _onIdle(String id) {
    final current = state[id];
    if (current == null || !current.enabled) return;
    if (_ports.byId(id) == null) {
      remove(id);
      return;
    }
    if (current.isActive || current.phase == AutopilotPhase.exhausted) return;
    if (current.phase == AutopilotPhase.settling) return;
    // 안정화 대기에 들어가되, 승인 프롬프트는 짧게 기다린 뒤 먼저 본다.
    // 아니면 남은 안정화 시간 뒤 기존 재개 판정으로 넘어간다.
    _set(id, current.copyWith(phase: AutopilotPhase.settling));
    _runtime.schedule(
      id,
      timing.approvalSettle,
      () => _afterApprovalSettle(id),
    );
  }

  /// [AutopilotTiming.approvalSettle] 뒤: 승인 프롬프트면 승인 흐름, 아니면 남은
  /// 안정화 시간 뒤 재개 판정. 승인 확인 직후의 재확인은 idle에서 들어온다.
  void _afterApprovalSettle(String id) {
    final settling = state[id];
    if (settling == null || !settling.enabled) return;
    if (settling.phase != AutopilotPhase.settling &&
        settling.phase != AutopilotPhase.idle) {
      return;
    }
    final current = settling.copyWith(phase: AutopilotPhase.idle);
    final port = _ports.byId(id);
    if (port == null) {
      _set(id, current);
      return;
    }
    final prompt = _approval.read(id, current, port);
    if (prompt != null) {
      _set(id, current);
      _approval.handle(id, current, port, prompt);
      return;
    }
    _approval.promptGone(id);
    final hit = _usage.freshLimit(id, port);
    if (hit != null) {
      _set(id, current);
      _usage.scheduleResume(id, current, port, hit);
      return;
    }
    if (_gate.check(id, current, requireQuiet: false) != null) {
      _set(id, current);
      return;
    }
    _set(id, current.copyWith(phase: AutopilotPhase.settling));
    _runtime.schedule(
      id,
      timing.settleDelay - timing.approvalSettle,
      () => _resume.afterSettle(id),
    );
  }

  // ---------------------------------------------------------------------------
  // 내부 유틸
  // ---------------------------------------------------------------------------

  /// 승인 보류 기록과 이 컨트롤러가 올린 "Agent 확인 필요" 표시를 모두 내린다.
  void _releaseBlock(String id) {
    _approval.forgetNotice(id);
    _runtime.clearBlock(id);
  }

  void _cancelTimer(String id) => _runtime._cancelTimer(id);

  void _invalidate(String id) {
    _runtime._operations.remove(id);
    _cancelTimer(id);
    final current = state[id];
    if (current != null && current.phase != AutopilotPhase.exhausted) {
      _set(id, current.copyWith(phase: AutopilotPhase.idle));
    }
  }

  // ---------------------------------------------------------------------------
  // 런타임([_ControllerRuntime])이 쓰는 비공개 기본 동작
  // ---------------------------------------------------------------------------

  AutopilotState? _stateAt(String id) => state[id];

  void _set(String id, AutopilotState next) {
    state = {...state, id: next};
  }

  T _read<T>(ProviderListenable<T> provider) => ref.read(provider);

  bool get _mounted => ref.mounted;
}

final agentAutopilotProvider =
    NotifierProvider<AutopilotController, Map<String, AutopilotState>>(
      AutopilotController.new,
    );
