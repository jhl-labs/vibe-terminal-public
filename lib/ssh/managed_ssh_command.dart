import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import '../core/bounded_command_output.dart';
import '../local/managed_process.dart';

/// SSH exec channel에서도 실제 명령 그룹을 소유하며 exit와 두 출력 stream을
/// 모두 기다린다. 명령 시작·실행·출력 전체에 하나의 deadline을 적용한다.
Future<ProcessResult> runManagedSshCommand(
  SSHClient client,
  String command, {
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  final opening = client.execute(managedPosixCommand(command));
  late SSHSession session;
  try {
    session = await opening.timeout(timeout);
  } catch (_) {
    // channel 생성이 늦게 성공하더라도 실행 프로세스를 남기지 않는다.
    unawaited(
      opening.then((lateSession) {
        lateSession.kill(SSHSignal.TERM);
        lateSession.close();
      }, onError: (Object _) {}),
    );
    rethrow;
  }
  final output = BoundedCommandOutput(session.stdout, 4 * 1024 * 1024);
  final error = BoundedCommandOutput(session.stderr, 4 * 1024 * 1024);
  try {
    final remaining = timeout - watch.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('SSH 명령 시작 시간 초과');
    await Future.wait<void>([
      session.done,
      session.stdin.close(),
      output.done.then<void>((_) {}),
      error.done.then<void>((_) {}),
    ], eagerError: true).timeout(remaining);
    return ProcessResult(0, session.exitCode ?? -1, output.text, error.text);
  } catch (_) {
    session.kill(SSHSignal.TERM);
    try {
      await session.done.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      session.kill(SSHSignal.KILL);
    }
    rethrow;
  } finally {
    session.close();
    await output.cancel();
    await error.cancel();
  }
}
