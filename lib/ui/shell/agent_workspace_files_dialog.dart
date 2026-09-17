import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../agent/agent_workspace_files.dart';

typedef WorkspaceFilesLoader =
    Future<List<AgentWorkspaceFileEntry>> Function(String directory);
typedef WorkspaceFileReader =
    Future<AgentWorkspaceFileContent> Function(String path);
typedef WorkspaceFileWriter =
    Future<AgentWorkspaceFileContent> Function(
      String path,
      String text,
      String? revision,
    );

Future<void> showAgentWorkspaceFilesDialog(
  BuildContext context, {
  required WorkspaceFilesLoader list,
  required WorkspaceFileReader read,
  required WorkspaceFileWriter write,
  Future<void> Function(AgentWorkspaceFileContent)? resolve,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => AgentWorkspaceFilesPanel(
    list: list,
    read: read,
    write: write,
    resolve: resolve,
  ),
);

class AgentWorkspaceFilesPanel extends StatefulWidget {
  const AgentWorkspaceFilesPanel({
    super.key,
    this.embedded = false,
    this.onClose,
    this.onReview,
    this.onIssues,
    this.title = '작업공간 파일',
    required this.list,
    required this.read,
    required this.write,
    this.resolve,
    this.resolveDelete,
  });
  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onReview;
  final VoidCallback? onIssues;
  final String title;
  final WorkspaceFilesLoader list;
  final WorkspaceFileReader read;
  final WorkspaceFileWriter write;
  final Future<void> Function(AgentWorkspaceFileContent)? resolve;
  final Future<void> Function(AgentWorkspaceFileContent)? resolveDelete;
  @override
  State<AgentWorkspaceFilesPanel> createState() =>
      AgentWorkspaceFilesPanelState();
}

class AgentWorkspaceFilesPanelState extends State<AgentWorkspaceFilesPanel> {
  final _editor = TextEditingController();
  String _directory = '';
  late Future<List<AgentWorkspaceFileEntry>> _entries;
  AgentWorkspaceFileContent? _file;
  String? _error;
  bool _busy = false;
  bool get _dirty => _file != null && _editor.text != _file!.text;
  @override
  void initState() {
    super.initState();
    _entries = widget.list('');
    _editor.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _navigate(String path) => setState(() {
    _directory = path;
    _entries = widget.list(path);
  });
  Future<bool> _discard() async =>
      !_dirty ||
      await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('저장하지 않은 변경을 버릴까요?'),
              content: Text(_file!.path),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('계속 편집'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('변경 버리기'),
                ),
              ],
            ),
          ) ==
          true;
  Future<void> _close() async {
    if (widget.embedded) {
      widget.onClose?.call();
      return;
    }
    if (!_busy && await _discard() && mounted) Navigator.pop(context);
  }

  Future<void> _open(String path) async {
    if (_busy || !await _discard() || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.read(path);
      if (!mounted) return;
      setState(() {
        _file = value;
        _editor.text = value.text;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (_busy || file == null || !file.editable || !_dirty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final text = _editor.text;
    try {
      final value = await widget.write(file.path, text, file.revision);
      if (!mounted) return;
      setState(() {
        _file = value;
        _entries = widget.list(_directory);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy || !await _discard() || !mounted) return;
    var name = '';
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 텍스트 파일'),
        content: TextField(
          onChanged: (value) => name = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: '현재 폴더 안의 파일 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('만들기'),
          ),
        ],
      ),
    );
    if (path == null || !mounted) return;
    if (path.isEmpty || path.contains('/') || path.contains('\\')) {
      setState(() => _error = '폴더 구분자 없는 파일 이름을 입력하세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.write(
        [if (_directory.isNotEmpty) _directory, path].join('/'),
        '',
        null,
      );
      if (!mounted) return;
      setState(() {
        _file = value;
        _editor.text = value.text;
        _entries = widget.list(_directory);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveDeletion() async {
    final file = _file;
    if (file == null || _busy || _dirty || widget.resolveDelete == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('파일을 삭제해 충돌을 해결할까요?'),
        content: Text(file.path),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('삭제하고 해결로 표시'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.resolveDelete!(file);
      if (mounted) {
        setState(() {
          _file = null;
          _editor.clear();
          _entries = widget.list(_directory);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    if (_file == null || _busy || _dirty || widget.resolve == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.resolve!(_file!);
      if (mounted) {
        setState(() => _error = '충돌 해결로 표시했습니다. 변경 검토에서 병합 전체를 커밋하세요.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: _FilesSurface(
        embedded: widget.embedded,
        child: SizedBox(
          width: 1120,
          height: 760,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_open),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (widget.onIssues != null)
                      IconButton(
                        tooltip: 'GitHub 이슈에서 작업 가져오기',
                        onPressed: widget.onIssues,
                        icon: const Icon(Icons.task_alt),
                      ),
                    if (widget.onReview != null)
                      IconButton(
                        tooltip: '변경 검토 · 테스트 · Run · 전달',
                        onPressed: widget.onReview,
                        icon: const Icon(Icons.difference_outlined),
                      ),
                    IconButton(
                      tooltip: '새 파일',
                      onPressed: _busy ? null : _create,
                      icon: const Icon(Icons.note_add_outlined),
                    ),
                    IconButton(
                      tooltip: '목록 새로고침',
                      onPressed: _busy ? null : () => _navigate(_directory),
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: _busy ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width:
                            widget.embedded ||
                                MediaQuery.sizeOf(context).width < 650
                            ? 120
                            : 240,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: '상위 폴더',
                                  onPressed: _directory.isEmpty
                                      ? null
                                      : () => _navigate(
                                          _directory
                                              .split('/')
                                              .take(
                                                _directory.split('/').length -
                                                    1,
                                              )
                                              .join('/'),
                                        ),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                Expanded(
                                  child: Text(
                                    _directory.isEmpty ? '/' : _directory,
                                    maxLines: 2,
                                  ),
                                ),
                              ],
                            ),
                            Expanded(
                              child: FutureBuilder<List<AgentWorkspaceFileEntry>>(
                                future: _entries,
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return SingleChildScrollView(
                                      child: SelectableText(
                                        '${snapshot.error}',
                                      ),
                                    );
                                  }
                                  if (!snapshot.hasData) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }
                                  return ListView(
                                    children: [
                                      for (final entry in snapshot.data!)
                                        ListTile(
                                          dense: true,
                                          selected: _file?.path == entry.path,
                                          leading: Icon(
                                            entry.isDirectory
                                                ? Icons.folder_outlined
                                                : entry.isFile
                                                ? Icons
                                                      .insert_drive_file_outlined
                                                : Icons.link,
                                          ),
                                          title: Text(entry.name),
                                          onTap: _busy
                                              ? null
                                              : entry.isDirectory
                                              ? () => _navigate(entry.path)
                                              : entry.isFile
                                              ? () => _open(entry.path)
                                              : null,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(),
                      Expanded(
                        child: _file == null
                            ? const Center(child: Text('파일을 선택하세요.'))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    '${_file!.path}${_dirty ? ' · 수정됨' : ''}',
                                  ),
                                  Wrap(
                                    children: [
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _open(_file!.path),
                                        child: const Text('다시 열기'),
                                      ),
                                      FilledButton(
                                        onPressed:
                                            _busy || !_dirty || !_file!.editable
                                            ? null
                                            : _save,
                                        child: const Text('저장'),
                                      ),
                                      if (widget.resolveDelete != null)
                                        TextButton(
                                          onPressed: _busy || _dirty
                                              ? null
                                              : _resolveDeletion,
                                          child: const Text('삭제로 해결'),
                                        ),
                                      if (widget.resolve != null)
                                        TextButton(
                                          onPressed: _busy || _dirty
                                              ? null
                                              : _resolve,
                                          child: const Text('충돌 해결로 표시'),
                                        ),
                                    ],
                                  ),
                                  if (!_file!.editable)
                                    Text(
                                      _file!.truncated
                                          ? '큰 파일: 앞 256 KiB만 표시합니다. 읽기 전용입니다.'
                                          : '읽기 전용 미리보기입니다.',
                                    ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: _file!.imageBase64 != null
                                        ? InteractiveViewer(
                                            child: Image.memory(
                                              base64Decode(_file!.imageBase64!),
                                              cacheWidth: 1600,
                                              errorBuilder: (_, _, _) =>
                                                  const Text(
                                                    '이미지를 해석하지 못했습니다.',
                                                  ),
                                            ),
                                          )
                                        : TextField(
                                            controller: _editor,
                                            readOnly: _busy || !_file!.editable,
                                            expands: true,
                                            maxLines: null,
                                            minLines: null,
                                            keyboardType:
                                                TextInputType.multiline,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 13,
                                            ),
                                            decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              contentPadding: EdgeInsets.all(
                                                12,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FilesSurface extends StatelessWidget {
  const _FilesSurface({required this.embedded, required this.child});
  final bool embedded;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      embedded ? Material(child: child) : Dialog(child: child);
}
