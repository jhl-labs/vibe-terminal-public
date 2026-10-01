import '../telemetry/telemetry.dart';
import 'error_reporter.dart';

/// 텔레메트리를 켜고 오류 리포터에 연결한다. 순서가 중요하다:
/// 1. initialize (실패해도 앱은 계속 뜬다 — 기록만 남기고 빠진다)
/// 2. 이미 쌓인 기록을 오래된 순으로 한 번 흘려보낸다 (부팅 초기 오류)
/// 3. sink 연결 (이후 기록은 실시간)
/// 4. 직전 실행 종료 사유 기록 — sink 가 연결된 뒤여야 서버로 간다
Future<void> bootstrapTelemetry({
  required Telemetry telemetry,
  required TelemetrySettings settings,
  required AppErrorReporter reporter,
  required Future<void> Function() recordExits,
}) async {
  try {
    await telemetry.initialize(settings);
  } catch (e, stack) {
    reporter.report(e, stack, source: 'telemetry', context: 'initialize');
    return;
  }
  // records 는 새 것이 앞이므로 뒤집어 시간순으로 보낸다.
  for (final record in reporter.records.reversed) {
    telemetry.recordError(record);
  }
  reporter.addSink(telemetry.recordError);
  await recordExits();
}
