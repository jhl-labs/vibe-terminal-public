import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../session/session_attention.dart';

/// 분할 칸 테두리에 반영할 세션 활동 상태.
///
/// 세션 레일의 스피너·Agent 상태 아이콘과 같은 정보를 칸 테두리로 옮긴 것이다.
/// 4분할처럼 여러 칸이 보일 때 어느 칸이 돌고 있고 어느 칸이 입력을 기다리는지
/// 레일을 보지 않고도 알 수 있게 한다.
enum PaneActivity {
  idle,

  /// 출력이 이어지고 있거나 Agent가 작업 중이다. 테두리가 맥동한다.
  working,

  /// Agent 작업이 끝났지만 아직 확인하지 않았다.
  done,

  /// Agent가 사용자 입력을 기다린다.
  blocked,
}

/// 터미널 활동(busy)과 Agent 주의 상태를 칸 테두리 상태 하나로 합친다.
///
/// 레일의 규칙과 같다: Agent 상태가 있으면 그것을, 없으면 busy 여부를 따른다.
PaneActivity paneActivityFor({
  required bool busy,
  SessionAttentionState? attention,
}) => switch (attention) {
  SessionAttentionState.blocked => PaneActivity.blocked,
  SessionAttentionState.done => PaneActivity.done,
  SessionAttentionState.working => PaneActivity.working,
  SessionAttentionState.idle ||
  null => busy ? PaneActivity.working : PaneActivity.idle,
};

/// 분할 칸의 테두리. 포커스 링과 활동 상태를 함께 그린다.
///
/// - 작업 중: 강조색이 맥동한다(포커스된 칸은 포커스색↔강조색).
/// - 입력 필요: 포커스와 무관하게 붉은 실선.
/// - 완료·미확인: 강조색 실선(포커스된 칸은 포커스색 유지).
/// - 대기: 포커스된 칸만 포커스색, 나머지는 투명.
///
/// 애니메이션 비활성(접근성) 환경에서는 맥동 대신 강조색 실선을 쓴다.
class PaneActivityFrame extends StatefulWidget {
  const PaneActivityFrame({
    super.key,
    required this.focused,
    required this.activity,
    required this.child,
  });

  final bool focused;
  final PaneActivity activity;
  final Widget child;

  /// 테두리 두께. 자식은 이만큼 안쪽으로 들어간다.
  static const double width = 2;

  /// 맥동 한 주기(밝아졌다 어두워지는 왕복)의 절반.
  static const pulsePeriod = Duration(milliseconds: 700);

  /// 포커스 링 색(Colors.tealAccent와 같은 값). 보간 결과와 비교할 수 있게 평범한
  /// Color로 둔다.
  static const focusColor = Color(0xFF64FFDA);

  @override
  State<PaneActivityFrame> createState() => _PaneActivityFrameState();
}

class _PaneActivityFrameState extends State<PaneActivityFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: PaneActivityFrame.pulsePeriod,
  );

  bool get _shouldPulse =>
      widget.activity == PaneActivity.working &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(PaneActivityFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) _syncPulse();
  }

  void _syncPulse() {
    if (_shouldPulse) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color _color(double t) {
    final focus = widget.focused ? PaneActivityFrame.focusColor : null;
    switch (widget.activity) {
      case PaneActivity.blocked:
        return VibeColors.statusError;
      case PaneActivity.done:
        return focus ?? VibeColors.accent.withValues(alpha: 0.8);
      case PaneActivity.working:
        if (!_shouldPulse) return focus ?? VibeColors.accent;
        final dim = focus ?? VibeColors.accent.withValues(alpha: 0.12);
        return Color.lerp(
          dim,
          VibeColors.accent,
          Curves.easeInOut.transform(t),
        )!;
      case PaneActivity.idle:
        return focus ?? Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      child: Padding(
        padding: const EdgeInsets.all(PaneActivityFrame.width),
        child: widget.child,
      ),
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: _color(_pulse.value),
            width: PaneActivityFrame.width,
          ),
        ),
        child: child,
      ),
    );
  }
}
