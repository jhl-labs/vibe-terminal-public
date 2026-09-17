import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/models/host.dart';
import '../local/managed_process.dart';

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
  const AgentWorkspaceTestRuntime(
    this._remoteExecutor, {
    this.executionTimeout = timeout,
  });

  final Duration executionTimeout;

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
        timeout: executionTimeout,
      );
    }

    final invocation = _localInvocation(
      host: host,
      command: command,
      workingDirectory: workingDirectory,
    );
    final process = await ManagedLocalProcess.start(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
    );
    final stdout = AgentBoundedOutputCollector(maximumOutputCharacters ~/ 2)
      ..listen(process.stdout);
    final stderr = AgentBoundedOutputCollector(maximumOutputCharacters ~/ 2)
      ..listen(process.stderr);
    var timedOut = false;
    int? exitCode;
    try {
      await (() async {
        exitCode = await process.exitCode;
        await Future.wait([stdout.done, stderr.done]);
      })().timeout(executionTimeout);
    } on TimeoutException {
      timedOut = true;
      try {
        await process.stop();
      } finally {
        await stdout.cancel();
        await stderr.cancel();
      }
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
          managedPosixCommand(command, directory: workingDirectory),
        ],
      ),
    };
  }
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
