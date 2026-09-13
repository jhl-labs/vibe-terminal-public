import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 앱에서 발생한 처리되지 않은 오류 한 건.
class AppErrorRecord {
  const AppErrorRecord({
    required this.timestamp,
    required this.source,
    required this.error,
    this.stackTrace,
    this.context,
  });

  final DateTime timestamp;

  /// 오류가 잡힌 경로. `flutter`, `platform`, `zone`, 또는 호출부가 준 이름.
  final String source;
  final String error;
  final String? stackTrace;

  /// 어떤 작업 중이었는지에 대한 짧은 설명(선택).
  final String? context;

  String format() {
    final buffer = StringBuffer()
      ..write('[${timestamp.toUtc().toIso8601String()}] ')
      ..write('($source) ');
    if (context != null && context!.isNotEmpty) {
      buffer.write('$context: ');
    }
    buffer.writeln(error);
    final trace = stackTrace;
    if (trace != null && trace.isNotEmpty) {
      buffer.writeln(trace.trimRight());
    }
    return buffer.toString();
  }
}

/// 처리되지 않은 오류를 한 곳으로 모은다.
///
/// 이 앱은 외부 크래시 리포팅 SDK를 쓰지 않는다(사용자 터미널 내용이 오류
/// 메시지에 섞여 나갈 수 있어 기본값으로 두기에 적절하지 않다). 대신 모든
/// 오류가 이 지점을 지나가도록 만들어서, 나중에 Crashlytics/Sentry를 붙일
/// 때 [addSink] 한 줄로 끝나게 한다.
///
/// 세 가지를 한다.
/// 1. 메모리에 최근 [maxRecords]건을 유지해 앱 안에서 바로 볼 수 있게 한다.
/// 2. 앱 지원 디렉터리의 `crash.log`에 덧붙여 다음 실행에서도 남아 있게 한다.
/// 3. 등록된 sink로 흘려보낸다.
class AppErrorReporter {
  AppErrorReporter({
    @visibleForTesting Future<File> Function()? logFileFactory,
    @visibleForTesting DateTime Function()? now,
  }) : _logFileFactory = logFileFactory ?? _defaultLogFile,
       _now = now ?? DateTime.now;

  static const maxRecords = 100;

  /// 파일이 이보다 커지면 새로 시작한다. 진단용이지 감사 로그가 아니다.
  static const maxLogFileBytes = 256 * 1024;

  final Future<File> Function() _logFileFactory;
  final DateTime Function() _now;
  final Queue<AppErrorRecord> _records = Queue<AppErrorRecord>();
  final List<void Function(AppErrorRecord)> _sinks = [];

  /// 디스크 쓰기를 한 줄로 세운다. [report]는 동기 메서드라 여러 곳에서 동시에
  /// 불릴 수 있는데, 각자 append를 열면 기록이 서로 섞여 들어간다.
  Future<void> _writeChain = Future<void>.value();

  /// 최근 오류(새 것이 앞).
  List<AppErrorRecord> get records => _records.toList(growable: false);

  /// 외부 리포터를 붙인다. 반환값을 호출하면 해제된다.
  VoidCallback addSink(void Function(AppErrorRecord) sink) {
    _sinks.add(sink);
    return () => _sinks.remove(sink);
  }

  /// 오류 한 건을 기록한다. 이 메서드는 절대 throw 하지 않는다 — 오류 처리
  /// 경로에서 다시 던지면 원래 오류를 덮어써 버린다.
  void report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    String? context,
  }) {
    final record = AppErrorRecord(
      timestamp: _now(),
      source: source,
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      context: context,
    );

    _records.addFirst(record);
    while (_records.length > maxRecords) {
      _records.removeLast();
    }

    if (kDebugMode) {
      debugPrint(record.format());
    }

    for (final sink in List.of(_sinks)) {
      try {
        sink(record);
      } catch (_) {
        // sink 하나가 실패해도 나머지 기록은 계속돼야 한다.
      }
    }

    _writeChain = _writeChain.then((_) => _appendToFile(record));
  }

  /// 예약된 디스크 쓰기가 끝날 때까지 기다린다. 종료 직전이나 테스트에서
  /// 로그 파일이 완성됐음을 보장해야 할 때 쓴다.
  Future<void> flush() => _writeChain;

  Future<void> _appendToFile(AppErrorRecord record) async {
    try {
      final file = await _logFileFactory();
      await file.parent.create(recursive: true);
      if (await file.exists() && await file.length() > maxLogFileBytes) {
        await file.writeAsString('');
      }
      await file.writeAsString(record.format(), mode: FileMode.append);
    } catch (_) {
      // 디스크에 못 써도 메모리 기록과 sink는 이미 처리됐다.
    }
  }

  /// 디스크에 쌓인 오류 로그를 읽는다. 없으면 빈 문자열.
  Future<String> readPersistedLog() async {
    try {
      final file = await _logFileFactory();
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  Future<void> clearPersistedLog() async {
    try {
      final file = await _logFileFactory();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 지우지 못해도 기능적으로 문제되지 않는다.
    }
    _records.clear();
  }

  static Future<File> _defaultLogFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'crash.log'));
  }
}

/// 앱 전역 리포터. [installGlobalErrorHandling]이 여기에 연결된다.
final AppErrorReporter appErrorReporter = AppErrorReporter();

/// Flutter/플랫폼/Zone 세 경로의 미처리 오류를 [reporter]로 모으고 [body]를
/// 실행한다.
///
/// 세 경로를 모두 잡아야 한다. `FlutterError.onError`는 위젯 빌드·레이아웃
/// 오류만, `PlatformDispatcher.onError`는 엔진이 올려주는 비동기 오류만,
/// `runZonedGuarded`는 그 밖의 Dart 비동기 오류만 각각 담당한다.
/// [body]는 `WidgetsFlutterBinding.ensureInitialized()`와 `runApp`을 모두
/// 포함해야 한다. 바인딩을 zone 밖에서 초기화하면 이후 비동기 오류가 이
/// zone으로 오지 않는다.
void installGlobalErrorHandling(
  FutureOr<void> Function() body, {
  AppErrorReporter? reporter,
}) {
  final target = reporter ?? appErrorReporter;

  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    target.report(
      details.exception,
      details.stack,
      source: 'flutter',
      context: details.context?.toDescription(),
    );
    previousFlutterOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    target.report(error, stack, source: 'platform');
    return true; // 처리했음을 알려 엔진이 프로세스를 죽이지 않게 한다.
  };

  runZonedGuarded(
    body,
    (error, stack) => target.report(error, stack, source: 'zone'),
  );
}
