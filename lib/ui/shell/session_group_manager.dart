import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../session/session_group.dart';
import '../../state/providers.dart';

/// 세션 그룹 관리 창을 띄운다. 호스트 관리 창과 같은 형태로 그룹을 추가·
/// 이름 변경·삭제한다. [hiddenGroupIds]는 이 빌드에서 표시하지 않는 그룹,
/// [onGroupCreated]는 새로 만든 그룹을 활성화하는 콜백이다.
Future<void> showSessionGroupManager(
  BuildContext context, {
  Set<String> hiddenGroupIds = const {},
  ValueChanged<String>? onGroupCreated,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 480,
        height: 560,
        child: SessionGroupManagerPage(
          hiddenGroupIds: hiddenGroupIds,
          onGroupCreated: onGroupCreated,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

class SessionGroupManagerPage extends ConsumerWidget {
  const SessionGroupManagerPage({
    super.key,
    this.hiddenGroupIds = const {},
    this.onGroupCreated,
    this.onClose,
  });

  final Set<String> hiddenGroupIds;
  final ValueChanged<String>? onGroupCreated;
  final VoidCallback? onClose;

  Future<void> _addGroup(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _GroupNameDialog(title: '세션 그룹 추가', confirmLabel: '추가'),
    );
    if (name == null || !context.mounted) return;
    final id = ref.read(sessionGroupProvider.notifier).createGroup(name);
    onGroupCreated?.call(id);
  }

  Future<void> _renameGroup(
    BuildContext context,
    WidgetRef ref,
    SessionGroup group,
  ) async {
    if (group.isFixed) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(
        title: '그룹 이름 변경',
        confirmLabel: '저장',
        initialName: group.name,
      ),
    );
    if (name == null || !context.mounted) return;
    ref.read(sessionGroupProvider.notifier).renameGroup(group.id, name);
  }

  Future<void> _deleteGroup(
    BuildContext context,
    WidgetRef ref,
    SessionGroup group,
    int sessionCount,
  ) async {
    if (group.isFixed) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('세션 그룹 삭제'),
        content: Text(
          sessionCount > 0
              ? '"${group.name}" 그룹을 삭제하면 소속 세션 $sessionCount개가 기본 그룹으로 이동합니다. 계속할까요?'
              : '"${group.name}" 그룹을 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(sessionGroupProvider.notifier).deleteGroup(group.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupState = ref.watch(sessionGroupProvider);
    final sessionCounts = <String, int>{};
    for (final session in ref.watch(sessionManagerProvider)) {
      sessionCounts.update(
        session.groupId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final groups = [
      for (final group in groupState.groups)
        if (!hiddenGroupIds.contains(group.id)) group,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('세션 그룹 관리'),
        actions: [
          if (onClose != null)
            IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final group = groups[index];
          final count = sessionCounts[group.id] ?? 0;
          return _GroupTile(
            key: ValueKey('session-group-tile-${group.id}'),
            group: group,
            sessionCount: count,
            active: group.id == groupState.activeGroupId,
            onRename: () => _renameGroup(context, ref, group),
            onDelete: () => _deleteGroup(context, ref, group, count),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: FilledButton.icon(
            onPressed: () => _addGroup(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('그룹 추가'),
          ),
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    super.key,
    required this.group,
    required this.sessionCount,
    required this.active,
    required this.onRename,
    required this.onDelete,
  });

  final SessionGroup group;
  final int sessionCount;
  final bool active;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final fixed = group.isFixed;
    final details = [
      '세션 $sessionCount개',
      if (active) '현재 그룹',
      if (fixed) '기본 제공 · 수정 불가',
    ].join(' · ');
    return Material(
      color: VibeColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: fixed ? null : onRename,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? VibeColors.accent : VibeColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                fixed ? Icons.folder_special_outlined : Icons.folder_outlined,
                color: VibeColors.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: VibeColors.onSurfaceDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (fixed)
                const Tooltip(
                  message: '기본 제공 그룹은 수정·삭제할 수 없습니다',
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: VibeColors.onSurfaceDim,
                    ),
                  ),
                )
              else ...[
                IconButton(
                  tooltip: '이름 변경',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onRename,
                ),
                IconButton(
                  tooltip: '그룹 삭제',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 그룹 이름 입력 다이얼로그. 확인 시 입력값을, 취소 시 null을 돌려준다.
class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialName = '',
  });

  final String title;
  final String confirmLabel;
  final String initialName;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialName.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '그룹 이름',
          hintText: '예: 고객사 A, 빌드 작업',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
