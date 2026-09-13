import 'dart:async';

import 'package:flutter/material.dart';

import '../../agent/agent_workspace_test.dart';
import '../../agent/agent_worktree.dart';
import '../../app/theme.dart';

typedef AgentWorkspaceTestStateLoader =
    Future<AgentWorkspaceTestState> Function();
typedef AgentWorkspaceTestRunner =
    Future<AgentWorkspaceTestResult> Function(String command);

Future<void> showAgentWorkspaceTestDialog(
  BuildContext context, {
  required AgentWorktreeRecord worktree,
  required AgentWorkspaceTestStateLoader load,
  required AgentWorkspaceTestRunner run,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _AgentWorkspaceTestDialog(worktree: worktree, load: load, run: run),
);

class _AgentWorkspaceTestDialog extends StatefulWidget {
  const _AgentWorkspaceTestDialog({
    required this.worktree,
    required this.load,
    required this.run,
  });

  final AgentWorktreeRecord worktree;
  final AgentWorkspaceTestStateLoader load;
  final AgentWorkspaceTestRunner run;

  @override
  State<_AgentWorkspaceTestDialog> createState() =>
      _AgentWorkspaceTestDialogState();
}

class _AgentWorkspaceTestDialogState extends State<_AgentWorkspaceTestDialog> {
  final _commandController = TextEditingController();
  late Future<AgentWorkspaceTestState> _state;
  Timer? _pollTimer;
  bool _runningHere = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _commandController.dispose();
    super.dispose();
  }

  void _reload() {
    final request = widget.load();
    _state = request;
    request.then((state) {
      if (!mounted || !identical(request, _state)) return;
      if (_commandController.text.trim().isEmpty &&
          state.suggestedCommand != null) {
        _commandController.text = state.suggestedCommand!;
      }
      _pollTimer?.cancel();
      if (state.running && !_runningHere) {
        _pollTimer = Timer(const Duration(seconds: 1), () {
          if (mounted) setState(_reload);
        });
      }
    }, onError: (_) {});
  }

  Future<void> _run() async {
    final command = _commandController.text.trim();
    if (_runningHere) return;
    if (command.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('테스트 명령을 입력해 주세요.')));
      return;
    }
    setState(() => _runningHere = true);
    try {
      final result = await widget.run(command);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_completionMessage(result))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _runningHere = false;
          _reload();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
            child: Row(
              children: [
                const Icon(Icons.fact_check_outlined, color: VibeColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Workspace 검증',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        widget.worktree.branchName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VibeColors.onSurfaceDim,
                          fontFamily: kMonoFontFamily,
                          fontFamilyFallback: kMonoFontFallback,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
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
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('workspace-test-command'),
                    controller: _commandController,
                    enabled: !_runningHere,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 4000,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    decoration: const InputDecoration(
                      labelText: '테스트 명령',
                      hintText: '예: flutter test',
                      prefixText: '> ',
                      helperText:
                          '현재 worktree에서 실행 · 15분 제한 · '
                          '최근 출력 240,000자를 앱 데이터에 보존',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const ValueKey('run-workspace-test'),
                  onPressed: _runningHere ? null : _run,
                  icon: _runningHere
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow, size: 19),
                  label: Text(_runningHere ? '실행 중' : '테스트 실행'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<AgentWorkspaceTestState>(
              future: _state,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _TestMessage(
                    icon: Icons.error_outline,
                    message: '${snapshot.error}'.replaceFirst(
                      'Bad state: ',
                      '',
                    ),
                    actionLabel: '다시 시도',
                    onAction: () => setState(_reload),
                  );
                }
                final state = snapshot.data!;
                if (state.running || _runningHere) {
                  return const _TestMessage(
                    icon: Icons.hourglass_top,
                    message: '테스트가 실행 중입니다. 창을 닫아도 실행과 결과 저장은 계속됩니다.',
                  );
                }
                final result = state.lastResult;
                if (result == null) {
                  return const _TestMessage(
                    icon: Icons.fact_check_outlined,
                    message: '아직 이 작업공간에서 저장된 테스트 결과가 없습니다.',
                  );
                }
                return _TestResultView(result: result, stale: state.isStale);
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _TestResultView extends StatelessWidget {
  const _TestResultView({required this.result, required this.stale});

  final AgentWorkspaceTestResult result;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final presentation = _testPresentation(result.outcome, stale: stale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: presentation.color.withValues(alpha: 0.08),
            border: Border(
              left: BorderSide(color: presentation.color, width: 4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(presentation.icon, color: presentation.color, size: 20),
              const SizedBox(width: 9),
              Text(
                presentation.label,
                style: TextStyle(
                  color: presentation.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${result.headSha} · ${_formatDuration(result.duration)} · '
                  '${result.finishedAt.toLocal()}',
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
              Text(
                result.exitCode == null ? 'exit —' : 'exit ${result.exitCode}',
                style: const TextStyle(
                  color: VibeColors.onSurfaceMuted,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          color: VibeColors.surfaceHigh,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            '> ${result.command}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VibeColors.onSurfaceMuted,
              fontFamily: kMonoFontFamily,
              fontFamilyFallback: kMonoFontFallback,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: VibeColors.terminal,
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Text(
                  result.output,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TestMessage extends StatelessWidget {
  const _TestMessage({
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
          Icon(icon, size: 40, color: VibeColors.onSurfaceDim),
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

({String label, Color color, IconData icon}) _testPresentation(
  AgentWorkspaceTestOutcome outcome, {
  required bool stale,
}) {
  if (stale) {
    return (
      label: '변경 후 재검증 필요',
      color: VibeColors.warning,
      icon: Icons.change_circle_outlined,
    );
  }
  return switch (outcome) {
    AgentWorkspaceTestOutcome.passed => (
      label: '테스트 통과',
      color: VibeColors.statusConnected,
      icon: Icons.check_circle_outline,
    ),
    AgentWorkspaceTestOutcome.failed => (
      label: '테스트 실패',
      color: VibeColors.statusError,
      icon: Icons.cancel_outlined,
    ),
    AgentWorkspaceTestOutcome.timedOut => (
      label: '시간 초과',
      color: VibeColors.warning,
      icon: Icons.timer_off_outlined,
    ),
    AgentWorkspaceTestOutcome.error => (
      label: '실행 오류',
      color: VibeColors.statusError,
      icon: Icons.error_outline,
    ),
  };
}

String _completionMessage(AgentWorkspaceTestResult result) =>
    switch (result.outcome) {
      AgentWorkspaceTestOutcome.passed => '테스트가 통과했습니다.',
      AgentWorkspaceTestOutcome.failed =>
        '테스트가 exit ${result.exitCode ?? '—'}로 실패했습니다.',
      AgentWorkspaceTestOutcome.timedOut => '테스트가 15분 제한을 넘어 종료됐습니다.',
      AgentWorkspaceTestOutcome.error => '테스트 실행 오류를 저장했습니다.',
    };

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes == 0 ? '${seconds}s' : '${minutes}m ${seconds}s';
}
