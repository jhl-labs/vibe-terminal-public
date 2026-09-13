import 'package:flutter/material.dart';

import '../../agent/agent_source_control.dart';
import '../../agent/agent_workspace_test.dart';
import '../../agent/agent_worktree.dart';
import '../../app/theme.dart';
import '../../settings/app_settings.dart';
import 'agent_delivery_dialog.dart';
import 'agent_conflict_dialog.dart';
import 'agent_workspace_run_dialog.dart';
import 'agent_workspace_test_dialog.dart';

typedef AgentSourceControlLoader =
    Future<AgentSourceControlSnapshot> Function();
typedef AgentFileDiffLoader =
    Future<AgentFileDiff> Function(AgentFileChange change);
typedef AgentSelectedCommitter =
    Future<AgentCommitResult> Function(
      Set<String> selectedPaths,
      String message,
    );

Future<void> showAgentSourceControlDialog(
  BuildContext context, {
  required AgentWorktreeRecord worktree,
  required AgentSourceControlLoader load,
  required AgentFileDiffLoader loadDiff,
  required AgentSelectedCommitter commit,
  required AgentConflictLoader loadConflicts,
  required AgentWorkspaceTestStateLoader loadTestState,
  required AgentWorkspaceTestRunner runTest,
  required AgentDeliveryPreviewLoader loadDeliveryPreview,
  required AgentDeliveryAction merge,
  required AgentDeliveryAction push,
  required AgentPullRequestCreator createPullRequest,
  required AgentDeliveryUrlOpener openUrl,
  required AgentWorkspaceRunStateLoader loadRunState,
  required AgentWorkspaceRunStarter startRun,
  required AgentWorkspaceRunStarter restartRun,
  required AgentWorkspaceRunStopper stopRun,
  required AgentWorkspaceRunUrlOpener openRunUrl,
  required AgentWorkspaceRunProbeCallback probeRunUrl,
  required List<AgentRunProfile> runProfiles,
  required AgentRunProfileSaver saveRunProfile,
  required AgentRunProfileRemover removeRunProfile,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AgentSourceControlDialog(
    worktree: worktree,
    load: load,
    loadDiff: loadDiff,
    commit: commit,
    loadConflicts: loadConflicts,
    loadTestState: loadTestState,
    runTest: runTest,
    loadDeliveryPreview: loadDeliveryPreview,
    merge: merge,
    push: push,
    createPullRequest: createPullRequest,
    openUrl: openUrl,
    loadRunState: loadRunState,
    startRun: startRun,
    restartRun: restartRun,
    stopRun: stopRun,
    openRunUrl: openRunUrl,
    probeRunUrl: probeRunUrl,
    runProfiles: runProfiles,
    saveRunProfile: saveRunProfile,
    removeRunProfile: removeRunProfile,
  ),
);

class _AgentSourceControlDialog extends StatefulWidget {
  const _AgentSourceControlDialog({
    required this.worktree,
    required this.load,
    required this.loadDiff,
    required this.commit,
    required this.loadConflicts,
    required this.loadTestState,
    required this.runTest,
    required this.loadDeliveryPreview,
    required this.merge,
    required this.push,
    required this.createPullRequest,
    required this.openUrl,
    required this.loadRunState,
    required this.startRun,
    required this.restartRun,
    required this.stopRun,
    required this.openRunUrl,
    required this.probeRunUrl,
    required this.runProfiles,
    required this.saveRunProfile,
    required this.removeRunProfile,
  });

  final AgentWorktreeRecord worktree;
  final AgentSourceControlLoader load;
  final AgentFileDiffLoader loadDiff;
  final AgentSelectedCommitter commit;
  final AgentConflictLoader loadConflicts;
  final AgentWorkspaceTestStateLoader loadTestState;
  final AgentWorkspaceTestRunner runTest;
  final AgentDeliveryPreviewLoader loadDeliveryPreview;
  final AgentDeliveryAction merge;
  final AgentDeliveryAction push;
  final AgentPullRequestCreator createPullRequest;
  final AgentDeliveryUrlOpener openUrl;
  final AgentWorkspaceRunStateLoader loadRunState;
  final AgentWorkspaceRunStarter startRun;
  final AgentWorkspaceRunStarter restartRun;
  final AgentWorkspaceRunStopper stopRun;
  final AgentWorkspaceRunUrlOpener openRunUrl;
  final AgentWorkspaceRunProbeCallback probeRunUrl;
  final List<AgentRunProfile> runProfiles;
  final AgentRunProfileSaver saveRunProfile;
  final AgentRunProfileRemover removeRunProfile;

  @override
  State<_AgentSourceControlDialog> createState() =>
      _AgentSourceControlDialogState();
}

class _AgentSourceControlDialogState extends State<_AgentSourceControlDialog> {
  final _messageController = TextEditingController();
  final _selectedPaths = <String>{};
  late Future<AgentSourceControlSnapshot> _snapshot;
  late Future<AgentWorkspaceTestState> _testState;
  Future<AgentFileDiff>? _diff;
  AgentFileChange? _focusedFile;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _testState = widget.loadTestState();
    _reload(initial: true);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _reload({bool initial = false}) {
    final request = widget.load();
    _snapshot = request;
    request.then(
      (snapshot) {
        if (!mounted || !identical(_snapshot, request)) return;
        final available = snapshot.files.map((file) => file.path).toSet();
        setState(() {
          _selectedPaths.removeWhere((path) => !available.contains(path));
          if (initial) {
            _selectedPaths.addAll(
              snapshot.files
                  .where((file) => !file.isConflicted)
                  .map((file) => file.path),
            );
          }
          final focusedPath = _focusedFile?.path;
          _focusedFile = snapshot.files.cast<AgentFileChange?>().firstWhere(
            (file) => file?.path == focusedPath,
            orElse: () => snapshot.files.firstOrNull,
          );
          _loadFocusedDiff();
        });
      },
      onError: (_) {
        // FutureBuilder가 사용자가 조치할 수 있는 오류 상태를 표시한다.
      },
    );
  }

  void _focus(AgentFileChange file) {
    setState(() {
      _focusedFile = file;
      _loadFocusedDiff();
    });
  }

  void _loadFocusedDiff() {
    final file = _focusedFile;
    _diff = file == null ? null : widget.loadDiff(file);
  }

  void _toggle(AgentFileChange file, bool selected) {
    if (file.isConflicted) return;
    setState(() {
      if (selected) {
        _selectedPaths.add(file.path);
      } else {
        _selectedPaths.remove(file.path);
      }
    });
  }

  Future<void> _openTests() async {
    await showAgentWorkspaceTestDialog(
      context,
      worktree: widget.worktree,
      load: widget.loadTestState,
      run: widget.runTest,
    );
    if (!mounted) return;
    setState(() {
      _testState = widget.loadTestState();
      _reload();
    });
  }

  Future<void> _openDelivery() async {
    await showAgentDeliveryDialog(
      context,
      worktree: widget.worktree,
      loadPreview: widget.loadDeliveryPreview,
      loadTestState: widget.loadTestState,
      merge: widget.merge,
      push: widget.push,
      createPullRequest: widget.createPullRequest,
      openUrl: widget.openUrl,
      inspectConflicts: _openConflicts,
    );
    if (!mounted) return;
    _refreshAll();
  }

  Future<void> _openConflicts() async {
    await showAgentConflictDialog(
      context,
      worktree: widget.worktree,
      load: widget.loadConflicts,
    );
    if (!mounted) return;
    _refreshAll();
  }

  Future<void> _openRun() async {
    Uri? selectedUrl;
    await showAgentWorkspaceRunDialog(
      context,
      worktree: widget.worktree,
      load: widget.loadRunState,
      start: widget.startRun,
      restart: widget.restartRun,
      stop: widget.stopRun,
      openUrl: (uri) async {
        selectedUrl = uri;
        if (mounted) Navigator.of(context).pop();
      },
      probeUrl: widget.probeRunUrl,
      profiles: widget.runProfiles,
      saveProfile: widget.saveRunProfile,
      removeProfile: widget.removeRunProfile,
    );
    if (!mounted) return;
    if (selectedUrl != null) {
      Navigator.of(context).pop();
      await widget.openRunUrl(selectedUrl!);
      return;
    }
    _refreshAll();
  }

  void _refreshAll() {
    setState(() {
      _testState = widget.loadTestState();
      _reload();
    });
  }

  Future<void> _confirmCommit(AgentSourceControlSnapshot snapshot) async {
    final message = _messageController.text.trim();
    if (_selectedPaths.isEmpty || _committing) return;
    if (message.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('커밋 메시지를 입력해 주세요.')));
      return;
    }
    final selectedFiles = snapshot.files
        .where((file) => _selectedPaths.contains(file.path))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${selectedFiles.length}개 파일을 커밋할까요?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final file in selectedFiles.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• ${file.path}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 12,
                      color: VibeColors.onSurfaceMuted,
                    ),
                  ),
                ),
              if (selectedFiles.length > 8)
                Text(
                  '외 ${selectedFiles.length - 8}개',
                  style: const TextStyle(color: VibeColors.onSurfaceDim),
                ),
              const SizedBox(height: 12),
              const Text(
                '선택한 파일만 stage하고 현재 브랜치에 커밋합니다. '
                'push나 merge는 실행하지 않습니다.',
                style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
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
            key: const ValueKey('confirm-agent-commit'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('선택 파일 커밋'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _committing = true);
    try {
      final result = await widget.commit(Set.of(_selectedPaths), message);
      if (!mounted) return;
      _messageController.clear();
      _selectedPaths.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.shortSha} ${result.subject} 커밋을 만들었습니다.'),
        ),
      );
      setState(() {
        _testState = widget.loadTestState();
        _reload(initial: true);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
      child: FutureBuilder<AgentSourceControlSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Column(
            children: [
              _Header(
                worktree: widget.worktree,
                snapshot: data,
                testState: _testState,
                busy: snapshot.connectionState != ConnectionState.done,
                onTest: _openTests,
                onRun: _openRun,
                onConflicts: _openConflicts,
                onDelivery: _openDelivery,
                onRefresh: _refreshAll,
                onClose: () => Navigator.of(context).pop(),
              ),
              const Divider(height: 1),
              Expanded(child: _buildContent(snapshot)),
              if (data != null) ...[
                const Divider(height: 1),
                _CommitBar(
                  controller: _messageController,
                  selectedCount: _selectedPaths.length,
                  committing: _committing,
                  onCommit: () => _confirmCommit(data),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );

  Widget _buildContent(AsyncSnapshot<AgentSourceControlSnapshot> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return _SourceMessage(
        icon: Icons.error_outline,
        message: '${snapshot.error}'.replaceFirst('Bad state: ', ''),
        actionLabel: '다시 시도',
        onAction: () => setState(_reload),
      );
    }
    final data = snapshot.data!;
    if (data.isClean) {
      return const _SourceMessage(
        icon: Icons.check_circle_outline,
        message: '커밋하지 않은 변경이 없습니다.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final files = _FileList(
          files: data.files,
          focusedPath: _focusedFile?.path,
          selectedPaths: _selectedPaths,
          onFocus: _focus,
          onToggle: _toggle,
          onSelectAll: () => setState(() {
            _selectedPaths.addAll(
              data.files
                  .where((file) => !file.isConflicted)
                  .map((file) => file.path),
            );
          }),
          onClear: () => setState(_selectedPaths.clear),
        );
        final diff = _DiffView(file: _focusedFile, diff: _diff);
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              SizedBox(height: 210, child: files),
              const Divider(height: 1),
              Expanded(child: diff),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 320, child: files),
            const VerticalDivider(width: 1),
            Expanded(child: diff),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.worktree,
    required this.snapshot,
    required this.testState,
    required this.busy,
    required this.onTest,
    required this.onRun,
    required this.onConflicts,
    required this.onDelivery,
    required this.onRefresh,
    required this.onClose,
  });

  final AgentWorktreeRecord worktree;
  final AgentSourceControlSnapshot? snapshot;
  final Future<AgentWorkspaceTestState> testState;
  final bool busy;
  final VoidCallback onTest;
  final VoidCallback onRun;
  final VoidCallback onConflicts;
  final VoidCallback onDelivery;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
    child: Row(
      children: [
        const Icon(Icons.difference_outlined, color: VibeColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                worktree.branchName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                snapshot == null
                    ? '${worktree.hostAlias} · 변경을 읽는 중'
                    : '${worktree.hostAlias} · ${snapshot!.headSha} · '
                          '${snapshot!.files.length}개 변경',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontSize: 12,
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
        FutureBuilder<AgentWorkspaceTestState>(
          future: testState,
          builder: (context, snapshot) => _TestGateButton(
            state: snapshot.data,
            loading: snapshot.connectionState != ConnectionState.done,
            onPressed: onTest,
          ),
        ),
        const SizedBox(width: 5),
        if (snapshot?.files.any((file) => file.isConflicted) == true) ...[
          OutlinedButton.icon(
            key: const ValueKey('open-agent-conflicts'),
            onPressed: busy ? null : onConflicts,
            style: OutlinedButton.styleFrom(
              foregroundColor: VibeColors.statusError,
              side: const BorderSide(color: VibeColors.statusError),
            ),
            icon: const Icon(Icons.warning_amber_rounded, size: 16),
            label: Text(
              '충돌 ${snapshot!.files.where((file) => file.isConflicted).length}',
            ),
          ),
          const SizedBox(width: 5),
        ],
        OutlinedButton.icon(
          key: const ValueKey('open-workspace-run'),
          onPressed: busy ? null : onRun,
          icon: const Icon(Icons.play_circle_outline, size: 16),
          label: const Text('실행'),
        ),
        const SizedBox(width: 5),
        OutlinedButton.icon(
          key: const ValueKey('open-agent-delivery'),
          onPressed: busy ? null : onDelivery,
          icon: const Icon(Icons.alt_route, size: 16),
          label: const Text('전달'),
        ),
        const SizedBox(width: 5),
        IconButton(
          key: const ValueKey('source-control-refresh'),
          tooltip: '변경 새로고침',
          onPressed: busy ? null : onRefresh,
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

class _TestGateButton extends StatelessWidget {
  const _TestGateButton({
    required this.state,
    required this.loading,
    required this.onPressed,
  });

  final AgentWorkspaceTestState? state;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final presentation = _testGatePresentation(state, loading: loading);
    return OutlinedButton.icon(
      key: const ValueKey('open-workspace-tests'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: presentation.color,
        side: BorderSide(color: presentation.color.withValues(alpha: 0.7)),
        minimumSize: const Size(40, 34),
      ),
      icon: Icon(presentation.icon, size: 16),
      label: Text(presentation.label),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.files,
    required this.focusedPath,
    required this.selectedPaths,
    required this.onFocus,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
  });

  final List<AgentFileChange> files;
  final String? focusedPath;
  final Set<String> selectedPaths;
  final ValueChanged<AgentFileChange> onFocus;
  final void Function(AgentFileChange, bool) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
        child: Row(
          children: [
            Text(
              '${selectedPaths.length}/${files.length} 선택',
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton(onPressed: onSelectAll, child: const Text('모두')),
            TextButton(onPressed: onClear, child: const Text('해제')),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            final presentation = _filePresentation(file.kind);
            final focused = file.path == focusedPath;
            return Material(
              color: focused ? VibeColors.surfacePressed : Colors.transparent,
              child: InkWell(
                key: ValueKey('source-file-${file.path}'),
                onTap: () => onFocus(file),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(width: 3, color: presentation.color),
                      Checkbox(
                        value: selectedPaths.contains(file.path),
                        onChanged: file.isConflicted
                            ? null
                            : (value) => onToggle(file, value ?? false),
                      ),
                      SizedBox(
                        width: 22,
                        child: Text(
                          presentation.code,
                          style: TextStyle(
                            color: presentation.color,
                            fontFamily: kMonoFontFamily,
                            fontFamilyFallback: kMonoFontFallback,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: kMonoFontFamily,
                                  fontFamilyFallback: kMonoFontFallback,
                                  fontSize: 12,
                                ),
                              ),
                              if (file.originalPath case final original?)
                                Text(
                                  '← $original',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: VibeColors.onSurfaceDim,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (file.isStaged)
                        const Tooltip(
                          message: '이미 stage됨',
                          child: Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              size: 13,
                              color: VibeColors.onSurfaceDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _DiffView extends StatelessWidget {
  const _DiffView({required this.file, required this.diff});

  final AgentFileChange? file;
  final Future<AgentFileDiff>? diff;

  @override
  Widget build(BuildContext context) {
    if (file == null || diff == null) {
      return const _SourceMessage(
        icon: Icons.article_outlined,
        message: '파일을 선택하면 diff를 표시합니다.',
      );
    }
    return FutureBuilder<AgentFileDiff>(
      future: diff,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _SourceMessage(
            icon: Icons.error_outline,
            message: '${snapshot.error}',
          );
        }
        final data = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: VibeColors.terminal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                data.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  color: VibeColors.onSurfaceMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (data.truncated)
              const MaterialBanner(
                content: Text('diff가 커서 앞부분 400,000자만 표시합니다.'),
                actions: [SizedBox.shrink()],
              ),
            Expanded(
              child: ColoredBox(
                color: VibeColors.terminal,
                child: SelectionArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text.rich(
                        TextSpan(children: _diffSpans(data.content)),
                        style: const TextStyle(
                          fontFamily: kMonoFontFamily,
                          fontFamilyFallback: kMonoFontFallback,
                          color: VibeColors.onSurfaceMuted,
                          fontSize: 12,
                          height: 1.42,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommitBar extends StatelessWidget {
  const _CommitBar({
    required this.controller,
    required this.selectedCount,
    required this.committing,
    required this.onCommit,
  });

  final TextEditingController controller;
  final int selectedCount;
  final bool committing;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('agent-commit-message'),
            controller: controller,
            enabled: !committing,
            maxLines: 2,
            minLines: 1,
            maxLength: 2000,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
            onSubmitted: (_) => onCommit(),
            decoration: const InputDecoration(
              labelText: '커밋 메시지',
              hintText: '변경 이유를 한 문장으로 입력',
              prefixIcon: Icon(Icons.commit, size: 19),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          key: const ValueKey('commit-selected-files'),
          onPressed: committing || selectedCount == 0 ? null : onCommit,
          icon: committing
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.commit, size: 18),
          label: Text('$selectedCount개 커밋'),
        ),
      ],
    ),
  );
}

class _SourceMessage extends StatelessWidget {
  const _SourceMessage({
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
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: VibeColors.onSurfaceDim),
          const SizedBox(height: 11),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 9),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

List<InlineSpan> _diffSpans(String content) => [
  for (final line in content.split('\n'))
    TextSpan(
      text: '$line\n',
      style: TextStyle(color: _diffLineColor(line)),
    ),
];

Color _diffLineColor(String line) {
  if (line.startsWith('+++') || line.startsWith('---')) {
    return VibeColors.onSurfaceMuted;
  }
  if (line.startsWith('+')) return VibeColors.statusConnected;
  if (line.startsWith('-')) return VibeColors.statusError;
  if (line.startsWith('@@')) return VibeColors.secondary;
  return VibeColors.onSurfaceMuted;
}

({String code, Color color}) _filePresentation(
  AgentFileChangeKind kind,
) => switch (kind) {
  AgentFileChangeKind.added => (code: 'A', color: VibeColors.statusConnected),
  AgentFileChangeKind.modified => (code: 'M', color: VibeColors.warning),
  AgentFileChangeKind.deleted => (code: 'D', color: VibeColors.statusError),
  AgentFileChangeKind.renamed => (code: 'R', color: VibeColors.secondary),
  AgentFileChangeKind.untracked => (code: 'U', color: VibeColors.accent),
  AgentFileChangeKind.conflicted => (code: '!', color: VibeColors.statusError),
};

({String label, Color color, IconData icon}) _testGatePresentation(
  AgentWorkspaceTestState? state, {
  required bool loading,
}) {
  if (loading) {
    return (
      label: '검증 확인 중',
      color: VibeColors.onSurfaceDim,
      icon: Icons.hourglass_top,
    );
  }
  if (state?.running == true) {
    return (label: '검증 중', color: VibeColors.secondary, icon: Icons.sync);
  }
  if (state == null || state.lastResult == null) {
    return (
      label: '검증 안 함',
      color: VibeColors.onSurfaceMuted,
      icon: Icons.fact_check_outlined,
    );
  }
  if (state.isStale) {
    return (
      label: '재검증 필요',
      color: VibeColors.warning,
      icon: Icons.change_circle_outlined,
    );
  }
  if (state.lastResult!.passed) {
    return (
      label: '검증 통과',
      color: VibeColors.statusConnected,
      icon: Icons.check_circle_outline,
    );
  }
  return (
    label: '검증 실패',
    color: VibeColors.statusError,
    icon: Icons.cancel_outlined,
  );
}
