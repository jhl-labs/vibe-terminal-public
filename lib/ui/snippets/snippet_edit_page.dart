import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/snippet.dart';
import '../../state/providers.dart';

class SnippetEditPage extends ConsumerStatefulWidget {
  const SnippetEditPage({super.key, this.existing, this.currentHostId});

  final Snippet? existing;
  final String? currentHostId;

  @override
  ConsumerState<SnippetEditPage> createState() => _SnippetEditPageState();
}

class _SnippetEditPageState extends ConsumerState<SnippetEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _body;
  late SnippetScope _scope;
  late SnippetRunMode _mode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _body = TextEditingController(text: e?.body ?? '');
    _scope = e?.scope ?? SnippetScope.global;
    _mode = e?.defaultRunMode ?? SnippetRunMode.paste;
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  /// host 범위일 때 붙일 hostId. 기존 host 스니펫을 편집 중이면 다른 호스트의
  /// 세션이 활성이어도 원래 host를 유지한다(편집이 조용히 다른 호스트로
  /// 옮겨 가는 것을 막는다). 새로 host 범위로 바꿀 때만 현재 host를 쓴다.
  String? _resolveHostId() {
    if (_scope != SnippetScope.host) return null;
    return widget.existing?.hostId ?? widget.currentHostId;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final e = widget.existing;
    final id = e?.id ?? now.microsecondsSinceEpoch.toString();
    final repo = ref.read(snippetRepositoryProvider);
    try {
      // 새 스니펫은 항상 목록 끝에 오도록 max(sortOrder)+1을 부여한다.
      final sortOrder = e?.sortOrder ?? await repo.nextSortOrder();
      final snippet = Snippet(
        id: id,
        name: _name.text.isEmpty ? '(이름 없음)' : _name.text,
        body: _body.text,
        scope: _scope,
        hostId: _resolveHostId(),
        defaultRunMode: _mode,
        sortOrder: sortOrder,
        createdAt: e?.createdAt ?? now,
        updatedAt: now,
      );
      await repo.upsert(snippet);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('저장 실패: $err')));
      return;
    }
    ref.invalidate(snippetListProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hostScopeEnabled =
        widget.currentHostId != null || widget.existing?.hostId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '스니펫 추가' : '스니펫 편집'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '이름'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              decoration: const InputDecoration(labelText: '본문 ({{변수}} 사용 가능)'),
              maxLines: 6,
            ),
            const SizedBox(height: 16),
            SegmentedButton<SnippetScope>(
              segments: [
                const ButtonSegment(
                  value: SnippetScope.global,
                  label: Text('글로벌'),
                ),
                ButtonSegment(
                  value: SnippetScope.host,
                  label: const Text('이 호스트'),
                  enabled: hostScopeEnabled,
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            const SizedBox(height: 16),
            SegmentedButton<SnippetRunMode>(
              segments: const [
                ButtonSegment(value: SnippetRunMode.paste, label: Text('붙여넣기')),
                ButtonSegment(value: SnippetRunMode.run, label: Text('실행')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}
