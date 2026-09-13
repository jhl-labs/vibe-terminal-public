import 'package:flutter/material.dart';

import '../../agent/agent_launcher.dart';
import '../../app/theme.dart';
import '../../settings/app_settings.dart';

typedef AgentLaunchProfileSaver = void Function(AgentLaunchProfile profile);
typedef AgentLaunchProfileRemover = void Function(String id);

Future<AgentLaunchSpec?> showAgentLaunchDialog(
  BuildContext context, {
  required AgentLaunchPreferences preferences,
  AgentCli initialCli = AgentCli.claude,
  required AgentLaunchProfileSaver saveProfile,
  required AgentLaunchProfileRemover removeProfile,
}) => showDialog<AgentLaunchSpec>(
  context: context,
  builder: (_) => _AgentLaunchDialog(
    preferences: preferences,
    initialCli: initialCli,
    saveProfile: saveProfile,
    removeProfile: removeProfile,
  ),
);

class _AgentLaunchDialog extends StatefulWidget {
  const _AgentLaunchDialog({
    required this.preferences,
    required this.initialCli,
    required this.saveProfile,
    required this.removeProfile,
  });

  final AgentLaunchPreferences preferences;
  final AgentCli initialCli;
  final AgentLaunchProfileSaver saveProfile;
  final AgentLaunchProfileRemover removeProfile;

  @override
  State<_AgentLaunchDialog> createState() => _AgentLaunchDialogState();
}

class _AgentLaunchDialogState extends State<_AgentLaunchDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _branchController;
  late final TextEditingController _argumentsController;
  final Map<AgentCli, List<String>> _argumentsByCli = {};
  late AgentCli _cli;
  late bool _isolated;
  late List<AgentLaunchProfile> _profiles;
  String? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    _cli = widget.initialCli;
    _isolated = widget.preferences.isolateByDefault;
    _profiles = List.of(widget.preferences.profiles);
    for (final cli in AgentCli.values) {
      _argumentsByCli[cli] = widget.preferences.argumentsFor(cli.name);
    }
    _argumentsController = TextEditingController(
      text: _argumentsByCli[_cli]!.join('\n'),
    );
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}-'
        '${twoDigits(now.hour)}${twoDigits(now.minute)}';
    _branchController = TextEditingController(text: 'vibe/agent-$stamp');
  }

  @override
  void dispose() {
    _branchController.dispose();
    _argumentsController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      AgentLaunchSpec(
        cli: _cli,
        isolatedWorktree: _isolated,
        branchName: _isolated ? _branchController.text.trim() : null,
        arguments: _argumentsFromText(),
      ),
    );
  }

  List<String> _argumentsFromText() => [
    for (final line in _argumentsController.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  void _selectCli(AgentCli cli) {
    _argumentsByCli[_cli] = _argumentsFromText();
    setState(() {
      _cli = cli;
      _selectedProfileId = null;
      _argumentsController.text = _argumentsByCli[cli]!.join('\n');
    });
  }

  void _applyProfile(AgentLaunchProfile profile) {
    final cli = AgentCli.values
        .where((item) => item.name == profile.cliName)
        .firstOrNull;
    if (cli == null) return;
    _argumentsByCli[_cli] = _argumentsFromText();
    setState(() {
      _selectedProfileId = profile.id;
      _cli = cli;
      _isolated = profile.isolateWorktree;
      _argumentsByCli[cli] = List.of(profile.arguments);
      _argumentsController.text = profile.arguments.join('\n');
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final selected = _profiles
        .where((item) => item.id == _selectedProfileId)
        .firstOrNull;
    final name = await _requestProfileName(
      context,
      title: selected == null ? 'Agent 프로필 저장' : 'Agent 프로필 업데이트',
      initialValue: selected?.name ?? '${_cli.label} 작업',
    );
    if (name == null || !mounted) return;
    final profile = AgentLaunchProfile(
      id: selected?.id ?? 'agent-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      cliName: _cli.name,
      arguments: List.unmodifiable(_argumentsFromText()),
      isolateWorktree: _isolated,
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

  Future<void> _removeProfile() async {
    final profile = _profiles
        .where((item) => item.id == _selectedProfileId)
        .firstOrNull;
    if (profile == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${profile.name} 프로필을 삭제할까요?'),
        content: const Text('현재 폼의 값과 이미 실행 중인 Agent에는 영향을 주지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('confirm-remove-agent-profile'),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('새 Agent 세션'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AgentProfileRack(
                profiles: _profiles,
                selectedId: _selectedProfileId,
                onSelected: _applyProfile,
                onSave: _saveProfile,
                onRemove: _selectedProfileId == null ? null : _removeProfile,
              ),
              const SizedBox(height: 16),
              const Text('Agent'),
              const SizedBox(height: 8),
              SegmentedButton<AgentCli>(
                segments: [
                  for (final cli in AgentCli.values)
                    ButtonSegment(value: cli, label: Text(cli.label)),
                ],
                selected: {_cli},
                onSelectionChanged: (selection) => _selectCli(selection.single),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('agent-cli-arguments'),
                controller: _argumentsController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'CLI 기본 인자',
                  hintText: '--model\nmodel-name',
                  helperText:
                      '인자 하나를 한 줄에 입력하며 Agent별로 기억합니다. '
                      '토큰·비밀번호는 입력하지 마세요.',
                ),
                validator: (value) {
                  final arguments = _argumentsFromText();
                  if (arguments.length > 20) {
                    return 'CLI 인자는 최대 20개까지 사용할 수 있습니다.';
                  }
                  if (arguments.any((argument) => argument.length > 500)) {
                    return '각 CLI 인자는 500자 이하여야 합니다.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isolated,
                title: const Text('Git worktree로 격리'),
                subtitle: const Text(
                  '현재 저장소와 같은 위치의 .vibe-worktrees에 독립 작업 폴더를 만듭니다.',
                ),
                onChanged: (value) =>
                    setState(() => _isolated = value ?? false),
              ),
              if (_isolated) ...[
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('agent-branch-name'),
                  controller: _branchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '새 브랜치',
                    hintText: 'vibe/agent-task',
                    helperText: '기준 커밋은 현재 저장소의 HEAD입니다.',
                  ),
                  validator: (value) =>
                      AgentLaunchCommandBuilder.validateBranchName(value ?? ''),
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _isolated
                    ? '세션을 닫아도 worktree와 브랜치는 보존됩니다. 정리는 Git에서 직접 수행할 수 있습니다.'
                    : '원본과 같은 작업 폴더를 공유합니다. 동시에 파일을 수정하면 충돌할 수 있습니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Agent 시작')),
      ],
    );
  }
}

class _AgentProfileRack extends StatelessWidget {
  const _AgentProfileRack({
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
    required this.onSave,
    required this.onRemove,
  });

  final List<AgentLaunchProfile> profiles;
  final String? selectedId;
  final ValueChanged<AgentLaunchProfile> onSelected;
  final VoidCallback onSave;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final selected = profiles
        .where((item) => item.id == selectedId)
        .firstOrNull;
    return Container(
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        border: Border.all(color: VibeColors.borderSoft),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 7, 9),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 17, color: VibeColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<String>(
              key: const ValueKey('agent-profile-menu'),
              tooltip: 'Agent 프로필 선택',
              onSelected: (id) {
                for (final profile in profiles) {
                  if (profile.id == id) onSelected(profile);
                }
              },
              itemBuilder: (_) => [
                if (profiles.isEmpty)
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('저장된 프로필 없음'),
                  ),
                for (final profile in profiles)
                  PopupMenuItem(
                    value: profile.id,
                    child: Text('${profile.name} · ${profile.cliName}'),
                  ),
              ],
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'AGENT PROFILE',
                      style: TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      selected?.name ?? '직접 설정',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('save-agent-profile'),
            tooltip: selected == null ? '현재 설정을 프로필로 저장' : '선택한 프로필 업데이트',
            onPressed: onSave,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          ),
          IconButton(
            key: const ValueKey('remove-agent-profile'),
            tooltip: '선택한 프로필 삭제',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}

Future<String?> _requestProfileName(
  BuildContext context, {
  required String title,
  required String initialValue,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _AgentProfileNameDialog(title: title, initialValue: initialValue),
);

class _AgentProfileNameDialog extends StatefulWidget {
  const _AgentProfileNameDialog({
    required this.title,
    required this.initialValue,
  });

  final String title;
  final String initialValue;

  @override
  State<_AgentProfileNameDialog> createState() =>
      _AgentProfileNameDialogState();
}

class _AgentProfileNameDialogState extends State<_AgentProfileNameDialog> {
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
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: TextFormField(
        key: const ValueKey('agent-profile-name'),
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
        key: const ValueKey('confirm-save-agent-profile'),
        onPressed: _submit,
        child: const Text('프로필 저장'),
      ),
    ],
  );
}
