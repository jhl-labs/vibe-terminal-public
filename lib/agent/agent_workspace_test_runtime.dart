import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/models/host.dart';

class AgentTestProcessResult {
  const AgentTestProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.outputTruncated,
  });

  final int? exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool outputTruncated;
}

typedef RemoteAgentTestExecutor =
    Future<AgentTestProcessResult> Function({
      required Host host,
      required String? preferredSessionId,
      required String command,
      required String workingDirectory,
      required Duration timeout,
    });

/// 사용자가 확인한 테스트 명령을 worktree의 셸에서 실행하고 출력을 제한한다.
/// Git 상태, Registry, UI는 알지 않으며 원격 채널은 주입된 executor가 소유한다.
class AgentWorkspaceTestRuntime {
  const AgentWorkspaceTestRuntime(this._remoteExecutor);

  static const timeout = Duration(minutes: 15);
  static const int maximumOutputCharacters = 240000;

  final RemoteAgentTestExecutor _remoteExecutor;

  Future<AgentTestProcessResult> run({
    required Host host,
    required String? preferredSessionId,
    required String command,
    required String workingDirectory,
  }) async {
    if (!host.isLocalShell) {
      return _remoteExecutor(
        host: host,
        preferredSessionId: preferredSessionId,
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout,
      );
    }

    final invocation = _localInvocation(
      host: host,
      command: command,
      workingDirectory: workingDirectory,
    );
    final process = await Process.start(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
      runInShell: false,
      environment: Platform.isWindows ? Platform.environment : null,
    );
    final stdout = AgentBoundedOutputCollector(maximumOutputCharacters ~/ 2)
      ..listen(process.stdout);
    final stderr = AgentBoundedOutputCollector(maximumOutputCharacters ~/ 2)
      ..listen(process.stderr);
    var timedOut = false;
    int? exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
      await Future.wait([stdout.done, stderr.done]);
    } on TimeoutException {
      timedOut = true;
      await _terminateLocalProcess(process);
      await stdout.cancel();
      await stderr.cancel();
    }
    return AgentTestProcessResult(
      exitCode: exitCode,
      stdout: stdout.text,
      stderr: stderr.text,
      timedOut: timedOut,
      outputTruncated: stdout.truncated || stderr.truncated,
    );
  }

  _LocalTestInvocation _localInvocation({
    required Host host,
    required String command,
    required String workingDirectory,
  }) {
    if (!Platform.isWindows) {
      return _LocalTestInvocation(
        executable: Platform.environment['SHELL'] ?? 'sh',
        arguments: ['-lc', command],
        workingDirectory: workingDirectory,
      );
    }
    return switch (host.localShellType) {
      LocalShellType.powershell => _LocalTestInvocation(
        executable: 'powershell.exe',
        arguments: [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          command,
        ],
        workingDirectory: workingDirectory,
      ),
      LocalShellType.cmd => _LocalTestInvocation(
        executable: 'cmd.exe',
        arguments: ['/d', '/s', '/c', command],
        workingDirectory: workingDirectory,
      ),
      LocalShellType.wsl => _LocalTestInvocation(
        executable: 'wsl.exe',
        arguments: [
          '--',
          'sh',
          '-lc',
          'cd ${_quotePosix(workingDirectory)} && (\n$command\n)',
        ],
      ),
    };
  }

  Future<void> _terminateLocalProcess(Process process) async {
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill.exe', [
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ], runInShell: false).timeout(const Duration(seconds: 5));
        return;
      } catch (_) {
        // taskkill을 사용할 수 없으면 정확한 셸 프로세스만 종료한다.
      }
    }
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  static String _quotePosix(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";
}

class _LocalTestInvocation {
  const _LocalTestInvocation({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class AgentBoundedOutputCollector {
  AgentBoundedOutputCollector(this.limit);

  final int limit;
  final _chunks = <String>[];
  final _done = Completer<void>();
  StreamSubscription<String>? _subscription;
  int _length = 0;
  bool truncated = false;

  Future<void> get done => _done.future;
  String get text => _chunks.join();

  void listen(Stream<List<int>> stream) {
    _subscription = utf8.decoder
        .bind(stream)
        .listen(
          _add,
          onDone: () {
            if (!_done.isCompleted) _done.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            _add('\n[출력 스트림 오류: $error]\n');
            if (!_done.isCompleted) _done.complete();
          },
        );
  }

  void _add(String chunk) {
    _chunks.add(chunk);
    _length += chunk.length;
    while (_length > limit && _chunks.isNotEmpty) {
      final overflow = _length - limit;
      final first = _chunks.first;
      if (first.length <= overflow) {
        _chunks.removeAt(0);
        _length -= first.length;
      } else {
        _chunks[0] = first.substring(overflow);
        _length -= overflow;
      }
      truncated = true;
    }
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    if (!_done.isCompleted) _done.complete();
  }
}
