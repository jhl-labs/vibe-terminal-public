import 'package:flutter/painting.dart';

import '../../app/bundled_font_licenses.dart';

typedef TextWidthMeasure = double Function(String family, String text);

/// 폰트 패밀리를 이 시스템에서 실제로 그릴 수 있는지 추정한다.
///
/// Flutter는 설치된 폰트 목록을 알려 주지 않고, 없는 패밀리는 조용히 플랫폼
/// 기본 폰트(대개 가변폭)로 대체한다. 그래서 좁은 글자와 넓은 글자의 폭이
/// 같은지(고정폭으로 그려지는지)로 판별한다. 앱에 포함한 폰트는 항상 있다.
class TerminalFontAvailability {
  TerminalFontAvailability({TextWidthMeasure? measure})
    : _measure = measure ?? _measureWithTextPainter;

  final TextWidthMeasure _measure;
  final Map<String, bool> _cache = {};

  static const _narrow = 'iiiiiiiiii';
  static const _wide = 'WWWWWWWWWW';

  bool isAvailable(String family) {
    if (bundledTerminalFontLicenses.containsKey(family)) return true;
    return _cache[family] ??=
        (_measure(family, _narrow) - _measure(family, _wide)).abs() < 0.5;
  }

  static double _measureWithTextPainter(String family, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: family, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// 앱 전체에서 같은 판별 결과를 쓴다(폰트 설치는 실행 중에 거의 바뀌지 않음).
final terminalFontAvailability = TerminalFontAvailability();
