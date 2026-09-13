import 'dart:async';
import 'dart:io';

import '../data/models/host.dart';

abstract interface class AgentWorkspaceRunHandle {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int?> get done;
  Future<void> stop();
}

typedef RemoteAgentWorkspaceRunStarter =
    Future<AgentWorkspaceRunHandle> Function({
      required Host host,
      required String? preferredSessionId,
      required String command,
      required String workingDirectory,
    });

/// 확인된 개발 서버 명령을 장기 실행 프로세스로 시작한다.
/// 상태 보존과 URL 해석은 상위 coordinator가 담당한다.
class AgentWorkspaceRunRuntime {
  const AgentWorkspaceRunRuntime(this._remoteStarter);

  final RemoteAgentWorkspaceRunStarter _remoteStarter;

  Future<AgentWorkspaceRunHandle> start({
    required Host host,
    required String? preferredSessionId,
    required String command,
    required String workingDirectory,
  }) async {
    if (!host.isLocalShell) {
      return _remoteStarter(
        host: host,
        preferredSessionId: preferredSessionId,
        command: command,
        workingDirectory: workingDirectory,
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
    return _LocalAgentWorkspaceRunHandle(process);
  }

  _LocalRunInvocation _localInvocation({
    required Host host,
    required String command,
    required String workingDirectory,
  }) {
    if (!Platform.isWindows) {
      return _LocalRunInvocation(
        executable: Platform.environment['SHELL'] ?? 'sh',
        arguments: ['-lc', command],
        workingDirectory: workingDirectory,
      );
    }
    return switch (host.localShellType) {
      LocalShellType.powershell => _LocalRunInvocation(
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
      LocalShellType.cmd => _LocalRunInvocation(
        executable: 'cmd.exe',
        arguments: ['/d', '/s', '/c', command],
        workingDirectory: workingDirectory,
      ),
      LocalShellType.wsl => _LocalRunInvocation(
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

  static String _quotePosix(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";
}

class _LocalRunInvocation {
  const _LocalRunInvocation({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class _LocalAgentWorkspaceRunHandle implements AgentWorkspaceRunHandle {
  _LocalAgentWorkspaceRunHandle(this._process);

  final Process _process;
  bool _stopping = false;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int?> get done => _process.exitCode;

  @override
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill.exe', [
          '/PID',
          '${_process.pid}',
          '/T',
          '/F',
        ], runInShell: false).timeout(const Duration(seconds: 5));
        await _process.exitCode.timeout(const Duration(seconds: 3));
        return;
      } catch (_) {
        // 정확한 프로세스 트리 종료가 실패하면 해당 셸 프로세스를 종료한다.
      }
    }
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      _process.kill(ProcessSignal.sigkill);
    }
  }
}
