import 'dart:async';

import 'package:flutter/material.dart';

import '../../agent/agent_workspace_run.dart';
import '../../agent/agent_workspace_run_probe.dart';
import '../../agent/agent_worktree.dart';
import '../../app/theme.dart';
import '../../settings/app_settings.dart';

typedef AgentWorkspaceRunStateLoader =
    Future<AgentWorkspaceRunState> Function();
typedef AgentWorkspaceRunStarter =
    Future<AgentWorkspaceRunRecord> Function(String command);
typedef AgentWorkspaceRunStopper = Future<void> Function();
typedef AgentWorkspaceRunUrlOpener = Future<void> Function(Uri uri);
typedef AgentWorkspaceRunProbeCallback =
    Future<AgentWorkspaceProbeResult> Function(Uri uri);
typedef AgentRunProfileSaver = void Function(AgentRunProfile profile);
typedef AgentRunProfileRemover = void Function(String id);

Future<void> showAgentWorkspaceRunDialog(
  BuildContext context, {
  required AgentWorktreeRecord worktree,
  required AgentWorkspaceRunStateLoader load,
  required AgentWorkspaceRunStarter start,
  required AgentWorkspaceRunStarter restart,
  required AgentWorkspaceRunStopper stop,
  required AgentWorkspaceRunUrlOpener openUrl,
  required AgentWorkspaceRunProbeCallback probeUrl,
  required List<AgentRunProfile> profiles,
  required AgentRunProfileSaver saveProfile,
  required AgentRunProfileRemover removeProfile,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AgentWorkspaceRunDialog(
    worktree: worktree,
    load: load,
    start: start,
    restart: restart,
    stop: stop,
    openUrl: openUrl,
    probeUrl: probeUrl,
    profiles: profiles,
    saveProfile: saveProfile,
    removeProfile: removeProfile,
  ),
);

class _AgentWorkspaceRunDialog extends StatefulWidget {
  const _AgentWorkspaceRunDialog({
    required this.worktree,
    required this.load,
    required this.start,
    required this.restart,
    required this.stop,
    required this.openUrl,
    required this.probeUrl,
    required this.profiles,
    required this.saveProfile,
    required this.removeProfile,
  });

  final AgentWorktreeRecord worktree;
  final AgentWorkspaceRunStateLoader load;
  final AgentWorkspaceRunStarter start;
  final AgentWorkspaceRunStarter restart;
  final AgentWorkspaceRunStopper stop;
  final AgentWorkspaceRunUrlOpener openUrl;
  final AgentWorkspaceRunProbeCallback probeUrl;
  final List<AgentRunProfile> profiles;
  final AgentRunProfileSaver saveProfile;
  final AgentRunProfileRemover removeProfile;

  @override
  State<_AgentWorkspaceRunDialog> createState() =>
      _AgentWorkspaceRunDialogState();
}

class _AgentWorkspaceRunDialogState extends State<_AgentWorkspaceRunDialog> {
  final _commandController = TextEditingController();
  late Future<AgentWorkspaceRunState> _state;
  Timer? _pollTimer;
  bool _busy = false;
  bool _commandInitialized = false;
  AgentWorkspaceRunState? _lastState;
  final Map<String, AgentWorkspaceProbeResult> _probes = {};
  final Set<String> _probing = {};
  var _probeGeneration = 0;
  late List<AgentRunProfile> _profiles;
  String? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    _profiles = List.of(widget.profiles);
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
      if (!mounted || !identical(_state, request)) return;
      _lastState = state;
      if (!_commandInitialized) {
        _commandInitialized = true;
        _commandController.text = state.suggestedCommand ?? '';
      }
      _schedulePolling(state.running);
      _probeUrls(state);
      setState(() {});
    }, onError: (_) {});
  }

  void _probeUrls(AgentWorkspaceRunState state) {
    final urls = state.lastRun?.urls ?? const <Uri>[];
    final activeKeys = urls.map((url) => url.toString()).toSet();
    _probes.removeWhere((key, _) => !activeKeys.contains(key));
    _probing.removeWhere((key) => !activeKeys.contains(key));
    if (!state.running) return;
    final now = DateTime.now();
    for (final url in urls) {
      final key = url.toString();
      final previous = _probes[key];
      if (_probing.contains(key) ||
          (previous != null &&
              now.difference(previous.checkedAt) <
                  const Duration(seconds: 3))) {
        continue;
      }
      _probing.add(key);
      final generation = _probeGeneration;
      unawaited(
        widget
            .probeUrl(url)
            .then(
              (result) {
                if (!mounted || generation != _probeGeneration) return;
                setState(() {
                  _probing.remove(key);
                  _probes[key] = result;
                });
              },
              onError: (Object error) {
                if (!mounted || generation != _probeGeneration) return;
                setState(() {
                  _probing.remove(key);
                  _probes[key] = AgentWorkspaceProbeResult(
                    sourceUri: url,
                    targetUri: url,
                    status: AgentWorkspaceProbeStatus.unreachable,
                    checkedAt: DateTime.now(),
                    latency: Duration.zero,
                    detail: '$error'.replaceFirst('Bad state: ', ''),
                  );
                });
              },
            ),
      );
    }
  }

  void _schedulePolling(bool running) {
    _pollTimer?.cancel();
    if (!running) return;
    _pollTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && !_busy) setState(_reload);
    });
  }

  Future<bool> _confirmRestart() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('개발 서버를 재시작할까요?'),
          content: const Text(
            '현재 프로세스 트리를 종료한 뒤 같은 worktree에서 입력한 명령으로 다시 시작합니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: const ValueKey('confirm-workspace-run-restart'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('종료 후 재시작'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _startOrRestart(bool running) async {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('실행 명령을 입력해 주세요.')));
      return;
    }
    if (running && !await _confirmRestart()) return;
    await _perform(
      () => running ? widget.restart(command) : widget.start(command),
    );
  }

  void _applyRunProfile(AgentRunProfile profile) {
    setState(() {
      _selectedProfileId = profile.id;
      _commandController.text = profile.command;
    });
  }

  Future<void> _saveRunProfile() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장할 실행 명령을 입력해 주세요.')));
      return;
    }
    final selected = _profiles
        .where((item) => item.id == _selectedProfileId)
        .firstOrNull;
    final name = await _requestRunProfileName(
      context,
      initialValue: selected?.name ?? '개발 서버',
      updating: selected != null,
    );
    if (name == null || !mounted) return;
    final profile = AgentRunProfile(
      id: selected?.id ?? 'run-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      command: command,
    );
    widget.saveProfile(profile);
    setState(() {
      _profiles = [
        for (final item in _profiles)
          if (item.id != profile.id) item,
        profile,
      ];
      _selectedProfileId = profile.id;
    });
  }

  Future<void> _removeRunProfile() async {
    final profile = _profiles
        .where((item) => item.id == _selectedProfileId)
        .firstOrNull;
    if (profile == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${profile.name} 실행 프로필을 삭제할까요?'),
        content: const Text('현재 입력된 명령과 실행 중인 서버에는 영향을 주지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-remove-run-profile'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('프로필 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.removeProfile(profile.id);
    setState(() {
      _profiles.removeWhere((item) => item.id == profile.id);
      _selectedProfileId = null;
    });
  }

  Future<void> _stop() => _perform(() async {
    await widget.stop();
    return null;
  });

  Future<void> _perform(Future<Object?> Function() action) async {
    if (_busy) return;
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _probeGeneration++;
      _probes.clear();
      _probing.clear();
    });
    try {
      await action();
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

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 940, maxHeight: 760),
      child: Column(
        children: [
          _RunHeader(
            worktree: widget.worktree,
            busy: _busy,
            onRefresh: _busy ? null : () => setState(_reload),
            onClose: () => Navigator.of(context).pop(),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<AgentWorkspaceRunState>(
              future: _state,
              builder: (context, snapshot) {
                final state = snapshot.data ?? _lastState;
                if (state == null &&
                    snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError && state == null) {
                  return _RunMessage(
                    text: '${snapshot.error}'.replaceFirst('Bad state: ', ''),
                    onRetry: () => setState(_reload),
                  );
                }
                return _RunContent(
                  state: state!,
                  controller: _commandController,
                  busy: _busy,
                  onStartOrRestart: () => _startOrRestart(state.running),
                  onStop: _stop,
                  onOpenUrl: widget.openUrl,
                  probes: _probes,
                  probing: _probing,
                  profiles: _profiles,
                  selectedProfileId: _selectedProfileId,
                  onSelectProfile: _applyRunProfile,
                  onSaveProfile: _saveRunProfile,
                  onRemoveProfile: _selectedProfileId == null
                      ? null
                      : _removeRunProfile,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({
    required this.worktree,
    required this.busy,
    required this.onRefresh,
    required this.onClose,
  });

  final AgentWorktreeRecord worktree;
  final bool busy;
  final VoidCallback? onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 9, 12),
    child: Row(
      children: [
        const Icon(Icons.play_circle_outline, color: VibeColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Run / Preview',
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
          key: const ValueKey('workspace-run-refresh'),
          tooltip: '실행 상태 새로고침',
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

class _RunContent extends StatelessWidget {
  const _RunContent({
    required this.state,
    required this.controller,
    required this.busy,
    required this.onStartOrRestart,
    required this.onStop,
    required this.onOpenUrl,
    required this.probes,
    required this.probing,
    required this.profiles,
    required this.selectedProfileId,
    required this.onSelectProfile,
    required this.onSaveProfile,
    required this.onRemoveProfile,
  });

  final AgentWorkspaceRunState state;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onStartOrRestart;
  final VoidCallback onStop;
  final AgentWorkspaceRunUrlOpener onOpenUrl;
  final Map<String, AgentWorkspaceProbeResult> probes;
  final Set<String> probing;
  final List<AgentRunProfile> profiles;
  final String? selectedProfileId;
  final ValueChanged<AgentRunProfile> onSelectProfile;
  final VoidCallback onSaveProfile;
  final VoidCallback? onRemoveProfile;

  @override
  Widget build(BuildContext context) {
    final run = state.lastRun;
    final presentation = _runPresentation(
      run,
      stale: state.isStale,
      probes: probes,
      probing: probing,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: presentation.color.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  color: presentation.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Icon(presentation.icon, color: presentation.color, size: 18),
              const SizedBox(width: 8),
              Text(
                presentation.label,
                style: TextStyle(
                  color: presentation.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (run != null) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${run.headSha} · ${_durationLabel(run)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 11,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
            ],
          ),
        ),
        _ReadinessRail(run: run, probes: probes, probing: probing),
        _RunProfileRack(
          profiles: profiles,
          selectedId: selectedProfileId,
          onSelected: onSelectProfile,
          onSave: onSaveProfile,
          onRemove: onRemoveProfile,
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('workspace-run-command'),
                  controller: controller,
                  enabled: !busy,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 4000,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  decoration: const InputDecoration(
                    labelText: '개발 서버 명령',
                    helperText: '현재 Agent worktree에서 실행하며, 창을 닫아도 계속 실행됩니다.',
                    prefixIcon: Icon(Icons.terminal, size: 19),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (state.running)
                OutlinedButton.icon(
                  key: const ValueKey('stop-workspace-run'),
                  onPressed: busy ? null : onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('중지'),
                ),
              if (state.running) const SizedBox(width: 7),
              FilledButton.icon(
                key: const ValueKey('start-workspace-run'),
                onPressed: busy ? null : onStartOrRestart,
                icon: Icon(
                  state.running ? Icons.restart_alt : Icons.play_arrow,
                  size: 18,
                ),
                label: Text(state.running ? '재시작' : '실행'),
              ),
            ],
          ),
        ),
        if (run != null && run.urls.isNotEmpty) ...[
          const Divider(height: 1),
          _DetectedUrls(
            urls: run.urls,
            probes: probes,
            probing: probing,
            onOpen: onOpenUrl,
          ),
        ],
        const Divider(height: 1),
        Expanded(child: _RunOutput(record: run)),
      ],
    );
  }
}

class _DetectedUrls extends StatelessWidget {
  const _DetectedUrls({
    required this.urls,
    required this.probes,
    required this.probing,
    required this.onOpen,
  });

  final List<Uri> urls;
  final Map<String, AgentWorkspaceProbeResult> probes;
  final Set<String> probing;
  final AgentWorkspaceRunUrlOpener onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'DETECTED URLS',
          style: TextStyle(
            color: VibeColors.onSurfaceDim,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 7,
          children: [
            for (var index = 0; index < urls.length; index++)
              _DetectedUrl(
                index: index,
                url: urls[index],
                result: probes[urls[index].toString()],
                probing: probing.contains(urls[index].toString()),
                onOpen: onOpen,
              ),
          ],
        ),
      ],
    ),
  );
}

class _RunProfileRack extends StatelessWidget {
  const _RunProfileRack({
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
    required this.onSave,
    required this.onRemove,
  });

  final List<AgentRunProfile> profiles;
  final String? selectedId;
  final ValueChanged<AgentRunProfile> onSelected;
  final VoidCallback onSave;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final selected = profiles
        .where((item) => item.id == selectedId)
        .firstOrNull;
    return Container(
      color: VibeColors.surfaceHigh,
      padding: const EdgeInsets.fromLTRB(14, 7, 7, 7),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 17, color: VibeColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<String>(
              key: const ValueKey('run-profile-menu'),
              tooltip: '실행 프로필 선택',
              onSelected: (id) {
                for (final profile in profiles) {
                  if (profile.id == id) onSelected(profile);
                }
              },
              itemBuilder: (_) => [
                if (profiles.isEmpty)
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('저장된 실행 프로필 없음'),
                  ),
                for (final profile in profiles)
                  PopupMenuItem(
                    value: profile.id,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name),
                        Text(
                          profile.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VibeColors.onSurfaceDim,
                            fontFamily: kMonoFontFamily,
                            fontFamilyFallback: kMonoFontFallback,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'RUN PROFILE',
                      style: TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      selected?.name ?? '프로젝트 제안 또는 직접 입력',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('save-run-profile'),
            tooltip: selected == null ? '현재 명령을 프로필로 저장' : '선택한 프로필 업데이트',
            onPressed: onSave,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          ),
          IconButton(
            key: const ValueKey('remove-run-profile'),
            tooltip: '선택한 실행 프로필 삭제',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}

Future<String?> _requestRunProfileName(
  BuildContext context, {
  required String initialValue,
  required bool updating,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _RunProfileNameDialog(initialValue: initialValue, updating: updating),
);

class _RunProfileNameDialog extends StatefulWidget {
  const _RunProfileNameDialog({
    required this.initialValue,
    required this.updating,
  });

  final String initialValue;
  final bool updating;

  @override
  State<_RunProfileNameDialog> createState() => _RunProfileNameDialogState();
}

class _RunProfileNameDialogState extends State<_RunProfileNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.updating ? '실행 프로필 업데이트' : '실행 프로필 저장'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        key: const ValueKey('run-profile-name'),
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(labelText: '프로필 이름'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '프로필 이름을 입력하세요.' : null,
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const ValueKey('confirm-save-run-profile'),
        onPressed: _submit,
        child: const Text('프로필 저장'),
      ),
    ],
  );
}

class _DetectedUrl extends StatelessWidget {
  const _DetectedUrl({
    required this.index,
    required this.url,
    required this.result,
    required this.probing,
    required this.onOpen,
  });

  final int index;
  final Uri url;
  final AgentWorkspaceProbeResult? result;
  final bool probing;
  final AgentWorkspaceRunUrlOpener onOpen;

  @override
  Widget build(BuildContext context) {
    final status = _probePresentation(result, probing: probing);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Container(
        decoration: BoxDecoration(
          color: VibeColors.surfaceHigh,
          border: Border.all(color: VibeColors.borderSoft),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(10, 7, 7, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 15, color: status.color),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    url.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: status.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: ValueKey('open-workspace-run-url-$index'),
              tooltip: 'Preview 열기',
              onPressed: () => onOpen(url),
              icon: const Icon(Icons.open_in_browser, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessRail extends StatelessWidget {
  const _ReadinessRail({
    required this.run,
    required this.probes,
    required this.probing,
  });

  final AgentWorkspaceRunRecord? run;
  final Map<String, AgentWorkspaceProbeResult> probes;
  final Set<String> probing;

  @override
  Widget build(BuildContext context) {
    final processActive = run?.running == true;
    final endpoints = run?.urls.length ?? 0;
    final ready = probes.values.where((probe) => probe.ready).length;
    final unsupported = probes.values
        .where((probe) => probe.status == AgentWorkspaceProbeStatus.unsupported)
        .length;
    final items = [
      (
        label: 'PROCESS',
        value: processActive ? '실행 중' : '대기',
        active: processActive,
        color: VibeColors.secondary,
      ),
      (
        label: 'ENDPOINT',
        value: endpoints == 0 ? 'URL 대기' : '$endpoints개 발견',
        active: endpoints > 0,
        color: VibeColors.warning,
      ),
      (
        label: 'RESPONSE',
        value: ready > 0
            ? '$ready개 준비됨'
            : endpoints > 0 && unsupported == endpoints
            ? '수동 확인'
            : probing.isNotEmpty
            ? '확인 중'
            : '응답 대기',
        active: ready > 0,
        color: VibeColors.statusConnected,
      ),
    ];
    return Container(
      key: const ValueKey('workspace-readiness-rail'),
      color: VibeColors.surfaceHigh,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              Expanded(
                child: _ReadinessStep(
                  label: items[index].label,
                  value: items[index].value,
                  active: items[index].active,
                  color: items[index].color,
                ),
              ),
              if (index < items.length - 1)
                Container(
                  width: constraints.maxWidth < 560 ? 14 : 34,
                  height: 1,
                  color: items[index].active
                      ? items[index].color.withValues(alpha: 0.65)
                      : VibeColors.border,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadinessStep extends StatelessWidget {
  const _ReadinessStep({
    required this.label,
    required this.value,
    required this.active,
    required this.color,
  });

  final String label;
  final String value;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: active ? color : VibeColors.border,
          shape: BoxShape.circle,
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 7)]
              : null,
        ),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? color : VibeColors.onSurfaceDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RunOutput extends StatelessWidget {
  const _RunOutput({required this.record});

  final AgentWorkspaceRunRecord? record;

  @override
  Widget build(BuildContext context) {
    final output = record?.output ?? '';
    return ColoredBox(
      color: VibeColors.terminal,
      child: output.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '실행하면 서버 출력과 발견된 URL을 여기에 표시합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VibeColors.onSurfaceDim),
                ),
              ),
            )
          : SelectionArea(
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(14),
                child: Text(
                  '${record!.outputTruncated ? '[이전 출력 일부를 생략했습니다.]\n\n' : ''}$output',
                  style: const TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 12,
                    height: 1.42,
                  ),
                ),
              ),
            ),
    );
  }
}

class _RunMessage extends StatelessWidget {
  const _RunMessage({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 38,
            color: VibeColors.onSurfaceDim,
          ),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}

({String label, Color color, IconData icon}) _runPresentation(
  AgentWorkspaceRunRecord? run, {
  required bool stale,
  required Map<String, AgentWorkspaceProbeResult> probes,
  required Set<String> probing,
}) {
  if (run == null) {
    return (
      label: '실행하지 않음',
      color: VibeColors.onSurfaceMuted,
      icon: Icons.radio_button_unchecked,
    );
  }
  if (run.running) {
    final ready = probes.values.where((result) => result.ready).toList();
    if (ready.isNotEmpty) {
      final fastest = ready.reduce(
        (left, right) => left.latency <= right.latency ? left : right,
      );
      return (
        label:
            'Preview 준비됨 · HTTP ${fastest.statusCode ?? '-'} · ${fastest.latency.inMilliseconds}ms',
        color: VibeColors.statusConnected,
        icon: Icons.podcasts,
      );
    }
    final unsupported = probes.values.where(
      (result) => result.status == AgentWorkspaceProbeStatus.unsupported,
    );
    if (run.urls.isNotEmpty && unsupported.length == run.urls.length) {
      return (
        label: '프로세스 실행 중 · Preview 수동 확인',
        color: VibeColors.secondary,
        icon: Icons.open_in_browser,
      );
    }
    return (
      label: run.urls.isEmpty
          ? '프로세스 실행 중 · URL 감지 대기'
          : probing.isNotEmpty
          ? '서버 시작 중 · HTTP 응답 확인 중'
          : '서버 시작 중 · HTTP 응답 대기',
      color: VibeColors.warning,
      icon: Icons.hourglass_top,
    );
  }
  if (stale) {
    return (
      label: '코드 변경 후 재실행 필요',
      color: VibeColors.warning,
      icon: Icons.change_circle_outlined,
    );
  }
  return switch (run.outcome) {
    AgentWorkspaceRunOutcome.stopped => (
      label: '사용자가 중지함',
      color: VibeColors.onSurfaceMuted,
      icon: Icons.stop_circle_outlined,
    ),
    AgentWorkspaceRunOutcome.exited => (
      label: '프로세스 종료 · code ${run.exitCode ?? 0}',
      color: run.exitCode == 0 ? VibeColors.secondary : VibeColors.statusError,
      icon: Icons.logout,
    ),
    AgentWorkspaceRunOutcome.failed => (
      label: '실행 실패 · code ${run.exitCode ?? '-'}',
      color: VibeColors.statusError,
      icon: Icons.error_outline,
    ),
    AgentWorkspaceRunOutcome.running => throw StateError('handled above'),
  };
}

({String label, Color color, IconData icon}) _probePresentation(
  AgentWorkspaceProbeResult? result, {
  required bool probing,
}) {
  if (probing || result == null) {
    return (label: 'HTTP 응답 확인 중', color: VibeColors.warning, icon: Icons.sync);
  }
  return switch (result.status) {
    AgentWorkspaceProbeStatus.ready => (
      label:
          '준비됨 · HTTP ${result.statusCode ?? '-'} · ${result.latency.inMilliseconds}ms',
      color: VibeColors.statusConnected,
      icon: Icons.check_circle_outline,
    ),
    AgentWorkspaceProbeStatus.unreachable => (
      label: '시작 중 · ${result.detail ?? '아직 응답하지 않음'}',
      color: VibeColors.warning,
      icon: Icons.hourglass_top,
    ),
    AgentWorkspaceProbeStatus.unsupported => (
      label: result.detail ?? 'readiness 확인 미지원',
      color: VibeColors.onSurfaceDim,
      icon: Icons.help_outline,
    ),
  };
}

String _durationLabel(AgentWorkspaceRunRecord run) {
  final end = run.finishedAt ?? DateTime.now();
  final duration = end.difference(run.startedAt);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
}
