import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 텔레메트리 첫 실행 안내 배너를 한 번만 보여 주기 위한 파일 플래그.
///
/// 설정 화면에 노출하는 값이 아니므로 [AppSettings]에 섞지 않고
/// `update_preferences.dart` 와 같은 방식으로 앱 지원 디렉터리에 빈 파일을 둔다.
/// 읽기·쓰기 모두 실패해도 던지지 않는다. 읽기에 실패하면 이미 본 것으로
/// 간주해 매 실행마다 배너가 반복되는 일을 막는다.
class TelemetryNoticeFlag {
  TelemetryNoticeFlag({@visibleForTesting Future<File> Function()? fileFactory})
    : _fileFactory = fileFactory ?? _defaultFile;

  final Future<File> Function() _fileFactory;

  static Future<File> _defaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'telemetry_notice_shown'));
  }

  Future<bool> isShown() async {
    try {
      return (await _fileFactory()).existsSync();
    } catch (_) {
      return true;
    }
  }

  Future<void> markShown() async {
    try {
      // 빈 파일 하나라 동기 IO 로 충분하다. 위젯 테스트의 fake async 존에서도
      // 즉시 반영된다.
      final file = await _fileFactory();
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('');
    } catch (_) {
      // 저장에 실패하면 다음 실행에서 한 번 더 안내하는 정도의 손해만 있다.
    }
  }
}
