import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/app_version.dart';
import 'app/error_reporter.dart';

void main() {
  // 바인딩 초기화와 runApp을 모두 이 안에 둬야 이후 발생하는 비동기 오류가
  // 전역 리포터로 들어온다.
  installGlobalErrorHandling(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // 빌드의 실제 버전을 읽어 UI 표시에 쓴다(좌측 상단/설정/About).
    await loadAppVersion();
    runApp(const ProviderScope(child: VibeTerminalApp()));
  });
}
