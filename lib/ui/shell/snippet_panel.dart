import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/snippet.dart';
import '../../session/session.dart';
import '../../snippets/placeholder_parser.dart';
import '../../state/providers.dart';
import '../snippets/placeholder_form.dart';
import '../snippets/snippet_edit_page.dart';

/// 우측 패널. 스니펫 목록/검색/실행/편집/정렬을 보여준다.
class SnippetPanel extends ConsumerStatefulWidget {
  const SnippetPanel({super.key});

  @override
  ConsumerState<SnippetPanel> createState() => _SnippetPanelState();
}

class _SnippetPanelState extends ConsumerState<SnippetPanel> {
  String _query = '';
  bool _gistBusy = false;

  SessionInfo? _activeSession() {
    final sessions = ref.read(sessionManagerProvider);
    final activeId = ref.read(activeSessionIdProvider);
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  Future<void> _run(Snippet s, SnippetRunMode mode) async {
    final active = _activeSession();
    if (active == null || active.status != SessionStatus.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결된 활성 세션이 없습니다')));
      return;
    }
    var body = s.body;
    final names = PlaceholderParser.extract(body);
    if (names.isNotEmpty) {
      final values = await showPlaceholderForm(context, names);
      if (values == null) return; // 취소
      body = PlaceholderParser.substitute(body, values);
    }
    active.engine.terminal.textInput(
      mode == SnippetRunMode.run ? '$body\n' : body,
    );
  }

  Future<void> _edit(Snippet? existing) async {
    final hostId = _activeSession()?.host.id;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SnippetEditPage(existing: existing, currentHostId: hostId),
      ),
    );
    ref.invalidate(snippetListProvider);
  }

  void _showError(String prefix, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$prefix: $error')));
  }

  Future<void> _delete(Snippet s) async {
    try {
      await ref.read(snippetRepositoryProvider).delete(s.id);
    } catch (e) {
      _showError('삭제 실패', e);
      return;
    }
    ref.invalidate(snippetListProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('스니펫을 삭제했습니다'),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () => unawaited(_restoreDeleted(s)),
          ),
        ),
      );
  }

  Future<void> _restoreDeleted(Snippet s) async {
    try {
      await ref.read(snippetRepositoryProvider).upsert(s);
    } catch (e) {
      _showError('복원 실패', e);
      return;
    }
    ref.invalidate(snippetListProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('스니펫을 복원했습니다')));
  }

  /// [s]와 [neighbour]의 sortOrder를 맞바꿔 목록에서 한 칸 이동한다.
  Future<void> _swapWith(Snippet s, Snippet neighbour) async {
    try {
      await ref
          .read(snippetRepositoryProvider)
          .swapSortOrder(s.id, neighbour.id);
    } catch (e) {
      _showError('순서 변경 실패', e);
      return;
    }
    ref.invalidate(snippetListProvider);
  }

  /// 로그인 토큰이 없으면 안내만 하고 null을 돌려준다.
  String? _requireGitHubToken() {
    final token = ref.read(appSettingsProvider).cloudSync.github.token.trim();
    if (token.isEmpty) {
      _showError('GitHub 로그인이 필요합니다', '설정 > GitHub 탭에서 먼저 로그인해주세요.');
      return null;
    }
    return token;
  }

  Future<void> _exportToGist() async {
    final token = _requireGitHubToken();
    if (token == null) return;
    setState(() => _gistBusy = true);
    try {
      final snippets = await ref.read(snippetRepositoryProvider).getAll();
      final service = ref.read(gistSyncServiceProvider);
      final content = service.encodeSnippets(snippets);
      final existingId = ref.read(appSettingsProvider).snippetGistId.trim();
      final result = await service.upload(
        token: token,
        content: content,
        gistId: existingId.isEmpty ? null : existingId,
      );
      ref.read(appSettingsProvider.notifier).setSnippetGistId(result.gistId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('스니펫 ${snippets.length}개를 Gist로 내보냈습니다')),
        );
    } catch (e) {
      _showError('내보내기 실패', e);
    } finally {
      if (mounted) setState(() => _gistBusy = false);
    }
  }

  Future<void> _importFromGist() async {
    final token = _requireGitHubToken();
    if (token == null) return;
    final currentId = ref.read(appSettingsProvider).snippetGistId;
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => _GistIdDialog(initialValue: currentId),
    );
    if (input == null) return;
    final gistId = _extractGistId(input);
    if (gistId == null || gistId.isEmpty) {
      _showError('가져오기 실패', 'Gist ID 또는 URL을 확인해주세요.');
      return;
    }
    setState(() => _gistBusy = true);
    try {
      final service = ref.read(gistSyncServiceProvider);
      final raw = await service.download(token: token, gistId: gistId);
      final incoming = service.decodeSnippets(raw);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('가져오기'),
          content: Text(
            '${incoming.length}개 항목을 가져옵니다.\n'
            '같은 id의 스니펫은 Gist 내용으로 덮어씁니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('가져오기'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final repo = ref.read(snippetRepositoryProvider);
      for (final s in incoming) {
        await repo.upsert(s);
      }
      ref.read(appSettingsProvider.notifier).setSnippetGistId(gistId);
      ref.invalidate(snippetListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('스니펫 ${incoming.length}개를 가져왔습니다')),
        );
    } catch (e) {
      _showError('가져오기 실패', e);
    } finally {
      if (mounted) setState(() => _gistBusy = false);
    }
  }

  /// gist 전체 URL(`https://gist.github.com/user/<id>`)이나 id 자체를 받아
  /// id만 뽑아낸다.
  String? _extractGistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return trimmed;
  }

  Widget _snippetTab() {
    final asyncSnippets = ref.watch(snippetListProvider);
    final hostId = _activeSession()?.host.id;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '스니펫 검색',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: asyncSnippets.when(
            data: (all) {
              final inScope = all
                  .where(
                    (s) =>
                        s.scope == SnippetScope.global ||
                        (hostId != null && s.hostId == hostId),
                  )
                  .toList();
              final query = _query.trim().toLowerCase();
              // 이름뿐 아니라 본문(명령어)도 검색 대상이다.
              final visible = query.isEmpty
                  ? inScope
                  : inScope
                        .where(
                          (s) =>
                              s.name.toLowerCase().contains(query) ||
                              s.body.toLowerCase().contains(query),
                        )
                        .toList();
              if (visible.isEmpty) {
                return Center(
                  child: Text(
                    inScope.isEmpty ? '스니펫이 없습니다' : '검색 결과가 없습니다',
                    style: const TextStyle(color: VibeColors.onSurfaceDim),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final s = visible[index];
                  return _SnippetTile(
                    snippet: s,
                    onTap: () => _run(s, s.defaultRunMode),
                    onLongPress: () => _showActions(
                      s,
                      above: index > 0 ? visible[index - 1] : null,
                      below: index < visible.length - 1
                          ? visible[index + 1]
                          : null,
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('오류: $e')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('스니펫 추가'),
            ),
          ),
        ),
      ],
    );
  }

  /// 길게 눌렀을 때의 동작 시트. [above]/[below]는 현재 목록에서의 이웃으로,
  /// 없으면(맨 위/맨 아래) 해당 이동 항목을 숨긴다.
  void _showActions(Snippet s, {Snippet? above, Snippet? below}) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('실행'),
              onTap: () {
                Navigator.pop(ctx);
                _run(s, SnippetRunMode.run);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('붙여넣기'),
              onTap: () {
                Navigator.pop(ctx);
                _run(s, SnippetRunMode.paste);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('편집'),
              onTap: () {
                Navigator.pop(ctx);
                _edit(s);
              },
            ),
            if (above != null)
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('위로 이동'),
                onTap: () {
                  Navigator.pop(ctx);
                  _swapWith(s, above);
                },
              ),
            if (below != null)
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('아래로 이동'),
                onTap: () {
                  Navigator.pop(ctx);
                  _swapWith(s, below);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('삭제'),
              onTap: () {
                Navigator.pop(ctx);
                _delete(s);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: VibeColors.surface,
      child: Column(
        children: [
          _PanelHeader(
            busy: _gistBusy,
            onExportGist: _exportToGist,
            onImportGist: _importFromGist,
          ),
          Expanded(child: _snippetTab()),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.busy,
    required this.onExportGist,
    required this.onImportGist,
  });

  final bool busy;
  final VoidCallback onExportGist;
  final VoidCallback onImportGist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      child: Row(
        children: [
          const Icon(Icons.code, color: VibeColors.accent, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Command shelf',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'runbooks and snippets',
                  style: TextStyle(
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
              padding: EdgeInsets.all(8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<VoidCallback>(
              tooltip: 'Gist 동기화',
              icon: const Icon(
                Icons.more_vert,
                size: 18,
                color: VibeColors.onSurfaceMuted,
              ),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: onExportGist,
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Gist로 내보내기'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: onImportGist,
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_download_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Gist에서 가져오기'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Gist ID나 전체 URL을 입력받는 작은 다이얼로그.
class _GistIdDialog extends StatefulWidget {
  const _GistIdDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_GistIdDialog> createState() => _GistIdDialogState();
}

class _GistIdDialogState extends State<_GistIdDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gist에서 가져오기'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Gist ID 또는 URL',
          hintText: 'https://gist.github.com/user/xxxxxxxx',
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

class _SnippetTile extends StatelessWidget {
  const _SnippetTile({
    required this.snippet,
    required this.onTap,
    required this.onLongPress,
  });

  final Snippet snippet;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final hostScoped = snippet.scope == SnippetScope.host;
    return Material(
      color: VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VibeColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hostScoped ? Icons.dns : Icons.public,
                    size: 16,
                    color: hostScoped
                        ? VibeColors.secondary
                        : VibeColors.onSurfaceDim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      snippet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.play_arrow,
                    size: 17,
                    color: VibeColors.accent,
                  ),
                ],
              ),
              if (snippet.body != snippet.name) ...[
                const SizedBox(height: 8),
                Text(
                  snippet.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
