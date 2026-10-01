import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/app_version.dart';
import 'app/error_reporter.dart';
import 'app/process_exit_recorder.dart';
import 'app/telemetry_bootstrap.dart';
import 'state/providers.dart';
import 'telemetry/telemetry.dart';

void main() {
  // 바인딩 초기화와 runApp을 모두 이 안에 둬야 이후 발생하는 비동기 오류가
  // 전역 리포터로 들어온다.
  installGlobalErrorHandling(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // 빌드의 실제 버전을 읽어 UI 표시에 쓴다(좌측 상단/설정/About).
    await loadAppVersion();
    final container = ProviderContainer();
    // 저장된 텔레메트리 설정을 먼저 읽는다. 아직 결정되지 않았으면(첫 실행,
    // 또는 이 키가 없던 버전에서 올라온 설치) 기기 로케일 기준 기본값(EEA 는
    // 사용 통계 끔). 영속화는 AppSettingsController 가 한다.
    final settings = await container.read(appSettingsStoreProvider).load();
    final locale = PlatformDispatcher.instance.locale;
    final stored = settings?.telemetry;
    final telemetrySettings = stored != null && stored.configured
        ? stored
        : TelemetrySettings.defaultsFor(locale);
    // 텔레메트리 초기화 → 이전 기록 재전송 → sink 연결 → 직전 실행 종료 사유
    // (네이티브 크래시·ANR·메모리 부족) 기록. 기다리지 않는다: 원격 텔레메트리
    // 초기화가 첫 화면을 늦추면 안 된다.
    unawaited(
      bootstrapTelemetry(
        telemetry: container.read(telemetryProvider),
        settings: telemetrySettings,
        reporter: appErrorReporter,
        recordExits: ProcessExitRecorder().recordSinceLastRun,
      ),
    );
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const VibeTerminalApp(),
      ),
    );
  });
}
