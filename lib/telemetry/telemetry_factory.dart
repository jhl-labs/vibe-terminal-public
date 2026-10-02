import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/build_features.dart';
import 'noop_telemetry.dart';
import 'telemetry.dart';

/// 빌드 플래그와 플랫폼으로 구현을 고른다. 공개판은 이 파일을 no-op 전용으로 교체한다.
Telemetry createTelemetry(BuildFeatures features) {
  if (!features.telemetry) return const NoopTelemetry();
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    return const NoopTelemetry();
  }
  // 공개판(Core)은 원격 텔레메트리를 포함하지 않는다.
  return const NoopTelemetry();
}
