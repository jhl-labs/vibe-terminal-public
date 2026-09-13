import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cli_config_home.dart';

/// Finds local CLI executables without running the CLI or inspecting credentials.
class CliInstallationDetector {
  CliInstallationDetector({
    Map<String, String>? environment,
    String? operatingSystem,
    Future<String?> Function()? loginShellPath,
    Future<bool> Function(String, bool)? isExecutable,
  }) : _environment = environment ?? Platform.environment,
       _os = operatingSystem ?? Platform.operatingSystem,
       _loginShellPath = loginShellPath ?? _readLoginShellPath,
       _isExecutable = isExecutable ?? isExecutableFile;

  final Map<String, String> _environment;
  final String _os;
  final Future<String?> Function() _loginShellPath;
  final Future<bool> Function(String, bool) _isExecutable;

  Future<Set<CliConfigApp>> detect() async {
    if (_os != 'macos' && _os != 'linux' && _os != 'windows') return {};
    final windows = _os == 'windows';
    final paths = p.Context(style: windows ? p.Style.windows : p.Style.posix);
    String? env(String key) {
      for (final entry in _environment.entries) {
        if (windows ? entry.key.toUpperCase() == key : entry.key == key) {
          return entry.value;
        }
      }
      return null;
    }

    final home = env(windows ? 'USERPROFILE' : 'HOME');
    final directories = <String>{};
    void addPath(String? value) {
      for (var path in (value ?? '').split(windows ? ';' : ':')) {
        path = path.trim();
        if (path.startsWith('"') && path.endsWith('"') && path.length > 1) {
          path = path.substring(1, path.length - 1);
        }
        // Never treat an empty or relative PATH entry as the app directory.
        if (paths.isAbsolute(path)) directories.add(path);
      }
    }

    addPath(env('PATH'));
    if (home != null) {
      for (final suffix in [
        ['.local', 'bin'],
        ['.opencode', 'bin'],
        ['.bun', 'bin'],
        ['.npm-global', 'bin'],
      ]) {
        addPath(paths.joinAll([home, ...suffix]));
      }
    }
    if (windows) {
      final appData = env('APPDATA');
      final localAppData = env('LOCALAPPDATA');
      if (appData != null) addPath(paths.join(appData, 'npm'));
      if (localAppData != null) {
        addPath(paths.join(localAppData, 'Microsoft', 'WinGet', 'Links'));
      }
    } else {
      addPath('/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin');
      // Finder-launched apps may not inherit the user's login-shell PATH.
      try {
        addPath(await _loginShellPath());
      } on Exception {
        // The inherited PATH and conventional install locations still work.
      }
    }

    final extensions = windows ? ['', '.exe', '.com', '.cmd', '.bat'] : [''];
    final installed = <CliConfigApp>{};
    for (final app in CliConfigApp.values) {
      for (final directory in directories) {
        for (final extension in extensions) {
          if (await _isExecutable(
            paths.join(directory, '${app.name}$extension'),
            windows,
          )) {
            installed.add(app);
            break;
          }
        }
        if (installed.contains(app)) break;
      }
    }
    return Set.unmodifiable(installed);
  }

  static Future<bool> isExecutableFile(String path, bool windows) async {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.file &&
        (windows || stat.mode & 0x49 != 0);
  }

  static Future<String?> _readLoginShellPath() async {
    final shell = Platform.environment['SHELL'];
    if (shell == null || !p.posix.isAbsolute(shell)) return null;
    final process = await Process.start(shell, [
      '-lc',
      r'''printf '\n__VIBE_CLI_PATH__%s\n' "$PATH"''',
    ]);
    final output = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final errors = process.stderr.drain<void>();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 3));
      if (code != 0) return null;
      final text = await output.timeout(const Duration(seconds: 1));
      return RegExp(
        r'^__VIBE_CLI_PATH__(.*)$',
        multiLine: true,
      ).firstMatch(text)?.group(1);
    } on TimeoutException {
      process.kill();
      return null;
    } finally {
      // Drain both pipes even if a startup script fails or times out.
      unawaited(output.then<void>((_) {}, onError: (Object _) {}));
      unawaited(errors);
    }
  }
}
