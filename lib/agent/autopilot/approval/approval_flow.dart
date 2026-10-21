import 'dart:async';

import 'package:clock/clock.dart';

import '../../session_port.dart';
import '../autopilot_gate.dart';
import '../autopilot_runtime.dart';
import '../autopilot_state.dart';
import 'approval_policy.dart';
import 'approval_prompt.dart';
import 'approval_prompt_parser.dart';

/// 권한 요청 자동 승인 흐름과 세션별 승인 실패 기억.
///
/// 안전한 요청에만 "이번만 Yes" 키를 한 번 보내고, 먹히지 않으면 쿨다운 뒤 한 번만
/// 다시 시도한 다음 사람에게 넘긴다. 타이머·작업 토큰·주입 표시는
/// [AutopilotRuntime]이 맡는다.
class ApprovalFlow {
  ApprovalFlow(
    this._runtime,
    this._gate, {
    required this.parser,
    required this.policy,
  });

  final AutopilotRuntime _runtime;
  final AutopilotGate _gate;
  final ApprovalPromptParser parser;
  final ApprovalPolicy policy;

  /// 세션별로 마지막으로 사람에게 알린 승인 프롬프트 fingerprint(중복 알림 방지).
  final Map<String, String> _notifiedApproval = {};

  /// 승인 키가 먹히지 않은 세션의 자동 승인 재개 시각. 재개 판정 쿨다운
  /// ([AutopilotState.cooldownUntil])과 분리해, 판정 쿨다운이 새 승인 프롬프트를
  /// 막지 않게 한다.
  final Map<String, DateTime> _approvalCooldownUntil = {};

  /// 승인 키가 한 번 먹히지 않은 프롬프트 fingerprint. 쿨다운 뒤 한 번만 다시 시도한다.
  final Map<String, String> _approvalFailedOnce = {};

  /// 다시 시도해도 먹히지 않아 사람에게 넘긴 프롬프트 fingerprint. 이 프롬프트에는
  /// 더는 키를 보내지 않는다(연타 금지).
  final Map<String, String> _approvalGaveUp = {};

  static const _approvalRepeatedFailure = ApprovalDecision.notify(
    '자동 승인 키가 먹히지 않음',
  );

  /// 승인 실패 쿨다운이 끝나는 시각([AutopilotGate]가 본다).
  DateTime? cooldownUntil(String id) => _approvalCooldownUntil[id];

  ApprovalPrompt? read(String id, AutopilotState current, SessionPort port) {
    final cli = _runtime.liveCli(id, current);
    if (cli == null) return null;
    return parser.parse(cli, port.readScreen(maxLines: 60));
  }

  /// 해석한 권한 요청 하나를 처리한다. 위험·알림만이면 사람에게 알리고, 아니면
  /// 보내기 직전 화면을 다시 읽어 같은 프롬프트일 때만 "이번만 Yes" 키를 한 번
  /// 보낸 뒤 [AutopilotTiming.approvalVerify] 뒤 사라졌는지 확인한다.
  void handle(
    String id,
    AutopilotState current,
    SessionPort port,
    ApprovalPrompt prompt,
  ) {
    final timing = _runtime.timing;
    final blocked = _gate.check(
      id,
      current,
      requireQuiet: false,
      forApproval: true,
    );
    if (blocked != null) {
      final recheck = _gate.recheckWhenTimedGateLifts(id, forApproval: true);
      _runtime.record(id, '승인 판단 생략: $blocked$recheck');
      return;
    }
    if (_approvalGaveUp[id] == prompt.fingerprint) {
      _hold(id, current, prompt, _approvalRepeatedFailure);
      return;
    }
    final decision = policy.decide(prompt);
    if (!decision.allow || current.notifyOnly) {
      _hold(id, current, prompt, decision);
      return;
    }
    if (current.approvalCount + 1 > timing.maxApprovals) {
      _runtime.setState(id, current.copyWith(phase: AutopilotPhase.exhausted));
      _runtime.record(id, '자동 승인 한도(${timing.maxApprovals}회) 도달');
      unawaited(_runtime.notify(id, '자동 승인 한도 도달', prompt.subject));
      return;
    }
    // 보내기 직전 같은 프롬프트인지 다시 확인한다.
    if (read(id, current, port)?.fingerprint != prompt.fingerprint) {
      _runtime.record(id, '승인 취소: 프롬프트가 바뀜');
      return;
    }
    clearNotice(id);
    final identity = port.connectionIdentity;
    final operation = _runtime.beginOperation(id);
    _runtime.setState(id, current.copyWith(phase: AutopilotPhase.approving));
    final answer = prompt.answer;
    _runtime.inject(id, () {
      final text = answer.text;
      if (text != null) {
        port.sendText(text);
      } else {
        port.submit();
      }
    });
    _runtime.record(id, '자동 승인: ${prompt.subject} ($answer)');
    _runtime.schedule(
      id,
      timing.approvalVerify,
      () => _verify(id, port, identity, operation, prompt),
    );
  }

  void _hold(
    String id,
    AutopilotState current,
    ApprovalPrompt prompt,
    ApprovalDecision decision,
  ) {
    if (_notifiedApproval[id] == prompt.fingerprint) return;
    _notifiedApproval[id] = prompt.fingerprint;
    final title = decision.allow ? '승인 대기 (알림만)' : '승인 필요';
    final reason = decision.allow ? '알림만 모드' : decision.reason;
    _runtime.record(id, '승인 보류: $reason — ${prompt.subject}');
    _runtime.setState(
      id,
      current.copyWith(lastAction: '$title: ${prompt.subject}'),
    );
    if (!decision.allow) {
      _runtime.raiseBlock(
        id,
        message: '${decision.reason}: ${prompt.subject}',
        agentHint: current.cli?.name ?? 'agent',
      );
    }
    unawaited(_runtime.notify(id, title, '$reason\n${prompt.subject}'));
  }

  void _verify(
    String id,
    SessionPort port,
    Object identity,
    Object operation,
    ApprovalPrompt prompt,
  ) {
    final timing = _runtime.timing;
    if (!_runtime.isCurrent(id, operation)) return;
    final after = _runtime.stateAt(id);
    if (after == null || after.phase != AutopilotPhase.approving) return;
    if (!_runtime.sameConnection(port, identity)) {
      _runtime.record(id, '승인 확인 취소: 세션 연결이 바뀜');
      _runtime.setState(id, after.copyWith(phase: AutopilotPhase.idle));
      return;
    }
    final still = read(id, after, port);
    if (still?.fingerprint == prompt.fingerprint) {
      // 키 매핑·버전 차이로 먹히지 않았다. 연타하지 않고 쉰다.
      final until = clock.now().add(timing.approvalFailureCooldown);
      _approvalCooldownUntil[id] = until;
      final failed = after.copyWith(
        phase: AutopilotPhase.idle,
        cooldownUntil: until,
        lastAction: '자동 승인 실패: ${prompt.subject}',
      );
      _runtime.setState(id, failed);
      if (_approvalFailedOnce[id] == prompt.fingerprint) {
        // 쿨다운 뒤 다시 보내도 먹히지 않았다. 이 프롬프트는 사람에게 넘긴다.
        _runtime.record(id, '승인 실패(재시도): 프롬프트가 그대로 남음 → 사람에게 넘김');
        _approvalGaveUp[id] = prompt.fingerprint;
        _hold(id, failed, prompt, _approvalRepeatedFailure);
        return;
      }
      _approvalFailedOnce[id] = prompt.fingerprint;
      // 승인 화면은 출력을 더 내지 않으므로 쿨다운이 끝나면 직접 다시 본다.
      final recheck = _gate.recheckWhenTimedGateLifts(id, forApproval: true);
      _runtime.record(id, '승인 실패: 프롬프트가 그대로 남음$recheck');
      unawaited(_runtime.notify(id, '자동 승인 실패', prompt.subject));
      return;
    }
    _runtime.setState(
      id,
      after.copyWith(
        phase: AutopilotPhase.idle,
        approvalCount: after.approvalCount + 1,
        lastAction: '승인: ${prompt.subject}',
      ),
    );
    // 다음 프롬프트가 곧바로 떠 있을 수 있다(idle 전이가 다시 오지 않는 경우).
    // 출력이 다시 나오면 컨트롤러의 활동 구독이 이 예약을 접는다.
    if (!_runtime.isBusy(id)) {
      _runtime.scheduleSettledCheck(id, timing.approvalSettle);
    }
  }

  /// 사람에게 알렸던 승인 프롬프트가 사라졌으면 그 "확인 필요" 표시를 내린다.
  /// 재개 한도 도달(exhausted)로 올린 표시는 새 프롬프트 제출로만 풀린다.
  void clearNotice(String id) {
    if (_notifiedApproval.remove(id) == null) return;
    if (_runtime.stateAt(id)?.phase == AutopilotPhase.exhausted) return;
    _runtime.clearBlock(id);
  }

  /// 화면에 승인 프롬프트가 없다. 알림 표시와 이 프롬프트의 실패 기록을 지운다
  /// (승인 실패 쿨다운은 유지한다).
  void promptGone(String id) {
    clearNotice(id);
    _approvalFailedOnce.remove(id);
    _approvalGaveUp.remove(id);
  }

  /// 승인 보류 기록만 지운다("확인 필요" 표시는 호출자가 내린다).
  void forgetNotice(String id) => _notifiedApproval.remove(id);

  void forgetFailures(String id) {
    _approvalCooldownUntil.remove(id);
    _approvalFailedOnce.remove(id);
    _approvalGaveUp.remove(id);
  }
}
