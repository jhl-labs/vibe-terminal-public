import 'dart:io';

/// Bundle the local-session helper; external control is disabled in Core.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart scripts/build_desktop_tools.dart <output-directory>',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(args.single);
  await output.create(recursive: true);
  final root = File.fromUri(Platform.script).parent.parent;
  final filename = Platform.isWindows ? 'vibe-daemon.exe' : 'vibe-daemon';
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '${root.path}/tool/vibe_daemon.dart',
    '-o',
    '${output.path}/$filename',
  ], workingDirectory: root.path);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}
