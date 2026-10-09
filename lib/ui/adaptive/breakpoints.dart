import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

/// 적응형 분기 임계값. 600dp 미만이면 compact(모바일) 레이아웃.
const double kCompactBreakpoint = 600.0;

bool isCompactWidth(double width) => width < kCompactBreakpoint;

/// Touch keyboard controls are required on tablets as well as narrow phones.
bool get usesSoftKeyboard =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

extension AdaptiveContext on BuildContext {
  bool get isCompact => isCompactWidth(MediaQuery.sizeOf(this).width);
}
