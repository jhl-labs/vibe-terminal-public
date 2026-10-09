import 'session_close_dialog.dart';
import '../settings/terminal_preferences_editor.dart';
import '../../session/session_pane_layout.dart';
import 'panes/pane_preset_icon.dart';
import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_launcher.dart';
import '../../app/app_edition.dart';
import '../../app/app_version.dart';
import '../../app/theme.dart';
import '../../app/update_notifier.dart';
import '../../session/session.dart';
import '../../session/session_activity.dart';
import '../../session/session_attention.dart';
import '../../session/session_group.dart';
import '../../state/providers.dart';
import 'agent_brand.dart';
import 'agent_launch_dialog.dart';
import 'release_notes_dialog.dart';
import 'remote_session_manager_dialog.dart';
import 'session_group_manager.dart';

/// 좌측 세로탭 세션 패널. 데스크톱 레일/모바일 drawer 양쪽에서 재사용.
class SessionRail extends ConsumerWidget {
  const SessionRail({
    super.key,
    required this.onNewSession,
    required this.onDuplicateSession,
    required this.onOpenSettings,
    this.onLaunchAgent,
    this.onReviewAgentChanges,
    this.onOpenAgentWorktrees,
    this.width = 264,
    this.onCollapse,
    this.onSessionSelected,
    this.onBulk,
    this.onPreviousSession,
    this.onNextSession,
  });

  final VoidCallback onNewSession;
  final Future<void> Function(SessionInfo session) onDuplicateSession;
  final Future<void> Function(SessionInfo session, AgentLaunchSpec spec)?
  onLaunchAgent;
  final Future<void> Function(SessionInfo session)? onReviewAgentChanges;
  final VoidCallback? onOpenAgentWorktrees;
  final VoidCallback onOpenSettings;
  final double width;
  final VoidCallback? onCollapse;

  /// 세션 타일을 탭해 활성 세션을 바꾼 직후 호출된다.
  /// 모바일 drawer에서는 이 콜백으로 drawer를 닫는다(데스크톱은 미지정).
  final VoidCallback? onSessionSelected;

  /// 여러 세션 조작(일괄 닫기 등). null이면 헤더에 버튼을 두지 않는다.
  final VoidCallback? onBulk;

  /// 목록 순서로 이전/다음 세션을 활성화한다. 세션 전환은 그룹(작업공간)
  /// 관점의 조작이라 세션 그룹 선택기 옆에 둔다. null이면 비활성화한다.
  final VoidCallback? onPreviousSession, onNextSession;

  Color _statusColor(SessionStatus s) {
    switch (s) {
      case SessionStatus.connecting:
        return VibeColors.statusConnecting;
      case SessionStatus.connected:
        return VibeColors.statusConnected;
      case SessionStatus.disconnected:
        return VibeColors.statusDisconnected;
      case SessionStatus.error:
        return VibeColors.statusError;
    }
  }

  RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _showSessionMenu(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
    Offset globalPosition,
  ) async {
    final action = await showMenu<_SessionAction>(
      context: context,
      position: _menuPosition(context, globalPosition),
      color: VibeColors.surfaceHigh,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      constraints: const BoxConstraints(minWidth: 232),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: VibeColors.borderSoft),
      ),
      items: [
        if (onLaunchAgent != null && session.status == SessionStatus.connected)
          _SessionMenuItem(
            value: _SessionAction.launchAgent,
            icon: Icons.smart_toy_outlined,
            label: '새 Agent 세션',
          ),
        if (onReviewAgentChanges != null &&
            session.agentWorkspace != null &&
            session.status == SessionStatus.connected)
          _SessionMenuItem(
            value: _SessionAction.reviewAgentChanges,
            icon: Icons.difference_outlined,
            label: 'Agent 변경 검토',
          ),
        _SessionMenuItem(
          value: _SessionAction.duplicate,
          icon: Icons.copy_all_outlined,
          label: '복제',
        ),
        if (ref.read(sessionGroupProvider).groups.length > 1)
          _SessionMenuItem(
            value: _SessionAction.moveGroup,
            icon: Icons.drive_file_move_outline,
            label: '그룹 이동',
          ),
        _SessionMenuItem(
          value: _SessionAction.terminalSettings,
          icon: Icons.palette_outlined,
          label: '세션 폰트·테마 설정',
        ),
        _SessionMenuItem(
          value: _SessionAction.hostTerminalDefaults,
          icon: Icons.dns_outlined,
          label: '호스트 기본 터미널 설정',
        ),
        _SessionMenuItem(
          value: _SessionAction.rename,
          icon: Icons.edit_outlined,
          label: '이름 변경',
        ),
        if (session.host.keepsRemoteSession &&
            session.status == SessionStatus.connected)
          _SessionMenuItem(
            value: _SessionAction.remoteSessions,
            icon: Icons.inventory_2_outlined,
            label: '서버 작업 보관함',
          ),
        _SessionMenuItem(
          value: _SessionAction.close,
          icon: Icons.close,
          label: '닫기',
        ),
      ],
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _SessionAction.launchAgent:
        final cwd = await ref
            .read(sessionManagerProvider.notifier)
            .currentWorkingDirectoryOf(session.id);
        if (!context.mounted) return;
        final spec = await showAgentLaunchDialog(
          context,
          preferences: ref.read(appSettingsProvider).agentLaunch,
          initialWorkingDirectory: cwd,
          saveProfile: ref
              .read(appSettingsProvider.notifier)
              .saveAgentLaunchProfile,
          removeProfile: ref
              .read(appSettingsProvider.notifier)
              .removeAgentLaunchProfile,
          onModelUsed: ref
              .read(appSettingsProvider.notifier)
              .rememberAgentLaunchModel,
        );
        if (spec != null && context.mounted) {
          await onLaunchAgent!(session, spec);
        }
      case _SessionAction.reviewAgentChanges:
        await onReviewAgentChanges!(session);
      case _SessionAction.duplicate:
        await onDuplicateSession(session);
      case _SessionAction.moveGroup:
        await _moveSessionToGroup(context, ref, session);
      case _SessionAction.terminalSettings:
        await _configureTerminal(context, ref, session, forHost: false);
      case _SessionAction.hostTerminalDefaults:
        await _configureTerminal(context, ref, session, forHost: true);
      case _SessionAction.rename:
        await _renameSession(context, ref, session);
      case _SessionAction.remoteSessions:
        await showRemoteSessionManagerDialog(context, session);
      case _SessionAction.close:
        await requestCloseSession(context, ref, session);
    }
  }

  void _activateGroup(WidgetRef ref, String groupId) {
    ref.read(sessionGroupProvider.notifier).setActive(groupId);
    final currentActiveId = ref.read(activeSessionIdProvider);
    final groupSessions = [
      for (final session in ref.read(sessionManagerProvider))
        if (session.groupId == groupId) session,
    ];
    if (groupSessions.any((session) => session.id == currentActiveId)) return;
    final remembered = ref
        .read(sessionPaneLayoutsProvider)[groupId]
        ?.focused
        .sessionId;
    ref
        .read(activeSessionIdProvider.notifier)
        .set(
          groupSessions.any((s) => s.id == remembered)
              ? remembered
              : groupSessions.firstOrNull?.id,
        );
  }

  void _activateNextAttentionSession(
    WidgetRef ref,
    List<SessionInfo> sessions,
    Map<String, SessionAttention> attention,
  ) {
    final candidates = [
      for (final state in SessionAttentionState.values)
        if (state == SessionAttentionState.blocked ||
            state == SessionAttentionState.done)
          for (final session in sessions)
            if (attention[session.id]?.state == state) session,
    ];
    if (candidates.isEmpty) return;
    final currentId = ref.read(activeSessionIdProvider);
    final currentIndex = candidates.indexWhere(
      (session) => session.id == currentId,
    );
    final target = candidates[(currentIndex + 1) % candidates.length];
    ref.read(sessionGroupProvider.notifier).setActive(target.groupId);
    ref.read(activeSessionIdProvider.notifier).set(target.id);
    onSessionSelected?.call();
  }

  Future<void> _openGroupManager(
    BuildContext context,
    WidgetRef ref,
    Set<String> hiddenGroupIds,
  ) {
    return showSessionGroupManager(
      context,
      hiddenGroupIds: hiddenGroupIds,
      onGroupCreated: (id) => _activateGroup(ref, id),
    );
  }

  Future<void> _moveSessionToGroup(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    var selectedGroupId = session.groupId;
    final groups = ref.read(sessionGroupProvider).groups;
    final targetGroupId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('세션 그룹 이동'),
            content: DropdownButtonFormField<String>(
              initialValue: selectedGroupId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '대상 그룹'),
              dropdownColor: VibeColors.surfaceHigh,
              items: [
                for (final group in groups)
                  DropdownMenuItem(value: group.id, child: Text(group.name)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => selectedGroupId = value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(selectedGroupId),
                child: const Text('이동'),
              ),
            ],
          );
        },
      ),
    );
    if (targetGroupId == null || targetGroupId == session.groupId) return;
    ref
        .read(sessionManagerProvider.notifier)
        .moveSessionToGroup(session.id, targetGroupId);
  }

  Future<void> _configureTerminal(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session, {
    required bool forHost,
  }) async {
    try {
      final repository = ref.read(hostRepositoryProvider);
      final host = await repository.getById(session.host.id);
      if (!context.mounted) return;
      if (forHost && host == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('먼저 호스트를 저장해 주세요.')));
        return;
      }
      final current = ref
          .read(sessionManagerProvider)
          .where((s) => s.id == session.id)
          .firstOrNull;
      if (!forHost && current == null) return;
      final global = ref.read(appSettingsProvider);
      final hostPreferences = (host ?? session.host).terminalPreferences;
      final result = await showTerminalPreferencesDialog(
        context,
        title: forHost
            ? '${session.host.alias} · 호스트 기본값'
            : '${current!.displayName} · 세션 설정',
        description: forHost
            ? '이 호스트의 세션에 적용됩니다. 열린 세션에서 따로 바꾼 항목은 유지됩니다.'
            : '이 세션의 폰트·테마와 입력 동작만 변경합니다. 기본값에는 영향을 주지 않습니다.',
        initialValue: forHost ? hostPreferences : current!.terminalPreferences,
        defaults: forHost ? global : hostPreferences.applyTo(global),
        hostDefaults: forHost,
      );
      if (result == null || !context.mounted) return;
      if (forHost) {
        final saved = await repository.setTerminalPreferences(
          session.host.id,
          result,
        );
        if (saved) {
          ref
              .read(sessionManagerProvider.notifier)
              .updateHostTerminalPreferences(session.host.id, result);
        }
        if (!context.mounted) return;
        ref.invalidate(hostListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved ? '호스트 기본값을 저장했습니다.' : '호스트가 삭제되어 저장하지 못했습니다.'),
          ),
        );
      } else {
        ref
            .read(sessionManagerProvider.notifier)
            .setTerminalPreferences(session.id, result);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('터미널 설정을 처리하지 못했습니다: $error')));
      }
    }
  }

  Future<void> _renameSession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _SessionRenameDialog(
        initialTitle: session.displayName,
        hintText: session.host.alias,
      ),
    );
    if (title == null || !context.mounted) return;
    ref.read(sessionManagerProvider.notifier).renameSession(session.id, title);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final railContext = context;
    final allSessions = ref.watch(sessionManagerProvider);
    final groupState = ref.watch(sessionGroupProvider);
    final activeGroupId = groupState.activeGroupId;
    final sessions = [
      for (final session in allSessions)
        if (session.groupId == activeGroupId) session,
    ];
    final activeId = ref.watch(activeSessionIdProvider);
    final mgr = ref.read(sessionManagerProvider.notifier);
    final sessionCounts = <String, int>{};
    for (final session in allSessions) {
      sessionCounts.update(
        session.groupId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    // 사용자 정의 앱이 없는 빌드에서는 비어 있는 "앱 세션" 그룹을 감춘다.
    // 그룹 정규화(normalizeSessionGroups)는 건드리지 않고 표시만 거른다.
    final hideAppsGroup = (sessionCounts[appsSessionGroupId] ?? 0) == 0;
    final visibleGroups = [
      for (final group in groupState.groups)
        if (!(hideAppsGroup && group.id == appsSessionGroupId)) group,
    ];
    final displayGroupId = hideAppsGroup && activeGroupId == appsSessionGroupId
        ? defaultSessionGroupId
        : activeGroupId;

    return Container(
      width: width,
      color: VibeColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            _RailHeader(onOpenSettings: onOpenSettings, onCollapse: onCollapse),
            _GroupSelector(
              groups: visibleGroups,
              activeGroupId: displayGroupId,
              sessionCounts: sessionCounts,
              onChanged: (groupId) => _activateGroup(ref, groupId),
              onManageGroups: () => _openGroupManager(context, ref, {
                if (hideAppsGroup) appsSessionGroupId,
              }),
            ),
            _RailToolbar(
              onNewSession: onNewSession,
              onBulk: onBulk,
              onPreviousSession: onPreviousSession,
              onNextSession: onNextSession,
              onOpenAgentWorktrees: onOpenAgentWorktrees,
            ),
            Consumer(
              builder: (context, summaryRef, child) {
                // 미리보기 변경은 목록이나 요약을 다시 만들 필요가 없다.
                final counts = summaryRef.watch(
                  sessionAttentionProvider.select(
                    (attention) => (
                      allSessions
                          .where(
                            (s) =>
                                attention[s.id]?.state ==
                                SessionAttentionState.blocked,
                          )
                          .length,
                      allSessions
                          .where(
                            (s) =>
                                attention[s.id]?.state ==
                                SessionAttentionState.done,
                          )
                          .length,
                    ),
                  ),
                );
                if (counts.$1 == 0 && counts.$2 == 0) {
                  return const SizedBox.shrink();
                }
                return _AttentionSummary(
                  blockedCount: counts.$1,
                  doneCount: counts.$2,
                  onTap: () => _activateNextAttentionSession(
                    ref,
                    allSessions,
                    ref.read(sessionAttentionProvider),
                  ),
                );
              },
            ),
            const Divider(height: 1, color: VibeColors.borderSoft),
            Expanded(
              child: sessions.isEmpty
                  ? const _EmptyRail()
                  : _SessionList(
                      groupId: activeGroupId,
                      sessions: sessions,
                      onReorder: (oldIndex, slot) => mgr.moveSessionInGroup(
                        activeGroupId,
                        oldIndex,
                        slot > oldIndex ? slot - 1 : slot,
                      ),
                      tileBuilder: (context, s, tileKey) => Consumer(
                        builder: (context, tileRef, child) => _SessionTile(
                          key: tileKey,
                          session: s,
                          paneNumber: tileRef.watch(
                            sessionPaneLayoutsProvider.select(
                              (layouts) =>
                                  (layouts[activeGroupId]?.panes.indexWhere(
                                        (p) => p.sessionId == s.id,
                                      ) ??
                                      -1) +
                                  1,
                            ),
                          ),
                          selected: s.id == activeId,
                          statusColor: _statusColor(s.status),
                          busy: tileRef.watch(
                            sessionActivityProvider.select(
                              (activity) => activity[s.id] ?? false,
                            ),
                          ),
                          attention: tileRef.watch(
                            sessionAttentionProvider.select(
                              (attention) => attention[s.id],
                            ),
                          ),
                          onTap: () {
                            ref
                                .read(activeSessionIdProvider.notifier)
                                .set(s.id);
                            onSessionSelected?.call();
                          },
                          onShowMenu: (position) =>
                              _showSessionMenu(railContext, ref, s, position),
                          onClose: () => unawaited(
                            requestCloseSession(railContext, ref, s),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRenameDialog extends StatefulWidget {
  const _SessionRenameDialog({
    required this.initialTitle,
    required this.hintText,
  });

  final String initialTitle;
  final String hintText;

  @override
  State<_SessionRenameDialog> createState() => _SessionRenameDialogState();
}

class _SessionRenameDialogState extends State<_SessionRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController.fromValue(
      TextEditingValue(
        text: widget.initialTitle,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialTitle.length,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('세션 이름 변경'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: '세션 이름',
        hintText: widget.hintText,
      ),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('취소'),
      ),
      FilledButton(onPressed: _save, child: const Text('저장')),
    ],
  );
}

enum _SessionAction {
  terminalSettings,
  hostTerminalDefaults,
  launchAgent,
  reviewAgentChanges,
  duplicate,
  moveGroup,
  rename,
  remoteSessions,
  close,
}

class _SessionMenuItem extends PopupMenuItem<_SessionAction> {
  _SessionMenuItem({
    required _SessionAction value,
    required IconData icon,
    required String label,
  }) : super(
         value: value,
         height: 46,
         child: _SessionMenuItemBody(icon: icon, label: label),
       );
}

class _SessionMenuItemBody extends StatelessWidget {
  const _SessionMenuItemBody({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: VibeColors.onSurfaceMuted, size: 19),
        const SizedBox(width: 14),
        Text(
          label,
          style: const TextStyle(
            color: VibeColors.onSurfaceMuted,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({
    required this.groups,
    required this.activeGroupId,
    required this.sessionCounts,
    required this.onChanged,
    required this.onManageGroups,
  });

  /// 드롭다운에 보일 그룹 목록. 빌드에 따라 숨긴 그룹은 빠져 있다.
  final List<SessionGroup> groups;
  final String activeGroupId;
  final Map<String, int> sessionCounts;
  final ValueChanged<String> onChanged;

  /// 그룹 추가·이름 변경·삭제를 한곳에서 하는 관리 창을 연다.
  final VoidCallback onManageGroups;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: '세션 그룹 선택',
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: VibeColors.surfaceHigh,
                  border: Border.all(color: VibeColors.borderSoft),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: activeGroupId,
                    isExpanded: true,
                    dropdownColor: VibeColors.surfaceHigh,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: VibeColors.onSurfaceDim,
                      size: 19,
                    ),
                    selectedItemBuilder: (context) => [
                      for (final group in groups)
                        _SelectedGroupLabel(group: group),
                    ],
                    items: [
                      for (final group in groups)
                        DropdownMenuItem(
                          value: group.id,
                          child: _GroupMenuLabel(
                            group: group,
                            count: sessionCounts[group.id] ?? 0,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      onChanged(value);
                    },
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: '그룹 관리',
            child: SizedBox.square(
              dimension: 38,
              child: IconButton(
                key: const ValueKey('rail-group-manage'),
                onPressed: onManageGroups,
                icon: const Icon(Icons.folder_open_outlined, size: 19),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 세션 그룹 선택기 바로 아래에 두는 도구 모음. 새 세션 만들기, 여러 세션
/// 조작, 이전/다음 세션 전환, Agent 작업공간 열기를 아이콘 한 줄로 모아
/// 하단 전용 버튼(예전 "새 세션" 풀폭 버튼)을 대신한다.
class _RailToolbar extends StatelessWidget {
  const _RailToolbar({
    required this.onNewSession,
    this.onBulk,
    this.onPreviousSession,
    this.onNextSession,
    this.onOpenAgentWorktrees,
  });

  final VoidCallback onNewSession;
  final VoidCallback? onBulk;
  final VoidCallback? onPreviousSession;
  final VoidCallback? onNextSession;
  final VoidCallback? onOpenAgentWorktrees;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Row(
        children: [
          _RailToolbarButton(
            key: const ValueKey('rail-toolbar-new-session'),
            tooltip: '새 세션',
            icon: Icons.add,
            onPressed: onNewSession,
          ),
          _RailToolbarButton(
            key: const ValueKey('rail-toolbar-bulk'),
            tooltip: '여러 세션 조작',
            icon: Icons.checklist,
            onPressed: onBulk,
          ),
          _RailToolbarButton(
            key: const ValueKey('rail-toolbar-prev'),
            tooltip: '이전 세션',
            icon: Icons.keyboard_arrow_up,
            onPressed: onPreviousSession,
          ),
          _RailToolbarButton(
            key: const ValueKey('rail-toolbar-next'),
            tooltip: '다음 세션',
            icon: Icons.keyboard_arrow_down,
            onPressed: onNextSession,
          ),
          if (onOpenAgentWorktrees != null)
            _RailToolbarButton(
              key: const ValueKey('rail-toolbar-agent-worktrees'),
              tooltip: 'Agent 작업공간',
              icon: Icons.account_tree_outlined,
              onPressed: onOpenAgentWorktrees,
            ),
        ],
      ),
    );
  }
}

class _RailToolbarButton extends StatelessWidget {
  const _RailToolbarButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: IconButton(onPressed: onPressed, icon: Icon(icon, size: 19)),
      ),
    );
  }
}

class _SelectedGroupLabel extends StatelessWidget {
  const _SelectedGroupLabel({required this.group});

  final SessionGroup group;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.folder_open_outlined,
          size: 17,
          color: VibeColors.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VibeColors.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupMenuLabel extends StatelessWidget {
  const _GroupMenuLabel({required this.group, required this.count});

  final SessionGroup group;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          group.isFixed ? Icons.folder_special_outlined : Icons.folder_outlined,
          color: VibeColors.onSurfaceMuted,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VibeColors.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count',
          style: const TextStyle(
            color: VibeColors.onSurfaceDim,
            fontFamily: kMonoFontFamily,
            fontFamilyFallback: kMonoFontFallback,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 버전 라벨 옆의 `↑ 0.13.1` 배지. 새 버전이 있을 때만 그려지고, 누르면
/// 릴리즈 페이지를 연다. 시작 다이얼로그를 "나중에"로 닫은 뒤에도 업데이트가
/// 있다는 사실이 눈에 남도록 한다.
class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.version, required this.onTap});

  final String version;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'v$version 업데이트가 있습니다. 눌러서 릴리즈 열기',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: VibeColors.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_upward_rounded,
                size: 10,
                color: VibeColors.accent,
              ),
              const SizedBox(width: 2),
              Text(
                version,
                style: const TextStyle(
                  color: VibeColors.accent,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailHeader extends ConsumerWidget {
  const _RailHeader({required this.onOpenSettings, this.onCollapse});

  final VoidCallback onOpenSettings;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingUpdate = ref.watch(pendingUpdateProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.terminal, color: VibeColors.accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vibe Terminal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                // 에디션(Core/Pro)과 버전. 빌드 번호 등 상세는 설정 > About.
                Row(
                  children: [
                    Flexible(
                      // Core(공개판)에서는 클릭으로 릴리즈 노트를 연다. Pro는
                      // GitHub Release로 배포하지 않으므로 아무 일도 하지
                      // 않는다.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: AppEdition.current == AppEdition.core
                            ? () => showReleaseNotesDialog(
                                context: context,
                                currentVersion: kAppVersion,
                                load: ref
                                    .read(updateCheckerProvider)
                                    .listReleases,
                                openUrl: ref.read(externalUrlLauncherProvider),
                              )
                            : null,
                        child: Text(
                          appEditionLabel(AppEdition.current, kAppVersion),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VibeColors.onSurfaceDim,
                            fontFamily: kMonoFontFamily,
                            fontFamilyFallback: kMonoFontFallback,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    if (pendingUpdate != null) ...[
                      const SizedBox(width: 6),
                      _UpdateBadge(
                        version: pendingUpdate.version,
                        onTap: () => ref.read(externalUrlLauncherProvider)(
                          pendingUpdate.url,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onCollapse != null)
            IconButton(
              tooltip: '좌측 패널 접기',
              onPressed: onCollapse,
              icon: const Icon(Icons.keyboard_double_arrow_left, size: 19),
            ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

class _EmptyRail extends StatelessWidget {
  const _EmptyRail();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(18),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          '아직 열린 세션이 없습니다',
          style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 13),
        ),
      ),
    );
  }
}

class _AttentionSummary extends StatelessWidget {
  const _AttentionSummary({
    required this.blockedCount,
    required this.doneCount,
    required this.onTap,
  });

  final int blockedCount;
  final int doneCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Material(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: const ValueKey('agent-attention-summary'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: VibeColors.borderSoft),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  size: 16,
                  color: VibeColors.accent,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Agent 확인 필요',
                    style: TextStyle(
                      color: VibeColors.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (blockedCount > 0)
                  _AttentionCount(
                    icon: Icons.priority_high_rounded,
                    count: blockedCount,
                    color: VibeColors.statusError,
                    tooltip: '입력 또는 승인 대기 $blockedCount개',
                  ),
                if (blockedCount > 0 && doneCount > 0) const SizedBox(width: 6),
                if (doneCount > 0)
                  _AttentionCount(
                    icon: Icons.check_rounded,
                    count: doneCount,
                    color: VibeColors.accent,
                    tooltip: '완료 후 미확인 $doneCount개',
                  ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 17,
                  color: VibeColors.onSurfaceDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttentionCount extends StatelessWidget {
  const _AttentionCount({
    required this.icon,
    required this.count,
    required this.color,
    required this.tooltip,
  });

  final IconData icon;
  final int count;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 2),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatefulWidget {
  const _SessionTile({
    super.key,
    required this.session,
    this.paneNumber = 0,
    required this.selected,
    required this.statusColor,
    required this.busy,
    required this.attention,
    required this.onTap,
    required this.onShowMenu,
    required this.onClose,
  });

  final int paneNumber;
  final SessionInfo session;
  final bool selected;
  final Color statusColor;

  /// 최근 출력 활동이 있어 작업 중(busy)인지 여부.
  final bool busy;

  /// Agent로 식별된 세션의 작업·승인 대기·미확인 완료 상태.
  final SessionAttention? attention;

  final VoidCallback onTap;
  final Future<void> Function(Offset position) onShowMenu;
  final VoidCallback onClose;

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _expanded = false;
  bool _hovering = false;

  void showMenuAtCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    unawaited(
      widget.onShowMenu(box.localToGlobal(box.size.center(Offset.zero))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildCompact();
  }

  /// 세션 레일: 화면 크기와 무관하게 항상 한 줄(세션명 + ▾ + ✕).
  /// 세션명 탭=바로 열기, ▾ 탭=정보(endpoint) 펼침. 행 전체는 길게 눌러
  /// 드래그하면 레일 안에서 순서 변경, 터미널 칸에서 분할 배치를 한다([_SessionList]).
  Widget _buildCompact() {
    final host = widget.session.host;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: widget.selected
            ? VibeColors.surfacePressed
            : VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          onSecondaryTapDown: (details) =>
              unawaited(widget.onShowMenu(details.globalPosition)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.selected
                    ? VibeColors.accent
                    : VibeColors.borderSoft,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (AgentBrand.forHint(widget.attention?.agentHint)
                        case final brand?) ...[
                      const SizedBox(width: 6),
                      AgentBrandBadge(brand: brand),
                    ],
                    if (widget.session.appId != null) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: '앱 세션',
                        child: Icon(
                          Icons.apps_outlined,
                          key: Key('session-app-badge-${widget.session.id}'),
                          size: 16,
                          color: VibeColors.onSurfaceDim,
                        ),
                      ),
                    ],
                    if (widget.paneNumber > 0 && _hovering) ...[
                      Tooltip(
                        message: '분할 창 ${widget.paneNumber}번에 열려 있음',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: VibeColors.statusConnected.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.view_column_outlined,
                                size: 11,
                                color: VibeColors.statusConnected,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${widget.paneNumber}',
                                style: const TextStyle(
                                  color: VibeColors.statusConnected,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.session.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VibeColors.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (widget.attention case final attention?)
                      _AgentAttentionIndicator(attention: attention)
                    else if (widget.busy)
                      const _BusyIndicator(),
                    _MiniTileButton(
                      icon: _expanded ? Icons.expand_less : Icons.expand_more,
                      tooltip: '세션 정보',
                      onTap: () => setState(() => _expanded = !_expanded),
                    ),
                    _MiniTileButton(
                      icon: Icons.close,
                      tooltip: '세션 닫기',
                      onTap: widget.onClose,
                    ),
                  ],
                ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host.endpointLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VibeColors.onSurfaceDim,
                            fontFamily: kMonoFontFamily,
                            fontFamilyFallback: kMonoFontFallback,
                            fontSize: 11,
                          ),
                        ),
                        if (host.keepsRemoteSession) ...[
                          const SizedBox(height: 3),
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.link_rounded,
                                size: 12,
                                color: VibeColors.accent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '작업 이어가기',
                                style: TextStyle(
                                  color: VibeColors.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (widget.session.agentWorkspace
                            case final workspace?) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.account_tree_outlined,
                                size: 12,
                                color: VibeColors.onSurfaceDim,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  workspace.isolatedWorktree
                                      ? '${workspace.cli.label} · ${workspace.branchName}'
                                      : '${workspace.cli.label} · 공유 작업 폴더',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: VibeColors.onSurfaceDim,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (widget.attention case final attention?) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${attention.agentHint?.toUpperCase() ?? 'SESSION'} · '
                            '${attention.state.label} · ${attention.source.label}',
                            style: TextStyle(
                              color: attention.state.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            attention.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: VibeColors.onSurfaceDim,
                              fontSize: 10,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// compact 타일용 작은 탭 아이콘. 부모 InkWell보다 먼저 탭을 가져가
/// 세션 열기(onTap)와 충돌하지 않는다.
class _MiniTileButton extends StatelessWidget {
  const _MiniTileButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: VibeColors.onSurfaceDim),
        ),
      ),
    );
  }
}

/// 세션이 작업 중(busy)일 때 보여주는 작은 회전 인디케이터.
class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: '작업 중',
        child: SizedBox(
          width: 13,
          height: 13,
          child: RepaintBoundary(
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: VibeColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentAttentionIndicator extends StatelessWidget {
  const _AgentAttentionIndicator({required this.attention});

  final SessionAttention attention;

  @override
  Widget build(BuildContext context) {
    if (attention.state == SessionAttentionState.working) {
      return const _BusyIndicator();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message:
            '${attention.agentHint ?? 'SESSION'} · ${attention.state.label}',
        child: Icon(
          attention.state.icon,
          size: 15,
          color: attention.state.color,
        ),
      ),
    );
  }
}

extension on SessionAttentionState {
  String get label => switch (this) {
    SessionAttentionState.idle => '대기',
    SessionAttentionState.working => '작업 중',
    SessionAttentionState.done => '완료 · 미확인',
    SessionAttentionState.blocked => '입력 필요',
  };

  IconData get icon => switch (this) {
    SessionAttentionState.idle => Icons.circle,
    SessionAttentionState.working => Icons.sync,
    SessionAttentionState.done => Icons.check_circle_outline,
    SessionAttentionState.blocked => Icons.error_outline,
  };

  Color get color => switch (this) {
    SessionAttentionState.idle => VibeColors.statusConnected,
    SessionAttentionState.working => VibeColors.accent,
    SessionAttentionState.done => VibeColors.accent,
    SessionAttentionState.blocked => VibeColors.statusError,
  };
}

/// 세션 행 하나를 통째로 드래그하는 목록. 전용 핸들 없이 행을 끌어
/// 레일 안의 다른 행 위·아래에 놓으면 순서가 바뀌고, 터미널 칸
/// ([SessionPaneDeck]의 [DragTarget]) 위에 놓으면 그 칸에 배치된다.
///
/// 클릭/탭은 세션 선택으로 남긴다. 마우스(데스크톱)는 slop 이상 움직이면 바로
/// 끌리고(즉시 인식하는 [Draggable]은 탭을 가로채므로 [Draggable.affinity]로
/// 거리 기준 인식), 터치는 스크롤과 겹치지 않도록 길게 눌러 끈다. 터치에서
/// 길게 누른 뒤 움직이지 않고 떼면 컨텍스트 메뉴를 연다.
class _SessionList extends StatefulWidget {
  const _SessionList({
    required this.groupId,
    required this.sessions,
    required this.tileBuilder,
    required this.onReorder,
  });

  final String groupId;
  final List<SessionInfo> sessions;

  final Widget Function(
    BuildContext context,
    SessionInfo session,
    GlobalKey<_SessionTileState> tileKey,
  )
  tileBuilder;

  /// [oldIndex]의 세션을 원래 목록 기준 삽입 위치 [slot](0..length) 앞으로 옮긴다.
  final void Function(int oldIndex, int slot) onReorder;

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList>
    with SingleTickerProviderStateMixin {
  static const _gap = 8.0;
  static const _autoScrollEdge = 48.0;
  static const _autoScrollStep = 6.0;

  final _scroll = ScrollController();
  final _tileKeys = <String, GlobalKey<_SessionTileState>>{};
  late final Ticker _ticker;

  /// 드롭 시 삽입될 위치(0..length). null이면 레일 위에 드래그 중이 아님.
  int? _dropSlot;

  /// 이 목록에서 시작한 드래그의 원래 인덱스. 칸에서 끌어온 드래그면 null.
  int? _draggedIndex;
  double _autoScrollDirection = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant _SessionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionIds = widget.sessions.map((session) => session.id).toSet();
    _tileKeys.removeWhere((id, _) => !sessionIds.contains(id));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _touch {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  bool _accepts(PaneSessionDrag drag) =>
      drag.groupId == widget.groupId &&
      widget.sessions.any((s) => s.id == drag.sessionId);

  int _indexOf(String sessionId) =>
      widget.sessions.indexWhere((s) => s.id == sessionId);

  void _setSlot(int? slot) {
    if (_dropSlot == slot) return;
    setState(() => _dropSlot = slot);
  }

  void _drop(PaneSessionDrag drag, int slot) {
    _setSlot(null);
    final oldIndex = _indexOf(drag.sessionId);
    if (oldIndex < 0 || slot == oldIndex || slot == oldIndex + 1) return;
    widget.onReorder(oldIndex, slot);
  }

  // ── 가장자리 자동 스크롤 ───────────────────────────────────────────────

  void _updateAutoScroll(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) return;
    final dy = box.globalToLocal(globalPosition).dy;
    final direction = dy < _autoScrollEdge
        ? -1.0
        : dy > box.size.height - _autoScrollEdge
        ? 1.0
        : 0.0;
    _autoScrollDirection = direction;
    if (direction == 0) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _stopAutoScroll() {
    _autoScrollDirection = 0;
    if (_ticker.isActive) _ticker.stop();
  }

  /// 드래그가 끝났을 때 공통 정리. Draggable은 드래그 도중 행 위젯이
  /// 폐기되면(스크롤로 화면 밖에 나가 재활용되거나 목록이 다시 그려지면)
  /// onDragEnd를 부르지 않는다. 그러면 가장자리 자동 스크롤이 멈추지 않아
  /// 사용자가 스크롤해도 목록이 계속 한쪽으로 끌려간다. onDragCompleted/
  /// onDraggableCanceled는 행이 폐기돼도 호출되므로 거기서도 이 정리를 한다.
  void _finishDrag() {
    if (!mounted) return;
    _draggedIndex = null;
    _stopAutoScroll();
    _setSlot(null);
  }

  void _onTick(Duration _) {
    if (!_scroll.hasClients || _autoScrollDirection == 0) return;
    final position = _scroll.position;
    final next = (position.pixels + _autoScrollDirection * _autoScrollStep)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next != position.pixels) _scroll.jumpTo(next);
  }

  // ── 위젯 ───────────────────────────────────────────────────────────────

  Widget _feedback(SessionInfo session) {
    return Material(
      elevation: 8,
      color: VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VibeColors.accent),
        ),
        child: Text(
          session.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: VibeColors.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _draggableRow(SessionInfo session, Widget tile, GlobalKey tileKey) {
    final data = PaneSessionDrag(session.id, widget.groupId);
    final feedback = _feedback(session);
    final whenDragging = Opacity(opacity: .35, child: tile);
    if (!_touch) {
      return Draggable<PaneSessionDrag>(
        data: data,
        // 축 지정 → 포인터가 slop 이상 움직여야 드래그가 시작되어 클릭(탭)이
        // 살아남는다. 일단 시작되면 어느 방향으로든 끌 수 있다.
        affinity: Axis.vertical,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: whenDragging,
        onDragStarted: () => _draggedIndex = _indexOf(session.id),
        onDragUpdate: (details) => _updateAutoScroll(details.globalPosition),
        onDragEnd: (_) => _finishDrag(),
        onDragCompleted: _finishDrag,
        onDraggableCanceled: (_, _) => _finishDrag(),
        child: tile,
      );
    }
    Offset? dragStart;
    return LongPressDraggable<PaneSessionDrag>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      hapticFeedbackOnStart: true,
      feedback: feedback,
      childWhenDragging: whenDragging,
      onDragStarted: () {
        dragStart = null;
        _draggedIndex = _indexOf(session.id);
      },
      onDragUpdate: (details) {
        dragStart ??= details.globalPosition;
        _updateAutoScroll(details.globalPosition);
      },
      onDragCompleted: _finishDrag,
      onDraggableCanceled: (_, _) => _finishDrag(),
      onDragEnd: (details) {
        _finishDrag();
        // 길게 누른 뒤 거의 움직이지 않고 떼면 메뉴로 취급한다.
        // 제자리 드롭은 자기 행이 받아 no-op이므로 wasAccepted는 보지 않는다.
        final start = dragStart;
        final moved = start == null ? 0.0 : (details.offset - start).distance;
        if (moved < kTouchSlop) {
          (tileKey.currentState as _SessionTileState?)?.showMenuAtCenter();
        }
      },
      child: tile,
    );
  }

  /// 행 하나 = 드롭 대상. 포인터가 위쪽 절반이면 이 행 앞, 아래쪽이면 뒤에 삽입.
  Widget _row(BuildContext _, int index) {
    final session = widget.sessions[index];
    final last = index == widget.sessions.length - 1;
    // 목록 갱신 중에도 세션 행의 상태와 context를 유지한다.
    final tileKey = _tileKeys.putIfAbsent(
      session.id,
      () => GlobalKey<_SessionTileState>(),
    );
    // Builder의 context로 이 행(RenderBox)의 위치를 얻는다. ListView builder의
    // context는 sliver 자체라 행 좌표로 쓸 수 없다.
    return Builder(
      key: ValueKey('session-row-${session.id}'),
      builder: (rowContext) => DragTarget<PaneSessionDrag>(
        onWillAcceptWithDetails: (details) => _accepts(details.data),
        onMove: (details) {
          final box = rowContext.findRenderObject();
          if (box is! RenderBox) return;
          final local = box.globalToLocal(details.offset);
          _setSlot(local.dy < box.size.height / 2 ? index : index + 1);
        },
        onLeave: (_) => _setSlot(null),
        onAcceptWithDetails: (details) =>
            _drop(details.data, _dropSlot ?? index),
        builder: (context, _, _) {
          final slot = _dropSlot;
          final showTop = slot == index && !_isOwnSlot(index);
          final showBottom =
              last && slot == index + 1 && !_isOwnSlot(index + 1);
          final tile = widget.tileBuilder(context, session, tileKey);
          return Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : _gap),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _draggableRow(session, tile, tileKey),
                if (showTop) _insertionLine(top: -(_gap / 2 + 1)),
                if (showBottom) _insertionLine(bottom: -(_gap / 2 + 1)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 드래그 중인 세션 자신의 바로 앞/뒤 슬롯은 순서가 바뀌지 않으므로 표시하지 않는다.
  /// 터미널 칸에서 끌어온 드래그([_draggedIndex]가 null)는 항상 표시한다.
  bool _isOwnSlot(int slot) {
    final dragged = _draggedIndex;
    return dragged != null && (slot == dragged || slot == dragged + 1);
  }

  Widget _insertionLine({double? top, double? bottom}) {
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: VibeColors.accent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 목록 아래 빈 공간에 놓으면 맨 끝으로 이동.
    return DragTarget<PaneSessionDrag>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: (_) => _setSlot(widget.sessions.length),
      onLeave: (_) => _setSlot(null),
      onAcceptWithDetails: (details) =>
          _drop(details.data, widget.sessions.length),
      builder: (context, _, _) => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(10),
        itemCount: widget.sessions.length,
        itemBuilder: _row,
      ),
    );
  }
}
