import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_launcher.dart';
import '../../agent/agent_worktree.dart';
import '../../agent/agent_workspace_run_probe.dart';
import '../../app/build_features.dart';
import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../security/host_key_store.dart';
import '../../session/session.dart';
import '../../settings/app_settings.dart';
import '../../settings/shortcut_bindings.dart';
import '../../ssh/ssh_service.dart';
import '../../state/providers.dart';
import '../adaptive/breakpoints.dart';
import '../hosts/host_edit_page.dart';
import '../hosts/host_list_page.dart';
import '../security/host_key_prompt.dart';
import '../security/keyboard_interactive_prompt.dart';
import '../settings/settings_sheet.dart';
import '../terminal/extra_keys_bar.dart';
import '../terminal/session_terminal_view.dart';
import 'agent_launch_dialog.dart';
import 'agent_source_control_dialog.dart';
import 'agent_worktrees_dialog.dart';
import 'ai_chat_panel.dart';
import '../../cli_config/cli_config_home.dart';
import '../../cli_config/cli_installation_provider.dart';
import 'cli_config_panel.dart';
import 'command_palette.dart';
import 'community_panel.dart';
import 'log_viewer_panel.dart';
import 'memo_panel.dart';
import 'session_rail.dart';
import 'snippet_panel.dart';

/// 플랫폼이 실제로 지원하는 도구만 레일에 올린다. 빌드 플래그는 플랫폼을
/// 구분하지 않으므로, 플러그인이 없거나(Linux 웹뷰) 기능 자체가 데스크톱
/// 전용인(X11) 도구는 여기서 걸러 빈 패널이 노출되지 않게 한다.

List<RightPanelTool> _enabledRightPanelTools(
  BuildFeatures features,
  Set<CliConfigApp> installedCliApps,
) {
  return [
    if (features.snippets) RightPanelTool.snippets,
    if (features.aiChat) RightPanelTool.aiChat,
    if (features.memo) RightPanelTool.memo,
    if (features.claudeSettings &&
        installedCliApps.contains(CliConfigApp.claude))
      RightPanelTool.claudeSettings,
    if (features.codexSettings && installedCliApps.contains(CliConfigApp.codex))
      RightPanelTool.codexSettings,
    if (features.opencodeSettings &&
        installedCliApps.contains(CliConfigApp.opencode))
      RightPanelTool.opencodeSettings,
    if (features.community && features.github) RightPanelTool.community,
    if (features.logs) RightPanelTool.logs,
  ];
}

IconData _rightPanelToolIcon(RightPanelTool tool) {
  return switch (tool) {
    RightPanelTool.snippets => Icons.code,
    RightPanelTool.aiChat => Icons.auto_awesome,
    RightPanelTool.memo => Icons.sticky_note_2_outlined,
    RightPanelTool.claudeSettings => appIconFor(CliConfigApp.claude),
    RightPanelTool.codexSettings => appIconFor(CliConfigApp.codex),
    RightPanelTool.opencodeSettings => appIconFor(CliConfigApp.opencode),
    RightPanelTool.community => Icons.groups_2_outlined,
    RightPanelTool.logs => Icons.receipt_long_outlined,
  };
}

String _rightPanelToolLabel(RightPanelTool tool) {
  return switch (tool) {
    RightPanelTool.snippets => '스니펫',
    RightPanelTool.aiChat => 'AI Chat',
    RightPanelTool.memo => '메모',
    RightPanelTool.claudeSettings => 'Claude Settings',
    RightPanelTool.codexSettings => 'Codex Settings',
    RightPanelTool.opencodeSettings => 'OpenCode Settings',
    RightPanelTool.community => 'Community',
    RightPanelTool.logs => '로그',
  };
}

Map<ShortcutActivator, VoidCallback> _appShortcutCallbacks(
  AppSettings settings,
  WidgetRef ref,
  VoidCallback onCommandPalette,
) {
  return shortcutCallbacksForActions(
    settings: settings,
    actions: {
      'sessionPrevious': () => switchToPreviousActiveSession(ref),
      'commandPalette': onCommandPalette,
    },
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _mobileScaffoldKey = GlobalKey<ScaffoldState>();
  final _mobileSessionSwipeGuard = _MobileSessionSwipeGuard();
  bool _mobileDrawerOpen = false;
  bool _mobileEndDrawerOpen = false;

  void _setMobileDrawerOpen(bool open) {
    if (_mobileDrawerOpen == open) return;
    setState(() => _mobileDrawerOpen = open);
  }

  void _setMobileEndDrawerOpen(bool open) {
    if (_mobileEndDrawerOpen == open) return;
    setState(() => _mobileEndDrawerOpen = open);
    if (!open) {
      ref.read(rightPanelProvider.notifier).close();
    }
  }

  void _handleMobileBack() {
    if (_mobileEndDrawerOpen) {
      _closeMobileEndDrawer();
      return;
    }
    if (_mobileDrawerOpen) {
      _closeMobileDrawer();
    }
  }

  void _closeMobileDrawer() {
    _mobileScaffoldKey.currentState?.closeDrawer();
  }

  void _closeMobileEndDrawer() {
    _mobileScaffoldKey.currentState?.closeEndDrawer();
  }

  Future<bool> _onHostKey(
    BuildContext context,
    String hostAlias,
    String _,
    String fingerprint,
    HostKeyVerdict v,
  ) async {
    // 콜백은 미지의 키(trustedNew)일 때만 호출되지만, 핀된 키 자동 신뢰를
    // 명시하기 위한 방어적 분기다.
    if (v == HostKeyVerdict.trustedKnown) return true;
    if (!context.mounted) return false;
    return showHostKeyPrompt(
      context,
      hostAlias: hostAlias,
      fingerprint: fingerprint,
      verdict: v,
    );
  }

  Future<List<String>?> _onKeyboardInteractive(
    BuildContext context,
    String hostAlias,
    KeyboardInteractiveRequest request,
  ) {
    if (!context.mounted) return Future.value(null);
    return showKeyboardInteractivePrompt(
      context,
      hostAlias: hostAlias,
      request: request,
    );
  }

  Future<void> _newSession(BuildContext context, WidgetRef ref) async {
    final host = await Navigator.push<Host>(
      context,
      MaterialPageRoute(builder: (_) => const HostListPage(pickMode: true)),
    );
    if (host == null || !context.mounted) return;
    final id = await ref
        .read(sessionManagerProvider.notifier)
        .openSession(
          host,
          groupId: ref.read(sessionGroupProvider).activeGroupId,
          onHostKey: (a, t, fp, v) => _onHostKey(context, a, t, fp, v),
          onKeyboardInteractive: (alias, request) =>
              _onKeyboardInteractive(context, alias, request),
        );
    if (!context.mounted) return;
    ref.read(activeSessionIdProvider.notifier).set(id);
  }

  Future<void> _retrySession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    final id = await ref
        .read(sessionManagerProvider.notifier)
        .retrySession(
          session.id,
          onHostKey: (a, t, fp, v) => _onHostKey(context, a, t, fp, v),
          onKeyboardInteractive: (alias, request) =>
              _onKeyboardInteractive(context, alias, request),
        );
    if (!context.mounted) return;
    ref.read(activeSessionIdProvider.notifier).set(id);
  }

  Future<void> _fallbackToCmdAndRetry(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    final repository = ref.read(hostRepositoryProvider);
    final latest = await repository.getById(session.host.id);
    if (latest == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로컬 셸 정보를 찾지 못해 기본 CMD 전환을 수행할 수 없습니다.'),
          ),
        );
      }
      return;
    }
    if (latest.localShellType == LocalShellType.cmd) {
      if (!context.mounted) return;
      await _retrySession(context, ref, session);
      return;
    }

    final next = latest.copyWith(
      localShellType: LocalShellType.cmd,
      updatedAt: DateTime.now(),
    );
    await repository.upsert(next);
    ref.invalidate(hostListProvider);
    if (!context.mounted) return;
    await _retrySession(context, ref, session);
  }

  Future<void> _duplicateSession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    final id = await ref
        .read(sessionManagerProvider.notifier)
        .duplicateSession(
          session.id,
          onHostKey: (a, t, fp, v) => _onHostKey(context, a, t, fp, v),
          onKeyboardInteractive: (alias, request) =>
              _onKeyboardInteractive(context, alias, request),
        );
    if (!context.mounted) return;
    ref.read(activeSessionIdProvider.notifier).set(id);
  }

  Future<void> _launchAgentSession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
    AgentLaunchSpec spec,
  ) async {
    try {
      ref
          .read(appSettingsProvider.notifier)
          .rememberAgentLaunch(
            cliName: spec.cli.name,
            arguments: spec.arguments,
            isolateByDefault: spec.isolatedWorktree,
          );
      final id = await ref
          .read(sessionManagerProvider.notifier)
          .launchAgentSession(
            session.id,
            spec,
            onHostKey: (a, t, fp, v) => _onHostKey(context, a, t, fp, v),
          );
      if (!context.mounted) return;
      ref.read(activeSessionIdProvider.notifier).set(id);
    } on ArgumentError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message?.toString() ?? 'Agent 실행 설정이 올바르지 않습니다.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _reviewAgentChanges(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    final id = await ref
        .read(sessionManagerProvider.notifier)
        .openAgentReviewSession(
          session.id,
          onHostKey: (a, t, fp, v) => _onHostKey(context, a, t, fp, v),
        );
    if (!context.mounted) return;
    ref.read(activeSessionIdProvider.notifier).set(id);
  }

  Future<void> _openAgentWorktrees(BuildContext context, WidgetRef ref) async {
    final manager = ref.read(sessionManagerProvider.notifier);
    await showAgentWorktreesDialog(
      context,
      load: manager.agentWorktrees,
      onInspect: (worktree) async {
        await manager.inspectAgentWorktree(worktree.id);
      },
      onReview: (worktree) =>
          _showAgentSourceControl(context, ref, worktree.id),
      onResume: (worktree) async {
        final id = await manager.resumeAgentWorktree(
          worktree.id,
          onHostKey: (a, t, fp, v) => _onHostKey(context, a, t, fp, v),
        );
        SessionInfo? session;
        for (final candidate in ref.read(sessionManagerProvider)) {
          if (candidate.id == id) {
            session = candidate;
            break;
          }
        }
        if (session != null) {
          ref.read(sessionGroupProvider.notifier).setActive(session.groupId);
        }
        ref.read(activeSessionIdProvider.notifier).set(id);
      },
      onCleanup: (worktree) => manager.cleanupAgentWorktree(worktree.id),
    );
  }

  Future<void> _showAgentSourceControl(
    BuildContext context,
    WidgetRef ref,
    String workspaceId,
  ) async {
    final manager = ref.read(sessionManagerProvider.notifier);
    final worktrees = await manager.agentWorktrees();
    if (!context.mounted) return;
    AgentWorktreeRecord? worktree;
    for (final candidate in worktrees) {
      if (candidate.id == workspaceId) {
        worktree = candidate;
        break;
      }
    }
    if (worktree == null) {
      // 목록을 본 뒤 작업공간이 정리됐을 수 있다. 예외를 던지면 아무 안내 없이
      // 다이얼로그만 안 열리므로 스낵바로 알리고 끝낸다.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Agent 작업공간 기록을 찾을 수 없습니다. 목록을 새로고침하세요.')),
      );
      return;
    }
    await showAgentSourceControlDialog(
      context,
      worktree: worktree,
      load: () => manager.agentSourceControl(workspaceId),
      loadDiff: (change) => manager.agentFileDiff(workspaceId, change),
      commit: (paths, message) => manager.commitAgentChanges(
        workspaceId,
        selectedPaths: paths,
        message: message,
      ),
      loadConflicts: () => manager.agentConflictSnapshot(workspaceId),
      loadTestState: () => manager.agentWorkspaceTestState(workspaceId),
      runTest: (command) => manager.runAgentWorkspaceTest(workspaceId, command),
      loadDeliveryPreview: () => manager.agentDeliveryPreview(workspaceId),
      merge: () => manager.mergeAgentWorkspace(workspaceId),
      push: () => manager.pushAgentWorkspace(workspaceId),
      createPullRequest: (draft) =>
          manager.createAgentPullRequest(workspaceId, draft),
      openUrl: ref.read(externalUrlLauncherProvider),
      loadRunState: () => manager.agentWorkspaceRunState(workspaceId),
      startRun: (command) =>
          manager.startAgentWorkspaceRun(workspaceId, command),
      restartRun: (command) =>
          manager.restartAgentWorkspaceRun(workspaceId, command),
      stopRun: () => manager.stopAgentWorkspaceRun(workspaceId),
      openRunUrl: (uri) =>
          _openAgentWorkspaceRunUrl(context, ref, worktree!, uri),
      probeRunUrl: (uri) => _probeAgentWorkspaceRunUrl(ref, worktree!, uri),
      runProfiles: ref.read(appSettingsProvider).agentLaunch.runProfiles,
      saveRunProfile: ref
          .read(appSettingsProvider.notifier)
          .saveAgentRunProfile,
      removeRunProfile: ref
          .read(appSettingsProvider.notifier)
          .removeAgentRunProfile,
    );
  }

  Future<AgentWorkspaceProbeResult> _probeAgentWorkspaceRunUrl(
    WidgetRef ref,
    AgentWorktreeRecord worktree,
    Uri uri,
  ) async {
    if (!isAgentWorkspaceAutoProbeUrl(uri)) {
      return AgentWorkspaceProbeResult(
        sourceUri: uri,
        targetUri: uri,
        status: AgentWorkspaceProbeStatus.unsupported,
        checkedAt: DateTime.now(),
        latency: Duration.zero,
        detail: '안전상 loopback 개발 서버만 자동 확인합니다.',
      );
    }
    final target = await _resolveAgentWorkspaceRunUrl(ref, worktree, uri);
    return const AgentWorkspaceRunProbe().probe(
      sourceUri: uri,
      targetUri: target,
    );
  }

  Future<void> _openAgentWorkspaceRunUrl(
    BuildContext context,
    WidgetRef ref,
    AgentWorktreeRecord worktree,
    Uri uri,
  ) async {
    final target = await _resolveAgentWorkspaceRunUrl(ref, worktree, uri);

    await ref.read(externalUrlLauncherProvider)(target);
  }

  Future<Uri> _resolveAgentWorkspaceRunUrl(
    WidgetRef ref,
    AgentWorktreeRecord worktree,
    Uri uri,
  ) async {
    final manager = ref.read(sessionManagerProvider.notifier);
    final host = await manager.agentWorkspaceHost(worktree.id);
    var target = uri;
    if (host.isLocalShell) {
      if (uri.host == '0.0.0.0' || uri.host == '::' || uri.host == '[::]') {
        target = uri.replace(host: '127.0.0.1');
      }
    } else {
      throw UnsupportedError('공개판에서는 원격 Run URL을 위한 포트 포워딩을 제공하지 않습니다.');
    }

    return target;
  }

  Future<void> _openCommandPalette(
    BuildContext context,
    WidgetRef ref, {
    required List<SessionInfo> sessions,
    required SessionInfo? active,
    required List<RightPanelTool> availableTools,
    required bool compact,
  }) async {
    Future<void> openTool(RightPanelTool tool) async {
      ref.read(rightPanelProvider.notifier).open(tool);
      if (compact && context.mounted) {
        _mobileScaffoldKey.currentState?.openEndDrawer();
      }
    }

    Future<void> launch(AgentCli cli) async {
      if (active == null || !context.mounted) return;
      final spec = await showAgentLaunchDialog(
        context,
        preferences: ref.read(appSettingsProvider).agentLaunch,
        initialCli: cli,
        saveProfile: ref
            .read(appSettingsProvider.notifier)
            .saveAgentLaunchProfile,
        removeProfile: ref
            .read(appSettingsProvider.notifier)
            .removeAgentLaunchProfile,
      );
      if (spec != null && context.mounted) {
        await _launchAgentSession(context, ref, active, spec);
      }
    }

    final entries = <CommandPaletteEntry>[
      CommandPaletteEntry(
        id: 'new-session',
        label: '새 세션',
        description: 'SSH 또는 로컬 셸 연결 열기',
        icon: Icons.add_box_outlined,
        keywords: const ['connect', 'ssh', 'local'],
        onSelected: () => _newSession(context, ref),
      ),
      CommandPaletteEntry(
        id: 'agent-worktrees',
        label: 'Agent 작업공간',
        description: '중단된 worktree 재개 및 안전 정리',
        icon: Icons.account_tree_outlined,
        keywords: const ['agent', 'worktree', 'registry', 'resume', 'cleanup'],
        onSelected: () => _openAgentWorktrees(context, ref),
      ),
      if (active?.status == SessionStatus.connected)
        for (final cli in AgentCli.values)
          CommandPaletteEntry(
            id: 'launch-agent-${cli.name}',
            label: '새 ${cli.label} Agent',
            description: '${active!.displayName}에서 병렬 작업 시작',
            icon: Icons.smart_toy_outlined,
            keywords: const ['agent', 'worktree', 'spawn'],
            onSelected: () => launch(cli),
          ),
      if (active?.agentWorkspace != null)
        CommandPaletteEntry(
          id: 'review-agent',
          label: 'Agent 변경 검토',
          description: active!.agentWorkspace!.branchName ?? active.displayName,
          icon: Icons.difference_outlined,
          keywords: const ['git', 'diff', 'status', 'source control'],
          onSelected: () {
            final workspaceId = active.agentWorkspace!.workspaceId;
            if (workspaceId != null) {
              return _showAgentSourceControl(context, ref, workspaceId);
            }
            return _reviewAgentChanges(context, ref, active);
          },
        ),
      for (final session in sessions)
        CommandPaletteEntry(
          id: 'session-${session.id}',
          label: '세션: ${session.displayName}',
          description:
              session.agentWorkspace?.branchName ?? session.host.endpointLabel,
          icon: session.agentWorkspace == null
              ? Icons.terminal
              : Icons.account_tree_outlined,
          keywords: [
            'session',
            session.host.alias,
            session.groupId,
            if (session.agentWorkspace case final workspace?)
              workspace.cli.label,
          ],
          onSelected: () {
            ref.read(sessionGroupProvider.notifier).setActive(session.groupId);
            ref.read(activeSessionIdProvider.notifier).set(session.id);
          },
        ),
      for (final tool in availableTools)
        CommandPaletteEntry(
          id: 'tool-${tool.name}',
          label: '도구: ${_rightPanelToolLabel(tool)}',
          icon: _rightPanelToolIcon(tool),
          keywords: const ['panel', 'tool'],
          onSelected: () => openTool(tool),
        ),
    ];
    await showVibeCommandPalette(context, entries);
  }

  Future<void> _editHost(BuildContext context, WidgetRef ref, Host host) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HostEditPage(existing: host)),
    );
    if (context.mounted) {
      ref.invalidate(hostListProvider);
    }
  }

  Widget _center(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionManagerProvider);
    final activeGroupId = ref.watch(sessionGroupProvider).activeGroupId;
    final visibleSessions = [
      for (final session in sessions)
        if (session.groupId == activeGroupId) session,
    ];
    final activeId = ref.watch(activeSessionIdProvider);
    if (visibleSessions.isEmpty) {
      return _EmptyConsole(onNewSession: () => _newSession(context, ref));
    }
    final index = visibleSessions.indexWhere((s) => s.id == activeId);
    if (index < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(activeSessionIdProvider.notifier)
            .set(visibleSessions.first.id);
      });
    }
    return IndexedStack(
      index: index < 0 ? 0 : index,
      children: [
        for (final s in visibleSessions)
          SessionTerminalView(
            session: s,
            onRetry: () => _retrySession(context, ref, s),
            onEditHost: () => _editHost(context, ref, s.host),
            isPowershellFallbackAvailable:
                s.host.localShellType == LocalShellType.powershell,
            onFallbackToCmd: s.host.localShellType == LocalShellType.powershell
                ? () => _fallbackToCmdAndRetry(context, ref, s)
                : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final rightPanel = ref.watch(rightPanelProvider);
    final sessions = ref.watch(sessionManagerProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final activeGroupId = ref.watch(sessionGroupProvider).activeGroupId;
    final visibleSessions = [
      for (final session in sessions)
        if (session.groupId == activeGroupId) session,
    ];
    final features = ref.watch(buildFeaturesProvider);
    final settings = ref.watch(appSettingsProvider);
    final availableTools = _enabledRightPanelTools(
      features,
      ref.watch(installedCliAppsProvider).asData?.value ?? const {},
    );
    // 수동 lookup: collection 패키지 없이 안전하게 처리
    SessionInfo? active;
    for (final s in sessions) {
      if (s.id == activeId && s.groupId == activeGroupId) {
        active = s;
        break;
      }
    }

    Widget withAppShortcuts(Widget child) {
      final bindings = _appShortcutCallbacks(
        settings,
        ref,
        () => unawaited(
          _openCommandPalette(
            context,
            ref,
            sessions: sessions,
            active: active,
            availableTools: availableTools,
            compact: compact,
          ),
        ),
      );
      if (bindings.isEmpty) return child;
      return CallbackShortcuts(bindings: bindings, child: child);
    }

    // 열린 세션 수가 바뀔 때마다 백그라운드 keep-alive(포그라운드 서비스)와
    // keepalive 박자를 갱신한다. 세션이 있으면 켜고, 모두 닫히면 끈다.
    ref.listen<List<SessionInfo>>(sessionManagerProvider, (prev, next) {
      ref.read(backgroundKeepAliveProvider).update(next.length);
      final pulse = ref.read(keepalivePulseProvider);
      if (next.isEmpty) {
        pulse.stop();
      } else {
        pulse.start(() {
          unawaited(
            ref.read(sessionManagerProvider.notifier).pingActiveSessions(),
          );
        });
      }
    });

    // 모바일에서는 중앙 터미널을 가로 스와이프로 세션 전환할 수 있게 감싼다.
    // 터미널의 TUI 스크롤은 gesture arena 밖에서 포인터를 직접 관찰하므로,
    // 세로가 우세한 대각선 플릭도 가로 속도가 충분하면 두 동작이 함께 실행될
    // 수 있다. 같은 포인터 흐름을 guard로 관찰해 세로 의도나 멀티터치가 확인된
    // 제스처에서는 세션 전환만 차단한다.
    Widget centerBody = _center(context, ref);
    if (compact && visibleSessions.length > 1) {
      centerBody = Listener(
        onPointerDown: _mobileSessionSwipeGuard.onPointerDown,
        onPointerMove: _mobileSessionSwipeGuard.onPointerMove,
        onPointerUp: _mobileSessionSwipeGuard.onPointerEnd,
        onPointerCancel: _mobileSessionSwipeGuard.onPointerEnd,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            if (_mobileSessionSwipeGuard.takeShouldBlock()) return;
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 240) return;
            // 왼쪽으로 밀면 다음 세션, 오른쪽으로 밀면 이전 세션.
            cycleActiveSession(ref, velocity < 0 ? 1 : -1);
          },
          child: centerBody,
        ),
      );
    }

    final centerArea = DecoratedBox(
      decoration: const BoxDecoration(color: VibeColors.terminal),
      child: Column(
        children: [
          Expanded(child: centerBody),
          if (compact &&
              active != null &&
              active.status == SessionStatus.connected)
            SafeArea(top: false, child: ExtraKeysBar(session: active)),
        ],
      ),
    );

    if (compact) {
      final mobilePanelOpen = _mobileDrawerOpen || _mobileEndDrawerOpen;
      final compactToolActions = <Widget>[];
      if (features.snippets) {
        compactToolActions.add(
          Builder(
            builder: (ctx) => IconButton(
              tooltip: '스니펫',
              icon: const Icon(Icons.code),
              onPressed: () {
                ref
                    .read(rightPanelProvider.notifier)
                    .open(RightPanelTool.snippets);
                Scaffold.of(ctx).openEndDrawer();
              },
            ),
          ),
        );
      }
      if (features.aiChat) {
        compactToolActions.add(
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'AI Chat',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () {
                ref
                    .read(rightPanelProvider.notifier)
                    .open(RightPanelTool.aiChat);
                Scaffold.of(ctx).openEndDrawer();
              },
            ),
          ),
        );
      }
      final popupTools = availableTools
          .where(
            (tool) =>
                tool != RightPanelTool.snippets &&
                tool != RightPanelTool.aiChat,
          )
          .toList();
      if (popupTools.isNotEmpty) {
        compactToolActions.add(
          Builder(
            builder: (ctx) => PopupMenuButton<RightPanelTool>(
              tooltip: '도구',
              icon: const Icon(Icons.more_vert),
              onSelected: (tool) {
                ref.read(rightPanelProvider.notifier).open(tool);
                Scaffold.of(ctx).openEndDrawer();
              },
              itemBuilder: (context) => [
                for (final tool in popupTools)
                  PopupMenuItem(
                    value: tool,
                    child: Row(
                      children: [
                        Icon(_rightPanelToolIcon(tool), size: 18),
                        const SizedBox(width: 9),
                        Expanded(child: Text(_rightPanelToolLabel(tool))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      return withAppShortcuts(
        PopScope<void>(
          canPop: !mobilePanelOpen,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleMobileBack();
          },
          child: Scaffold(
            key: _mobileScaffoldKey,
            onDrawerChanged: _setMobileDrawerOpen,
            onEndDrawerChanged: _setMobileEndDrawerOpen,
            appBar: AppBar(
              title: Text(active?.displayName ?? 'Vibe Terminal'),
              actions: compactToolActions,
            ),
            drawer: Drawer(
              child: SafeArea(
                child: SessionRail(
                  onNewSession: () {
                    _closeMobileDrawer();
                    _newSession(context, ref);
                  },
                  onDuplicateSession: (session) async {
                    _closeMobileDrawer();
                    await _duplicateSession(context, ref, session);
                  },
                  onLaunchAgent: (session, spec) async {
                    _closeMobileDrawer();
                    await _launchAgentSession(context, ref, session, spec);
                  },
                  onReviewAgentChanges: (session) async {
                    _closeMobileDrawer();
                    await _reviewAgentChanges(context, ref, session);
                  },
                  onOpenAgentWorktrees: () {
                    _closeMobileDrawer();
                    _openAgentWorktrees(context, ref);
                  },
                  onOpenSettings: () {
                    _closeMobileDrawer();
                    showVibeTerminalSettings(context);
                  },
                  // 세션을 고르면 drawer를 닫아 바로 터미널이 보이게 한다.
                  onSessionSelected: _closeMobileDrawer,
                ),
              ),
            ),
            // Drawer는 Scaffold의 resizeToAvoidBottomInset 적용을 받지 않아,
            // 키보드가 올라오면 AI Chat 입력창이 가려진다. viewInsets.bottom만큼
            // 내용을 밀어올려 입력창이 키보드 위에 보이도록 한다.
            endDrawer: Drawer(
              width: MediaQuery.sizeOf(context).width,
              child: Builder(
                builder: (drawerContext) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(drawerContext).bottom,
                  ),
                  child: SafeArea(
                    child: _RightPanelContent(
                      onOpenSettings: () {
                        _closeMobileEndDrawer();
                        showVibeTerminalSettings(context);
                      },
                    ),
                  ),
                ),
              ),
            ),
            body: centerArea,
          ),
        ),
      );
    }

    // 데스크톱: 좌측 세션 보드 + 중앙 터미널 + 우측 도구 스트립.
    return withAppShortcuts(
      Scaffold(
        body: ColoredBox(
          color: VibeColors.bg,
          child: Row(
            children: [
              _ResizableLeftPanel(
                onNewSession: () => _newSession(context, ref),
                onDuplicateSession: (session) =>
                    _duplicateSession(context, ref, session),
                onLaunchAgent: (session, spec) =>
                    _launchAgentSession(context, ref, session, spec),
                onReviewAgentChanges: (session) =>
                    _reviewAgentChanges(context, ref, session),
                onOpenAgentWorktrees: () => _openAgentWorktrees(context, ref),
                onOpenSettings: () => showVibeTerminalSettings(context),
              ),
              const _PaneDivider(),
              Expanded(child: centerArea),
              if (availableTools.isNotEmpty) ...[
                const _PaneDivider(),
                _ToolStrip(
                  panelState: rightPanel,
                  availableTools: availableTools,
                  onToggleTool: (tool) =>
                      ref.read(rightPanelProvider.notifier).toggle(tool),
                ),
                if (rightPanel.open) ...[
                  const _PaneDivider(),
                  _ResizableRightPanel(
                    onOpenSettings: () => showVibeTerminalSettings(context),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 모바일 세션 전환과 터미널 세로 스크롤이 같은 포인터 흐름을 함께 소비하지
/// 않도록 세로 의도와 멀티터치를 기억한다. 실제 제스처 인식은 기존
/// [GestureDetector]에 맡기고, 이 객체는 세션 전환 가능 여부만 판정한다.
class _MobileSessionSwipeGuard {
  static const _touchDevices = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  final _origins = <int, Offset>{};
  bool _shouldBlock = false;
  bool _completedGestureShouldBlock = false;

  void onPointerDown(PointerDownEvent event) {
    if (!_touchDevices.contains(event.kind)) return;
    if (_origins.isEmpty) {
      _shouldBlock = false;
      _completedGestureShouldBlock = false;
    }
    _origins[event.pointer] = event.position;
    if (_origins.length > 1) {
      _shouldBlock = true;
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    final origin = _origins[event.pointer];
    if (origin == null || _shouldBlock) return;
    final total = event.position - origin;
    if (total.distance >= kTouchSlop && total.dy.abs() > total.dx.abs()) {
      _shouldBlock = true;
    }
  }

  void onPointerEnd(PointerEvent event) {
    if (_origins.remove(event.pointer) == null) return;
    _completedGestureShouldBlock |= _shouldBlock;
  }

  bool takeShouldBlock() {
    final result = _shouldBlock || _completedGestureShouldBlock;
    _completedGestureShouldBlock = false;
    if (_origins.isEmpty) {
      _shouldBlock = false;
    }
    return result;
  }
}

class _ResizableLeftPanel extends ConsumerStatefulWidget {
  const _ResizableLeftPanel({
    required this.onNewSession,
    required this.onDuplicateSession,
    required this.onLaunchAgent,
    required this.onReviewAgentChanges,
    required this.onOpenAgentWorktrees,
    required this.onOpenSettings,
  });

  final VoidCallback onNewSession;
  final Future<void> Function(SessionInfo session) onDuplicateSession;
  final Future<void> Function(SessionInfo session, AgentLaunchSpec spec)
  onLaunchAgent;
  final Future<void> Function(SessionInfo session) onReviewAgentChanges;
  final VoidCallback onOpenAgentWorktrees;
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<_ResizableLeftPanel> createState() =>
      _ResizableLeftPanelState();
}

class _ResizableLeftPanelState extends ConsumerState<_ResizableLeftPanel> {
  double? _dragWidth;

  double _maxWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth * 0.42)
        .clamp(AppSettings.minLeftPanelWidth, AppSettings.maxLeftPanelWidth)
        .toDouble();
  }

  double _clampWidth(BuildContext context, double width) =>
      width.clamp(AppSettings.minLeftPanelWidth, _maxWidth(context)).toDouble();

  void _startResize(double width) {
    setState(() => _dragWidth = width);
  }

  void _resize(DragUpdateDetails details) {
    final current =
        _dragWidth ??
        _clampWidth(context, ref.read(appSettingsProvider).leftPanelWidth);
    setState(
      () => _dragWidth = _clampWidth(context, current + details.delta.dx),
    );
  }

  void _endResize() {
    final width = _dragWidth;
    if (width != null) {
      ref.read(appSettingsProvider.notifier).setLeftPanelWidth(width);
    }
    if (mounted) setState(() => _dragWidth = null);
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(leftPanelCollapsedProvider);
    final settings = ref.watch(appSettingsProvider);
    final width = _clampWidth(context, _dragWidth ?? settings.leftPanelWidth);
    final canResize = MediaQuery.sizeOf(context).width >= 700;

    if (collapsed) {
      return _CollapsedLeftPanel(
        onExpand: () => ref.read(leftPanelCollapsedProvider.notifier).expand(),
        onNewSession: widget.onNewSession,
        onOpenSettings: widget.onOpenSettings,
      );
    }

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: SessionRail(
              width: width,
              onNewSession: widget.onNewSession,
              onDuplicateSession: widget.onDuplicateSession,
              onLaunchAgent: widget.onLaunchAgent,
              onReviewAgentChanges: widget.onReviewAgentChanges,
              onOpenAgentWorktrees: widget.onOpenAgentWorktrees,
              onOpenSettings: widget.onOpenSettings,
              onCollapse: () =>
                  ref.read(leftPanelCollapsedProvider.notifier).collapse(),
            ),
          ),
          if (canResize)
            _LeftPanelResizeHandle(
              onDragStart: () => _startResize(width),
              onDragUpdate: _resize,
              onDragEnd: _endResize,
            ),
        ],
      ),
    );
  }
}

class _CollapsedLeftPanel extends StatelessWidget {
  const _CollapsedLeftPanel({
    required this.onExpand,
    required this.onNewSession,
    required this.onOpenSettings,
  });

  final VoidCallback onExpand;
  final VoidCallback onNewSession;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      color: VibeColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _ToolButton(
              tooltip: '좌측 패널 펼치기',
              active: false,
              icon: Icons.keyboard_double_arrow_right,
              onPressed: onExpand,
            ),
            const SizedBox(height: 4),
            _ToolButton(
              tooltip: '새 세션',
              active: false,
              icon: Icons.add,
              onPressed: onNewSession,
            ),
            const Spacer(),
            _ToolButton(
              tooltip: 'Settings',
              active: false,
              icon: Icons.settings_outlined,
              onPressed: onOpenSettings,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _LeftPanelResizeHandle extends StatelessWidget {
  const _LeftPanelResizeHandle({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 10,
      child: Tooltip(
        message: '좌측 패널 폭 조절',
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => onDragStart(),
            onHorizontalDragUpdate: onDragUpdate,
            onHorizontalDragEnd: (_) => onDragEnd(),
            onHorizontalDragCancel: onDragEnd,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 3,
                height: 72,
                decoration: BoxDecoration(
                  color: VibeColors.accent.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizableRightPanel extends ConsumerStatefulWidget {
  const _ResizableRightPanel({required this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<_ResizableRightPanel> createState() =>
      _ResizableRightPanelState();
}

class _ResizableRightPanelState extends ConsumerState<_ResizableRightPanel> {
  double? _dragWidth;

  double _maxWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth * 0.64)
        .clamp(AppSettings.minRightPanelWidth, AppSettings.maxRightPanelWidth)
        .toDouble();
  }

  double _clampWidth(BuildContext context, double width) => width
      .clamp(AppSettings.minRightPanelWidth, _maxWidth(context))
      .toDouble();

  void _startResize(double width) {
    setState(() => _dragWidth = width);
  }

  void _resize(DragUpdateDetails details) {
    final current =
        _dragWidth ??
        _clampWidth(context, ref.read(appSettingsProvider).rightPanelWidth);
    setState(
      () => _dragWidth = _clampWidth(context, current - details.delta.dx),
    );
  }

  void _endResize() {
    final width = _dragWidth;
    if (width != null) {
      ref.read(appSettingsProvider.notifier).setRightPanelWidth(width);
    }
    if (mounted) setState(() => _dragWidth = null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final width = _clampWidth(context, _dragWidth ?? settings.rightPanelWidth);
    final canResize = MediaQuery.sizeOf(context).width >= 700;

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: _RightPanelContent(onOpenSettings: widget.onOpenSettings),
          ),
          if (canResize)
            _RightPanelResizeHandle(
              onDragStart: () => _startResize(width),
              onDragUpdate: _resize,
              onDragEnd: _endResize,
            ),
        ],
      ),
    );
  }
}

class _RightPanelResizeHandle extends StatelessWidget {
  const _RightPanelResizeHandle({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 10,
      child: Tooltip(
        message: '우측 패널 폭 조절',
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => onDragStart(),
            onHorizontalDragUpdate: onDragUpdate,
            onHorizontalDragEnd: (_) => onDragEnd(),
            onHorizontalDragCancel: onDragEnd,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 3,
                height: 72,
                decoration: BoxDecoration(
                  color: VibeColors.accent.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneDivider extends StatelessWidget {
  const _PaneDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 1,
      child: ColoredBox(color: VibeColors.borderSoft),
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({
    required this.panelState,
    required this.availableTools,
    required this.onToggleTool,
  });

  final RightPanelState panelState;
  final List<RightPanelTool> availableTools;
  final ValueChanged<RightPanelTool> onToggleTool;

  @override
  Widget build(BuildContext context) {
    if (availableTools.isEmpty) return const SizedBox.shrink();
    return Container(
      width: 52,
      color: VibeColors.surface,
      child: SafeArea(
        // 도구가 창 높이보다 많아지면(개발 빌드는 전 기능이 켜진다) 잘리지
        // 않고 스크롤되게 한다.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              for (final tool in availableTools) ...[
                Builder(
                  builder: (context) {
                    return _ToolButton(
                      tooltip: _rightPanelToolLabel(tool),
                      active: panelState.open && panelState.tool == tool,
                      icon: _rightPanelToolIcon(tool),
                      onPressed: () => onToggleTool(tool),
                    );
                  },
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.active,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool active;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox.square(
            dimension: 40,
            child: Stack(
              children: [
                IconButton(
                  onPressed: onPressed,
                  style: IconButton.styleFrom(
                    backgroundColor: active
                        ? VibeColors.accentSoft
                        : Colors.transparent,
                    foregroundColor: active
                        ? VibeColors.accent
                        : VibeColors.onSurfaceDim,
                    disabledForegroundColor: VibeColors.onSurfaceDim.withValues(
                      alpha: 0.45,
                    ),
                  ),
                  icon: Icon(icon, size: 19),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RightPanelContent extends ConsumerWidget {
  const _RightPanelContent({required this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(buildFeaturesProvider);
    final availableTools = _enabledRightPanelTools(
      features,
      ref.watch(installedCliAppsProvider).asData?.value ?? const {},
    );
    if (availableTools.isEmpty) return const SizedBox.shrink();

    final requestedTool = ref.watch(rightPanelProvider).tool;
    final visibleTool = availableTools.contains(requestedTool)
        ? requestedTool
        : availableTools.first;

    return switch (visibleTool) {
      RightPanelTool.aiChat => AiChatPanel(onOpenSettings: onOpenSettings),
      RightPanelTool.snippets => const SnippetPanel(),
      RightPanelTool.memo => const MemoPanel(),
      RightPanelTool.claudeSettings => const CliConfigPanel(
        app: CliConfigApp.claude,
      ),
      RightPanelTool.codexSettings => const CliConfigPanel(
        app: CliConfigApp.codex,
      ),
      RightPanelTool.opencodeSettings => const CliConfigPanel(
        app: CliConfigApp.opencode,
      ),
      RightPanelTool.community => const CommunityPanel(),
      RightPanelTool.logs => const LogViewerPanel(),
    };
  }
}

/// 세션이 없을 때 중앙에 보이는 빈 상태 — 터미널 프롬프트 모양으로
/// 앱 정체성을 드러내고 다음 행동을 안내한다.
class _EmptyConsole extends StatelessWidget {
  const _EmptyConsole({required this.onNewSession});

  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vibe Terminal',
                style: TextStyle(
                  color: VibeColors.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: VibeColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VibeColors.border),
                ),
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 16,
                      height: 1.45,
                    ),
                    children: [
                      TextSpan(
                        text: 'vibe-terminal ',
                        style: TextStyle(color: VibeColors.accent),
                      ),
                      TextSpan(
                        text: '~ % ',
                        style: TextStyle(color: VibeColors.onSurfaceDim),
                      ),
                      TextSpan(
                        text: 'ssh | powershell | wsl ',
                        style: TextStyle(color: VibeColors.onSurface),
                      ),
                      TextSpan(
                        text: 'ready',
                        style: TextStyle(color: VibeColors.warning),
                      ),
                      TextSpan(
                        text: '\n',
                        style: TextStyle(color: VibeColors.onSurfaceDim),
                      ),
                      TextSpan(
                        text: '새 세션을 열면 이 영역이 바로 터미널이 됩니다.',
                        style: TextStyle(
                          color: VibeColors.onSurfaceDim,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '연결된 세션이 없습니다.',
                style: TextStyle(color: VibeColors.onSurface, fontSize: 14),
              ),
              const SizedBox(height: 6),
              const Text(
                'SSH 호스트를 선택하거나 로컬 셸 프로필을 추가해 세션을 시작하세요.',
                style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 13),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onNewSession,
                icon: const Icon(Icons.add),
                label: const Text('새 세션'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
