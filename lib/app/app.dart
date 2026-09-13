import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_version.dart';
import 'theme.dart';
import 'update_checker.dart';
import '../state/providers.dart';
import '../ui/shell/app_shell.dart';

const _appChannel = MethodChannel('vibe_terminal/app');

class VibeTerminalApp extends StatelessWidget {
  const VibeTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibe Terminal $kAppVersion',
      debugShowCheckedModeBanner: false,
      theme: buildVibeTerminalTheme(),
      home: const _AppRoot(),
    );
  }
}

/// 앱 루트. 안드로이드에서 루트 화면의 뒤로가기는 앱을 종료하지 않고
/// 백그라운드로 보내, 열려 있는 SSH 세션을 유지한다(Termius와 유사).
/// 내부 화면(호스트 추가 등 push된 라우트)의 뒤로가기는 정상 동작한다.
///
/// 또한 앱 lifecycle을 관찰해 포그라운드 여부를 갱신한다(작업 완료 알림 조건).
class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot>
    with WidgetsBindingObserver {
  bool _updateCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreSessionsOnStartup());
      unawaited(_checkForUpdatesOnStartup());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    ref.read(appForegroundProvider.notifier).set(resumed);
    if (!resumed) {
      unawaited(
        ref
            .read(sessionManagerProvider.notifier)
            .persistOpenSessionsForRestore(),
      );
    }
    // 포그라운드 복귀 시, 백그라운드에서 끊긴 세션을 백오프(최대 30초, Doze로
    // 지연될 수 있음)를 기다리지 않고 즉시 재연결한다.
    if (resumed) {
      ref.read(sessionManagerProvider.notifier).reconnectDisconnectedNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const AppShell();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _appChannel.invokeMethod('moveToBackground');
      },
      child: const AppShell(),
    );
  }

  Future<void> _restoreSessionsOnStartup() async {
    await ref.read(sessionManagerProvider.notifier).restoreSavedSessions();
  }

  Future<void> _checkForUpdatesOnStartup() async {
    if (_updateCheckStarted || kAppVersion.isEmpty) return;
    if (!ref.read(buildFeaturesProvider).github) return;
    _updateCheckStarted = true;
    final result = await ref.read(updateCheckerProvider).check(kAppVersion);
    if (!mounted || result == null || !result.updateAvailable) return;
    await showVibeTerminalUpdateDialog(
      context: context,
      result: result,
      openUrl: ref.read(externalUrlLauncherProvider),
    );
  }
}

Future<void> showVibeTerminalUpdateDialog({
  required BuildContext context,
  required UpdateCheckResult result,
  required ExternalUrlLauncher openUrl,
}) {
  final release = result.latestRelease;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('업데이트가 있습니다'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '현재 v${result.currentVersion}에서 v${release.version}로 업데이트할 수 있습니다.',
          ),
          if (release.publishedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '릴리즈 날짜: ${release.publishedAt!.toLocal().toString().split('.').first}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('나중에'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await openUrl(release.htmlUrl);
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('릴리즈 열기'),
        ),
      ],
    ),
  );
}
