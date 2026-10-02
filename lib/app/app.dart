import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_version.dart';
import 'theme.dart';
import 'update_checker.dart';
import 'update_notifier.dart';
import '../state/providers.dart';
import '../ui/shell/app_shell.dart';

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
    return const AppShell();
  }

  Future<void> _restoreSessionsOnStartup() async {
    await _migrateHostIdentities();
    await _seedDefaultLocalHosts();
    await ref.read(sessionManagerProvider.notifier).restoreSavedSessions();
  }

  /// v15 이전 호스트가 직접 들고 있던 인증 정보를 Identity/키체인으로 옮긴다.
  Future<void> _migrateHostIdentities() async {
    try {
      final migrated = await ref
          .read(hostRepositoryProvider)
          .migrateLegacyIdentities();
      if (migrated > 0) ref.invalidate(hostListProvider);
    } catch (_) {
      // 마이그레이션 실패는 앱 시작을 막지 않는다. 호스트는 기존 필드로 계속 동작한다.
    }
  }

  /// 처음 쓰는 사람이 PowerShell/WSL/로컬 셸을 직접 등록하지 않아도 되게,
  /// 기기에 맞는 기본 로컬 호스트를 한 번만 만든다.
  Future<void> _seedDefaultLocalHosts() async {
    try {
      if (await ref.read(defaultLocalHostSeederProvider).seed()) {
        ref.invalidate(hostListProvider);
      }
    } catch (_) {
      // 기본 호스트는 편의 기능이다. 실패해도 앱 시작을 막지 않는다.
    }
  }

  Future<void> _checkForUpdatesOnStartup() async {
    if (_updateCheckStarted || kAppVersion.isEmpty) return;
    if (!ref.read(buildFeaturesProvider).updateCheck) return;
    _updateCheckStarted = true;

    final preferences = ref.read(updatePreferencesProvider);
    var state = await preferences.load();
    final now = DateTime.now().toUtc();

    if (state.shouldCheck(now)) {
      final result = await ref.read(updateCheckerProvider).check(kAppVersion);
      // 조회에 성공하든 실패하든 시각을 남긴다. GitHub가 죽어 있을 때 실행할
      // 때마다 재시도하지 않게 하기 위해서다.
      state = state.copyWith(
        lastCheckedAt: now,
        latestVersion: result?.latestRelease.version,
        latestUrl: result?.latestRelease.htmlUrl,
      );
      await preferences.save(state);
      if (!mounted) return;

      // 새로 알게 된 버전만 다이얼로그로 알린다. 하루 1회 제한에 걸린 실행은
      // 헤더 배지로만 조용히 알린다.
      final pending = state.pendingUpdate(kAppVersion);
      ref.read(pendingUpdateProvider.notifier).set(pending);
      if (result == null || !result.updateAvailable || pending == null) return;

      final skipped = await showVibeTerminalUpdateDialog(
        context: context,
        result: result,
        openUrl: ref.read(externalUrlLauncherProvider),
      );
      if (skipped) {
        state = state.copyWith(skippedVersion: pending.version);
        await preferences.save(state);
        if (mounted) ref.read(pendingUpdateProvider.notifier).set(null);
      }
      return;
    }

    if (!mounted) return;
    ref
        .read(pendingUpdateProvider.notifier)
        .set(state.pendingUpdate(kAppVersion));
  }
}

/// 업데이트 안내를 띄운다. 사용자가 "이 버전 건너뛰기"를 골랐으면 true.
Future<bool> showVibeTerminalUpdateDialog({
  required BuildContext context,
  required UpdateCheckResult result,
  required ExternalUrlLauncher openUrl,
}) async {
  final release = result.latestRelease;
  final skipped = await showDialog<bool>(
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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('나중에'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('이 버전 건너뛰기'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await openUrl(release.htmlUrl);
            if (context.mounted) Navigator.of(context).pop(false);
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('릴리즈 열기'),
        ),
      ],
    ),
  );
  return skipped ?? false;
}
