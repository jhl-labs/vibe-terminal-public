import 'package:clock/clock.dart';

import '../../session/session_attention.dart';
import '../agent_attention.dart';
import '../agent_launcher.dart';
import '../quiescence_detector.dart';
import 'approval/approval_prompt_parser.dart';
import 'autopilot_runtime.dart';
import 'autopilot_state.dart';
import 'usage_limit/usage_limit_parser.dart';

/// 자율사용이 지금 개입해도 되는지 판단한다. 상태를 바꾸지 않고 이유만 돌려준다
/// ([recheckWhenTimedGateLifts]의 재확인 예약은 예외).
class AutopilotGate {
  AutopilotGate(
    this._runtime, {
    required this.supportedClis,
    required this.approvalParser,
    required this.approvalCooldownUntil,
  });

  final AutopilotRuntime _runtime;
  final Set<AgentCli> supportedClis;
  final ApprovalPromptParser approvalParser;

  /// 승인 키가 먹히지 않은 세션의 자동 승인 재개 시각(승인 흐름이 기록한다).
  final DateTime? Function(String id) approvalCooldownUntil;

  /// 개입하면 안 되는 이유. null이면 진행해도 된다.
  String? check(
    String id,
    AutopilotState current, {
    required bool requireQuiet,
    bool forApproval = false,
    bool forUsageLimit = false,
  }) {
    final port = _runtime.portOf(id);
    if (port == null || !port.isConnected) return '세션 미연결';
    final cli = _runtime.liveCli(id, current);
    if (cli == null || !supportedClis.contains(cli)) {
      return '지원하지 않는 CLI(${cli?.label ?? '미상'})';
    }
    if (_runtime.observedByAgentChat(id)) {
      return 'Agent Chat이 이 세션을 관찰 중';
    }
    final now = clock.now();
    // 승인은 승인 실패 쿨다운만 따른다(재개 판정 쿨다운과 별개). 한도 대기는
    // 대기 자체가 간격이므로 판정 쿨다운을 보지 않는다.
    final cooldown = forApproval
        ? approvalCooldownUntil(id)
        : forUsageLimit
        ? null
        : current.cooldownUntil;
    if (cooldown != null && now.isBefore(cooldown)) return '쿨다운';
    final lastInput = _runtime.lastUserInputAt(id);
    if (lastInput != null &&
        now.difference(lastInput) < _runtime.timing.userInputGrace) {
      return '사용자가 조작 중';
    }
    // 한도 문구는 입력 대기 패턴에도 걸려 화면 기반 blocked를 만든다. 그래서
    // 한도 대기는 한도 줄을 뺀 화면으로 입력 대기를 다시 본다(해석 못 한 승인
    // 화면도 여기서 막힌다).
    if (forUsageLimit) {
      final screen = port.readScreen(maxLines: 60);
      if (approvalParser.parse(cli, screen) != null) return '승인 대기';
      if (needsInputBesidesUsageLimit(screen)) return '화면에 승인·입력 대기 문구';
    }
    // 승인 프롬프트 자체가 blocked를 만들므로 승인 판단에서는 보지 않는다.
    // 한도 대기는 화면 기반 blocked만 건너뛴다(hook·외부 표시는 그대로 따른다).
    final attention = _runtime.attentionOf(id);
    final ignoreBlocked =
        forApproval ||
        (forUsageLimit && attention?.source == SessionAttentionSource.screen);
    if (!ignoreBlocked && attention?.state == SessionAttentionState.blocked) {
      return '승인·입력 대기(${attention!.source.label})';
    }
    if (requireQuiet) {
      if (_runtime.isBusy(id)) {
        return '출력 진행 중';
      }
      final screen = port.readScreen(maxLines: 60);
      if (QuiescenceDetector.hasWorkingIndicator(screen)) return '작업 중 표시';
      if (!forUsageLimit &&
          const AgentAttentionClassifier().inspect(screen).needsInput) {
        return '화면에 승인·입력 대기 문구';
      }
    }
    return null;
  }

  /// 한도 공지 줄을 뺀 화면이 여전히 승인·입력을 기다리는지(무인 입력 기준).
  static bool needsInputBesidesUsageLimit(String screen) {
    final rest = screen
        .split('\n')
        .where((line) => !UsageLimitParser.isUsageLimitLine(line))
        .join('\n');
    return const AgentAttentionClassifier(
      requireAgent: false,
    ).inspect(rest).needsInput;
  }

  /// 사용자 조작 유예·승인 실패 쿨다운처럼 시간이 지나면 풀리는 게이트가 걸려
  /// 있으면, 풀리는 시각에 승인·한도 확인을 다시 예약한다
  /// ([AutopilotRuntime.scheduleSettledCheck]). 승인 화면·한도 공지는 출력을 더
  /// 내지 않아 idle 전이가 다시 오지 않기 때문이다.
  ///
  /// 세션당 타이머 하나 원칙: 이미 예약된 타이머(한도 대기·백오프 등)는 덮어쓰지
  /// 않는다. 사용자 입력·끄기와 출력 재개가 이 예약을 취소한다. 기록에 붙일
  /// 문구를 돌려준다(예약 안 했으면 빈 문자열).
  String recheckWhenTimedGateLifts(String id, {required bool forApproval}) {
    final now = clock.now();
    DateTime? until;
    final lastInput = _runtime.lastUserInputAt(id);
    if (lastInput != null) {
      until = lastInput.add(_runtime.timing.userInputGrace);
    }
    final cooldown = forApproval ? approvalCooldownUntil(id) : null;
    if (cooldown != null && (until == null || cooldown.isAfter(until))) {
      until = cooldown;
    }
    if (until == null || !until.isAfter(now) || _runtime.hasTimer(id)) {
      return '';
    }
    final delay = until.difference(now);
    _runtime.scheduleSettledCheck(id, delay);
    return ' (${delay.inSeconds}s 뒤 다시 확인)';
  }
}
