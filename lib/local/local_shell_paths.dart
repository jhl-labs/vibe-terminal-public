import 'dart:io';

import 'package:path/path.dart' as p;

class LocalShellPaths {
  const LocalShellPaths._();

  static String? wslWorkingDirectoryForLaunch(String? value) =>
      _normalizeWslWorkingDirectory(value, keepHome: false);

  static String? wslWorkingDirectoryForState(String? value) =>
      _normalizeWslWorkingDirectory(value, keepHome: true);

  static String? _normalizeWslWorkingDirectory(
    String? value, {
    required bool keepHome,
  }) {
    final cleaned = _clean(value);
    if (cleaned == null) return null;
    if (cleaned == '~') return keepHome ? '~' : null;
    if (cleaned.startsWith('~/')) return p.posix.normalize(cleaned);
    // 복원 데이터에 셸 실행 파일 경로가 작업 디렉터리로 잘못 저장된 경우가
    // 있다. POSIX 절대 경로도 디렉터리로 간주하기 전에 실제 파일이면 버린다.
    if (File(cleaned).existsSync()) return null;
    if (cleaned.startsWith('/')) return p.posix.normalize(cleaned);

    if (_looksLikeWindowsPath(cleaned)) {
      return _windowsDirectoryToWsl(cleaned);
    }
    return null;
  }

  static String? _windowsDirectoryToWsl(String value) {
    final path = _stripQuotes(value);
    if (!p.windows.isAbsolute(path) && !RegExp(r'^[a-zA-Z]:').hasMatch(path)) {
      return null;
    }
    if (!Directory(path).existsSync()) return null;

    final root = p.windows.rootPrefix(path);
    if (!RegExp(r'^[a-zA-Z]:[\\/]*$').hasMatch(root)) return null;
    final drive = root[0].toLowerCase();
    final relative = p.windows.relative(path, from: root);
    final segments = p.windows
        .split(relative)
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    return p.posix.normalize(p.posix.joinAll(['/mnt/$drive', ...segments]));
  }

  static bool _looksLikeWindowsPath(String value) {
    final path = _stripQuotes(value);
    return RegExp(r'^[a-zA-Z]:').hasMatch(path) ||
        path.startsWith(r'\\') ||
        path.contains(r'\');
  }

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return _stripQuotes(cleaned);
  }

  static String _stripQuotes(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) return trimmed;
    final first = trimmed[0];
    final last = trimmed[trimmed.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }
}
