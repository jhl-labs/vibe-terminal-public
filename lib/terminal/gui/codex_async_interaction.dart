part of 'terminal_interaction.dart';

/// Codex's queued questions use a different editor and navigation from its
/// request_user_input overlay. Require its active chrome, not numbered prose.
class _CodexAsyncInteractionParser {
  static final _heading = RegExp(r'^\s*•?\s*Queued follow-up inputs\s*$');
  static final _count = RegExp(r'^\s*\?\s+([1-9]\d*)\s+questions?\b');
  static final _open = RegExp(
    r'(?:shift\s*\+\s*(?:←|left)|⇧\s*←)\s+to answer',
    caseSensitive: false,
  );
  static final _back = RegExp(
    r'(?:shift\s*\+\s*(?:→|right)|⇧\s*→)\s+(main prompt|prev question)',
    caseSensitive: false,
  );
  static final _next = RegExp(
    r'(?:shift\s*\+\s*(?:←|left)|⇧\s*←)\s+next question',
    caseSensitive: false,
  );
  static final _number = RegExp(r'^\s*([›❯>]?)\s*(\d{1,2})[.)](?:\s+(.*))?$');
  static final _progress = RegExp(r'^\s*\d+ of \d+\s*$');
  static final _other = RegExp(
    r'^Other(?: \(write an answer\))?$',
    caseSensitive: false,
  );
  static final _shell = RegExp(r'^(?:[\w.@:/~ -]+)?[\$#>%]\s*$');
  static final _submit = RegExp(
    r'^\s*enter\s+submit(?:\s|$)',
    caseSensitive: false,
  );
  static final _skip = RegExp(
    r'(?:⌃\s*\]|ctrl\s*\+\s*\])\s+skip',
    caseSensitive: false,
  );

  static TerminalInteraction? collapsed(
    List<String> rows,
    int last,
    String cursor,
    List<bool>? wrappedRows,
  ) {
    if (wrappedRows != null) {
      final logical = <String>[];
      for (var i = 0; i < rows.length; i++) {
        if (wrappedRows[i] && logical.isNotEmpty) {
          logical[logical.length - 1] += rows[i];
        } else {
          logical.add(rows[i]);
        }
      }
      rows = logical;
      last = rows.lastIndexWhere((s) => s.trim().isNotEmpty);
    }
    final hint = rows.lastIndexWhere((s) => _open.hasMatch(s));
    if (hint < 1 || TerminalInteractionParser._insideFence(rows, hint)) {
      return null;
    }
    final summary = rows.lastIndexWhere((s) => _count.hasMatch(s), hint);
    if (summary < 0 || hint - summary > 2) return null;
    final tail = rows.sublist(hint + 1, last + 1);
    if (tail.any((s) => _shell.hasMatch(s.trim()))) return null;
    final following = tail.where((s) => s.trim().isNotEmpty).toList();
    if (following.isNotEmpty) {
      // An inline composer and its model/status row can follow the queue. Do not
      // accept arbitrary output appended to a historical question example.
      if (last - hint > 12 ||
          !RegExp(r'^\s*[›❯](?:\s|$)').hasMatch(following.first) ||
          following.length > 1 && !following.last.contains(' · ')) {
        return null;
      }
    }
    final question = rows.sublist(summary, hint + 1).join('\n').trim();
    return TerminalInteraction(
      agent: 'codex',
      kind: TerminalInteractionKind.collapsed,
      question: question,
      options: const [],
      identity: 'codex:collapsed:$question',
      cursor: cursor,
      protocol: TerminalInteractionProtocol.codexAsync,
    );
  }

  static int? footer(List<String> rows, int last) {
    final index = rows.lastIndexWhere((s) => RegExp(r'\bsubmit\b').hasMatch(s));
    if (index < 0 ||
        last - index > 5 ||
        TerminalInteractionParser._insideFence(rows, index)) {
      return null;
    }
    final tips = rows.sublist(index, last + 1).join(' ');
    // Recognize the editor even when bindings were remapped, so an unsupported
    // async menu never falls through to the standard overlay's key contract.
    return RegExp(r'\bskip\b').hasMatch(tips) &&
            RegExp(r'\b(?:main prompt|prev question)\b').hasMatch(tips)
        ? index
        : null;
  }

  static TerminalInteraction? expanded(
    List<String> rows,
    int last,
    int cursorX,
    int cursorY,
    TerminalInteraction? previous,
    int footer,
  ) {
    final tips = rows.sublist(footer, last + 1).join(' ');
    final back = _back.firstMatch(tips);
    if (!_submit.hasMatch(rows[footer]) ||
        !_skip.hasMatch(tips) ||
        back == null) {
      return null;
    }
    final queue = rows.lastIndexWhere((s) => _heading.hasMatch(s), footer);
    final begin = queue + 1;
    final optionRows = <int>[];
    final options = <TerminalInteractionOption>[];
    for (var row = begin; row < footer; row++) {
      final match = _number.firstMatch(rows[row]);
      if (match == null) continue;
      final number = int.parse(match[2]!);
      if (number == 1) {
        options.clear();
        optionRows.clear();
      }
      // Clipped menus are not complete enough to safely map a clicked row.
      if (number != options.length + 1 || options.length >= 12) continue;
      var end = row + 1;
      while (end < footer && _number.firstMatch(rows[end]) == null) {
        end++;
      }
      final label = [
        match[3] ?? '',
        ...rows.sublist(row + 1, end),
      ].map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
      options.add(
        TerminalInteractionOption(
          number,
          label,
          selected: match[1]!.isNotEmpty,
          customInput: false,
        ),
      );
      optionRows.add(row);
    }
    if (options.isNotEmpty && options.every((o) => !o.selected)) return null;
    var inputStart = -1;
    var headerEnd = options.isEmpty ? -1 : optionRows.first;
    if (options.isEmpty) {
      inputStart = rows.indexWhere(
        (s) => s.trim() == 'Type your answer',
        begin,
      );
      if (inputStart < 0 && cursorY >= begin && cursorY < footer) {
        inputStart = cursorY;
        while (inputStart > begin && rows[inputStart - 1].trim().isNotEmpty) {
          inputStart--;
        }
      }
      headerEnd = inputStart;
    }
    if (headerEnd < begin) return null;
    var end = headerEnd;
    while (end > begin && rows[end - 1].trim().isEmpty) {
      end--;
    }
    var start = end;
    while (start > begin && rows[start - 1].trim().isNotEmpty) {
      start--;
    }
    final progress = rows.lastIndexWhere(
      (s) => _progress.hasMatch(s),
      start - 1,
    );
    final header = rows.sublist(start, end).join('\n').trim();
    if (header.isEmpty || header.startsWith('↳')) return null;
    final question = progress >= begin
        ? '${rows[progress].trim()}\n$header'
        : header;
    var inputText = options.isEmpty
        ? rows.sublist(inputStart, footer).join('\n')
        : '';
    if (options.isNotEmpty) {
      final lastOption = options.last;
      final sameQuestion =
          previous?.isCodexAsync == true &&
          previous?.question == question &&
          previous!.options.length == options.length &&
          options.asMap().entries.every(
            (e) =>
                e.key == options.length - 1 ||
                e.value.label == previous.options[e.key].label,
          );
      final custom =
          _other.hasMatch(lastOption.label) ||
          sameQuestion && previous.options.last.custom;
      if (custom) {
        final label = _other.hasMatch(lastOption.label)
            ? lastOption.label
            : previous!.options.last.label;
        if (lastOption.selected) {
          inputText = rows.sublist(optionRows.last, footer).join('\n');
        }
        options[options.length - 1] = TerminalInteractionOption(
          lastOption.number,
          label,
          selected: lastOption.selected,
          customInput: true,
        );
      }
    }
    final editing =
        options.isEmpty || options.any((o) => o.custom && o.selected);
    return TerminalInteraction(
      agent: 'codex',
      kind: options.isEmpty
          ? TerminalInteractionKind.input
          : TerminalInteractionKind.choices,
      question: question,
      options: List.unmodifiable(options),
      identity:
          'codex:async:$question:${options.map((o) => '${o.number}:${o.label}').join('|')}',
      protocol: TerminalInteractionProtocol.codexAsync,
      editing: editing,
      inputText: editing ? inputText : '',
      cursor: '$cursorX:$cursorY',
      canNavigateQuestions:
          back[1]!.toLowerCase() == 'prev question' || _next.hasMatch(tips),
      canNavigatePrevious: back[1]!.toLowerCase() == 'prev question',
      canNavigateNext: _next.hasMatch(tips),
    );
  }
}
