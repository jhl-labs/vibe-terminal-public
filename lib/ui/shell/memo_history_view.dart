import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/memo_version.dart';
import 'memo_line_diff.dart';

/// 메모 패널 안에서 편집기 자리를 대체하는 버전 히스토리 화면.
/// 위에는 버전 목록, 선택하면 아래에 현재 본문과의 줄 단위 diff(또는 원문)를
/// 보여주고 복원할 수 있다. 데이터 접근은 부모가 콜백으로 담당한다.
class MemoHistoryView extends StatefulWidget {
  const MemoHistoryView({
    super.key,
    required this.versions,
    required this.currentBody,
    required this.onRestore,
    required this.onDelete,
    required this.onBack,
  });

  final Future<List<MemoVersion>> versions;

  /// diff의 기준이 되는 지금 편집 중인 본문.
  final String currentBody;
  final Future<void> Function(MemoVersion version) onRestore;
  final Future<void> Function(MemoVersion version) onDelete;
  final VoidCallback onBack;

  @override
  State<MemoHistoryView> createState() => _MemoHistoryViewState();
}

class _MemoHistoryViewState extends State<MemoHistoryView> {
  MemoVersion? _selected;
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    // 패널은 색이 있는 Container라 ListTile 잉크가 보이도록 Material을 깐다.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(),
          Expanded(
            child: FutureBuilder<List<MemoVersion>>(
              future: widget.versions,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '버전을 불러오지 못했습니다\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: VibeColors.statusError),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final versions = snap.data!;
                if (versions.isEmpty) {
                  return const Center(
                    child: Text(
                      '아직 저장된 버전이 없습니다.\n편집이 저장되면 자동으로 쌓이고,\n버전 저장 아이콘으로 직접 남길 수도 있습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: VibeColors.onSurfaceDim),
                    ),
                  );
                }
                final selected = _selected;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: selected == null ? 1 : 2,
                      child: _list(versions),
                    ),
                    if (selected != null) ...[
                      const Divider(height: 1, color: VibeColors.border),
                      _detailBar(selected),
                      Expanded(flex: 3, child: _detail(selected)),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '편집기로 돌아가기',
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          const Text(
            '버전 히스토리',
            style: TextStyle(
              color: VibeColors.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<MemoVersion> versions) {
    return ListView.builder(
      itemCount: versions.length,
      itemBuilder: (context, i) {
        final v = versions[i];
        final selected = v.id == _selected?.id;
        final title = v.label ?? '자동 저장';
        return ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: VibeColors.surfaceHigh,
          leading: Icon(
            v.label != null ? Icons.bookmark : Icons.history,
            size: 18,
            color: v.label != null
                ? VibeColors.accent
                : VibeColors.onSurfaceDim,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: VibeColors.onSurface, fontSize: 13),
          ),
          subtitle: Text(
            '${_formatAt(v.createdAt)} · ${v.body.length}자',
            style: const TextStyle(
              color: VibeColors.onSurfaceDim,
              fontFamily: kMonoFontFamily,
              fontFamilyFallback: kMonoFontFallback,
              fontSize: 11,
            ),
          ),
          trailing: IconButton(
            tooltip: '버전 삭제',
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await widget.onDelete(v);
              if (!mounted) return;
              if (_selected?.id == v.id) setState(() => _selected = null);
            },
          ),
          onTap: () => setState(() => _selected = v),
        );
      },
    );
  }

  Widget _detailBar(MemoVersion v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _showRaw ? '버전 원문' : '현재 본문과 비교',
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            tooltip: _showRaw ? '비교 보기' : '원문 보기',
            icon: Icon(
              _showRaw ? Icons.difference_outlined : Icons.article_outlined,
              size: 18,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _showRaw = !_showRaw),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: () => widget.onRestore(v),
            child: const Text('이 버전으로 복원'),
          ),
        ],
      ),
    );
  }

  Widget _detail(MemoVersion v) {
    const mono = TextStyle(
      color: VibeColors.onSurface,
      fontFamily: kMonoFontFamily,
      fontFamilyFallback: kMonoFontFallback,
      fontSize: 12,
      height: 1.4,
    );
    if (_showRaw) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: SelectableText(v.body, style: mono),
      );
    }
    // 버전(과거) → 현재: 현재에만 있는 줄이 added, 버전에만 있는 줄이 removed.
    final lines = diffLines(v.body, widget.currentBody);
    if (lines.every((l) => l.kind == DiffKind.equal)) {
      return const Center(
        child: Text(
          '현재 본문과 같습니다.',
          style: TextStyle(color: VibeColors.onSurfaceDim),
        ),
      );
    }
    var added = 0, removed = 0;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final l = lines[i];
        final (Key? key, Color? bg, Color fg, String sign) = switch (l.kind) {
          DiffKind.added => (
            Key('diff-added-${added++}'),
            VibeColors.statusConnected.withValues(alpha: .15),
            VibeColors.statusConnected,
            '+',
          ),
          DiffKind.removed => (
            Key('diff-removed-${removed++}'),
            VibeColors.statusError.withValues(alpha: .15),
            VibeColors.statusError,
            '-',
          ),
          DiffKind.equal => (null, null, VibeColors.onSurfaceDim, ' '),
        };
        return Container(
          key: key,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          child: Text('$sign ${l.text}', style: mono.copyWith(color: fg)),
        );
      },
    );
  }
}

String _formatAt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
