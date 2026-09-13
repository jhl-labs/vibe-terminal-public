import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_launcher.dart';
import '../../app/theme.dart';
import '../../session/session.dart';
import '../../session/session_activity.dart';
import '../../session/session_attention.dart';
import '../../session/session_group.dart';
import '../../state/providers.dart';
import 'agent_launch_dialog.dart';
import 'remote_session_manager_dialog.dart';

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
        final spec = await showAgentLaunchDialog(
          context,
          preferences: ref.read(appSettingsProvider).agentLaunch,
          saveProfile: ref
              .read(appSettingsProvider.notifier)
              .saveAgentLaunchProfile,
          removeProfile: ref
              .read(appSettingsProvider.notifier)
              .removeAgentLaunchProfile,
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
      case _SessionAction.rename:
        await _renameSession(context, ref, session);
      case _SessionAction.remoteSessions:
        await showRemoteSessionManagerDialog(context, session);
      case _SessionAction.close:
        await _requestCloseSession(context, ref, session);
    }
  }

  Future<void> _requestCloseSession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    final manager = ref.read(sessionManagerProvider.notifier);
    if (!session.host.keepsRemoteSession) {
      manager.closeSession(session.id);
      return;
    }

    final connected = session.status == SessionStatus.connected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(connected ? '서버의 작업을 종료할까요?' : '탭을 닫을까요?'),
        content: Text(
          connected
              ? '이 탭을 닫으면 서버에서 실행 중인 작업도 종료됩니다. 네트워크가 끊기거나 앱을 다시 시작할 때는 자동으로 이어집니다.'
              : '현재는 서버에 종료 명령을 보낼 수 없습니다. 탭을 닫으면 종료 요청을 저장하고, 이 서버에 다시 연결될 때 안전하게 정리합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VibeColors.statusError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(connected ? '작업 종료' : '탭 닫기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final terminated = await manager.terminatePersistentSession(session.id);
    manager.closeSession(session.id);
    if (!terminated && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료 요청을 저장했습니다. 이 서버에 다시 연결하면 정리합니다.')),
      );
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
    ref
        .read(activeSessionIdProvider.notifier)
        .set(groupSessions.isEmpty ? null : groupSessions.first.id);
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

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    var draftName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('세션 그룹 추가'),
        content: TextField(
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '그룹 이름',
            hintText: '예: 고객사 A, 빌드 작업',
          ),
          onChanged: (value) => draftName = value,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draftName),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final id = ref.read(sessionGroupProvider.notifier).createGroup(name);
    _activateGroup(ref, id);
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

  Future<void> _renameSession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    var draftTitle = session.displayName;
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('세션 이름 변경'),
        content: TextFormField(
          initialValue: session.displayName,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: '세션 이름',
            hintText: session.host.alias,
          ),
          onChanged: (value) => draftTitle = value,
          onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draftTitle),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (title == null) return;
    ref.read(sessionManagerProvider.notifier).renameSession(session.id, title);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSessions = ref.watch(sessionManagerProvider);
    final groupState = ref.watch(sessionGroupProvider);
    final activeGroupId = groupState.activeGroupId;
    final sessions = [
      for (final session in allSessions)
        if (session.groupId == activeGroupId) session,
    ];
    final activeId = ref.watch(activeSessionIdProvider);
    final activity = ref.watch(sessionActivityProvider);
    final attention = ref.watch(sessionAttentionProvider);
    final mgr = ref.read(sessionManagerProvider.notifier);
    final sessionCounts = <String, int>{};
    for (final session in allSessions) {
      sessionCounts.update(
        session.groupId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final blockedCount = allSessions
        .where(
          (session) =>
              attention[session.id]?.state == SessionAttentionState.blocked,
        )
        .length;
    final doneCount = allSessions
        .where(
          (session) =>
              attention[session.id]?.state == SessionAttentionState.done,
        )
        .length;

    return Container(
      width: width,
      color: VibeColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            _RailHeader(onOpenSettings: onOpenSettings, onCollapse: onCollapse),
            _GroupSelector(
              state: groupState,
              sessionCounts: sessionCounts,
              onChanged: (groupId) => _activateGroup(ref, groupId),
              onAddGroup: () => _createGroup(context, ref),
            ),
            if (blockedCount > 0 || doneCount > 0)
              _AttentionSummary(
                blockedCount: blockedCount,
                doneCount: doneCount,
                onTap: () =>
                    _activateNextAttentionSession(ref, allSessions, attention),
              ),
            const Divider(height: 1, color: VibeColors.borderSoft),
            Expanded(
              child: sessions.isEmpty
                  ? const _EmptyRail()
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(10),
                      buildDefaultDragHandles: false,
                      itemCount: sessions.length,
                      onReorderItem: (oldIndex, targetIndex) =>
                          mgr.moveSessionInGroup(
                            activeGroupId,
                            oldIndex,
                            targetIndex,
                          ),
                      proxyDecorator: (child, _, animation) => AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          final t = Curves.easeOut.transform(animation.value);
                          return Material(
                            color: Colors.transparent,
                            elevation: 8 * t,
                            borderRadius: BorderRadius.circular(8),
                            shadowColor: Colors.black.withValues(alpha: 0.45),
                            child: child,
                          );
                        },
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final s = sessions[index];
                        return Padding(
                          key: ValueKey(s.id),
                          padding: EdgeInsets.only(
                            bottom: index == sessions.length - 1 ? 0 : 8,
                          ),
                          child: _SessionTile(
                            session: s,
                            selected: s.id == activeId,
                            statusColor: _statusColor(s.status),
                            busy: activity[s.id] ?? false,
                            attention: attention[s.id],
                            onTap: () {
                              ref
                                  .read(activeSessionIdProvider.notifier)
                                  .set(s.id);
                              onSessionSelected?.call();
                            },
                            onShowMenu: (position) =>
                                _showSessionMenu(context, ref, s, position),
                            dragHandle: ReorderableDragStartListener(
                              index: index,
                              child: const _DragHandle(),
                            ),
                            onClose: () => unawaited(
                              _requestCloseSession(context, ref, s),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onOpenAgentWorktrees != null) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('open-agent-worktrees'),
                      onPressed: onOpenAgentWorktrees,
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Text('Agent 작업공간'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: onNewSession,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('새 세션'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SessionAction {
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
    required this.state,
    required this.sessionCounts,
    required this.onChanged,
    required this.onAddGroup,
  });

  final SessionGroupState state;
  final Map<String, int> sessionCounts;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddGroup;

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
                    value: state.activeGroupId,
                    isExpanded: true,
                    dropdownColor: VibeColors.surfaceHigh,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: VibeColors.onSurfaceDim,
                      size: 19,
                    ),
                    selectedItemBuilder: (context) => [
                      for (final group in state.groups)
                        _SelectedGroupLabel(group: group),
                    ],
                    items: [
                      for (final group in state.groups)
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
          const SizedBox(width: 6),
          Tooltip(
            message: '세션 그룹 추가',
            child: SizedBox.square(
              dimension: 38,
              child: IconButton(
                onPressed: onAddGroup,
                icon: const Icon(Icons.create_new_folder_outlined, size: 19),
              ),
            ),
          ),
        ],
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
          group.isDefault
              ? Icons.folder_special_outlined
              : Icons.folder_outlined,
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

class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.onOpenSettings, this.onCollapse});

  final VoidCallback onOpenSettings;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.terminal, color: VibeColors.accent, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더에는 제품 이름만 둔다. 버전은 설정 > About에서 확인한다.
                Text(
                  'Vibe Terminal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'SSH workspace',
                  style: TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                  ),
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
    required this.session,
    required this.selected,
    required this.statusColor,
    required this.busy,
    required this.attention,
    required this.onTap,
    required this.onShowMenu,
    required this.dragHandle,
    required this.onClose,
  });

  final SessionInfo session;
  final bool selected;
  final Color statusColor;

  /// 최근 출력 활동이 있어 작업 중(busy)인지 여부.
  final bool busy;

  /// Agent로 식별된 세션의 작업·승인 대기·미확인 완료 상태.
  final SessionAttention? attention;

  final VoidCallback onTap;
  final Future<void> Function(Offset position) onShowMenu;
  final Widget dragHandle;
  final VoidCallback onClose;

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _expanded = false;

  void _showMenuAtCenter() {
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

  /// 세션 레일: 화면 크기와 무관하게 항상 한 줄(세션명 + 드래그 핸들 + ▾ + ✕).
  /// 세션명 탭=바로 열기, ▾ 탭=정보(endpoint) 펼침, 드래그 핸들=순서 변경.
  Widget _buildCompact() {
    final host = widget.session.host;
    return Material(
      color: widget.selected
          ? VibeColors.surfacePressed
          : VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onTap,
        onSecondaryTapDown: (details) =>
            unawaited(widget.onShowMenu(details.globalPosition)),
        onLongPress: _showMenuAtCenter,
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
                  const SizedBox(width: 10),
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
                  widget.dragHandle,
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
                          '${attention.agentHint.toUpperCase()} · '
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
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: VibeColors.accent,
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
        message: '${attention.agentHint} · ${attention.state.label}',
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

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '드래그로 순서 변경',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox.square(
          dimension: 28,
          child: Icon(
            Icons.drag_indicator,
            color: VibeColors.onSurfaceDim.withValues(alpha: 0.75),
            size: 18,
          ),
        ),
      ),
    );
  }
}
