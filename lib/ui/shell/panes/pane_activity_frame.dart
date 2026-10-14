import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../session/session_attention.dart';
import '../../common/activity_clock.dart';

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
/// 애니메이션 비활성(접근성) 환경이나 숨은 칸에서는 맥동 대신 강조색 실선을 쓴다.
/// 맥동은 [activityClock]을 따라 초당 몇 번만 갱신한다.
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

  /// 테두리를 그리는 [CustomPaint]. 테스트에서 현재 색을 읽을 때 쓴다.
  static const borderKey = ValueKey('pane-activity-border');

  /// 포커스 링 색(Colors.tealAccent와 같은 값). 보간 결과와 비교할 수 있게 평범한
  /// Color로 둔다.
  static const focusColor = Color(0xFF64FFDA);

  @override
  State<PaneActivityFrame> createState() => _PaneActivityFrameState();
}

class _PaneActivityFrameState extends State<PaneActivityFrame> {
  @override
  Widget build(BuildContext context) {
    final pulse =
        widget.activity == PaneActivity.working &&
        activityAnimationsEnabled(context);
    // 테두리만 자기 레이어에서 다시 그린다. 칸 헤더와 터미널은 맥동 때문에
    // 다시 빌드·페인트되지 않는다.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Padding(
          padding: const EdgeInsets.all(PaneActivityFrame.width),
          child: widget.child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                key: PaneActivityFrame.borderKey,
                painter: PaneBorderPainter(
                  activity: widget.activity,
                  focused: widget.focused,
                  clock: pulse ? activityClock : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [PaneActivityFrame]의 테두리. 맥동은 [clock] 값을 따른다.
class PaneBorderPainter extends CustomPainter {
  PaneBorderPainter({
    required this.activity,
    required this.focused,
    required this.clock,
  }) : super(repaint: clock);

  final PaneActivity activity;
  final bool focused;

  /// null이면 맥동하지 않는다.
  final ValueListenable<double>? clock;

  /// 지금 그릴 테두리 색.
  Color get color {
    final focus = focused ? PaneActivityFrame.focusColor : null;
    switch (activity) {
      case PaneActivity.blocked:
        return VibeColors.statusError;
      case PaneActivity.done:
        return focus ?? VibeColors.accent.withValues(alpha: 0.8);
      case PaneActivity.working:
        final clock = this.clock;
        if (clock == null) return focus ?? VibeColors.accent;
        // 한 주기 동안 어두움 → 밝음 → 어두움으로 왕복한다.
        final phase = clock.value;
        final t = phase < .5 ? phase * 2 : (1 - phase) * 2;
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
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color.a == 0) return;
    const inset = PaneActivityFrame.width / 2;
    canvas.drawRect(
      (Offset.zero & size).deflate(inset),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = PaneActivityFrame.width,
    );
  }

  @override
  bool shouldRepaint(PaneBorderPainter oldDelegate) =>
      oldDelegate.activity != activity ||
      oldDelegate.focused != focused ||
      oldDelegate.clock != clock;
}
