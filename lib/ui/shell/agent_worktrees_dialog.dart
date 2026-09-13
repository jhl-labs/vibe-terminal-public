import 'package:flutter/material.dart';

import '../../agent/agent_launcher.dart';
import '../../agent/agent_worktree.dart';
import '../../app/theme.dart';

typedef AgentWorktreeAction =
    Future<void> Function(AgentWorktreeRecord worktree);

Future<void> showAgentWorktreesDialog(
  BuildContext context, {
  required Future<List<AgentWorktreeRecord>> Function() load,
  required AgentWorktreeAction onInspect,
  required AgentWorktreeAction onReview,
  required AgentWorktreeAction onResume,
  required AgentWorktreeAction onCleanup,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AgentWorktreesDialog(
    load: load,
    onInspect: onInspect,
    onReview: onReview,
    onResume: onResume,
    onCleanup: onCleanup,
  ),
);

class _AgentWorktreesDialog extends StatefulWidget {
  const _AgentWorktreesDialog({
    required this.load,
    required this.onInspect,
    required this.onReview,
    required this.onResume,
    required this.onCleanup,
  });

  final Future<List<AgentWorktreeRecord>> Function() load;
  final AgentWorktreeAction onInspect;
  final AgentWorktreeAction onReview;
  final AgentWorktreeAction onResume;
  final AgentWorktreeAction onCleanup;

  @override
  State<_AgentWorktreesDialog> createState() => _AgentWorktreesDialogState();
}

class _AgentWorktreesDialogState extends State<_AgentWorktreesDialog> {
  late Future<List<AgentWorktreeRecord>> _worktrees;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _worktrees = widget.load();
  }

  Future<void> _run(
    AgentWorktreeRecord worktree,
    AgentWorktreeAction action,
  ) async {
    if (_busy.contains(worktree.id)) return;
    setState(() => _busy.add(worktree.id));
    try {
      await action(worktree);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(_reload);
    } finally {
      if (mounted) setState(() => _busy.remove(worktree.id));
    }
  }

  Future<void> _confirmCleanup(AgentWorktreeRecord worktree) async {
    final missing = worktree.lifecycle == AgentWorktreeLifecycle.missing;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(missing ? 'Registry 기록을 지울까요?' : 'worktree를 정리할까요?'),
        content: Text(
          missing
              ? '실제 worktree 경로가 없어 Registry 기록만 삭제합니다.'
              : 'Git 상태를 다시 확인한 뒤 clean 상태이고 ${worktree.baseRef}에 '
                    '병합된 경우에만 worktree를 제거합니다. '
                    '브랜치 ${worktree.branchName}은 보존합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(missing ? '기록 삭제' : '안전 정리'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(worktree, widget.onCleanup);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agent 작업공간',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '중단된 worktree를 재개하고 Git 상태를 확인합니다.',
                          style: TextStyle(color: VibeColors.onSurfaceDim),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('agent-worktrees-refresh'),
                    tooltip: '목록 새로고침',
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<AgentWorktreeRecord>>(
                future: _worktrees,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _Message(
                      icon: Icons.error_outline,
                      message: '작업공간 목록을 불러오지 못했습니다.',
                      actionLabel: '다시 시도',
                      onAction: () => setState(_reload),
                    );
                  }
                  final worktrees = snapshot.data ?? const [];
                  if (worktrees.isEmpty) {
                    return const _Message(
                      icon: Icons.inventory_2_outlined,
                      message: '앱에서 만든 Agent worktree가 없습니다.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: worktrees.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final worktree = worktrees[index];
                      return _WorktreeCard(
                        key: ValueKey('agent-worktree-${worktree.id}'),
                        worktree: worktree,
                        busy: _busy.contains(worktree.id),
                        onInspect: () => _run(worktree, widget.onInspect),
                        onReview: () => _run(worktree, widget.onReview),
                        onResume: () => _run(worktree, widget.onResume),
                        onCleanup: () => _confirmCleanup(worktree),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorktreeCard extends StatelessWidget {
  const _WorktreeCard({
    super.key,
    required this.worktree,
    required this.busy,
    required this.onInspect,
    required this.onReview,
    required this.onResume,
    required this.onCleanup,
  });

  final AgentWorktreeRecord worktree;
  final bool busy;
  final VoidCallback onInspect;
  final VoidCallback onReview;
  final VoidCallback onResume;
  final VoidCallback onCleanup;

  @override
  Widget build(BuildContext context) {
    final lifecycle = _lifecyclePresentation(worktree.lifecycle);
    final git = _gitPresentation(worktree.gitState);
    final canResume =
        worktree.lifecycle != AgentWorktreeLifecycle.active &&
        worktree.lifecycle != AgentWorktreeLifecycle.missing;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, color: lifecycle.color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${worktree.cli.label} · ${worktree.branchName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(label: lifecycle.label, color: lifecycle.color),
                const SizedBox(width: 6),
                _StatusChip(label: git.label, color: git.color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${worktree.hostAlias} · ${worktree.worktreePath}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
              ),
            ),
            Text(
              '기준: ${worktree.baseRef}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 11,
              ),
            ),
            if (worktree.lastError case final error?) ...[
              const SizedBox(height: 7),
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VibeColors.statusError,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                TextButton.icon(
                  key: ValueKey('inspect-${worktree.id}'),
                  onPressed: busy ? null : onInspect,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('상태 확인'),
                ),
                if (worktree.lifecycle != AgentWorktreeLifecycle.missing)
                  TextButton.icon(
                    key: ValueKey('review-${worktree.id}'),
                    onPressed: busy ? null : onReview,
                    icon: const Icon(Icons.difference_outlined, size: 17),
                    label: const Text('변경 검토'),
                  ),
                if (canResume)
                  TextButton.icon(
                    key: ValueKey('resume-${worktree.id}'),
                    onPressed: busy ? null : onResume,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('재개'),
                  ),
                if (worktree.canSafelyRemove)
                  TextButton.icon(
                    key: ValueKey('cleanup-${worktree.id}'),
                    onPressed: busy ? null : onCleanup,
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 17,
                    ),
                    label: const Text('안전 정리'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: VibeColors.onSurfaceDim),
        const SizedBox(height: 12),
        Text(message),
        if (actionLabel != null) ...[
          const SizedBox(height: 10),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

({String label, Color color}) _lifecyclePresentation(
  AgentWorktreeLifecycle lifecycle,
) => switch (lifecycle) {
  AgentWorktreeLifecycle.provisioning => (
    label: '생성 중',
    color: VibeColors.statusConnecting,
  ),
  AgentWorktreeLifecycle.active => (
    label: '실행 중',
    color: VibeColors.statusConnected,
  ),
  AgentWorktreeLifecycle.stranded => (
    label: '중단됨',
    color: VibeColors.statusConnecting,
  ),
  AgentWorktreeLifecycle.missing => (
    label: '경로 없음',
    color: VibeColors.statusError,
  ),
};

({String label, Color color}) _gitPresentation(AgentWorktreeGitState state) =>
    switch (state) {
      AgentWorktreeGitState.unknown => (
        label: '미확인',
        color: VibeColors.onSurfaceDim,
      ),
      AgentWorktreeGitState.cleanUnmerged => (
        label: '미병합',
        color: VibeColors.statusConnecting,
      ),
      AgentWorktreeGitState.dirty => (
        label: '변경 있음',
        color: VibeColors.statusError,
      ),
      AgentWorktreeGitState.merged => (
        label: '병합됨',
        color: VibeColors.statusConnected,
      ),
    };
