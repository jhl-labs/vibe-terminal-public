import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cli_config_home.dart';
import 'cli_installation.dart';

final cliInstallationDetectorProvider = Provider<CliInstallationDetector>(
  (ref) => CliInstallationDetector(),
);

/// Recheck after returning from an installer or another terminal.
final installedCliAppsProvider = FutureProvider<Set<CliConfigApp>>((ref) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return ref.watch(cliInstallationDetectorProvider).detect();
});
