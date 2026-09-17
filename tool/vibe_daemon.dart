import 'dart:io';
import 'package:vibe_terminal/local/daemon/server.dart';
import 'package:vibe_terminal/local/daemon/client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: vibe-daemon <private-directory>');
    exitCode = 64;
    return;
  }
  final daemon = LocalPtyDaemon(Directory(args.single));
  try {
    await daemon.start();
  } catch (error) {
    try {
      await LocalDaemonClient(Directory(args.single)).call('ping');
      return; // Another authenticated daemon already owns the directory.
    } catch (_) {}
    stderr.writeln('Daemon startup failed: $error');
    exitCode = 1;
    return;
  }
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) async {
      await daemon.close();
      exit(0);
    });
    ProcessSignal.sigint.watch().listen((_) async {
      await daemon.close();
      exit(0);
    });
  }
  await daemon.done;
  exit(0);
}
