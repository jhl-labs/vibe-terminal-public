import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../session/session_attention.dart';
import '../../session/session_manager.dart' show SessionCloseIntent;
import '../../session/session_tab_group.dart';
import '../../session/session_tab_group_controller.dart';
import '../../state/providers.dart';
import 'session_status_indicators.dart';

/// 탭 그룹 팔레트의 실제 색과 이름.
extension SessionTabGroupColorStyle on SessionTabGroupColor {
  Color get color => switch (this) {
    SessionTabGroupColor.grey => const Color(0xFF8B98A5),
    SessionTabGroupColor.blue => const Color(0xFF6EA8FE),
    SessionTabGroupColor.red => const Color(0xFFFF7B72),
    SessionTabGroupColor.yellow => const Color(0xFFF2CC60),
    SessionTabGroupColor.green => const Color(0xFF56D364),
    SessionTabGroupColor.pink => const Color(0xFFF778BA),
    SessionTabGroupColor.purple => const Color(0xFFBC8CFF),
    SessionTabGroupColor.cyan => const Color(0xFF39C5CF),
    SessionTabGroupColor.orange => const Color(0xFFFFA657),
  };

  String get label => switch (this) {
    SessionTabGroupColor.grey => '회색',
    SessionTabGroupColor.blue => '파랑',
    SessionTabGroupColor.red => '빨강',
    SessionTabGroupColor.yellow => '노랑',
    SessionTabGroupColor.green => '초록',
    SessionTabGroupColor.pink => '분홍',
    SessionTabGroupColor.purple => '보라',
    SessionTabGroupColor.cyan => '청록',
    SessionTabGroupColor.orange => '주황',
  };
}

/// 세로 탭 목록의 탭 그룹 머리 행. 색 막대·이름·세션 수·접기 토글을 보이고,
/// 접혀 있으면 멤버 중 가장 확인이 급한 Agent 상태를 요약해 보인다.
class SessionTabGroupHeader extends StatelessWidget {
  const SessionTabGroupHeader({
    super.key,
    required this.group,
    required this.memberCount,
    required this.onToggleCollapsed,
    required this.onShowMenu,
    this.summaryState,
    this.highlighted = false,
  });

  final SessionTabGroup group;
  final int memberCount;

  /// 접힌 그룹에서만 보이는 멤버 Agent 상태 요약.
  final SessionAttentionState? summaryState;

  /// 드래그한 세션이 이 그룹에 들어갈 위치에 있으면 강조한다.
  final bool highlighted;
  final VoidCallback onToggleCollapsed;
  final void Function(Offset globalPosition) onShowMenu;

  @override
  Widget build(BuildContext context) {
    final color = group.color.color;
    return Material(
      color: highlighted
          ? color.withValues(alpha: 0.22)
          : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('tab-group-header-${group.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onToggleCollapsed,
        onSecondaryTapDown: (details) => onShowMenu(details.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject();
          if (box is RenderBox) {
            onShowMenu(box.localToGlobal(box.size.center(Offset.zero)));
          }
        },
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              Container(width: 4, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibeColors.onAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$memberCount',
                key: ValueKey('tab-group-count-${group.id}'),
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (group.collapsed && summaryState != null)
                KeyedSubtree(
                  key: ValueKey('tab-group-summary-${group.id}'),
                  child: AgentAttentionIndicator(
                    state: summaryState!,
                    agentHint: group.name,
                    size: 14,
                  ),
                ),
              Tooltip(
                message: group.collapsed ? '탭 그룹 펼치기' : '탭 그룹 접기',
                child: Icon(
                  group.collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: VibeColors.onSurfaceDim,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TabGroupAction { rename, color, ungroup, closeAll }

/// 탭 그룹 머리 행의 컨텍스트 메뉴: 이름 변경, 색상 변경, 그룹 해제,
/// 그룹의 세션 모두 닫기.
Future<void> showSessionTabGroupMenu(
  BuildContext context,
  WidgetRef ref,
  SessionTabGroup group,
  Offset globalPosition,
) async {
  final position = _menuPosition(context, globalPosition);
  final action = await showMenu<_TabGroupAction>(
    context: context,
    position: position,
    color: VibeColors.surfaceHigh,
    items: const [
      PopupMenuItem(
        value: _TabGroupAction.rename,
        child: _MenuLabel(icon: Icons.edit_outlined, label: '이름 변경'),
      ),
      PopupMenuItem(
        value: _TabGroupAction.color,
        child: _MenuLabel(icon: Icons.palette_outlined, label: '색상 변경'),
      ),
      PopupMenuItem(
        value: _TabGroupAction.ungroup,
        child: _MenuLabel(icon: Icons.layers_clear_outlined, label: '그룹 해제'),
      ),
      PopupMenuItem(
        value: _TabGroupAction.closeAll,
        child: _MenuLabel(icon: Icons.close, label: '그룹의 세션 모두 닫기'),
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  final controller = ref.read(sessionTabGroupProvider.notifier);
  switch (action) {
    case _TabGroupAction.rename:
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _TabGroupNameDialog(initialName: group.name),
      );
      if (name != null) controller.rename(group.id, name);
    case _TabGroupAction.color:
      final color = await showMenu<SessionTabGroupColor>(
        context: context,
        position: position,
        color: VibeColors.surfaceHigh,
        items: [
          for (final color in SessionTabGroupColor.values)
            PopupMenuItem(
              key: ValueKey('tab-group-color-${color.name}'),
              value: color,
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(color.label),
                  if (color == group.color) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 16),
                  ],
                ],
              ),
            ),
        ],
      );
      if (color != null) controller.setColor(group.id, color);
    case _TabGroupAction.ungroup:
      controller.ungroup(group.id);
    case _TabGroupAction.closeAll:
      await _confirmCloseAll(context, ref, group);
  }
}

Future<void> _confirmCloseAll(
  BuildContext context,
  WidgetRef ref,
  SessionTabGroup group,
) async {
  final memberIds = ref
      .read(sessionTabGroupProvider.notifier)
      .memberIds(group.id);
  if (memberIds.isEmpty) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('"${group.name}" 세션 ${memberIds.length}개를 닫을까요?'),
      content: const Text('작업 이어가기 탭은 탭만 닫고 서버의 작업은 남겨 둡니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('tab-group-close-all-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: VibeColors.statusError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('모두 닫기'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final manager = ref.read(sessionManagerProvider.notifier);
  for (final id in memberIds) {
    // 일괄 닫기와 같다. 작업 이어가기 세션은 서버에 남기고 내려놓는다.
    manager.closeSession(id, intent: SessionCloseIntent.detachRemoteWork);
  }
}

RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return RelativeRect.fromRect(
    Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
    Offset.zero & overlay.size,
  );
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: VibeColors.onSurfaceMuted),
      const SizedBox(width: 12),
      Text(label),
    ],
  );
}

class _TabGroupNameDialog extends StatefulWidget {
  const _TabGroupNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_TabGroupNameDialog> createState() => _TabGroupNameDialogState();
}

class _TabGroupNameDialogState extends State<_TabGroupNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialName.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('탭 그룹 이름 변경'),
    content: TextField(
      key: const ValueKey('tab-group-name-field'),
      controller: _controller,
      autofocus: true,
      maxLength: sessionTabGroupNameMaxLength,
      decoration: const InputDecoration(labelText: '탭 그룹 이름'),
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
