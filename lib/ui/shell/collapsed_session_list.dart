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
/// - 세션: Agent 브랜드 배지 또는 이름 첫 글자(연결 상태 색), 모서리에 Agent
///   상태(대기 점·작업 중 스피너·완료·입력 필요). 누르면 그 세션을 연다.
/// - 펼친 탭 그룹: 그룹 색의 얇은 막대 아래에 멤버를 보인다.
/// - 접힌 탭 그룹: 그룹 칩 하나(색·세션 수·요약 상태). 누르면 그룹을 펼친다.
class CollapsedSessionList extends ConsumerWidget {
  const CollapsedSessionList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenSessionTabGroupCleanup(ref);
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

    return ListView(
      key: const ValueKey('collapsed-session-list'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final block in blocks)
          switch (block) {
            SessionTabSingle(:final item) => sessionItem(item),
            SessionTabGroupBlock(:final group, :final members)
                when group.collapsed =>
              _CollapsedGroupChip(
                key: ValueKey('collapsed-tab-group-${group.id}'),
                group: group,
                members: members,
                onTap: () => ref
                    .read(sessionTabGroupProvider.notifier)
                    .setCollapsed(group.id, false),
              ),
            SessionTabGroupBlock(:final group, :final members) => Column(
              key: ValueKey('collapsed-tab-group-${group.id}'),
              children: [
                _GroupBar(group: group),
                for (final member in members) sessionItem(member),
              ],
            ),
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
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: SessionInfoTooltip(
        session: session,
        attention: attention,
        preferBelow: false,
        child: Material(
          color: selected ? VibeColors.surfacePressed : VibeColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? VibeColors.accent : VibeColors.borderSoft,
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: brand != null
                        ? AgentBrandBadge(brand: brand)
                        : Text(
                            initial,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  // 브랜드 배지는 자체 색을 써서, 연결 상태는 점으로 따로 보인다.
                  Positioned(
                    left: 3,
                    bottom: 3,
                    child: Container(
                      key: ValueKey('collapsed-status-${session.id}'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  if (attention != null || busy)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: _CornerBadge(
                        child: attention != null
                            ? AgentAttentionIndicator(
                                key: ValueKey(
                                  'collapsed-attention-${session.id}',
                                ),
                                state: attention.state,
                                agentHint: attention.agentHint,
                                size: 11,
                                padding: 0,
                              )
                            : const SessionBusyIndicator(size: 9, padding: 0),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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

/// 접힌 탭 그룹 하나를 대신하는 칩. 그룹 색·세션 수와 멤버 Agent 상태 요약을
/// 보이고, 누르면 그룹을 펼친다.
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Tooltip(
        message: '${group.name} · 세션 ${members.length}개 (눌러서 펼치기)',
        child: Material(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Text(
                      '${members.length}',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (summary != null)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: _CornerBadge(
                        child: AgentAttentionIndicator(
                          key: ValueKey('collapsed-group-summary-${group.id}'),
                          state: summary,
                          agentHint: group.name,
                          size: 11,
                          padding: 0,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
