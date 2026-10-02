import 'dart:async';

import '../app/error_reporter.dart';
import 'telemetry.dart';

/// 데스크톱·공개판·플래그 off. 아무것도 보내지 않는다.
class NoopTelemetry implements Telemetry {
  const NoopTelemetry();

  @override
  Future<void> initialize(TelemetrySettings settings) async {}
  @override
  Future<void> applySettings(TelemetrySettings settings) async {}
  @override
  void recordError(AppErrorRecord record) {}
  @override
  void setKey(String key, Object value) {}
  @override
  void logEvent(TelemetryEvent event) {}
  @override
  Stream<TelemetryMessage> get messages => const Stream.empty();
  @override
  set onAnnouncementsDenied(void Function()? callback) {}
}
