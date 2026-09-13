import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../app/error_reporter.dart';
import '../core/atomic_file.dart';
import 'app_settings.dart';

class AppSettingsStore {
  AppSettingsStore({AppErrorReporter? errorReporter})
    : _errorReporter = errorReporter ?? appErrorReporter;

  final AppErrorReporter _errorReporter;

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}settings.json');
  }

  Future<AppSettings?> load() async {
    try {
      final file = await _settingsFile();
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      return AppSettings.fromJson(decoded);
    } catch (error, stackTrace) {
      // 읽기 실패는 기본 설정으로 계속 진행하되, 조용히 넘기지는 않는다.
      // 손상된 settings.json이 매번 초기화되는 증상을 진단하려면 기록이 필요하다.
      _errorReporter.report(
        error,
        stackTrace,
        source: 'settings',
        context: 'settings.json 읽기 실패, 기본값으로 시작',
      );
      return null;
    }
  }

  /// 설정을 저장한다. 저장에 성공했으면 true.
  ///
  /// 실패해도 throw 하지 않는다(런타임 설정은 이미 적용돼 있다). 대신
  /// 반환값과 오류 리포터로 실패를 드러내, 다음 실행에서 설정이 사라지는
  /// 현상을 추적할 수 있게 한다.
  Future<bool> save(AppSettings settings) async {
    try {
      final file = await _settingsFile();
      // 원자적으로 바꾼다. 저장 중 앱이 종료돼도 설정이 통째로 날아가지 않는다.
      await writeFileAtomically(
        file,
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
      return true;
    } catch (error, stackTrace) {
      _errorReporter.report(
        error,
        stackTrace,
        source: 'settings',
        context: 'settings.json 저장 실패, 변경은 이번 실행에만 적용됨',
      );
      return false;
    }
  }
}
