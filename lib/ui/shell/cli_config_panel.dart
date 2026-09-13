import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../cli_config/cli_config_home.dart';

/// 우측 패널: 코딩 에이전트 CLI(Claude Code, Codex, OpenCode)의 전역 설정과
/// 확장(지침·스킬·커맨드·에이전트 등)을 한곳에서 보고 편집한다.
/// 개요(섹션 목록) → 섹션(파일 목록) → 편집기 순으로 들어간다.
class CliConfigPanel extends StatefulWidget {
  const CliConfigPanel({super.key, required this.app, this.home});

  final CliConfigApp app;

  /// 테스트나 다른 홈 경로를 쓸 때 주입한다. null이면 환경변수로 결정한다.
  final CliConfigHome? home;

  @override
  State<CliConfigPanel> createState() => _CliConfigPanelState();
}

class _CliConfigPanelState extends State<CliConfigPanel> {
  late final CliConfigHome? _home =
      widget.home ?? CliConfigHome.fromEnvironment(widget.app);

  CliConfigSection? _section;
  CliConfigEntry? _entry;
  List<CliConfigEntry> _entries = const [];
  Map<CliConfigSection, int> _counts = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _reloadCounts();
  }

  void _reloadCounts() {
    final home = _home;
    if (home == null) return;
    try {
      _counts = {
        for (final section in widget.app.sections)
          section: home.countEntries(section),
      };
      _error = null;
    } catch (error) {
      _error = '읽기 실패: $error';
    }
    if (mounted) setState(() {});
  }

  void _reloadEntries() {
    final home = _home;
    final section = _section;
    if (home == null || section == null) return;
    try {
      _entries = home.listEntries(section);
      _error = null;
    } catch (error) {
      _entries = const [];
      _error = '읽기 실패: $error';
    }
    if (mounted) setState(() {});
  }

  void _openSection(CliConfigSection section) {
    final home = _home;
    if (home == null) return;
    setState(() {
      _section = section;
      _entry = section.isDirectory ? null : home.fileEntry(section);
    });
    if (section.isDirectory) _reloadEntries();
  }

  void _openEntry(CliConfigEntry entry) {
    setState(() => _entry = entry);
  }

  void _back() {
    setState(() {
      if (_entry != null && _section?.isDirectory == true) {
        _entry = null;
      } else {
        _entry = null;
        _section = null;
      }
    });
    if (_section != null) {
      _reloadEntries();
    } else {
      _reloadCounts();
    }
  }

  Future<void> _createEntry() async {
    final home = _home;
    final section = _section;
    if (home == null || section == null || !section.isDirectory) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewEntryDialog(section: section),
    );
    if (name == null || !mounted) return;
    try {
      final entry = home.create(section, name);
      _reloadEntries();
      _openEntry(entry);
    } catch (error) {
      _showMessage(error is FormatException ? error.message : '$error');
    }
  }

  Future<void> _deleteEntry(CliConfigEntry entry) async {
    final home = _home;
    if (home == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: Text('${entry.name} 파일을 삭제할까요?\n되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('cli-config-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      home.delete(entry);
      if (_entry == entry) _entry = null;
      _reloadEntries();
      _showMessage('${entry.name} 을(를) 삭제했습니다.');
    } catch (error) {
      _showMessage('삭제 실패: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _showMessage('경로를 복사했습니다');
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    return Material(
      color: VibeColors.surface,
      child: home == null
          ? _MissingHome(app: widget.app)
          : _entry != null
          ? _CliFileEditor(
              key: ValueKey('cli-config-editor:${_entry!.path}'),
              home: home,
              entry: _entry!,
              onBack: _back,
              onCopyPath: _copyPath,
            )
          : _section != null
          ? _SectionView(
              home: home,
              section: _section!,
              entries: _entries,
              error: _error,
              onBack: _back,
              onRefresh: _reloadEntries,
              onCopyPath: _copyPath,
              onOpen: _openEntry,
              onCreate: _createEntry,
              onDelete: _deleteEntry,
            )
          : _OverviewView(
              home: home,
              counts: _counts,
              error: _error,
              onRefresh: _reloadCounts,
              onCopyPath: _copyPath,
              onOpen: _openSection,
            ),
    );
  }
}

class _MissingHome extends StatelessWidget {
  const _MissingHome({required this.app});

  final CliConfigApp app;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        '${app.title} 홈 디렉터리를 찾지 못했습니다. '
        '${app.rootEnvironmentHint} 환경변수를 확인하세요.',
        style: const TextStyle(
          color: VibeColors.onSurfaceMuted,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 아이콘
// ---------------------------------------------------------------------------

IconData appIconFor(CliConfigApp app) => switch (app) {
  CliConfigApp.claude => Icons.tune,
  CliConfigApp.codex => Icons.data_object,
  CliConfigApp.opencode => Icons.developer_mode,
};

IconData _sectionIcon(CliConfigSection section) => switch (section.id) {
  'settings' || 'config' => Icons.tune,
  'memory' || 'instructions' => Icons.psychology_outlined,
  'rules' => Icons.rule,
  'commands' || 'prompts' => Icons.terminal,
  'skills' => Icons.auto_awesome,
  'agents' => Icons.smart_toy_outlined,
  'keybindings' => Icons.keyboard,
  'plugins' => Icons.extension_outlined,
  'tools' => Icons.handyman_outlined,
  'themes' => Icons.palette_outlined,
  _ => Icons.folder_outlined,
};

// ---------------------------------------------------------------------------
// 공통 헤더
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              key: const ValueKey('cli-config-back'),
              tooltip: '뒤로',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(icon, color: VibeColors.accent, size: 20),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
          ...actions,
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        message,
        style: const TextStyle(color: VibeColors.statusError, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 개요: 섹션 목록
// ---------------------------------------------------------------------------

class _OverviewView extends StatelessWidget {
  const _OverviewView({
    required this.home,
    required this.counts,
    required this.error,
    required this.onRefresh,
    required this.onCopyPath,
    required this.onOpen,
  });

  final CliConfigHome home;
  final Map<CliConfigSection, int> counts;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<String> onCopyPath;
  final ValueChanged<CliConfigSection> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: appIconFor(home.app),
          title: home.app.title,
          subtitle: home.rootPath,
          actions: [
            IconButton(
              tooltip: '경로 복사',
              onPressed: () => onCopyPath(home.rootPath),
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: '새로고침',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        if (error != null) _ErrorNote(error!),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: [
              for (final section in home.app.sections)
                _SectionTile(
                  section: section,
                  count: counts[section],
                  onTap: () => onOpen(section),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.count,
    required this.onTap,
  });

  final CliConfigSection section;
  final int? count;
  final VoidCallback onTap;

  String get _countLabel {
    final n = count;
    if (n == null) return '';
    if (!section.isDirectory) return n > 0 ? '있음' : '없음';
    return '$n개';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('cli-config-section-${section.id}'),
      color: VibeColors.surfaceHigh,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: VibeColors.borderSoft),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(
          _sectionIcon(section),
          color: VibeColors.accent,
          size: 20,
        ),
        title: Text(
          section.title,
          style: const TextStyle(
            color: VibeColors.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          section.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: VibeColors.onSurfaceDim, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _countLabel,
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: VibeColors.onSurfaceDim,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 섹션: 파일 목록
// ---------------------------------------------------------------------------

class _SectionView extends StatelessWidget {
  const _SectionView({
    required this.home,
    required this.section,
    required this.entries,
    required this.error,
    required this.onBack,
    required this.onRefresh,
    required this.onCopyPath,
    required this.onOpen,
    required this.onCreate,
    required this.onDelete,
  });

  final CliConfigHome home;
  final CliConfigSection section;
  final List<CliConfigEntry> entries;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<String> onCopyPath;
  final ValueChanged<CliConfigEntry> onOpen;
  final VoidCallback onCreate;
  final ValueChanged<CliConfigEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final path = home.sectionPath(section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: _sectionIcon(section),
          title: section.title,
          subtitle: path,
          onBack: onBack,
          actions: [
            IconButton(
              tooltip: '경로 복사',
              onPressed: () => onCopyPath(path),
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: '새로고침',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.summary,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('cli-config-new-entry'),
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 16),
                label: Text(section.skillLayout ? '새 스킬' : '새 파일'),
              ),
            ],
          ),
        ),
        if (error != null) _ErrorNote(error!),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    '아직 항목이 없습니다.',
                    style: TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 12.5,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _EntryTile(
                      entry: entry,
                      onTap: () => onOpen(entry),
                      onDelete: () => onDelete(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final CliConfigEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final description = entry.description;
    return ListTile(
      key: ValueKey('cli-config-entry:${entry.name}'),
      dense: true,
      onTap: onTap,
      contentPadding: const EdgeInsets.only(left: 12, right: 4),
      leading: Icon(
        entry.isSkillManifest
            ? Icons.auto_awesome
            : entry.isJson
            ? Icons.data_object
            : Icons.description_outlined,
        color: entry.isSkillManifest
            ? VibeColors.accent
            : VibeColors.onSurfaceMuted,
        size: 18,
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: VibeColors.onSurface,
          fontFamily: kMonoFontFamily,
          fontFamilyFallback: kMonoFontFallback,
          fontSize: 12.5,
        ),
      ),
      subtitle: description == null
          ? null
          : Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 11,
              ),
            ),
      trailing: IconButton(
        key: ValueKey('cli-config-delete:${entry.name}'),
        tooltip: '삭제',
        onPressed: onDelete,
        icon: const Icon(
          Icons.delete_outline,
          size: 18,
          color: VibeColors.onSurfaceDim,
        ),
      ),
    );
  }
}

class _NewEntryDialog extends StatefulWidget {
  const _NewEntryDialog({required this.section});

  final CliConfigSection section;

  @override
  State<_NewEntryDialog> createState() => _NewEntryDialogState();
}

class _NewEntryDialogState extends State<_NewEntryDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      CliConfigHome.normalizeNewEntryName(widget.section, _controller.text);
      Navigator.of(context).pop(_controller.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    return AlertDialog(
      title: Text(section.skillLayout ? '새 스킬' : '새 ${section.title} 파일'),
      content: TextField(
        key: const ValueKey('cli-config-new-entry-name'),
        controller: _controller,
        autofocus: true,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: '이름',
          hintText: section.nameHint,
          helperText: section.skillLayout
              ? '이름/SKILL.md 가 만들어집니다.'
              : '확장자를 생략하면 ${section.defaultExtension} 가 붙습니다. '
                    '하위 폴더는 / 로 구분합니다.',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('cli-config-new-entry-submit'),
          onPressed: _submit,
          child: const Text('만들기'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 편집기
// ---------------------------------------------------------------------------

class _CliFileEditor extends StatefulWidget {
  const _CliFileEditor({
    super.key,
    required this.home,
    required this.entry,
    required this.onBack,
    required this.onCopyPath,
  });

  final CliConfigHome home;
  final CliConfigEntry entry;
  final VoidCallback onBack;
  final ValueChanged<String> onCopyPath;

  @override
  State<_CliFileEditor> createState() => _CliFileEditorState();
}

class _CliFileEditorState extends State<_CliFileEditor> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  bool _saving = false;
  bool _dirty = false;
  bool _valid = true;
  bool _exists = false;
  String? _status;
  bool _statusOk = true;

  bool get _isJson => widget.entry.isJson;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _load() {
    try {
      final entry = widget.entry;
      final text = widget.home.read(entry);
      _exists = text.isNotEmpty || entry.exists;
      final content = text.isEmpty && !entry.exists
          ? widget.home.initialContentFor(entry.section)
          : text;
      final validation = _isJson ? JsonObjectValidation.of(content) : null;
      _controller.text = content;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _valid = validation?.valid ?? true;
      _dirty = false;
      _statusOk = _valid;
      _status = !_exists
          ? '파일이 없습니다. 저장하면 새로 생성됩니다.'
          : validation?.message ?? '${_controller.text.length}자';
    } catch (error) {
      _valid = false;
      _statusOk = false;
      _status = '읽기 실패: $error';
    }
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    final validation = _isJson ? JsonObjectValidation.of(value) : null;
    setState(() {
      _dirty = true;
      _valid = validation?.valid ?? true;
      _statusOk = _valid;
      _status = validation?.message ?? '저장하지 않은 변경이 있습니다.';
    });
  }

  void _save() {
    if (_isJson) {
      final validation = JsonObjectValidation.of(_controller.text);
      if (!validation.valid) {
        setState(() {
          _valid = false;
          _statusOk = false;
          _status = validation.message;
        });
        return;
      }
    }
    setState(() => _saving = true);
    try {
      widget.home.write(widget.entry, _controller.text);
      _exists = true;
      _dirty = false;
      _statusOk = true;
      _status = '저장했습니다.';
    } catch (error) {
      _statusOk = false;
      _status = '저장 실패: $error';
    }
    _saving = false;
    if (mounted) setState(() {});
  }

  void _formatJson() {
    final validation = JsonObjectValidation.of(_controller.text);
    if (!validation.valid) {
      setState(() {
        _valid = false;
        _statusOk = false;
        _status = validation.message;
      });
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    final formatted = '${encoder.convert(validation.value)}\n';
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    setState(() {
      _dirty = true;
      _valid = true;
      _statusOk = true;
      _status = 'JSON 형식을 정리했습니다.';
    });
  }

  Future<void> _back() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('저장하지 않은 변경'),
          content: const Text('변경 내용을 버리고 나갈까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('계속 편집'),
            ),
            FilledButton(
              key: const ValueKey('cli-config-discard-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('버리기'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: _sectionIcon(entry.section),
          title: entry.section.isDirectory ? entry.name : entry.section.title,
          subtitle: entry.path,
          onBack: _back,
          actions: [
            IconButton(
              tooltip: '경로 복사',
              onPressed: () => widget.onCopyPath(entry.path),
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: '다시 읽기',
              onPressed: _saving ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: _ValidationBanner(
            valid: _valid,
            ok: _statusOk,
            message: _status ?? '편집하세요.',
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              key: const ValueKey('cli-config-editor-field'),
              controller: _controller,
              scrollController: _scrollController,
              onChanged: _onChanged,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 12.5,
                height: 1.38,
              ),
              decoration: InputDecoration(
                hintText: _isJson ? '{\n  "permissions": {}\n}' : '# 제목',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              if (_isJson) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _formatJson,
                    icon: const Icon(Icons.auto_fix_high, size: 17),
                    label: const Text('Format'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('cli-config-save'),
                  onPressed: _saving || !_valid || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 17),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner({
    required this.valid,
    required this.ok,
    required this.message,
  });

  final bool valid;
  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = valid && ok
        ? VibeColors.statusConnected
        : valid
        ? VibeColors.warning
        : VibeColors.statusError;
    final icon = valid && ok
        ? Icons.check_circle_outline
        : valid
        ? Icons.info_outline
        : Icons.error_outline;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
