import 'dart:async';

import 'package:clock/clock.dart';

import '../../agent_attention.dart';
import '../../agent_launcher.dart';
import '../../agent_session_inspector.dart';
import '../../agent_worktree.dart';
import '../../quiescence_detector.dart';
import '../../session_port.dart';
import '../autopilot_gate.dart';
import '../autopilot_runtime.dart';
import '../autopilot_state.dart';
import 'resume_judge.dart';
import 'resume_recovery.dart';

/// 끊김 재개 흐름: 조용해진 세션을 판정하고, 비정상 중단이면 백오프 뒤 재개 지시
/// (필요하면 CLI 재실행)를 보낸다. 판정 LLM과 작업공간 조회는 생성자로 받고,
/// 타이머·작업 토큰·주입 표시는 [AutopilotRuntime]이 맡는다.
class ResumeFlow {
  ResumeFlow(
    this._runtime,
    this._gate, {
    required this.judge,
    required this.workspaceIdOf,
    required this.findWorktree,
  });

  final AutopilotRuntime _runtime;
  final AutopilotGate _gate;

  /// 판정기. 호출할 때마다 앱 AI 설정을 다시 읽도록 매번 얻는다.
  final ResumeJudge Function() judge;

  /// 세션의 Agent 작업공간 id. 작업공간이 없으면 null.
  final String? Function(String id) workspaceIdOf;

  final Future<AgentWorktreeRecord?> Function(String workspaceId) findWorktree;

  /// 안정화 대기가 끝났다. 게이트를 거쳐 [ResumeJudge]로 판정하고, 비정상 중단이면
  /// 백오프 뒤 재개를 예약한다. 판정·재개 중 사람 입력·끄기·재연결이면 손을 뗀다.
  Future<void> afterSettle(String id) async {
    final current = _runtime.stateAt(id);
    if (current == null || !current.enabled) return;
    if (current.phase != AutopilotPhase.settling) return;
    final blocked = _gate.check(id, current, requireQuiet: true);
    if (blocked != null) {
      _runtime.setState(id, current.copyWith(phase: AutopilotPhase.idle));
      _runtime.record(id, '판정 생략: $blocked');
      return;
    }
    final port = _runtime.portOf(id)!;
    final identity = port.connectionIdentity;
    final operation = _runtime.beginOperation(id);
    final screen = port.readScreen(maxLines: 160);
    final now = clock.now();
    _runtime.setState(id, current.copyWith(phase: AutopilotPhase.judging));
    final verdict = await judge().judge(
      screen: screen,
      idleFor: now.difference(_runtime.idleSince(id) ?? now),
      attempt: current.resumeAttempt,
      now: now,
      allowLlm: _runtime.aiConfigured,
    );
    if (!_runtime.isCurrent(id, operation)) return;
    final afterJudge = _runtime.stateAt(id);
    if (afterJudge == null || !afterJudge.enabled) return;
    final blockedNow = _gate.check(id, afterJudge, requireQuiet: true);
    if (!_runtime.sameConnection(port, identity) || blockedNow != null) {
      _runtime.setState(id, afterJudge.copyWith(phase: AutopilotPhase.idle));
      _runtime.record(id, '판정 취소: ${blockedNow ?? '세션 연결이 바뀜'}');
      return;
    }
    _runtime.record(id, '판정(${verdict.source.label}): $verdict');
    // 한도 문구 없이 판정까지 왔으면 한도 대기 연장은 끝났다.
    final judged = afterJudge.copyWith(
      lastVerdict: verdict,
      lastJudgedAt: clock.now(),
      usageResetAt: null,
      usageWaitStartedAt: null,
    );
    if (verdict.source == ResumeVerdictSource.error) {
      _runtime.setState(
        id,
        judged.copyWith(
          phase: AutopilotPhase.idle,
          cooldownUntil: clock.now().add(_runtime.timing.errorCooldown),
        ),
      );
      return;
    }
    if (!verdict.isInterrupted) {
      _runtime.setState(
        id,
        judged.copyWith(
          phase: AutopilotPhase.idle,
          cooldownUntil: clock.now().add(_runtime.timing.minJudgeInterval),
        ),
      );
      return;
    }
    if (judged.notifyOnly) {
      _runtime.setState(
        id,
        judged.copyWith(
          phase: AutopilotPhase.idle,
          cooldownUntil: clock.now().add(_runtime.timing.minJudgeInterval),
        ),
      );
      unawaited(
        _runtime.notify(
          id,
          '중단 감지 (알림만)',
          '${verdict.reason}\n${verdict.evidence}',
        ),
      );
      return;
    }
    final attempt = judged.resumeAttempt + 1;
    if (attempt > _runtime.timing.maxAttempts) {
      _runtime.setState(id, judged.copyWith(phase: AutopilotPhase.exhausted));
      _runtime.record(id, '재개 한도(${_runtime.timing.maxAttempts}회) 도달');
      _runtime.raiseBlock(
        id,
        message:
            '자동 재개 ${_runtime.timing.maxAttempts}회 뒤에도 Agent가 계속 중단됩니다. '
            '터미널에서 상태·네트워크를 확인하세요.',
        agentHint: judged.cli?.name ?? 'agent',
      );
      unawaited(_runtime.notify(id, '자동 재개 한도 도달', verdict.reason));
      return;
    }
    if (!_runtime.sameConnection(port, identity)) {
      _runtime.setState(id, judged.copyWith(phase: AutopilotPhase.idle));
      return;
    }
    _runtime.setState(
      id,
      judged.copyWith(
        resumeAttempt: attempt,
        phase: AutopilotPhase.waitingBackoff,
      ),
    );
    final delay = _runtime.timing.backoff(attempt);
    _runtime.record(id, '재개 #$attempt 예약 (${delay.inSeconds}s 뒤)');
    _runtime.schedule(
      id,
      delay,
      () => _resume(id, verdict, identity, operation),
    );
  }

  Future<void> _resume(
    String id,
    ResumeVerdict verdict,
    Object identity,
    Object operation,
  ) async {
    if (!_runtime.isCurrent(id, operation)) return;
    final current = _runtime.stateAt(id);
    if (current == null ||
        !current.enabled ||
        current.phase != AutopilotPhase.waitingBackoff) {
      return;
    }
    final port = _runtime.portOf(id);
    if (port == null || !_runtime.sameConnection(port, identity)) {
      _runtime.setState(id, current.copyWith(phase: AutopilotPhase.idle));
      _runtime.record(id, '재개 취소: 세션 연결이 바뀜');
      return;
    }
    // 백오프 동안 스스로 재개했거나 사람이 개입했으면 손대지 않는다.
    final blocked = _gate.check(id, current, requireQuiet: true);
    if (blocked != null) {
      _runtime.setState(id, current.copyWith(phase: AutopilotPhase.idle));
      _runtime.record(id, '재개 취소: $blocked');
      return;
    }
    final cli = _runtime.liveCli(id, current);
    if (cli == null) {
      _runtime.setState(id, current.copyWith(phase: AutopilotPhase.idle));
      _runtime.record(id, '재개 취소: CLI를 알 수 없음');
      return;
    }
    _runtime.setState(id, current.copyWith(phase: AutopilotPhase.resuming));
    final plan = planResumeRecovery(
      cli: cli,
      verdict: verdict,
      attempt: current.resumeAttempt,
      nativeSessionId: await _nativeSessionIdFor(id),
    );
    if (!_stillResuming(id, port, identity, operation)) return;
    try {
      if (plan.needsRelaunch) {
        _runtime.record(id, '재실행: ${plan.relaunchCommand}');
        _runtime.inject(id, () => port.sendText(plan.relaunchCommand!));
        await _runtime.sleep(_runtime.timing.submitDelay);
        if (!_stillResuming(id, port, identity, operation)) return;
        _runtime.inject(id, port.submit);
        final ready = await _waitForTui(id, port, identity, operation);
        if (!_stillResuming(id, port, identity, operation)) return;
        if (!ready) {
          _runtime.record(id, '재개 실패: TUI가 뜨지 않음');
          _runtime.setState(
            id,
            _runtime.stateOf(id).copyWith(phase: AutopilotPhase.idle),
          );
          return;
        }
      }
      _runtime.inject(id, () => port.sendText(plan.prompt));
      await _runtime.sleep(_runtime.timing.submitDelay);
      if (!_stillResuming(id, port, identity, operation)) return;
      _runtime.inject(id, port.submit);
      _runtime.record(id, '재개 #${current.resumeAttempt} 지시 전송');
      _runtime.markTaskSubmitted(id);
    } catch (error) {
      if (!_runtime.isCurrent(id, operation)) return;
      _runtime.record(id, '재개 실패: $error');
      _runtime.setState(
        id,
        _runtime
            .stateOf(id)
            .copyWith(
              phase: AutopilotPhase.idle,
              cooldownUntil: clock.now().add(_runtime.timing.errorCooldown),
            ),
      );
      return;
    }
    if (!_runtime.isCurrent(id, operation)) return;
    _runtime.setState(
      id,
      _runtime
          .stateOf(id)
          .copyWith(
            phase: AutopilotPhase.idle,
            cooldownUntil: clock.now().add(_runtime.timing.minJudgeInterval),
          ),
    );
    unawaited(
      _runtime.notify(
        id,
        '${cli.label} 작업을 자동으로 이어갑니다 #${current.resumeAttempt}',
        verdict.reason,
      ),
    );
  }

  bool _stillResuming(
    String id,
    SessionPort port,
    Object identity,
    Object operation,
  ) {
    if (!_runtime.isCurrent(id, operation)) return false;
    final current = _runtime.stateAt(id);
    if (current == null ||
        !current.enabled ||
        current.phase != AutopilotPhase.resuming) {
      return false;
    }
    final reason = !_runtime.sameConnection(port, identity)
        ? '세션 연결이 바뀜'
        : _gate.check(id, current, requireQuiet: false) ??
              (const AgentAttentionClassifier(
                    requireAgent: false,
                  ).inspect(port.readScreen(maxLines: 60)).needsInput
                  ? '화면에 승인·입력 대기 문구'
                  : null);
    if (reason != null) {
      _runtime.record(id, '재개 중단: $reason');
      _runtime.setState(id, current.copyWith(phase: AutopilotPhase.idle));
      return false;
    }
    return true;
  }

  /// 재실행 뒤 Agent 입력창이 뜰 때까지 기다린다.
  Future<bool> _waitForTui(
    String id,
    SessionPort port,
    Object identity,
    Object operation,
  ) async {
    final deadline = clock.now().add(_runtime.timing.tuiReadyTimeout);
    while (clock.now().isBefore(deadline)) {
      await _runtime.sleep(_runtime.timing.tuiReadyPoll);
      if (!_stillResuming(id, port, identity, operation)) return false;
      final screen = port.readScreen(maxLines: 40);
      if (_tuiReady(screen)) return true;
    }
    return false;
  }

  /// 셸 프롬프트가 아니고 Agent 화면이 보이면 입력창이 준비된 것으로 본다.
  /// `command not found: opencode`처럼 실패 메시지에 제품명이 남는 경우가
  /// 있어 셸 프롬프트 검사를 먼저 한다.
  static bool _tuiReady(String screen) {
    if (screen.trim().isEmpty) return false;
    if (ResumeJudge.endsWithShellPrompt(screen)) return false;
    final inspection = AgentSessionInspector.inspect(screen);
    return inspection.isPossibleAgent &&
        !QuiescenceDetector.hasWorkingIndicator(screen);
  }

  /// 세션 작업공간의 Agent 고유 세션 id(재실행 때 이어 붙일 대화). 모르면 null.
  Future<String?> _nativeSessionIdFor(String id) async {
    final workspaceId = workspaceIdOf(id);
    if (workspaceId == null) return null;
    try {
      final record = await findWorktree(workspaceId);
      return record?.nativeSessionId;
    } catch (_) {
      return null;
    }
  }
}
