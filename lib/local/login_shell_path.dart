import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 사용자 로그인 셸(`$SHELL -lc`)이 구성하는 PATH를 읽는다.
///
/// Finder/Dock에서 실행한 데스크톱 앱은 `.zprofile` 등이 추가한 경로를
/// 물려받지 못한다. 셸이 없거나 3초 안에 답하지 않으면 null.
Future<String?> readLoginShellPath() async {
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
