import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'error_reporter.dart';

/// 직전 실행이 왜 끝났는지를 앱 시작 때 `crash.log`에 남긴다.
///
/// Dart 예외는 [installGlobalErrorHandling]이 잡지만, 네이티브 예외·ANR·메모리
/// 부족(LMK)·시스템 종료는 Dart 코드가 실행될 틈 없이 프로세스가 사라져 아무
/// 기록도 남지 않는다. Android 11+는 그 이유를 `ApplicationExitInfo`로 보관하므로
/// 다음 실행 때 읽어 남기면, adb 없이 사용자 기기에서도 원인을 볼 수 있다.
///
/// 같은 종료를 매 실행마다 다시 적지 않도록 마지막으로 기록한 시각을 파일에 둔다.
class ProcessExitRecorder {
  ProcessExitRecorder({
    MethodChannel? channel,
    AppErrorReporter? reporter,
    @visibleForTesting Future<File> Function()? stateFileFactory,
    bool? enabled,
  }) : _channel = channel ?? const MethodChannel('vibe_terminal/app'),
       _reporter = reporter ?? appErrorReporter,
       _stateFileFactory = stateFileFactory ?? _defaultStateFile,
       _enabled = enabled ?? (!kIsWeb && Platform.isAndroid);

  final MethodChannel _channel;
  final AppErrorReporter _reporter;
  final Future<File> Function() _stateFileFactory;
  final bool _enabled;

  /// 정상 종료로 보아 기록하지 않는 사유. 사용자가 직접 끝냈거나 앱이 스스로 끝낸 것.
  static const _quietReasons = {'EXIT_SELF', 'USER_REQUESTED', 'USER_STOPPED'};

  /// 절대 throw 하지 않는다. 진단 기능이 앱 시작을 막으면 안 된다.
  Future<void> recordSinceLastRun() async {
    if (!_enabled) return;
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'getProcessExitReasons',
      );
      if (raw == null || raw.isEmpty) return;
      final lastSeen = await _readLastSeen();
      var newest = lastSeen;
      // 네이티브는 최신 순으로 주므로 오래된 것부터 남겨 로그가 시간순이 되게 한다.
      for (final item in raw.reversed) {
        if (item is! Map) continue;
        final entry = item.cast<Object?, Object?>();
        final timestamp = (entry['timestamp'] as num?)?.toInt() ?? 0;
        if (timestamp <= lastSeen) continue;
        if (timestamp > newest) newest = timestamp;
        final reason = entry['reason']?.toString() ?? 'UNKNOWN';
        if (_quietReasons.contains(reason)) continue;
        _reporter.report(
          formatExit(entry),
          null,
          source: 'exit-info',
          context: '이전 실행 종료 사유',
        );
      }
      if (newest > lastSeen) await _writeLastSeen(newest);
    } on MissingPluginException {
      // 채널 미구현(테스트·다른 플랫폼).
    } catch (_) {
      // 진단 실패는 조용히 넘어간다.
    }
  }

  /// 사람이 읽을 한 줄. 예: `CRASH status=0 pss=210MB rss=340MB
  /// ForegroundServiceDidNotStopInTimeException ...`
  @visibleForTesting
  static String formatExit(Map<Object?, Object?> entry) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      (entry['timestamp'] as num?)?.toInt() ?? 0,
      isUtc: true,
    );
    final pss = ((entry['pss'] as num?)?.toInt() ?? 0) ~/ 1024;
    final rss = ((entry['rss'] as num?)?.toInt() ?? 0) ~/ 1024;
    final description = entry['description']?.toString().trim();
    final buffer = StringBuffer()
      ..write(entry['reason'] ?? 'UNKNOWN')
      ..write(' at ${at.toIso8601String()}')
      ..write(' status=${entry['status'] ?? '?'}')
      ..write(' importance=${entry['importance'] ?? '?'}')
      ..write(' pss=${pss}MB rss=${rss}MB');
    if (description != null && description.isNotEmpty) {
      buffer.write(' :: $description');
    }
    return buffer.toString();
  }

  Future<int> _readLastSeen() async {
    try {
      final file = await _stateFileFactory();
      if (!await file.exists()) return 0;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['lastSeen'] is num) {
        return (decoded['lastSeen'] as num).toInt();
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _writeLastSeen(int timestamp) async {
    try {
      final file = await _stateFileFactory();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'lastSeen': timestamp}));
    } catch (_) {}
  }

  static Future<File> _defaultStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'exit_info_state.json'));
  }
}
