import 'package:flutter/material.dart';

import '../../agent/agent_delivery.dart';
import '../../agent/agent_workspace_test.dart';
import '../../agent/agent_worktree.dart';
import '../../app/theme.dart';

typedef AgentDeliveryPreviewLoader = Future<AgentDeliveryPreview> Function();
typedef AgentDeliveryAction = Future<AgentDeliveryResult> Function();
typedef AgentPullRequestCreator =
    Future<AgentDeliveryResult> Function(AgentPullRequestDraft draft);
typedef AgentDeliveryUrlOpener = Future<bool> Function(Uri uri);
typedef AgentConflictInspector = Future<void> Function();

Future<void> showAgentDeliveryDialog(
  BuildContext context, {
  required AgentWorktreeRecord worktree,
  required AgentDeliveryPreviewLoader loadPreview,
  required Future<AgentWorkspaceTestState> Function() loadTestState,
  required AgentDeliveryAction merge,
  required AgentDeliveryAction push,
  required AgentPullRequestCreator createPullRequest,
  required AgentDeliveryUrlOpener openUrl,
  required AgentConflictInspector inspectConflicts,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AgentDeliveryDialog(
    worktree: worktree,
    loadPreview: loadPreview,
    loadTestState: loadTestState,
    merge: merge,
    push: push,
    createPullRequest: createPullRequest,
    openUrl: openUrl,
    inspectConflicts: inspectConflicts,
  ),
);

class _DeliverySnapshot {
  const _DeliverySnapshot({required this.preview, required this.testState});

  final AgentDeliveryPreview preview;
  final AgentWorkspaceTestState testState;

  bool get verified =>
      !testState.running &&
      !testState.isStale &&
      testState.lastResult?.passed == true;
}

class _AgentDeliveryDialog extends StatefulWidget {
  const _AgentDeliveryDialog({
    required this.worktree,
    required this.loadPreview,
    required this.loadTestState,
    required this.merge,
    required this.push,
    required this.createPullRequest,
    required this.openUrl,
    required this.inspectConflicts,
  });

  final AgentWorktreeRecord worktree;
  final AgentDeliveryPreviewLoader loadPreview;
  final Future<AgentWorkspaceTestState> Function() loadTestState;
  final AgentDeliveryAction merge;
  final AgentDeliveryAction push;
  final AgentPullRequestCreator createPullRequest;
  final AgentDeliveryUrlOpener openUrl;
  final AgentConflictInspector inspectConflicts;

  @override
  State<_AgentDeliveryDialog> createState() => _AgentDeliveryDialogState();
}

class _AgentDeliveryDialogState extends State<_AgentDeliveryDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  late Future<_DeliverySnapshot> _snapshot;
  bool _busy = false;
  bool _draftInitialized = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _reload() {
    _snapshot = _load();
  }

  Future<_DeliverySnapshot> _load() async {
    final values = await Future.wait<Object>([
      widget.loadPreview(),
      widget.loadTestState(),
    ]);
    final snapshot = _DeliverySnapshot(
      preview: values[0] as AgentDeliveryPreview,
      testState: values[1] as AgentWorkspaceTestState,
    );
    if (!_draftInitialized && snapshot.preview.commits.isNotEmpty) {
      _draftInitialized = true;
      _titleController.text = snapshot.preview.commits.last.subject;
      final test = snapshot.testState.lastResult;
      _bodyController.text = [
        '## 요약',
        '',
        '- ${snapshot.preview.aheadCount} commit(s)',
        '- ${snapshot.preview.changedFiles} changed file(s)',
        '',
        '## 검증',
        '',
        if (test != null)
          '- `${test.command}` (종료 코드 ${test.exitCode ?? '-'})'
        else
          '- 실행하지 않음',
      ].join('\n');
    }
    return snapshot;
  }

  Future<bool> _confirm({
    required String title,
    required String effect,
    required String warning,
    required String buttonLabel,
    required Key buttonKey,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  effect,
                  style: const TextStyle(
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  warning,
                  style: const TextStyle(color: VibeColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: buttonKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _runAction(Future<AgentDeliveryResult> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.summary} ${result.detail}')),
      );
      if (result.url != null) await widget.openUrl(result.url!);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge(_DeliverySnapshot state) async {
    final preview = state.preview;
    final confirmed = await _confirm(
      title: '${preview.baseRef}에 병합할까요?',
      effect: '${preview.branchName}  →  ${preview.baseRef}',
      warning:
          '기준 브랜치를 ${preview.headSha}까지 fast-forward합니다. '
          'merge commit이나 force 동작은 만들지 않습니다.',
      buttonLabel: 'Fast-forward 병합',
      buttonKey: const ValueKey('confirm-agent-merge'),
    );
    if (confirmed) await _runAction(widget.merge);
  }

  Future<void> _push(_DeliverySnapshot state) async {
    final preview = state.preview;
    final confirmed = await _confirm(
      title: '${preview.remoteName}에 브랜치를 push할까요?',
      effect:
          '${preview.branchName}  →  ${preview.remoteName}/${preview.branchName}',
      warning: '원격 저장소를 변경합니다. 일반 push만 실행하며, 원격 변경과 충돌하면 중단합니다.',
      buttonLabel: preview.remoteBranchExists ? '브랜치 업데이트' : '브랜치 게시',
      buttonKey: const ValueKey('confirm-agent-push'),
    );
    if (confirmed) await _runAction(widget.push);
  }

  Future<void> _createPullRequest(_DeliverySnapshot state) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PR 제목을 입력해 주세요.')));
      return;
    }
    final preview = state.preview;
    final confirmed = await _confirm(
      title: 'Pull Request를 만들까요?',
      effect: '${preview.branchName}  →  ${preview.baseRef}\n$title',
      warning: 'GitHub에 새 Pull Request를 생성합니다. 제목과 본문은 이 화면에 입력한 내용으로 전송됩니다.',
      buttonLabel: 'PR 생성',
      buttonKey: const ValueKey('confirm-agent-pr'),
    );
    if (!confirmed) return;
    await _runAction(
      () => widget.createPullRequest(
        AgentPullRequestDraft(title: title, body: _bodyController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
      child: Column(
        children: [
          _DeliveryHeader(
            worktree: widget.worktree,
            busy: _busy,
            onRefresh: _busy ? null : () => setState(_reload),
            onClose: _busy ? null : () => Navigator.of(context).pop(),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<_DeliverySnapshot>(
              future: _snapshot,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _DeliveryMessage(
                    icon: Icons.error_outline,
                    text: '${snapshot.error}'.replaceFirst('Bad state: ', ''),
                    onRetry: () => setState(_reload),
                  );
                }
                final state = snapshot.data!;
                return _DeliveryContent(
                  state: state,
                  busy: _busy,
                  titleController: _titleController,
                  bodyController: _bodyController,
                  onMerge: () => _merge(state),
                  onPush: () => _push(state),
                  onCreatePullRequest: () => _createPullRequest(state),
                  onOpenPullRequest:
                      state.preview.existingPullRequestUrl == null
                      ? null
                      : () => widget.openUrl(
                          state.preview.existingPullRequestUrl!,
                        ),
                  onInspectConflicts: widget.inspectConflicts,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _DeliveryHeader extends StatelessWidget {
  const _DeliveryHeader({
    required this.worktree,
    required this.busy,
    required this.onRefresh,
    required this.onClose,
  });

  final AgentWorktreeRecord worktree;
  final bool busy;
  final VoidCallback? onRefresh;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 9, 12),
    child: Row(
      children: [
        const Icon(Icons.alt_route, color: VibeColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '변경 전달',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                '${worktree.hostAlias} · ${worktree.branchName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          key: const ValueKey('delivery-refresh'),
          tooltip: '전달 상태 새로고침',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '닫기',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _DeliveryContent extends StatelessWidget {
  const _DeliveryContent({
    required this.state,
    required this.busy,
    required this.titleController,
    required this.bodyController,
    required this.onMerge,
    required this.onPush,
    required this.onCreatePullRequest,
    required this.onOpenPullRequest,
    required this.onInspectConflicts,
  });

  final _DeliverySnapshot state;
  final bool busy;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final VoidCallback onMerge;
  final VoidCallback onPush;
  final VoidCallback onCreatePullRequest;
  final VoidCallback? onOpenPullRequest;
  final VoidCallback onInspectConflicts;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview;
    final actionsEnabled = state.verified && !busy;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApprovalRail(state: state),
          if (preview.conflictPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ConflictWarning(
              paths: preview.conflictPaths,
              onInspect: onInspectConflicts,
            ),
          ],
          const SizedBox(height: 16),
          _ChangeManifest(preview: preview),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final merge = _RoutePanel(
                key: const ValueKey('local-merge-route'),
                eyebrow: 'LOCAL ROUTE',
                icon: Icons.call_merge,
                title: '${preview.baseRef}에 병합',
                description: _mergeDescription(preview.mergeReadiness),
                buttonLabel: 'Fast-forward 병합',
                buttonKey: const ValueKey('merge-agent-workspace'),
                enabled: actionsEnabled && preview.canMerge,
                onPressed: onMerge,
              );
              final review = _PullRequestRoute(
                preview: preview,
                verified: actionsEnabled,
                busy: busy,
                titleController: titleController,
                bodyController: bodyController,
                onPush: onPush,
                onCreate: onCreatePullRequest,
                onOpen: onOpenPullRequest,
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  children: [merge, const SizedBox(height: 12), review],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: merge),
                  const SizedBox(width: 12),
                  Expanded(child: review),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ConflictWarning extends StatelessWidget {
  const _ConflictWarning({required this.paths, required this.onInspect});

  final List<String> paths;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('delivery-conflict-warning'),
    decoration: BoxDecoration(
      color: VibeColors.warning.withValues(alpha: 0.08),
      border: Border.all(color: VibeColors.warning.withValues(alpha: 0.55)),
      borderRadius: BorderRadius.circular(6),
    ),
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: VibeColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '병합 시 ${paths.length}개 파일에서 충돌이 예상됩니다',
                style: const TextStyle(
                  color: VibeColors.warning,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                paths.take(4).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 11,
                  color: VibeColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        TextButton.icon(
          key: const ValueKey('inspect-delivery-conflicts'),
          onPressed: onInspect,
          icon: const Icon(Icons.difference_outlined, size: 16),
          label: const Text('문제 파일 보기'),
        ),
      ],
    ),
  );
}

class _ApprovalRail extends StatelessWidget {
  const _ApprovalRail({required this.state});

  final _DeliverySnapshot state;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview;
    final test = state.testState.lastResult;
    final items = [
      (
        label: 'COMMIT',
        value: preview.hasCommits
            ? '${preview.aheadCount}개 준비됨'
            : '전달할 commit 없음',
        ok: preview.hasCommits,
      ),
      (
        label: 'VERIFY',
        value: state.verified
            ? '${test!.command} · 통과'
            : state.testState.isStale
            ? '변경 후 재검증 필요'
            : '통과한 검증 필요',
        ok: state.verified,
      ),
      (label: 'APPROVE', value: '각 전달 동작에서 직접 승인', ok: false),
    ];
    return Container(
      decoration: BoxDecoration(
        color: VibeColors.terminal,
        border: Border.all(color: VibeColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              const SizedBox(height: 62, child: VerticalDivider(width: 1)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(
                      items[index].ok
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: items[index].ok
                          ? VibeColors.statusConnected
                          : VibeColors.onSurfaceDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[index].label,
                            style: const TextStyle(
                              color: VibeColors.onSurfaceDim,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            items[index].value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangeManifest extends StatelessWidget {
  const _ChangeManifest({required this.preview});

  final AgentDeliveryPreview preview;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: VibeColors.surface,
      border: Border.all(color: VibeColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${preview.branchName}  →  ${preview.baseRef}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${preview.changedFiles} files  +${preview.additions}  -${preview.deletions}',
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (preview.commits.isEmpty)
          const Text(
            '기준 브랜치보다 앞선 commit이 없습니다.',
            style: TextStyle(color: VibeColors.onSurfaceDim),
          )
        else
          for (final commit in preview.commits.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  Text(
                    commit.shortSha,
                    style: const TextStyle(
                      color: VibeColors.secondary,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      commit.subject,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    commit.author,
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
        if (preview.commits.length > 8)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              '외 ${preview.commits.length - 8}개 commit',
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 11,
              ),
            ),
          ),
      ],
    ),
  );
}

class _RoutePanel extends StatelessWidget {
  const _RoutePanel({
    super.key,
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonKey,
    required this.enabled,
    required this.onPressed,
  });

  final String eyebrow;
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final Key buttonKey;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: VibeColors.surface,
      border: Border.all(color: VibeColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: VibeColors.onSurfaceDim,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(icon, size: 20, color: VibeColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            color: VibeColors.onSurfaceMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: buttonKey,
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, size: 17),
          label: Text(buttonLabel),
        ),
      ],
    ),
  );
}

class _PullRequestRoute extends StatelessWidget {
  const _PullRequestRoute({
    required this.preview,
    required this.verified,
    required this.busy,
    required this.titleController,
    required this.bodyController,
    required this.onPush,
    required this.onCreate,
    required this.onOpen,
  });

  final AgentDeliveryPreview preview;
  final bool verified;
  final bool busy;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final VoidCallback onPush;
  final VoidCallback onCreate;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: VibeColors.surface,
      border: Border.all(color: VibeColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'REVIEW ROUTE',
          style: TextStyle(
            color: VibeColors.onSurfaceDim,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.merge_type, size: 20, color: VibeColors.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preview.remoteName == null
                    ? 'Git remote 없음'
                    : '${preview.remoteName} · Pull Request',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('agent-pr-title'),
          controller: titleController,
          enabled: !busy,
          maxLength: 256,
          decoration: const InputDecoration(
            labelText: 'PR 제목',
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('agent-pr-body'),
          controller: bodyController,
          enabled: !busy,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'PR 본문'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('push-agent-branch'),
          onPressed: verified && preview.canPush ? onPush : null,
          icon: const Icon(Icons.cloud_upload_outlined, size: 17),
          label: Text(preview.remoteBranchExists ? '원격 브랜치 업데이트' : '원격 브랜치 게시'),
        ),
        const SizedBox(height: 7),
        FilledButton.icon(
          key: const ValueKey('create-agent-pr'),
          onPressed:
              onOpen ??
              (verified && preview.canCreatePullRequest ? onCreate : null),
          icon: Icon(
            onOpen != null ? Icons.open_in_new : Icons.merge_type,
            size: 17,
          ),
          label: Text(onOpen != null ? '열린 PR 보기' : 'Pull Request 생성'),
        ),
      ],
    ),
  );
}

class _DeliveryMessage extends StatelessWidget {
  const _DeliveryMessage({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: VibeColors.onSurfaceDim),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}

String _mergeDescription(AgentDeliveryMergeReadiness readiness) =>
    switch (readiness) {
      AgentDeliveryMergeReadiness.ready =>
        '기준 작업 트리를 움직이는 로컬 병합입니다. fast-forward가 아니면 실행하지 않습니다.',
      AgentDeliveryMergeReadiness.alreadyMerged => '기준 브랜치가 이미 이 변경을 포함합니다.',
      AgentDeliveryMergeReadiness.worktreeDirty => '커밋하지 않은 변경을 먼저 처리해야 합니다.',
      AgentDeliveryMergeReadiness.baseNotCheckedOut =>
        '저장소 루트에서 기준 브랜치를 checkout해야 합니다.',
      AgentDeliveryMergeReadiness.baseDirty => '기준 작업 트리의 변경을 먼저 처리해야 합니다.',
      AgentDeliveryMergeReadiness.diverged =>
        '브랜치가 갈라졌습니다. Agent 브랜치에서 기준 브랜치를 먼저 반영해야 합니다.',
    };
