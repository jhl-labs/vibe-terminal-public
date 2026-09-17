import 'dart:async';
import 'dart:io';
import '../core/bounded_command_output.dart';

/// 프로세스 그룹을 소유하는 supervisor. 사용자 명령은 위치 인자로만 전달한다.
/// bash job control로 자식에 별도 PGID를 부여하고 정상 종료에도 남은 자식을 정리한다.
/// bash가 없는 호스트에서는 조용히 약한 종료 정책으로 바꾸지 않고 시작을 실패시킨다.
const posixProcessSupervisor = r'''
set -m
"$@" <&0 &
vibe_child=$!
vibe_cleanup() {
  trap '' TERM INT HUP
  if kill -TERM -- "-$vibe_child" 2>/dev/null; then
    sleep 0.25
    kill -KILL -- "-$vibe_child" 2>/dev/null || :
  fi
  wait "$vibe_child" 2>/dev/null || :
}
trap 'vibe_cleanup; exit 143' TERM INT HUP
wait "$vibe_child"
vibe_status=$?
vibe_cleanup
exit "$vibe_status"
''';

String managedPosixCommand(String command, {String? directory}) {
  final script = directory == null
      ? command
      : 'cd ${quotePosixArgument(directory)} && (\n$command\n)';
  return 'exec bash -c ${quotePosixArgument(posixProcessSupervisor)} '
      'vibe-supervisor sh -lc ${quotePosixArgument(script)}';
}

String quotePosixArgument(String value) =>
    "'${value.replaceAll("'", "'\"'\"'")}'";

class ManagedLocalProcess {
  ManagedLocalProcess._(this._process);

  final Process _process;
  Future<void>? _stopFuture;

  Stream<List<int>> get stdout => _process.stdout;
  Stream<List<int>> get stderr => _process.stderr;
  Future<int> get exitCode => _process.exitCode;

  static Future<ManagedLocalProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      Platform.isWindows ? executable : '/bin/bash',
      Platform.isWindows
          ? arguments
          : [
              '-c',
              posixProcessSupervisor,
              'vibe-supervisor',
              executable,
              ...arguments,
            ],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    // 테스트/Run은 대화형 입력을 받지 않는다. pipe를 상속한 자식도 EOF를 받는다.
    await process.stdin.close();
    return ManagedLocalProcess._(process);
  }

  Future<void> stop() => _stopFuture ??= _stop();

  Future<void> _stop() async {
    if (Platform.isWindows) {
      final result = await Process.run('taskkill.exe', [
        '/PID',
        '${_process.pid}',
        '/T',
        '/F',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) {
        // 정상 종료와 경합할 수 있다. 종료되지 않았다면 실패를 숨기지 않는다.
        await _process.exitCode.timeout(const Duration(seconds: 1));
      }
    } else {
      _process.kill(ProcessSignal.sigterm);
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode.timeout(const Duration(seconds: 2));
      throw StateError('프로세스 supervisor가 응답하지 않아 강제 종료했습니다.');
    }
  }
}

/// 짧은 Git/CLI 명령도 deadline과 출력 상한을 갖고 프로세스 수명을 정리한다.
Future<ProcessResult> runManagedCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Duration timeout = const Duration(seconds: 45),
  int maximumOutputBytes = 4 * 1024 * 1024,
}) async {
  final process = await ManagedLocalProcess.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final output = BoundedCommandOutput(process.stdout, maximumOutputBytes);
  final error = BoundedCommandOutput(process.stderr, maximumOutputBytes);
  try {
    final completed = await Future.wait<Object>([
      process.exitCode,
      output.done,
      error.done,
    ], eagerError: true).timeout(timeout);
    return ProcessResult(0, completed[0] as int, output.text, error.text);
  } catch (_) {
    await process.stop();
    rethrow;
  } finally {
    await output.cancel();
    await error.cancel();
  }
}
