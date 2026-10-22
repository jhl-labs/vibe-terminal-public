import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../session/server_work_tabs.dart';
import '../../session/session.dart';
import '../../session/session_activity.dart';
import '../../session/session_attention.dart';
import '../../session/session_tab_group.dart';
import '../../session/session_tab_group_controller.dart';
import '../../session/session_tab_layout.dart';
import '../../state/providers.dart';
import 'agent_brand.dart';
import 'session_info_tooltip.dart';
import 'session_status_indicators.dart';
import 'session_tab_group_header.dart';

/// 접힌 좌측 패널(폭 52)의 세션 아이콘 목록. 활성 작업공간의 세션을 세로
/// 탭 순서대로 보인다.
///
/// - 세션: 아주 작은 글씨의 이름 한 줄. 연결 상태는 왼쪽 위 점, Agent 종류는
///   아래쪽 얇은 브랜드 색 선, Agent 상태(대기 점·작업 중 스피너·완료·입력
///   필요)는 오른쪽 위 배지로 보인다. 누르면 그 세션을 연다.
/// - 펼친 탭 그룹: 그룹 색의 얇은 막대 아래에 멤버를 보인다.
/// - 접힌 탭 그룹: 그룹 색 칩 하나(이름·요약 상태, 세션 수는 툴팁). 누르면
///   그룹을 펼친다. 활성 세션이 그 그룹에 있으면 칩 아래에 그 세션만 보인다.
class CollapsedSessionList extends ConsumerWidget {
  const CollapsedSessionList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(
      sessionGroupProvider.select((state) => state.activeGroupId),
    );
    final sessions = [
      for (final session in ref.watch(sessionManagerProvider))
        if (session.groupId == workspaceId) session,
    ];
    final blocks = buildSessionTabBlocks(
      sessions,
      tabGroupOf: (session) => session.tabGroupId,
      groups: ref.watch(sessionTabGroupProvider).mapForWorkspace(workspaceId),
    );
    final activeId = ref.watch(activeSessionIdProvider);
    final showingTerminal = ref.watch(
      serverWorkTabsProvider.select((state) => state.activeId == null),
    );

    Widget sessionItem(SessionInfo session) => _CollapsedSessionItem(
      key: ValueKey('collapsed-session-${session.id}'),
      session: session,
      selected: showingTerminal && session.id == activeId,
      onTap: () {
        ref.read(serverWorkTabsProvider.notifier).showTerminal();
        ref.read(activeSessionIdProvider.notifier).set(session.id);
      },
    );

    List<SessionInfo> visibleMembers(SessionTabGroupBlock<SessionInfo> block) =>
        block.visibleMembers(isActive: (member) => member.id == activeId);

    return ListView(
      key: const ValueKey('collapsed-session-list'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final block in blocks)
          ...switch (block) {
            SessionTabSingle(:final item) => [sessionItem(item)],
            SessionTabGroupBlock(:final group, :final members)
                when group.collapsed =>
              [
                _CollapsedGroupChip(
                  key: ValueKey('collapsed-tab-group-${group.id}'),
                  group: group,
                  members: members,
                  onTap: () => ref
                      .read(sessionTabGroupProvider.notifier)
                      .setCollapsed(group.id, false),
                ),
                // 접힌 그룹이어도 활성 세션은 칩 바로 아래에 보인다(레일과 같은
                // 규칙). 그룹의 접힘 상태는 바꾸지 않는다.
                for (final member in visibleMembers(block)) sessionItem(member),
              ],
            SessionTabGroupBlock(:final group, :final members) => [
              Column(
                key: ValueKey('collapsed-tab-group-${group.id}'),
                children: [
                  _GroupBar(group: group),
                  for (final member in members) sessionItem(member),
                ],
              ),
            ],
          },
      ],
    );
  }
}

/// 펼친 탭 그룹의 시작을 알리는 그룹 색 막대.
class _GroupBar extends StatelessWidget {
  const _GroupBar({required this.group});

  final SessionTabGroup group;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: group.name,
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      height: 3,
      decoration: BoxDecoration(
        color: group.color.color,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _CollapsedSessionItem extends ConsumerWidget {
  const _CollapsedSessionItem({
    super.key,
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final SessionInfo session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attention = ref.watch(
      sessionAttentionProvider.select((attention) => attention[session.id]),
    );
    final busy = ref.watch(
      sessionActivityProvider.select(
        (activity) => activity[session.id] ?? false,
      ),
    );
    final statusColor = sessionStatusColor(session.status);
    final brand = AgentBrand.forHint(attention?.agentHint);
    final name = session.displayName.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: SessionInfoTooltip(
        session: session,
        attention: attention,
        preferBelow: false,
        child: _CollapsedTile(
          selected: selected,
          onTap: onTap,
          background: selected
              ? VibeColors.surfacePressed
              : VibeColors.surfaceHigh,
          borderColor: selected ? VibeColors.accent : VibeColors.borderSoft,
          label: name.isEmpty ? '?' : name,
          labelColor: selected
              ? VibeColors.onSurface
              : VibeColors.onSurfaceMuted,
          // Agent 종류는 글자 대신 브랜드 색의 얇은 선으로만 구분한다.
          accent: brand?.background,
          topLeft: Container(
            key: ValueKey('collapsed-status-${session.id}'),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          topRight: attention != null
              ? AgentAttentionIndicator(
                  key: ValueKey('collapsed-attention-${session.id}'),
                  state: attention.state,
                  agentHint: attention.agentHint,
                  size: 10,
                  padding: 0,
                )
              : busy
              ? const SessionBusyIndicator(size: 8, padding: 0)
              : null,
        ),
      ),
    );
  }
}

/// 접힌 목록의 칸 하나. 이름은 작은 글씨 한 줄로 줄이고, 상태 표시는 모서리에
/// 겹쳐 그려 글자 자리를 차지하지 않는다.
class _CollapsedTile extends StatelessWidget {
  const _CollapsedTile({
    required this.selected,
    required this.onTap,
    required this.background,
    required this.borderColor,
    required this.label,
    required this.labelColor,
    this.accent,
    this.topLeft,
    this.topRight,
  });

  static const height = 28.0;

  final bool selected;
  final VoidCallback onTap;
  final Color background;
  final Color borderColor;
  final String label;
  final Color labelColor;
  final Color? accent;
  final Widget? topLeft;
  final Widget? topRight;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  // 좁은 칸에서 말줄임표가 글자 자리를 먹지 않도록 끝을 흐리게 자른다.
                  overflow: TextOverflow.fade,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 8.5,
                    height: 1.1,
                    letterSpacing: -0.3,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (accent != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 2,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            if (topLeft != null) Positioned(left: 3, top: 3, child: topLeft!),
            if (topRight != null)
              Positioned(
                right: -3,
                top: -3,
                child: _CornerBadge(child: topRight!),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 아이콘 모서리 배지 바탕. 아이콘 경계와 겹쳐도 상태가 읽히게 한다.
class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1.5),
    decoration: const BoxDecoration(
      color: VibeColors.surface,
      shape: BoxShape.circle,
    ),
    child: child,
  );
}

/// 접힌 탭 그룹 하나를 대신하는 칩. 그룹 색·이름과 멤버 Agent 상태 요약을
/// 보이고(세션 수는 툴팁), 누르면 그룹을 펼친다.
class _CollapsedGroupChip extends ConsumerWidget {
  const _CollapsedGroupChip({
    super.key,
    required this.group,
    required this.members,
    required this.onTap,
  });

  final SessionTabGroup group;
  final List<SessionInfo> members;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(
      sessionAttentionProvider.select(
        (attention) => strongestAttentionState(
          members.map((session) => attention[session.id]?.state),
        ),
      ),
    );
    final color = group.color.color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Tooltip(
        message: '${group.name} · 세션 ${members.length}개 (눌러서 펼치기)',
        child: _CollapsedTile(
          selected: false,
          onTap: onTap,
          background: color.withValues(alpha: 0.16),
          borderColor: color,
          label: group.name,
          labelColor: color,
          topRight: summary != null
              ? AgentAttentionIndicator(
                  key: ValueKey('collapsed-group-summary-${group.id}'),
                  state: summary,
                  agentHint: group.name,
                  size: 10,
                  padding: 0,
                )
              : null,
        ),
      ),
    );
  }
}
