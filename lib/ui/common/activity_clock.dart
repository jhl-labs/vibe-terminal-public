import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// "작업 중" 표시기(세션 레일 스피너·분할 칸 테두리 맥동)가 함께 쓰는 저속 시계.
///
/// 표시기마다 60fps 애니메이션을 돌리면 출력 중인 세션이 하나만 있어도 앱이 매
/// vsync마다 창 전체 프레임을 만든다. 세션이 많거나 CPU가 약하면 이 비용이 입력
/// 반응을 늦춘다. 표시기는 흐름만 보이면 되므로 초당 [fps]번만 값을 바꾸고,
/// 듣는 쪽이 없으면 타이머를 멈춰 프레임을 요청하지 않는다.
class ActivityClock extends ChangeNotifier implements ValueListenable<double> {
  ActivityClock({
    this.fps = 12,
    this.period = const Duration(milliseconds: 1400),
  });

  final int fps;

  /// [value]가 0에서 1까지 한 바퀴 도는 시간.
  final Duration period;

  Timer? _timer;
  int _ticks = 0;

  int get _ticksPerPeriod =>
      math.max(1, (period.inMilliseconds * fps / 1000).round());

  /// 주기 안의 위치(0 이상 1 미만).
  @override
  double get value => (_ticks % _ticksPerPeriod) / _ticksPerPeriod;

  @visibleForTesting
  bool get isTicking => _timer != null;

  @override
  void addListener(VoidCallback listener) {
    final wasIdle = !hasListeners;
    super.addListener(listener);
    if (wasIdle) {
      _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ fps), (_) {
        _ticks++;
        notifyListeners();
      });
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// 앱 전체가 공유하는 표시기 시계.
final activityClock = ActivityClock();

/// 표시기가 지금 움직여야 하는지. 숨은 탭(TickerMode 꺼짐)이나 접근성의
/// 애니메이션 줄이기 설정에서는 멈춘 모양을 그린다.
bool activityAnimationsEnabled(BuildContext context) =>
    TickerMode.valuesOf(context).enabled &&
    !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

/// [activityClock]으로 도는 작은 원호 스피너.
///
/// `CircularProgressIndicator`는 표시기마다 60fps 티커를 돌리므로, 세션 레일처럼
/// 여러 개가 동시에 보이는 곳에서는 이 위젯을 쓴다.
class ActivitySpinner extends StatelessWidget {
  const ActivitySpinner({
    super.key,
    required this.color,
    this.size = 13,
    this.strokeWidth = 1.8,
  });

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final animate = activityAnimationsEnabled(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: ActivitySpinnerPainter(
          clock: animate ? activityClock : null,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class ActivitySpinnerPainter extends CustomPainter {
  ActivitySpinnerPainter({
    required this.clock,
    required this.color,
    required this.strokeWidth,
  }) : super(repaint: clock);

  /// null이면 멈춘 원호를 그린다.
  final ValueListenable<double>? clock;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final start = (clock?.value ?? 0) * 2 * math.pi - math.pi / 2;
    canvas.drawArc(
      rect,
      start,
      math.pi * 1.5,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(ActivitySpinnerPainter oldDelegate) =>
      oldDelegate.clock != clock ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
