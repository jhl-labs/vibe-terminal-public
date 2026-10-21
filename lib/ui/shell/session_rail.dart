import 'session_close_dialog.dart';
import '../common/device_aware_draggable.dart';
import '../settings/terminal_preferences_editor.dart';
import '../../session/session_pane_layout.dart';
import 'panes/pane_preset_icon.dart';
import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_launcher.dart';
import '../../agent/autopilot/autopilot_controller.dart';
import '../../agent/autopilot/autopilot_state.dart';
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
import 'release_notes_dialog.dart';
import '../../session/server_work_tabs.dart';
import 'session_group_manager.dart';
import 'session_status_indicators.dart';
import 'session_info_tooltip.dart';
import 'session_tab_group_header.dart';
import '../../session/session_tab_group.dart';
import '../../session/session_tab_group_controller.dart';
import '../../session/session_tab_layout.dart';

/// 좌측 세로탭 세션 패널. 데스크톱 레일/모바일 drawer 양쪽에서 재사용.
class SessionRail extends ConsumerWidget {
  const SessionRail({
    super.key,
    required this.onNewSession,
    required this.onDuplicateSession,
    required this.onOpenSettings,
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
        ..._autopilotMenuItems(ref, session),
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
        ..._tabGroupMenuItems(ref, session),
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
            session.status == SessionStatus.connected &&
            !session.fellBackToDirectSsh)
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
      case _SessionAction.toggleAutopilot:
        ref.read(agentAutopilotProvider.notifier).toggle(session.id);
      case _SessionAction.toggleAutopilotNotifyOnly:
        final controller = ref.read(agentAutopilotProvider.notifier);
        controller.setNotifyOnly(
          session.id,
          !controller.stateOf(session.id).notifyOnly,
        );
      case _SessionAction.duplicate:
        await onDuplicateSession(session);
      case _SessionAction.moveGroup:
        await _moveSessionToGroup(context, ref, session);
      case _SessionAction.addToNewTabGroup:
        ref.read(sessionTabGroupProvider.notifier).addToNewGroup(session.id);
      case _SessionAction.moveToTabGroup:
        final position = _menuPosition(context, globalPosition);
        final targetId = await showMenu<String>(
          context: context,
          position: position,
          color: VibeColors.surfaceHigh,
          items: [
            for (final group in _otherTabGroups(ref, session))
              PopupMenuItem(
                key: ValueKey('move-to-tab-group-${group.id}'),
                value: group.id,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: group.color.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(group.name, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
          ],
        );
        if (targetId != null) {
          ref
              .read(sessionTabGroupProvider.notifier)
              .moveToGroup(session.id, targetId);
        }
      case _SessionAction.removeFromTabGroup:
        ref.read(sessionTabGroupProvider.notifier).removeFromGroup(session.id);
      case _SessionAction.terminalSettings:
        await _configureTerminal(context, ref, session, forHost: false);
      case _SessionAction.hostTerminalDefaults:
        await _configureTerminal(context, ref, session, forHost: true);
      case _SessionAction.rename:
        await _renameSession(context, ref, session);
      case _SessionAction.remoteSessions:
        FocusScope.of(context).unfocus();
        ref.read(serverWorkTabsProvider.notifier).open(session);
        onSessionSelected?.call();
      case _SessionAction.close:
        await requestCloseSession(context, ref, session);
    }
  }

  /// 세션이 속한 작업공간에서 옮겨 갈 수 있는(현재 소속이 아닌) 탭 그룹.
  List<SessionTabGroup> _otherTabGroups(WidgetRef ref, SessionInfo session) => [
    for (final group
        in ref
            .read(sessionTabGroupProvider.notifier)
            .groupsWithMembers(session.groupId))
      if (group.id != session.tabGroupId) group,
  ];

  List<PopupMenuEntry<_SessionAction>> _tabGroupMenuItems(
    WidgetRef ref,
    SessionInfo session,
  ) {
    final grouped =
        ref.read(sessionTabGroupProvider).byId(session.tabGroupId) != null;
    return [
      _SessionMenuItem(
        key: const ValueKey('session-add-to-new-tab-group'),
        value: _SessionAction.addToNewTabGroup,
        icon: Icons.add_box_outlined,
        label: '새 탭 그룹에 추가',
      ),
      if (_otherTabGroups(ref, session).isNotEmpty)
        _SessionMenuItem(
          key: const ValueKey('session-move-to-tab-group'),
          value: _SessionAction.moveToTabGroup,
          icon: Icons.drive_file_move_rtl_outlined,
          label: '탭 그룹으로 이동 ▸',
        ),
      if (grouped)
        _SessionMenuItem(
          key: const ValueKey('session-remove-from-tab-group'),
          value: _SessionAction.removeFromTabGroup,
          icon: Icons.layers_clear_outlined,
          label: '탭 그룹에서 제거',
        ),
    ];
  }

  void _activateGroup(WidgetRef ref, String groupId) {
    ref.read(serverWorkTabsProvider.notifier).showTerminal();
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
    listenSessionTabGroupCleanup(ref);
    final allSessions = ref.watch(sessionManagerProvider);
    final groupState = ref.watch(sessionGroupProvider);
    final activeGroupId = groupState.activeGroupId;
    final sessions = [
      for (final session in allSessions)
        if (session.groupId == activeGroupId) session,
    ];
    final tabBlocks = buildSessionTabBlocks(
      sessions,
      tabGroupOf: (session) => session.tabGroupId,
      groups: ref.watch(sessionTabGroupProvider).mapForWorkspace(activeGroupId),
    );
    final activeId = ref.watch(activeSessionIdProvider);
    final archiveState = ref.watch(serverWorkTabsProvider);
    final archiveTabs = archiveState.tabs.where(
      (tab) => tab.groupId == activeGroupId,
    );
    final archiveTiles = [
      for (final tab in archiveTabs)
        if (tab.connection(allSessions) case final connection?)
          _ServerWorkTabTile(
            key: ValueKey('server-work-tab-${tab.id}'),
            hostAlias: connection.host.alias,
            selected: archiveState.activeId == tab.id,
            busy: archiveState.busyIds.contains(tab.id),
            onTap: () {
              FocusScope.of(context).unfocus();
              ref.read(serverWorkTabsProvider.notifier).select(tab.id);
              onSessionSelected?.call();
            },
            onClose: () =>
                ref.read(serverWorkTabsProvider.notifier).close(tab.id),
          ),
    ];
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
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    Expanded(
                      child: sessions.isEmpty
                          ? const _EmptyRail()
                          : _SessionList(
                              groupId: activeGroupId,
                              blocks: tabBlocks,
                              onDrop: (sessionId, target) => ref
                                  .read(sessionTabGroupProvider.notifier)
                                  .dropSession(sessionId, target),
                              headerBuilder: (context, block, highlighted) =>
                                  Consumer(
                                    builder: (context, headerRef, child) =>
                                        SessionTabGroupHeader(
                                          group: block.group,
                                          memberCount: block.members.length,
                                          highlighted: highlighted,
                                          summaryState: headerRef.watch(
                                            sessionAttentionProvider.select(
                                              (
                                                attention,
                                              ) => strongestAttentionState(
                                                block.members.map(
                                                  (s) => attention[s.id]?.state,
                                                ),
                                              ),
                                            ),
                                          ),
                                          onToggleCollapsed: () => ref
                                              .read(
                                                sessionTabGroupProvider
                                                    .notifier,
                                              )
                                              .toggleCollapsed(block.group.id),
                                          onShowMenu: (position) =>
                                              showSessionTabGroupMenu(
                                                railContext,
                                                ref,
                                                block.group,
                                                position,
                                              ),
                                        ),
                                  ),
                              tileBuilder: (context, s, tileKey) => Consumer(
                                builder: (context, tileRef, child) =>
                                    _SessionTile(
                                      key: tileKey,
                                      session: s,
                                      paneNumber: tileRef.watch(
                                        sessionPaneLayoutsProvider.select(
                                          (layouts) =>
                                              (layouts[activeGroupId]?.panes
                                                      .indexWhere(
                                                        (p) =>
                                                            p.sessionId == s.id,
                                                      ) ??
                                                  -1) +
                                              1,
                                        ),
                                      ),
                                      selected:
                                          archiveState.activeId == null &&
                                          s.id == activeId,
                                      statusColor: sessionStatusColor(s.status),
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
                                      aiConfigured: tileRef.watch(
                                        appSettingsProvider.select(
                                          (s) => s.ai.isConfigured,
                                        ),
                                      ),
                                      autopilot: tileRef.watch(
                                        agentAutopilotProvider.select(
                                          (states) =>
                                              states[s.id]?.enabled == true
                                              ? states[s.id]
                                              : null,
                                        ),
                                      ),
                                      onTap: () {
                                        ref
                                            .read(
                                              serverWorkTabsProvider.notifier,
                                            )
                                            .showTerminal();
                                        ref
                                            .read(
                                              activeSessionIdProvider.notifier,
                                            )
                                            .set(s.id);
                                        onSessionSelected?.call();
                                      },
                                      onShowMenu: (position) =>
                                          _showSessionMenu(
                                            railContext,
                                            ref,
                                            s,
                                            position,
                                          ),
                                      onClose: () => unawaited(
                                        requestCloseSession(
                                          railContext,
                                          ref,
                                          s,
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                    ),
                    if (archiveTiles.isNotEmpty)
                      _ServerWorkTabsFooter(
                        groupId: activeGroupId,
                        maxHeight: constraints.maxHeight * 0.4,
                        tabs: archiveTiles,
                      ),
                  ],
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
  toggleAutopilot,
  toggleAutopilotNotifyOnly,
  duplicate,
  moveGroup,
  addToNewTabGroup,
  moveToTabGroup,
  removeFromTabGroup,
  rename,
  remoteSessions,
  close,
}

class _SessionMenuItem extends PopupMenuItem<_SessionAction> {
  _SessionMenuItem({
    required _SessionAction value,
    required IconData icon,
    required String label,
    String? detail,
    super.key,
  }) : super(
         value: value,
         height: detail == null ? 46 : 58,
         child: _SessionMenuItemBody(icon: icon, label: label, detail: detail),
       );
}

/// Agent 자율사용 토글. 연결된 세션에서 claude·codex·opencode가 보일 때만 나온다.
/// AI 설정이 없어도 켤 수 있다(조용한 멈춤 판정만 생략).
List<PopupMenuEntry<_SessionAction>> _autopilotMenuItems(
  WidgetRef ref,
  SessionInfo session,
) {
  final controller = ref.read(agentAutopilotProvider.notifier);
  if (!controller.isAvailableFor(session.id)) return const [];
  final state = controller.stateOf(session.id);
  return [
    _SessionMenuItem(
      key: const ValueKey('session-autopilot-toggle'),
      value: _SessionAction.toggleAutopilot,
      icon: state.enabled ? Icons.check_box : Icons.check_box_outline_blank,
      label: 'Agent 자율사용',
    ),
    if (state.enabled)
      _SessionMenuItem(
        key: const ValueKey('session-autopilot-notify-only'),
        value: _SessionAction.toggleAutopilotNotifyOnly,
        icon: state.notifyOnly
            ? Icons.check_box
            : Icons.check_box_outline_blank,
        label: '자동 입력 없이 알림만',
      ),
  ];
}

class _SessionMenuItemBody extends StatelessWidget {
  const _SessionMenuItemBody({
    required this.icon,
    required this.label,
    this.detail,
  });

  final IconData icon;
  final String label;

  /// 항목 아래 작은 상태 줄(진행 중·실패 원인).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      label,
      style: const TextStyle(
        color: VibeColors.onSurfaceMuted,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
    return Row(
      children: [
        Icon(icon, color: VibeColors.onSurfaceMuted, size: 19),
        const SizedBox(width: 14),
        if (detail case final detail?)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          )
        else
          title,
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
                Row(
                  children: [
                    Flexible(
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
    this.autopilot,
    this.aiConfigured = true,
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

  /// Agent 자율사용이 켜진 세션의 상태. 꺼져 있으면 null.
  final AutopilotState? autopilot;
  final bool aiConfigured;

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
                      // 이름 영역에만 정보 툴팁을 둔다. 작은 버튼의 툴팁과
                      // 겹치지 않게 하기 위해서다.
                      child: SessionInfoTooltip(
                        session: widget.session,
                        attention: widget.attention,
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
                    ),
                    if (widget.autopilot case final autopilot?)
                      _AutopilotBadge(
                        state: autopilot,
                        aiConfigured: widget.aiConfigured,
                      ),
                    if (widget.attention case final attention?)
                      AgentAttentionIndicator(
                        state: attention.state,
                        agentHint: attention.agentHint,
                      )
                    else if (widget.busy)
                      const SessionBusyIndicator(),
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
                        if (widget.autopilot case final autopilot?) ...[
                          const SizedBox(height: 5),
                          Text(
                            autopilot.statusLabel,
                            key: const ValueKey('session-autopilot-status'),
                            style: TextStyle(
                              color: _autopilotColor(autopilot),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (autopilot.lastAction case final action?) ...[
                            const SizedBox(height: 2),
                            Text(
                              action,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: VibeColors.onSurfaceDim,
                                fontSize: 10,
                                height: 1.25,
                              ),
                            ),
                          ],
                          if (autopilot.lastVerdict case final verdict?) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${verdict.source.label}: ${verdict.reason}',
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

Color _autopilotColor(AutopilotState state) => switch (state.phase) {
  AutopilotPhase.exhausted => VibeColors.statusError,
  AutopilotPhase.waitingUsageReset => VibeColors.warning,
  AutopilotPhase.idle => VibeColors.onSurfaceDim,
  _ => VibeColors.accent,
};

/// Agent 자율사용이 켜진 세션의 배지. 동작 중이면 accent, 한도 대기는 경고색, 포기는 빨강.
class _AutopilotBadge extends StatelessWidget {
  const _AutopilotBadge({required this.state, required this.aiConfigured});

  final AutopilotState state;
  final bool aiConfigured;

  @override
  Widget build(BuildContext context) {
    final message = aiConfigured
        ? state.statusLabel
        : '${state.statusLabel}\nAI 설정 없음: 조용한 멈춤 판정은 생략';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: message,
        child: Icon(
          Icons.auto_mode,
          key: const ValueKey('session-autopilot-badge'),
          size: 14,
          color: _autopilotColor(state),
        ),
      ),
    );
  }
}

/// 세로 탭 목록의 한 줄: 탭 그룹 머리 행 또는 세션 행.
sealed class _RailEntry {
  const _RailEntry();
}

class _HeaderEntry extends _RailEntry {
  const _HeaderEntry(this.block);

  final SessionTabGroupBlock<SessionInfo> block;
}

class _SessionEntry extends _RailEntry {
  const _SessionEntry(this.session, this.group);

  final SessionInfo session;

  /// 세션이 속한(펼쳐진) 탭 그룹. 그룹 없는 세션이면 null.
  final SessionTabGroup? group;
}

/// 드래그 중 포인터가 가리키는 드롭 위치와 표시 방법.
class _DropHover {
  const _DropHover(
    this.index,
    this.target, {
    this.lineAfter,
    this.joins = false,
  });

  /// 가리키는 행([_RailEntry]) 인덱스.
  final int index;
  final SessionDropTarget target;

  /// 삽입선을 행 아래(true)/위(false)에 그린다. null이면 선 없음.
  final bool? lineAfter;

  /// 접힌 탭 그룹 머리 행 위: 선 대신 머리 행을 강조한다.
  final bool joins;

  @override
  bool operator ==(Object other) =>
      other is _DropHover &&
      other.index == index &&
      other.target == target &&
      other.lineAfter == lineAfter &&
      other.joins == joins;

  @override
  int get hashCode => Object.hash(index, target, lineAfter, joins);
}

/// 세션 행 하나를 통째로 드래그하는 목록. 전용 핸들 없이 행을 끌어
/// 레일 안의 다른 행 위·아래에 놓으면 순서가 바뀌고, 터미널 칸
/// ([SessionPaneDeck]의 [DragTarget]) 위에 놓으면 그 칸에 배치된다.
///
/// 탭 그룹 안 행에 놓으면 그 그룹에 들어가고, 그룹 밖 행·목록 아래 빈 공간에
/// 놓으면 그룹에서 빠진다. 탭 그룹 머리 행의 위쪽은 그룹 앞(그룹 밖),
/// 아래쪽은 그룹 맨 앞, 접힌 그룹은 그룹 끝으로 들어간다.
///
/// 클릭/탭은 세션 선택으로 남긴다. 플랫폼과 무관하게 마우스는 slop 이상
/// 움직이면 바로 끌리고, 터치는 스크롤과 겹치지 않도록 길게 눌러 끈다. 터치에서
/// 길게 누른 뒤 움직이지 않고 떼면 컨텍스트 메뉴를 연다.
class _SessionList extends StatefulWidget {
  const _SessionList({
    required this.groupId,
    required this.blocks,
    required this.tileBuilder,
    required this.headerBuilder,
    required this.onDrop,
  });

  final String groupId;

  /// 작업공간 세션을 탭 그룹 단위로 묶은 목록([buildSessionTabBlocks]).
  final List<SessionTabBlock<SessionInfo>> blocks;

  final Widget Function(
    BuildContext context,
    SessionInfo session,
    GlobalKey<_SessionTileState> tileKey,
  )
  tileBuilder;

  final Widget Function(
    BuildContext context,
    SessionTabGroupBlock<SessionInfo> block,
    bool highlighted,
  )
  headerBuilder;

  /// 세션을 [SessionDropTarget] 위치·소속으로 옮긴다.
  final void Function(String sessionId, SessionDropTarget target) onDrop;

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

  /// 화면에 그리는 행(접힌 그룹의 멤버 제외).
  late List<_RailEntry> _entries;

  /// 작업공간 세션 전체의 현재 배치(접힌 그룹의 멤버 포함).
  late List<SessionPlacement> _placements;

  /// 드롭될 위치. null이면 레일 위에 드래그 중이 아니거나 제자리다.
  _DropHover? _hover;

  // 드롭 위치 변경이 행을 리빌드해도 시작점과 이동 이력을 유지한다.
  Offset? _dragOrigin;
  bool _longPressDrag = false;
  bool _dragMoved = false;
  double _autoScrollDirection = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _rebuildEntries();
  }

  @override
  void didUpdateWidget(covariant _SessionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildEntries();
    final sessionIds = _placements.map((p) => p.id).toSet();
    _tileKeys.removeWhere((id, _) => !sessionIds.contains(id));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _rebuildEntries() {
    final entries = <_RailEntry>[];
    final placements = <SessionPlacement>[];
    for (final block in widget.blocks) {
      switch (block) {
        case SessionTabSingle(:final item):
          entries.add(_SessionEntry(item, null));
          placements.add(SessionPlacement(item.id, null));
        case SessionTabGroupBlock(:final group, :final members):
          entries.add(_HeaderEntry(block));
          for (final member in members) {
            if (!group.collapsed) entries.add(_SessionEntry(member, group));
            placements.add(SessionPlacement(member.id, group.id));
          }
      }
    }
    _entries = entries;
    _placements = placements;
  }

  bool _accepts(PaneSessionDrag drag) =>
      drag.groupId == widget.groupId &&
      _placements.any((p) => p.id == drag.sessionId);

  /// 놓아도 순서·소속이 그대로인 위치(자기 자리)인지.
  bool _isNoOp(String sessionId, SessionDropTarget target) {
    final next = placeSession(_placements, sessionId, target);
    if (next.length != _placements.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i] != _placements[i]) return false;
    }
    return true;
  }

  void _setHover(_DropHover? hover) {
    if (_hover == hover) return;
    setState(() => _hover = hover);
  }

  /// 포인터가 [index] 행 높이의 [fraction] 지점(0=위, 1=아래)에 있을 때의
  /// 드롭 위치.
  _DropHover _hoverAt(int index, double fraction) {
    switch (_entries[index]) {
      case _SessionEntry(:final session, :final group):
        final after = fraction >= 0.5;
        return _DropHover(
          index,
          SessionDropTarget(
            anchorId: session.id,
            after: after,
            tabGroupId: group?.id,
          ),
          lineAfter: after,
        );
      case _HeaderEntry(:final block):
        final group = block.group;
        final first = block.members.first.id;
        final beforeGroup = fraction < (group.collapsed ? 1 / 3 : 0.5);
        if (beforeGroup) {
          return _DropHover(
            index,
            SessionDropTarget(anchorId: first),
            lineAfter: false,
          );
        }
        if (group.collapsed) {
          return _DropHover(
            index,
            SessionDropTarget(
              anchorId: block.members.last.id,
              after: true,
              tabGroupId: group.id,
            ),
            joins: true,
          );
        }
        return _DropHover(
          index,
          SessionDropTarget(anchorId: first, tabGroupId: group.id),
          lineAfter: true,
        );
    }
  }

  void _drop(PaneSessionDrag drag, _DropHover fallback) {
    final hover = _hover ?? fallback;
    _setHover(null);
    if (_isNoOp(drag.sessionId, hover.target)) return;
    widget.onDrop(drag.sessionId, hover.target);
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
    _dragOrigin = null;
    _longPressDrag = false;
    _dragMoved = false;
    _stopAutoScroll();
    _setHover(null);
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
    return DeviceAwareDraggable<PaneSessionDrag>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: whenDragging,
      onDragStartAt: (position, delayed) {
        _dragOrigin = position;
        _longPressDrag = delayed;
        _dragMoved = false;
      },
      onDragUpdate: (details) {
        final start = _dragOrigin;
        if (start != null &&
            (details.globalPosition - start).distance >= kTouchSlop) {
          _dragMoved = true;
        }
        _updateAutoScroll(details.globalPosition);
      },
      onDragCompleted: _finishDrag,
      onDraggableCanceled: (_, _) => _finishDrag(),
      onDragEnd: (details) {
        final showMenu = _longPressDrag && !_dragMoved;
        _finishDrag();
        // 길게 누른 뒤 거의 움직이지 않고 떼면 메뉴로 취급한다.
        // 제자리 드롭은 자기 행이 받아 no-op이므로 wasAccepted는 보지 않는다.
        if (showMenu) {
          (tileKey.currentState as _SessionTileState?)?.showMenuAtCenter();
        }
      },
      child: tile,
    );
  }

  /// 행 하나 = 드롭 대상. 포인터 위치로 [_hoverAt]이 삽입 위치·소속을 정한다.
  Widget _row(BuildContext _, int index) {
    final entry = _entries[index];
    final last = index == _entries.length - 1;
    // Builder의 context로 이 행(RenderBox)의 위치를 얻는다. ListView builder의
    // context는 sliver 자체라 행 좌표로 쓸 수 없다.
    return Builder(
      key: switch (entry) {
        _SessionEntry(:final session) => ValueKey('session-row-${session.id}'),
        _HeaderEntry(:final block) => ValueKey(
          'tab-group-row-${block.group.id}',
        ),
      },
      builder: (rowContext) => DragTarget<PaneSessionDrag>(
        onWillAcceptWithDetails: (details) => _accepts(details.data),
        onMove: (details) {
          final box = rowContext.findRenderObject();
          if (box is! RenderBox) return;
          final local = box.globalToLocal(details.offset);
          final hover = _hoverAt(index, local.dy / box.size.height);
          _setHover(
            _isNoOp(details.data.sessionId, hover.target) ? null : hover,
          );
        },
        onLeave: (_) => _setHover(null),
        onAcceptWithDetails: (details) =>
            _drop(details.data, _hoverAt(index, 0)),
        builder: (context, _, _) {
          final hover = _hover?.index == index ? _hover : null;
          final Widget content = switch (entry) {
            _SessionEntry(:final session, :final group) => _sessionRow(
              context,
              session,
              group,
            ),
            _HeaderEntry(:final block) => widget.headerBuilder(
              context,
              block,
              hover?.joins ?? false,
            ),
          };
          return Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : _gap),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                content,
                if (hover?.lineAfter == false)
                  _insertionLine(top: -(_gap / 2 + 1)),
                if (hover?.lineAfter == true)
                  _insertionLine(bottom: -(_gap / 2 + 1)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sessionRow(
    BuildContext context,
    SessionInfo session,
    SessionTabGroup? group,
  ) {
    // 목록 갱신 중에도 세션 행의 상태와 context를 유지한다.
    final tileKey = _tileKeys.putIfAbsent(
      session.id,
      () => GlobalKey<_SessionTileState>(),
    );
    final row = _draggableRow(
      session,
      widget.tileBuilder(context, session, tileKey),
      tileKey,
    );
    if (group == null) return row;
    // 탭 그룹 멤버는 그룹 색 막대로 묶어 보인다.
    return Container(
      key: ValueKey('tab-group-member-${session.id}'),
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: group.color.color, width: 3)),
      ),
      child: row,
    );
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
    // 목록 아래 빈 공간에 놓으면 맨 끝(그룹 밖)으로 이동한다. 표시는 마지막
    // 행 아래 선으로 대신한다.
    final endHover = _DropHover(
      _entries.length - 1,
      SessionDropTarget.end,
      lineAfter: true,
    );
    return DragTarget<PaneSessionDrag>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: (details) => _setHover(
        _isNoOp(details.data.sessionId, SessionDropTarget.end)
            ? null
            : endHover,
      ),
      onLeave: (_) => _setHover(null),
      onAcceptWithDetails: (details) => _drop(details.data, endHover),
      builder: (context, _, _) => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(10),
        itemCount: _entries.length,
        itemBuilder: _row,
      ),
    );
  }
}

class _ServerWorkTabsFooter extends StatelessWidget {
  const _ServerWorkTabsFooter({
    required this.groupId,
    required this.maxHeight,
    required this.tabs,
  });

  final String groupId;
  final double maxHeight;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(maxHeight: maxHeight),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: VibeColors.borderSoft)),
    ),
    child: ListView.separated(
      key: PageStorageKey('server-work-tabs-$groupId'),
      primary: false,
      shrinkWrap: true,
      padding: const EdgeInsets.all(10),
      itemCount: tabs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => tabs[index],
    ),
  );
}

class _ServerWorkTabTile extends StatelessWidget {
  const _ServerWorkTabTile({
    super.key,
    required this.hostAlias,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onClose,
  });

  final String hostAlias;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? VibeColors.accentSoft : VibeColors.surfaceHigh,
    borderRadius: BorderRadius.circular(8),
    child: ListTile(
      contentPadding: const EdgeInsets.only(left: 12, right: 4),
      leading: const Icon(
        Icons.inventory_2_outlined,
        size: 19,
        color: VibeColors.accent,
      ),
      title: const Text(
        '서버 작업 보관함',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        hostAlias,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      selected: selected,
      onTap: onTap,
      trailing: IconButton(
        tooltip: '보관함 탭 닫기',
        onPressed: busy ? null : onClose,
        icon: const Icon(Icons.close, size: 16),
      ),
    ),
  );
}
