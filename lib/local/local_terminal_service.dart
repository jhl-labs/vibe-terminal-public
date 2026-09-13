import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;

import '../core/result.dart';
import '../data/models/host.dart';
import '../terminal/terminal_session_handle.dart';
import 'local_shell_paths.dart';

class LocalTerminalService {
  Future<Result<TerminalSessionHandle>> start({
    required Host host,
    required int cols,
    required int rows,
  }) async {
    if (!host.isLocalShell) {
      return const Err(UnknownFailure('로컬 셸 프로필이 아닙니다'));
    }

    try {
      final spec = _resolveShell(host);
      if (!_commandExists(spec.probeExecutable)) {
        return Err(
          LocalShellMissingExecutableFailure(
            shellLabel: host.localShellType.label,
            executable: spec.probeExecutable,
            guidance: _missingShellGuidance(host.localShellType),
          ),
        );
      }
      try {
        final pty = Pty.start(
          spec.executable,
          arguments: spec.arguments,
          workingDirectory: spec.workingDirectory,
          environment: Platform.isWindows ? Platform.environment : null,
          rows: rows,
          columns: cols,
        );
        return Ok(LocalTerminalSessionHandle(pty));
      } on Object catch (e) {
        if (!Platform.isWindows) rethrow;
        final home = _homePath() ?? spec.workingDirectory;
        return Ok(
          _fallbackLineHandle(
            host.localShellType,
            home,
            spec.workingDirectory,
            LocalShellPaths.wslWorkingDirectoryForState(
                  host.workingDirectory,
                ) ??
                '~',
            e,
          ),
        );
      }
    } on Object catch (e) {
      return Err(UnknownFailure('로컬 셸을 시작하지 못했습니다: $e'));
    }
  }

  LocalLineSessionHandle _fallbackLineHandle(
    LocalShellType shell,
    String? home,
    String? workingDirectory,
    String wslWorkingDirectory,
    Object cause,
  ) {
    return LocalLineSessionHandle(
      initialShell: shell,
      executables: {
        LocalShellType.powershell: _windowsExecutable(
          LocalShellType.powershell,
        ),
        LocalShellType.cmd: _windowsExecutable(LocalShellType.cmd),
        LocalShellType.wsl: _windowsExecutable(LocalShellType.wsl),
      },
      homeDirectory: home,
      workingDirectory: workingDirectory ?? home,
      wslHomeDirectory: wslWorkingDirectory,
      startupNotice:
          'PTY 시작 실패로 호환 모드로 전환했습니다. '
          '이 모드에서는 셸 네이티브 자동완성이 제한됩니다: $cause\r\n',
    );
  }

  _LocalShellSpec _resolveShell(Host host) {
    if (!Platform.isWindows) {
      return _LocalShellSpec(
        executable: Platform.environment['SHELL'] ?? 'sh',
        arguments: const [],
        workingDirectory: _cleanDirectory(host.workingDirectory) ?? _homePath(),
      );
    }

    final shell = host.localShellType;
    final workingDirectory = shell == LocalShellType.wsl
        ? LocalShellPaths.wslWorkingDirectoryForLaunch(host.workingDirectory)
        : _cleanDirectory(host.workingDirectory) ?? _homePath();
    return _windowsShellSpec(shell, workingDirectory: workingDirectory);
  }

  _LocalShellSpec _windowsShellSpec(
    LocalShellType shell, {
    required String? workingDirectory,
  }) {
    final executable = _windowsExecutable(shell);
    if (shell == LocalShellType.wsl) {
      final arguments = [
        if (workingDirectory != null) ...['--cd', workingDirectory],
      ];
      return _LocalShellSpec(
        executable: executable,
        arguments: arguments,
        workingDirectory: null,
      );
    }
    return _LocalShellSpec(
      executable: executable,
      arguments: shell.arguments,
      workingDirectory: workingDirectory,
    );
  }

  String _windowsExecutable(LocalShellType shell) {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return switch (shell) {
      LocalShellType.powershell =>
        _powershellExecutable() ??
            '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      LocalShellType.cmd => '$systemRoot\\System32\\cmd.exe',
      LocalShellType.wsl => '$systemRoot\\System32\\wsl.exe',
    };
  }

  String? _powershellExecutable() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final userProfile = Platform.environment['USERPROFILE'];
    final programFiles = Platform.environment['ProgramFiles'];
    final candidates = [
      _findWindowsAppPowerShell(programFiles),
      if (programFiles != null) '$programFiles\\PowerShell\\7\\pwsh.exe',
      if (localAppData != null)
        '$localAppData\\Microsoft\\WindowsApps\\pwsh.exe',
      if (userProfile != null)
        '$userProfile\\AppData\\Local\\Microsoft\\WindowsApps\\pwsh.exe',
      'pwsh.exe',
    ];
    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (_commandExists(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  bool _commandExists(String commandOrPath) {
    if (commandOrPath.isEmpty) return false;
    if (commandOrPath.contains('\\') || commandOrPath.contains('/')) {
      return File(commandOrPath).existsSync();
    }

    final pathValue = Platform.environment['PATH'];
    if (pathValue == null || pathValue.trim().isEmpty) return false;
    final separators = Platform.isWindows ? ';' : ':';
    final hasExtension = p.extension(commandOrPath).isNotEmpty;
    final candidateNames = hasExtension
        ? [commandOrPath]
        : [
            commandOrPath,
            '$commandOrPath.exe',
            '$commandOrPath.cmd',
            '$commandOrPath.bat',
            '$commandOrPath.com',
          ];

    for (final dirPath in pathValue.split(separators)) {
      final trimmed = dirPath.trim();
      if (trimmed.isEmpty) continue;
      final dir = Directory(trimmed);
      if (!dir.existsSync()) continue;
      for (final name in candidateNames) {
        final candidate = File(p.join(trimmed, name));
        if (candidate.existsSync()) return true;
      }
    }
    return false;
  }

  String? _findWindowsAppPowerShell(String? programFiles) {
    if (programFiles == null) return null;
    final appsDir = Directory('$programFiles\\WindowsApps');
    if (!appsDir.existsSync()) return null;
    try {
      final matches =
          appsDir
              .listSync()
              .whereType<Directory>()
              .where(
                (entry) =>
                    entry.uri.pathSegments.last.startsWith(
                      'Microsoft.PowerShell_',
                    ) &&
                    entry.uri.pathSegments.last.contains('_x64__'),
              )
              .map((entry) => File('${entry.path}\\pwsh.exe'))
              .where((file) => file.existsSync())
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      return matches.isEmpty ? null : matches.first.path;
    } on FileSystemException {
      return null;
    }
  }

  String? _cleanDirectory(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  String? _homePath() {
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

  String _missingShellGuidance(LocalShellType shellType) {
    if (!Platform.isWindows) return '시스템 PATH에 기본 로컬 셸이 등록되어 있는지 확인하세요.';
    return switch (shellType) {
      LocalShellType.powershell =>
        'PowerShell 7(pwsh.exe)을 사용하려면 Microsoft Store 또는 설치 관리자에서 PATH 등록까지 함께 확인하세요. '
            '임시로는 로컬 셸 프로필에서 Command Prompt(cmd)를 선택해 실행해도 됩니다.',
      LocalShellType.cmd => 'Windows cmd 실행 파일이 없으면 system 환경 복구가 필요합니다.',
      LocalShellType.wsl => 'WSL이 설치되지 않았거나 구성되지 않았습니다. WSL을 설치한 뒤 다시 시도하세요.',
    };
  }
}

class LocalTerminalSessionHandle implements TerminalSessionHandle {
  LocalTerminalSessionHandle(this._pty);

  final Pty _pty;
  bool _closed = false;

  @override
  Stream<List<int>> get output => _pty.output.cast<List<int>>();

  @override
  void write(List<int> data) => _pty.write(Uint8List.fromList(data));

  @override
  void resize(int cols, int rows) => _pty.resize(rows, cols);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pty.kill();
    try {
      await _pty.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // The OS will reclaim the ConPTY process; do not block app shutdown.
    }
  }
}

class LocalLineSessionHandle implements TerminalSessionHandle {
  LocalLineSessionHandle({
    required LocalShellType initialShell,
    required Map<LocalShellType, String> executables,
    required String? homeDirectory,
    required String? workingDirectory,
    required String wslHomeDirectory,
    String? startupNotice,
  }) : _shell = initialShell,
       _executables = Map.unmodifiable(executables),
       _homeDirectory = homeDirectory,
       _windowsCwd = workingDirectory ?? homeDirectory,
       _wslCwd = wslHomeDirectory {
    if (startupNotice != null) {
      scheduleMicrotask(() => _emit(startupNotice));
    }
    scheduleMicrotask(_writePrompt);
  }

  LocalShellType _shell;
  final Map<LocalShellType, String> _executables;
  final String? _homeDirectory;
  final _output = StreamController<List<int>>();
  final _input = StringBuffer();
  final _shellStack = <LocalShellType>[];
  String? _windowsCwd;
  String _wslCwd;
  Process? _activeProcess;
  bool _running = false;
  bool _closed = false;

  @override
  Stream<List<int>> get output => _output.stream;

  @override
  void write(List<int> data) {
    if (_closed) return;
    final text = utf8.decode(data, allowMalformed: true);
    for (final rune in text.runes) {
      _handleInput(String.fromCharCode(rune));
    }
  }

  @override
  void resize(int cols, int rows) {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _activeProcess?.kill();
    await _output.close();
  }

  void _handleInput(String char) {
    if (_running) {
      if (char == '\x03') {
        _activeProcess?.kill();
        _emit('^C\r\n');
      }
      return;
    }

    switch (char) {
      case '\r':
      case '\n':
        final command = _input.toString();
        _input.clear();
        _emit('\r\n');
        unawaited(_runCommand(command));
      case '\x7f':
      case '\b':
        _backspace();
      case '\t':
        _completeInput();
      case '\x03':
        _input.clear();
        _emit('^C\r\n');
        _writePrompt();
      default:
        if (char.codeUnitAt(0) == 27) return;
        _input.write(char);
        _emit(char);
    }
  }

  void _backspace() {
    final runes = _input.toString().runes.toList();
    if (runes.isEmpty) return;
    runes.removeLast();
    _input
      ..clear()
      ..write(String.fromCharCodes(runes));
    _emit('\b \b');
  }

  void _completeInput() {
    final line = _input.toString();
    final token = _currentToken(line);
    final matches =
        token.commandPosition && _lastSeparatorIndex(token.value) < 0
        ? _commandCompletionMatches(token.value)
        : _pathCompletionMatches(token, line);

    if (matches.isEmpty) {
      _emit('\x07');
      return;
    }

    final common = _commonPrefix(
      matches.map((match) => match.name),
      caseSensitive: !_caseInsensitiveCompletion,
    );
    if (common.length > token.namePrefix.length) {
      final match = matches.length == 1 ? matches.first : null;
      _replaceInputSuffix(
        token.start,
        _formatCompletionToken(
          token,
          '${token.pathPrefix}$common',
          isDirectory: match?.isDirectory ?? false,
          exact: matches.length == 1,
        ),
      );
      return;
    }

    if (matches.length == 1) {
      final match = matches.first;
      _replaceInputSuffix(
        token.start,
        _formatCompletionToken(
          token,
          '${token.pathPrefix}${match.name}',
          isDirectory: match.isDirectory,
          exact: true,
        ),
      );
      return;
    }

    _emit('\r\n${matches.map((match) => match.label).join('  ')}\r\n');
    _writePrompt();
    _emit(_input.toString());
  }

  _CompletionToken _currentToken(String line) {
    var start = 0;
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote != null) {
        if (char == quote) quote = null;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (_isWhitespace(char)) start = i + 1;
    }

    final raw = line.substring(start);
    final commandPosition = line.substring(0, start).trim().isEmpty;
    var tokenQuote = raw.isNotEmpty && (raw[0] == '"' || raw[0] == "'")
        ? raw[0]
        : null;
    var value = tokenQuote == null ? raw : raw.substring(1);
    if (tokenQuote != null && value.endsWith(tokenQuote)) {
      value = value.substring(0, value.length - 1);
    }

    final separatorIndex = _lastSeparatorIndex(value);
    final pathPrefix = separatorIndex < 0
        ? ''
        : value.substring(0, separatorIndex + 1);
    final namePrefix = separatorIndex < 0
        ? value
        : value.substring(separatorIndex + 1);
    return _CompletionToken(
      start: start,
      raw: raw,
      quote: tokenQuote,
      value: value,
      commandPosition: commandPosition,
      pathPrefix: pathPrefix,
      namePrefix: namePrefix,
    );
  }

  List<_CompletionMatch> _pathCompletionMatches(
    _CompletionToken token,
    String line,
  ) {
    if (_shell == LocalShellType.wsl) return const [];
    final directory = _completionDirectory(token.pathPrefix);
    if (directory == null || !directory.existsSync()) return const [];

    final directoriesOnly = _isDirectoryCompletionCommand(_commandName(line));
    final matches = <_CompletionMatch>[];
    try {
      for (final entry in directory.listSync()) {
        if (directoriesOnly && entry is! Directory) continue;
        final name = p.basename(entry.path);
        if (!_startsWithCompletion(name, token.namePrefix)) continue;
        matches.add(
          _CompletionMatch(name: name, isDirectory: entry is Directory),
        );
      }
    } on FileSystemException {
      return const [];
    }
    matches.sort(_compareCompletionMatch);
    return matches;
  }

  List<_CompletionMatch> _commandCompletionMatches(String prefix) {
    if (prefix.trim().isEmpty) return const [];
    final names = <String>{
      'cd',
      'chdir',
      'clear',
      'cls',
      'cmd',
      'exit',
      'logout',
      'powershell',
      'pwsh',
      'set-location',
      'sl',
      'wsl',
    };

    final pathValue = Platform.environment['PATH'];
    if (pathValue != null) {
      for (final dirPath in pathValue.split(Platform.isWindows ? ';' : ':')) {
        if (dirPath.trim().isEmpty) continue;
        final dir = Directory(dirPath);
        if (!dir.existsSync()) continue;
        try {
          for (final entry in dir.listSync()) {
            if (entry is Directory) continue;
            final basename = p.basename(entry.path);
            names.add(basename);
            final extension = p.extension(basename);
            if (extension.isNotEmpty) {
              names.add(
                basename.substring(0, basename.length - extension.length),
              );
            }
          }
        } on FileSystemException {
          continue;
        }
      }
    }

    final matches =
        names
            .where((name) => _startsWithCompletion(name, prefix))
            .map((name) => _CompletionMatch(name: name, isDirectory: false))
            .toList()
          ..sort(_compareCompletionMatch);
    return matches;
  }

  Directory? _completionDirectory(String pathPrefix) {
    final cwd = _windowsCwd ?? _homeDirectory;
    if (cwd == null) return null;
    final expanded = _expandHome(pathPrefix);
    final path = expanded.isEmpty
        ? cwd
        : (p.isAbsolute(expanded) ? expanded : p.join(cwd, expanded));
    return Directory(p.normalize(path));
  }

  String _formatCompletionToken(
    _CompletionToken token,
    String value, {
    required bool isDirectory,
    required bool exact,
  }) {
    final completed = isDirectory
        ? _appendSeparator(value, token.preferredSeparator)
        : value;
    final quote = token.quote ?? (_containsWhitespace(completed) ? '"' : null);
    if (quote != null) {
      if (!exact) return '$quote$completed';
      return isDirectory ? '$quote$completed$quote' : '$quote$completed$quote ';
    }
    return exact && !isDirectory ? '$completed ' : completed;
  }

  void _replaceInputSuffix(int start, String replacement) {
    final line = _input.toString();
    final oldSuffix = line.substring(start);
    for (final _ in oldSuffix.runes) {
      _emit('\b \b');
    }
    _input
      ..clear()
      ..write(line.substring(0, start))
      ..write(replacement);
    _emit(replacement);
  }

  String _commandName(String line) {
    final token = _currentToken(line);
    final beforeToken = line.substring(0, token.start).trimRight();
    if (beforeToken.isEmpty) return token.value;
    return _currentToken(beforeToken).value;
  }

  bool _isDirectoryCompletionCommand(String command) {
    final normalized = command.toLowerCase();
    return normalized == 'cd' ||
        normalized == 'chdir' ||
        normalized == 'set-location' ||
        normalized == 'sl';
  }

  bool _startsWithCompletion(String value, String prefix) {
    if (_caseInsensitiveCompletion) {
      return value.toLowerCase().startsWith(prefix.toLowerCase());
    }
    return value.startsWith(prefix);
  }

  int _compareCompletionMatch(_CompletionMatch a, _CompletionMatch b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  String _commonPrefix(Iterable<String> values, {required bool caseSensitive}) {
    final list = values.toList(growable: false);
    if (list.isEmpty) return '';
    var prefix = list.first;
    for (final value in list.skip(1)) {
      var i = 0;
      while (i < prefix.length && i < value.length) {
        final a = prefix[i];
        final b = value[i];
        if (caseSensitive ? a != b : a.toLowerCase() != b.toLowerCase()) break;
        i++;
      }
      prefix = prefix.substring(0, i);
      if (prefix.isEmpty) break;
    }
    return prefix;
  }

  String _appendSeparator(String value, String separator) {
    if (value.endsWith('/') || value.endsWith(r'\')) return value;
    return '$value$separator';
  }

  String _expandHome(String value) {
    if (value == '~') return _homeDirectory ?? value;
    if (value.startsWith('~/') || value.startsWith(r'~\')) {
      final home = _homeDirectory;
      if (home == null) return value;
      return p.join(home, value.substring(2));
    }
    return value;
  }

  int _lastSeparatorIndex(String value) =>
      value.lastIndexOf('/') > value.lastIndexOf(r'\')
      ? value.lastIndexOf('/')
      : value.lastIndexOf(r'\');

  bool _isWhitespace(String char) => char.trim().isEmpty;

  bool _containsWhitespace(String value) => value.runes.any((rune) {
    final char = String.fromCharCode(rune);
    return char.trim().isEmpty;
  });

  bool get _caseInsensitiveCompletion =>
      Platform.isWindows || _shell != LocalShellType.wsl;

  Future<void> _runCommand(String rawCommand) async {
    final command = rawCommand.trim();
    if (_closed) return;
    if (command.isEmpty) {
      _writePrompt();
      return;
    }
    final nextShell = _shellTransition(command);
    if (nextShell != null) {
      _switchShell(nextShell);
      _writePrompt();
      return;
    }
    if (_isExitCommand(command)) {
      if (_shellStack.isNotEmpty) {
        _shell = _shellStack.removeLast();
        _writePrompt();
        return;
      }
      await close();
      return;
    }
    if (_isClearCommand(command)) {
      _emit('\x1b[2J\x1b[H');
      _writePrompt();
      return;
    }
    if (_isCdCommand(command)) {
      await _changeDirectory(command);
      _writePrompt();
      return;
    }

    _running = true;
    try {
      final invocation = _commandInvocation(command);
      final process = await Process.start(
        invocation.executable,
        invocation.arguments,
        workingDirectory: invocation.workingDirectory,
      );
      _activeProcess = process;
      // 파이프 read 경계는 바이트 단위라 한글 3바이트나 CRLF 중간에서 청크가
      // 갈라질 수 있다. 스트림별로 상태를 유지하는 디코더/정규화기를 둔다.
      final stdoutSink = _ChildOutputSink(_emit);
      final stderrSink = _ChildOutputSink(_emit);
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      final stdoutSub = process.stdout.listen(
        stdoutSink.add,
        onDone: stdoutDone.complete,
        onError: (Object _) => stdoutDone.complete(),
      );
      final stderrSub = process.stderr.listen(
        stderrSink.add,
        onDone: stderrDone.complete,
        onError: (Object _) => stderrDone.complete(),
      );
      await process.exitCode;
      // 종료 직후 파이프에 남은 출력을 마저 받는다. 백그라운드 손자 프로세스가
      // 파이프를 계속 쥐고 있을 수 있으므로 무한정 기다리지는 않는다.
      await Future.wait([stdoutDone.future, stderrDone.future]).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => const [],
      );
      await stdoutSub.cancel();
      await stderrSub.cancel();
      stdoutSink.close();
      stderrSink.close();
    } on Object catch (e) {
      _emit('명령을 실행하지 못했습니다: $e\r\n');
    } finally {
      _activeProcess = null;
      _running = false;
      if (!_closed) _writePrompt();
    }
  }

  _CommandInvocation _commandInvocation(String command) {
    return switch (_shell) {
      LocalShellType.powershell => _CommandInvocation(
        executable: _executableFor(LocalShellType.powershell),
        arguments: [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          _powerShellCommand(command),
        ],
        workingDirectory: _windowsCwd,
      ),
      LocalShellType.cmd => _CommandInvocation(
        executable: _executableFor(LocalShellType.cmd),
        arguments: ['/d', '/s', '/c', 'chcp 65001 >NUL & $command'],
        workingDirectory: _windowsCwd,
      ),
      LocalShellType.wsl => _CommandInvocation(
        executable: _executableFor(LocalShellType.wsl),
        arguments: ['--cd', _wslCwd, '--', 'bash', '-lc', command],
        workingDirectory: _homeDirectory,
      ),
    };
  }

  String _powerShellCommand(String command) =>
      '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); '
      r'$OutputEncoding = [Console]::OutputEncoding; '
      '$command';

  Future<void> _changeDirectory(String command) async {
    final target = _cdTarget(command);
    if (_shell == LocalShellType.wsl) {
      await _changeWslDirectory(target);
      return;
    }

    final next = _resolveWindowsDirectory(target);
    if (next == null) {
      _emit('디렉터리를 찾을 수 없습니다.\r\n');
      return;
    }
    _windowsCwd = next;
  }

  Future<void> _changeWslDirectory(String? target) async {
    final destination = target == null || target.isEmpty ? '~' : target;
    final cdCommand = destination == '~'
        ? 'cd ~ && pwd'
        : 'cd ${_shQuote(destination)} && pwd';
    try {
      final result = await Process.run(
        _executableFor(LocalShellType.wsl),
        ['--cd', _wslCwd, '--', 'bash', '-lc', cdCommand],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        _emit('${err.isEmpty ? '디렉터리를 찾을 수 없습니다.' : err}\r\n');
        return;
      }
      final resolved = const LineSplitter()
          .convert(result.stdout.toString())
          .where((line) => line.trim().isNotEmpty)
          .lastOrNull;
      if (resolved != null) _wslCwd = resolved;
    } on Object catch (e) {
      _emit('디렉터리를 변경하지 못했습니다: $e\r\n');
    }
  }

  String? _resolveWindowsDirectory(String? target) {
    final home = _homeDirectory;
    if (target == null || target.isEmpty || target == '~') return home;
    var candidate = _stripQuotes(target);
    if (candidate.toLowerCase().startsWith('/d ')) {
      candidate = candidate.substring(3).trim();
    }
    final base = _windowsCwd ?? home;
    if (base == null) return null;
    final resolved = p.normalize(
      p.isAbsolute(candidate) ? candidate : p.join(base, candidate),
    );
    return Directory(resolved).existsSync() ? resolved : null;
  }

  String? _cdTarget(String command) {
    final trimmed = command.trim();
    final lower = trimmed.toLowerCase();
    for (final prefix in ['set-location', 'chdir', 'cd', 'sl']) {
      if (lower == prefix) return null;
      if (lower.startsWith('$prefix ')) {
        return _stripQuotes(trimmed.substring(prefix.length).trim());
      }
    }
    return null;
  }

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

  bool _isCdCommand(String command) {
    final lower = command.trim().toLowerCase();
    return lower == 'cd' ||
        lower == 'chdir' ||
        lower == 'sl' ||
        lower == 'set-location' ||
        lower.startsWith('cd ') ||
        lower.startsWith('chdir ') ||
        lower.startsWith('sl ') ||
        lower.startsWith('set-location ');
  }

  bool _isExitCommand(String command) {
    final lower = command.trim().toLowerCase();
    return lower == 'exit' || lower == 'logout';
  }

  bool _isClearCommand(String command) {
    final lower = command.trim().toLowerCase();
    return lower == 'clear' || lower == 'cls';
  }

  void _writePrompt() {
    if (_closed) return;
    _emit(switch (_shell) {
      LocalShellType.powershell => 'PS ${_windowsCwd ?? _homeDirectory}> ',
      LocalShellType.cmd => '${_windowsCwd ?? _homeDirectory}> ',
      LocalShellType.wsl => 'WSL $_wslCwd \$ ',
    });
  }

  /// 이미 정규화된(또는 청크 경계 문제가 없는 단일 문자열) 텍스트를 내보낸다.
  void _emit(String text) {
    if (_output.isClosed) return;
    _output.add(utf8.encode(_normalizeOutput(text)));
  }

  static String _normalizeOutput(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '\r\n');

  String _shQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  LocalShellType? _shellTransition(String command) {
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

  void _switchShell(LocalShellType nextShell) {
    if (nextShell == _shell) return;
    _shellStack.add(_shell);
    _shell = nextShell;
    if (nextShell == LocalShellType.wsl) {
      _wslCwd = '~';
    }
  }

  String _executableFor(LocalShellType shell) => _executables[shell]!;
}

class _CompletionToken {
  const _CompletionToken({
    required this.start,
    required this.raw,
    required this.quote,
    required this.value,
    required this.commandPosition,
    required this.pathPrefix,
    required this.namePrefix,
  });

  final int start;
  final String raw;
  final String? quote;
  final String value;
  final bool commandPosition;
  final String pathPrefix;
  final String namePrefix;

  String get preferredSeparator {
    final slash = pathPrefix.lastIndexOf('/');
    final backslash = pathPrefix.lastIndexOf(r'\');
    if (slash < 0 && backslash < 0) return p.separator;
    return slash > backslash ? '/' : r'\';
  }
}

class _CompletionMatch {
  const _CompletionMatch({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;

  String get label => isDirectory ? '$name${p.separator}' : name;
}

class _CommandInvocation {
  const _CommandInvocation({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class _LocalShellSpec {
  const _LocalShellSpec({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    String? probeExecutable,
  }) : probeExecutable = probeExecutable ?? executable;

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final String probeExecutable;
}

/// 자식 프로세스의 바이트 스트림을 청크 경계와 무관하게 텍스트로 바꾼다.
///
/// - UTF-8 멀티바이트가 청크 사이에서 갈라져도 `Utf8Decoder`의 chunked
///   conversion 이 상태를 유지해 이어 붙인다.
/// - 청크 끝의 `\r`은 다음 청크가 `\n`으로 시작할 수 있으므로 보류했다가
///   함께 정규화한다. 그렇지 않으면 CRLF 하나가 줄바꿈 두 개로 찍힌다.
class _ChildOutputSink {
  _ChildOutputSink(this._emit) {
    _decoder = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      StringConversionSink.fromStringSink(_CallbackStringSink(_onDecoded)),
    );
  }

  final void Function(String) _emit;
  late final ByteConversionSink _decoder;
  bool _pendingCr = false;

  void add(List<int> bytes) => _decoder.add(bytes);

  void close() {
    _decoder.close();
    if (_pendingCr) {
      _pendingCr = false;
      _emit('\r');
    }
  }

  void _onDecoded(String text) {
    if (text.isEmpty) return;
    var chunk = _pendingCr ? '\r$text' : text;
    _pendingCr = false;
    if (chunk.endsWith('\r')) {
      _pendingCr = true;
      chunk = chunk.substring(0, chunk.length - 1);
    }
    if (chunk.isNotEmpty) _emit(chunk);
  }
}

class _CallbackStringSink implements StringSink {
  _CallbackStringSink(this._onChunk);

  final void Function(String) _onChunk;

  @override
  void write(Object? object) => _onChunk(object.toString());

  @override
  void writeCharCode(int charCode) => _onChunk(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => _onChunk('$object\n');

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _onChunk(objects.join(separator));
}
