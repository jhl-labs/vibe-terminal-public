import 'dart:io';

import 'remote_terminal_launcher.dart';

/// 별도 exec 채널에서 원본 tmux의 활성 pane 경로를 읽는다.
/// 새 로그인 셸의 pwd나 키 입력에서 추정한 경로는 사용하지 않는다.
Future<String?> readRemoteWorkingDirectory(
  String sessionName,
  Future<ProcessResult> Function(String command) run,
) async {
  final target = "'=${sessionName.replaceAll("'", "'\"'\"'")}:'";
  try {
    final result = await run(
      'tmux -L ${TmuxRemoteTerminalLauncher.serverName} '
      "display-message -p -t $target '#{pane_current_path}'",
    );
    if (result.exitCode != 0 || result.stdout is! String) return null;
    final output = result.stdout as String;
    final path = output.endsWith('\n')
        ? output.substring(0, output.length - 1)
        : output;
    if (!path.startsWith('/') || path.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }
    return path;
  } catch (_) {
    return null;
  }
}
