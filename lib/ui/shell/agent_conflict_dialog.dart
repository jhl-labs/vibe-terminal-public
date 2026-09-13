import 'package:flutter/material.dart';

import '../../agent/agent_conflict.dart';
import '../../agent/agent_worktree.dart';
import '../../app/theme.dart';

typedef AgentConflictLoader = Future<AgentConflictSnapshot> Function();

Future<void> showAgentConflictDialog(
  BuildContext context, {
  required AgentWorktreeRecord worktree,
  required AgentConflictLoader load,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AgentConflictDialog(worktree: worktree, load: load),
);

class _AgentConflictDialog extends StatefulWidget {
  const _AgentConflictDialog({required this.worktree, required this.load});

  final AgentWorktreeRecord worktree;
  final AgentConflictLoader load;

  @override
  State<_AgentConflictDialog> createState() => _AgentConflictDialogState();
}

class _AgentConflictDialogState extends State<_AgentConflictDialog> {
  late Future<AgentConflictSnapshot> _snapshot;
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final request = widget.load();
    _snapshot = request;
    request.then((value) {
      if (!mounted || !identical(_snapshot, request)) return;
      final paths = value.allPaths;
      setState(() {
        if (!paths.contains(_selectedPath)) {
          _selectedPath = paths.firstOrNull;
        }
      });
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 9, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: VibeColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Git 충돌 · Agent 입력 필요',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${widget.worktree.hostAlias} · ${widget.worktree.branchName}',
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
                IconButton(
                  key: const ValueKey('conflict-refresh'),
                  tooltip: '충돌 상태 새로고침',
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
            child: FutureBuilder<AgentConflictSnapshot>(
              future: _snapshot,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ConflictMessage(
                    icon: Icons.error_outline,
                    text: '${snapshot.error}'.replaceFirst('Bad state: ', ''),
                    onRetry: () => setState(_reload),
                  );
                }
                final data = snapshot.data!;
                if (!data.hasConflicts) {
                  return _ConflictMessage(
                    icon: Icons.check_circle_outline,
                    text: '현재 충돌이 없습니다. 변경되었다면 테스트를 다시 실행해 주세요.',
                    onRetry: () => setState(_reload),
                  );
                }
                return _ConflictWorkspace(
                  snapshot: data,
                  selectedPath: _selectedPath ?? data.allPaths.first,
                  onSelect: (path) => setState(() => _selectedPath = path),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConflictWorkspace extends StatelessWidget {
  const _ConflictWorkspace({
    required this.snapshot,
    required this.selectedPath,
    required this.onSelect,
  });

  final AgentConflictSnapshot snapshot;
  final String selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    AgentConflictFile? unresolved;
    for (final file in snapshot.unresolvedFiles) {
      if (file.path == selectedPath) unresolved = file;
    }
    final detail = unresolved == null
        ? _PredictedConflictDetail(path: selectedPath)
        : _UnresolvedConflictDetail(file: unresolved);
    return LayoutBuilder(
      builder: (context, constraints) {
        final list = _ConflictFileList(
          snapshot: snapshot,
          selectedPath: selectedPath,
          onSelect: onSelect,
        );
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              SizedBox(height: 190, child: list),
              const Divider(height: 1),
              Expanded(child: detail),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 300, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

class _ConflictFileList extends StatelessWidget {
  const _ConflictFileList({
    required this.snapshot,
    required this.selectedPath,
    required this.onSelect,
  });

  final AgentConflictSnapshot snapshot;
  final String selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final unresolved = {for (final file in snapshot.unresolvedFiles) file.path};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 9),
          child: Text(
            '${snapshot.allPaths.length}개 문제 파일',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: snapshot.allPaths.length,
            itemBuilder: (context, index) {
              final path = snapshot.allPaths[index];
              final active = path == selectedPath;
              final current = unresolved.contains(path);
              return Material(
                color: active ? VibeColors.surfacePressed : Colors.transparent,
                child: InkWell(
                  onTap: () => onSelect(path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          current ? Icons.error_outline : Icons.alt_route,
                          size: 17,
                          color: current
                              ? VibeColors.statusError
                              : VibeColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: kMonoFontFamily,
                              fontFamilyFallback: kMonoFontFallback,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(
                          current ? 'UNMERGED' : 'PREDICTED',
                          style: TextStyle(
                            color: current
                                ? VibeColors.statusError
                                : VibeColors.warning,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
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
}

class _UnresolvedConflictDetail extends StatelessWidget {
  const _UnresolvedConflictDetail({required this.file});

  final AgentConflictFile file;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DetailBanner(
        title: '병합이 중단된 상태입니다',
        body: '터미널의 Agent에게 아래 세 버전을 참고해 ${file.path} 충돌을 해결하도록 요청하세요.',
        color: VibeColors.statusError,
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panes = [
              _StagePane(
                title: 'BASE · 공통 조상',
                color: VibeColors.onSurfaceDim,
                stage: file.stage(AgentConflictStageKind.ancestor),
              ),
              _StagePane(
                title: 'OURS · Agent 브랜치',
                color: VibeColors.accent,
                stage: file.stage(AgentConflictStageKind.ours),
              ),
              _StagePane(
                title: 'THEIRS · 반영할 기준',
                color: VibeColors.warning,
                stage: file.stage(AgentConflictStageKind.theirs),
              ),
            ];
            if (constraints.maxWidth < 680) {
              return ListView(
                children: [
                  for (final pane in panes) SizedBox(height: 220, child: pane),
                ],
              );
            }
            return Row(
              children: [for (final pane in panes) Expanded(child: pane)],
            );
          },
        ),
      ),
    ],
  );
}

class _StagePane extends StatelessWidget {
  const _StagePane({
    required this.title,
    required this.color,
    required this.stage,
  });

  final String title;
  final Color color;
  final AgentConflictStage? stage;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: color, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: VibeColors.surfaceHigh,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              stage == null
                  ? '(이 버전에는 파일이 없습니다.)'
                  : stage!.binary
                  ? '(바이너리 파일 · ${stage!.blobSha.substring(0, 10)})'
                  : '${stage!.content}${stage!.truncated ? '\n\n… 미리보기 생략됨' : ''}',
              style: const TextStyle(
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 11,
                height: 1.45,
                color: VibeColors.onSurfaceMuted,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PredictedConflictDetail extends StatelessWidget {
  const _PredictedConflictDetail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alt_route, size: 42, color: VibeColors.warning),
            const SizedBox(height: 14),
            const Text(
              '병합 시 충돌이 예상됩니다',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              path,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                color: VibeColors.warning,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'git merge-tree로 작업 트리를 바꾸지 않고 예측했습니다. Agent 브랜치에서 기준 브랜치를 반영한 뒤 충돌을 해결하고 다시 검증하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VibeColors.onSurfaceMuted, height: 1.45),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailBanner extends StatelessWidget {
  const _DetailBanner({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    color: color.withValues(alpha: 0.09),
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          style: const TextStyle(
            color: VibeColors.onSurfaceMuted,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _ConflictMessage extends StatelessWidget {
  const _ConflictMessage({
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
          TextButton(onPressed: onRetry, child: const Text('새로고침')),
        ],
      ),
    ),
  );
}
