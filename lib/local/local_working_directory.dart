import 'dart:async';
import 'dart:io';

/// 로컬 셸 프로세스의 실제 작업 디렉터리를 OS에서 읽는다.
///
/// 키 입력에서 `cd`를 추정하는 [LocalSessionStateTracker]는 자동완성·히스토리·
/// 커서 이동이 섞이면 경로를 잃는다. 복제처럼 정확한 현재 위치가 필요한
/// 순간에는 프로세스 테이블이 유일한 진실이므로 이쪽을 먼저 본다.
///
/// Linux는 `/proc/<pid>/cwd`, macOS는 `lsof`를 쓴다. Windows는 외부 프로세스의
/// cwd를 안전하게 읽을 표준 방법이 없어 null을 돌려주고 추적기에 맡긴다.
Future<String?> readLocalWorkingDirectory(
  int pid, {
  Future<ProcessResult> Function(String executable, List<String> arguments)?
  run,
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (pid <= 0) return null;
  try {
    if (Platform.isLinux) {
      final target = await Link('/proc/$pid/cwd').target().timeout(timeout);
      return _validDirectory(target);
    }
    if (Platform.isMacOS) {
      final result = await (run ?? Process.run)('lsof', [
        '-a',
        '-p',
        '$pid',
        '-d',
        'cwd',
        '-Fn',
      ]).timeout(timeout);
      if (result.exitCode != 0 || result.stdout is! String) return null;
      for (final line in (result.stdout as String).split('\n')) {
        if (line.startsWith('n')) return _validDirectory(line.substring(1));
      }
      return null;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _validDirectory(String path) {
  final cleaned = path.trim();
  if (!cleaned.startsWith('/') ||
      cleaned.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return null;
  }
  // 삭제된 디렉터리는 `(deleted)` 접미사가 붙거나 존재하지 않는다. 그런 경로로
  // 새 셸을 띄우면 시작 자체가 실패하므로 추적기 값에 맡긴다.
  if (!Directory(cleaned).existsSync()) return null;
  return cleaned;
}
