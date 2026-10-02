import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/snippet.dart';

/// 긴 스니펫을 넓은 선택 가능한 코드 영역에서 읽는다.
class SnippetViewDialog extends StatelessWidget {
  const SnippetViewDialog({
    super.key,
    required this.snippet,
    required this.onCopy,
    this.onEdit,
  });

  final Snippet snippet;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final lineCount = '\n'.allMatches(snippet.body).length + 1;
    final scope = snippet.scope == SnippetScope.global ? '글로벌' : '호스트';
    final runMode = snippet.defaultRunMode == SnippetRunMode.run
        ? '실행'
        : '붙여넣기';

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: (size.width - 32).clamp(0.0, 1120.0),
        height: (size.height - 32).clamp(0.0, 880.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.code, color: VibeColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snippet.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$scope · 기본 동작: $runMode',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: VibeColors.onSurfaceDim),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '복사',
                    onPressed: onCopy,
                    icon: const Icon(Icons.content_copy),
                  ),
                  if (onEdit != null)
                    IconButton(
                      tooltip: '편집',
                      onPressed: () {
                        Navigator.of(context).pop();
                        onEdit!();
                      },
                      icon: const Icon(Icons.edit_outlined),
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
              child: Container(
                width: double.infinity,
                color: VibeColors.surface,
                padding: const EdgeInsets.all(20),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      snippet.body.isEmpty ? '(내용 없음)' : snippet.body,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontFamily: kMonoFontFamily,
                        fontFamilyFallback: kMonoFontFallback,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Text(
                    '$lineCount줄 · ${snippet.body.length}자',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: VibeColors.onSurfaceDim,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '드래그해 텍스트를 선택할 수 있습니다',
                    style: TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
