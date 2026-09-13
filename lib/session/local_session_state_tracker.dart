import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/models/host.dart';
import '../local/local_shell_paths.dart';

/// 로컬 셸은 프로세스 자체를 앱 재시작 후 이어 붙일 수 없으므로, 복원에 필요한
/// 최소 상태(현재 셸 종류와 작업 디렉터리)를 사용자의 입력에서 추적한다.
class LocalSessionStateTracker {
  LocalSessionStateTracker(
    Host host, {
    LocalShellType? restoredShellType,
    String? restoredWorkingDirectory,
  }) : _host = host,
       _posixOnly = !host.isLocalShell || !Platform.isWindows,
       // 경로 추적은 _posixOnly가 담당한다. _shell은 복원 시 다시 띄울 셸의
       // 정체성이므로, 플랫폼과 무관하게 호스트가 선언한 셸 종류를 보존한다
       // (비Windows에서 wsl 센티널로 덮으면 PowerShell 세션이 wsl로 저장됨).
       _shell = host.isLocalShell
           ? restoredShellType ?? host.localShellType
           : LocalShellType.wsl,
       _nativeCwd = host.isLocalShell
           ? _clean(restoredWorkingDirectory) ??
                 _clean(host.workingDirectory) ??
                 _homePath()
           : null,
       _posixCwd = _initialPosixCwd(
         host,
         restoredShellType: restoredShellType,
         restoredWorkingDirectory: restoredWorkingDirectory,
       );

  static const Object _notCdCommand = Object();

  final Host _host;
  final bool _posixOnly;
  LocalShellType _shell;
  final _input = StringBuffer();
  final _shellStack = <LocalShellType>[];
  bool _escaping = false;
  bool _csiEscape = false;
  bool _oscEscape = false;
  String? _nativeCwd;
  String _posixCwd;

  LocalShellType get shellType => _shell;

  String? get workingDirectory {
    if (_posixOnly) return _posixCwd;
    return _shell == LocalShellType.wsl ? _posixCwd : _nativeCwd;
  }

  /// 터미널에서 셸로 나가는 입력을 반영한다.
  ///
  /// true를 반환하면 복원 스냅샷에 기록할 상태가 바뀐 것이다.
  bool handleInput(String data) {
    var changed = false;
    for (final rune in data.runes) {
      final char = String.fromCharCode(rune);
      if (_escaping) {
        _consumeEscapeChar(char);
        continue;
      }
      if (char == '\x1b') {
        _escaping = true;
        continue;
      }

      switch (char) {
        case '\r':
        case '\n':
          final command = _input.toString();
          _input.clear();
          changed = _applyCommand(command) || changed;
        case '\x7f':
        case '\b':
          _backspace();
        case '\x03':
          _input.clear();
        default:
          if (char.codeUnitAt(0) < 32) continue;
          _input.write(char);
      }
    }
    return changed;
  }

  bool _applyCommand(String rawCommand) {
    final command = rawCommand.trim();
    if (command.isEmpty) return false;

    final nextShell = _shellTransition(command);
    if (nextShell != null) {
      if (nextShell == _shell) return false;
      _shellStack.add(_shell);
      _shell = nextShell;
      if (nextShell == LocalShellType.wsl) _posixCwd = '~';
      return true;
    }

    if (_isExitCommand(command)) {
      if (_shellStack.isEmpty) return false;
      _shell = _shellStack.removeLast();
      return true;
    }

    final target = _cdTarget(command);
    if (identical(target, _notCdCommand)) return false;

    if (_posixOnly || _shell == LocalShellType.wsl) {
      final next = _resolvePosixDirectory(target as String?);
      if (next == _posixCwd) return false;
      _posixCwd = next;
      return true;
    }

    final next = _resolveNativeDirectory(target as String?);
    if (next == null || next == _nativeCwd) return false;
    _nativeCwd = next;
    return true;
  }

  Object? _cdTarget(String command) {
    final first = _firstCommandSegment(command).trim();
    final lower = first.toLowerCase();
    final prefixes = _posixOnly
        ? const ['cd']
        : Platform.isWindows
        ? const ['set-location', 'chdir', 'cd', 'sl']
        : const ['cd'];

    for (final prefix in prefixes) {
      if (lower == prefix) return null;
      if (lower.startsWith('$prefix ')) {
        var target = first.substring(prefix.length).trim();
        if (!_posixOnly &&
            Platform.isWindows &&
            target.toLowerCase().startsWith('/d ')) {
          target = target.substring(3).trim();
        }
        if (target == '-') return _notCdCommand;
        return _posixOnly || _shell == LocalShellType.wsl
            ? _decodePosixShellWord(target)
            : _stripQuotes(target);
      }
    }
    return _notCdCommand;
  }

  String? _resolveNativeDirectory(String? target) {
    final home = _homePath();
    if (target == null || target.isEmpty || target == '~') {
      return home ?? _nativeCwd;
    }

    var candidate = _stripQuotes(target);
    if (candidate.isEmpty) return home ?? _nativeCwd;
    final base = _nativeCwd ?? home;
    if (base == null) return null;

    final resolved = _isNativeAbsolute(candidate)
        ? _normalizeNative(candidate)
        : _normalizeNative(_joinNative(base, candidate));
    return Directory(resolved).existsSync() ? resolved : null;
  }

  String _resolvePosixDirectory(String? target) {
    if (target == null || target.isEmpty || target == '~') return '~';
    final candidate = _stripQuotes(target);
    if (candidate == '-') return _posixCwd;
    if (candidate.startsWith('/')) return p.posix.normalize(candidate);
    if (candidate.startsWith('~/')) return p.posix.normalize(candidate);
    return p.posix.normalize(p.posix.join(_posixCwd, candidate));
  }

  LocalShellType? _shellTransition(String command) {
    if (!_host.isLocalShell) return null;
    if (!Platform.isWindows) return null;
    final lower = command.trim().toLowerCase();
    return switch (lower) {
      'wsl' || 'wsl.exe' => LocalShellType.wsl,
      'cmd' || 'cmd.exe' => LocalShellType.cmd,
      'powershell' ||
      'powershell.exe' ||
      'pwsh' ||
      'pwsh.exe' => LocalShellType.powershell,
      _ => null,
    };
  }

  void _backspace() {
    final runes = _input.toString().runes.toList();
    if (runes.isEmpty) return;
    runes.removeLast();
    _input
      ..clear()
      ..write(String.fromCharCodes(runes));
  }

  String _firstCommandSegment(String command) {
    String? quote;
    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (quote != null) {
        if (char == quote) quote = null;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == ';') return command.substring(0, i);
      if (char == '&' && i + 1 < command.length && command[i + 1] == '&') {
        return command.substring(0, i);
      }
    }
    return command;
  }

  bool _isExitCommand(String command) {
    final lower = command.trim().toLowerCase();
    return lower == 'exit' || lower == 'logout';
  }

  bool _endsEscapeSequence(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x40 && code <= 0x7e;
  }

  void _consumeEscapeChar(String char) {
    if (_oscEscape) {
      if (char == '\x07') _resetEscape();
      return;
    }
    if (!_csiEscape && char == '[') {
      _csiEscape = true;
      return;
    }
    if (!_oscEscape && char == ']') {
      _oscEscape = true;
      return;
    }
    if (_endsEscapeSequence(char)) _resetEscape();
  }

  void _resetEscape() {
    _escaping = false;
    _csiEscape = false;
    _oscEscape = false;
  }

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  static String _initialPosixCwd(
    Host host, {
    required LocalShellType? restoredShellType,
    required String? restoredWorkingDirectory,
  }) {
    if (!host.isLocalShell) {
      return _clean(restoredWorkingDirectory) ??
          _clean(host.workingDirectory) ??
          '~';
    }
    if (!Platform.isWindows) {
      return _clean(restoredWorkingDirectory) ??
          _clean(host.workingDirectory) ??
          '~';
    }
    final shell = restoredShellType ?? host.localShellType;
    if (shell != LocalShellType.wsl) return '~';
    return LocalShellPaths.wslWorkingDirectoryForState(
          restoredWorkingDirectory,
        ) ??
        LocalShellPaths.wslWorkingDirectoryForState(host.workingDirectory) ??
        '~';
  }

  static String? _homePath() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return userProfile;
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) return home;

    final drive = Platform.environment['HOMEDRIVE'];
    final path = Platform.environment['HOMEPATH'];
    if (drive == null || path == null) return null;
    return '$drive$path';
  }

  bool _isNativeAbsolute(String value) {
    if (Platform.isWindows) {
      return p.windows.isAbsolute(value) ||
          RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
    }
    return p.isAbsolute(value);
  }

  String _joinNative(String base, String child) =>
      Platform.isWindows ? p.windows.join(base, child) : p.join(base, child);

  String _normalizeNative(String value) =>
      Platform.isWindows ? p.windows.normalize(value) : p.normalize(value);

  String _stripQuotes(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2) {
      final first = trimmed[0];
      final last = trimmed[trimmed.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  String _decodePosixShellWord(String value) {
    final decoded = StringBuffer();
    String? quote;
    var escaping = false;
    for (final rune in value.trim().runes) {
      final char = String.fromCharCode(rune);
      if (escaping) {
        decoded.write(char);
        escaping = false;
        continue;
      }
      if (quote == "'") {
        if (char == "'") {
          quote = null;
        } else {
          decoded.write(char);
        }
        continue;
      }
      if (quote == '"') {
        if (char == '"') {
          quote = null;
        } else if (char == r'\') {
          escaping = true;
        } else {
          decoded.write(char);
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
      } else if (char == r'\') {
        escaping = true;
      } else {
        decoded.write(char);
      }
    }
    if (escaping) decoded.write(r'\');
    return decoded.toString();
  }
}
