import 'package:flutter/material.dart';

import '../../../ai/terminal_reply_suggestions.dart';
import '../../../terminal/gui/terminal_reply_suggestion_controller.dart';

class TerminalReplySuggestionPanel extends StatelessWidget {
  const TerminalReplySuggestionPanel({
    super.key,
    required this.controller,
    required this.onSelected,
  });
  final TerminalReplySuggestionController controller;
  final void Function(TerminalReplySuggestion) onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('terminal-reply-suggestions'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(controller.busy ? '답변 제안 생성 중…' : '자동 응답 제안')),
            IconButton(
              tooltip: '제안 닫기',
              onPressed: controller.clear,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
        if (controller.busy) const LinearProgressIndicator(),
        if (controller.error case final error?) Text(error),
        for (final (index, suggestion) in controller.items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Tooltip(
              message: suggestion.text,
              child: OutlinedButton(
                key: ValueKey('terminal-reply-suggestion-$index'),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => onSelected(suggestion),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (suggestion.text != suggestion.label)
                        Text(
                          suggestion.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
