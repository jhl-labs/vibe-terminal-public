import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../agent/agent_session_inspector.dart';

part 'codex_async_interaction.dart';

enum TerminalInteractionKind { choices, collapsed, review, input }

enum TerminalInteractionProtocol { standard, codexAsync }

@immutable
class TerminalInteractionOption {
  const TerminalInteractionOption(
    this.number,
    this.label, {
    this.selected = false,
    this.checked = false,
    this.customInput,
  });
  final int number;
  final String label;
  final bool selected;
  final bool checked;
  final bool? customInput;
  bool get custom =>
      customInput ??
      RegExp(
        r'^(?:type something\.?|type your own answer|none of the above|other\.?|직접 입력|기타)$',
        caseSensitive: false,
      ).hasMatch(label);
}

/// Only the interpreted live viewport participates; scrollback is never input.
@immutable
class TerminalInteraction {
  const TerminalInteraction({
    required this.agent,
    required this.kind,
    required this.question,
    required this.options,
    required this.identity,
    this.multiple = false,
    this.horizontal = false,
    this.canNavigateQuestions = false,
    this.canAddNotes = false,
    this.editing = false,
    this.cursor = '',
    this.inputText = '',
    this.protocol = TerminalInteractionProtocol.standard,
    this.canNavigatePrevious = true,
    this.canNavigateNext = true,
  });
  final String agent;
  final TerminalInteractionKind kind;
  final String question;
  final List<TerminalInteractionOption> options;
  final String identity;
  final bool multiple;
  final bool horizontal;
  final bool canNavigateQuestions;
  final bool canAddNotes;
  final bool editing;
  final String cursor;
  final String inputText;
  final TerminalInteractionProtocol protocol;
  final bool canNavigatePrevious;
  final bool canNavigateNext;
  bool get isCodexAsync => protocol == TerminalInteractionProtocol.codexAsync;
  int get selected => options.indexWhere((o) => o.selected);
  String get revision =>
      '$identity|$cursor|$editing|$inputText|${options.map((o) => '${o.selected}:${o.checked}').join(',')}';

  static TerminalInteraction? capture(
    Terminal terminal, {
    String title = '',
    TerminalInteraction? previous,
  }) {
    final buffer = terminal.buffer;
    if (terminal.viewWidth * terminal.viewHeight > 200000) return null;
    final rows = <String>[];
    final wrappedRows = <bool>[];
    for (var y = buffer.scrollBack; y < buffer.height; y++) {
      final line = buffer.lines[y];
      final text = StringBuffer();
      for (var x = 0; x < line.length && x < terminal.viewWidth; x++) {
        final code = line.getCodePoint(x);
        if (code == 0 && x > 0 && line.getWidth(x - 1) == 2) continue;
        text.write(
          line.getAttributes(x) & CellFlags.invisible != 0
              ? ' '
              : code == 0
              ? ' '
              : String.fromCharCode(code),
        );
      }
      rows.add(text.toString().trimRight());
      wrappedRows.add(line.isWrapped);
    }
    final screen = rows.join('\n');
    final inspection = AgentSessionInspector.inspect(
      screen,
      title: title,
      liveSession: true,
    );
    final hint = inspection.isConfirmedAgent ? inspection.agentHint : '';
    return TerminalInteractionParser.parse(
      rows,
      agentHint: hint,
      cursorX: buffer.cursorX,
      cursorY: buffer.cursorY,
      previous: previous,
      wrappedRows: wrappedRows,
      styleAt: (row, column) {
        final line = buffer.lines[buffer.scrollBack + row];
        return (
          line.getForeground(column),
          line.getBackground(column),
          line.getAttributes(column),
        );
      },
    );
  }
}

/// CLI-specific chrome and key semantics, separate from Flutter presentation.
class TerminalInteractionParser {
  const TerminalInteractionParser._();
  static final _number = RegExp(r'^\s*([❯›>]?)\s*(\d{1,2})[.)]\s+(.+)$');
  static final _border = RegExp(r'^\s*[│┃║]\s?');
  static final _footer = RegExp(
    r'(?:enter.*(?:confirm|submit|select|toggle)|esc.*(?:cancel|dismiss)|tab.*to add notes)',
    caseSensitive: false,
  );

  static bool _insideFence(List<String> rows, int end) {
    var fenced = false;
    for (var i = 0; i <= end; i++) {
      if (rows[i].trimLeft().startsWith('```')) fenced = !fenced;
    }
    return fenced;
  }

  static TerminalInteraction? parse(
    List<String> raw, {
    String agentHint = '',
    int cursorX = -1,
    int cursorY = -1,
    TerminalInteraction? previous,
    List<bool>? wrappedRows,
    (int, int, int) Function(int row, int column)? styleAt,
  }) {
    final rows = raw
        .map((s) => s.replaceFirst(_border, '').trimRight())
        .toList();
    final nonEmpty = rows.indexWhere((s) => s.trim().isNotEmpty);
    if (nonEmpty < 0) return null;
    final last = rows.lastIndexWhere((s) => s.trim().isNotEmpty);
    final cursor = '$cursorX:$cursorY';
    final collapsed = _CodexAsyncInteractionParser.collapsed(
      rows,
      last,
      cursor,
      wrappedRows,
    );
    if (collapsed != null) return collapsed;
    // A returned shell/normal CLI composer invalidates a historical dialog.
    if (RegExp(
      r'^(?:[\w.@:/~ -]+)?[\$#>%❯›]\s*$',
    ).hasMatch(rows[last].trim())) {
      return null;
    }
    final text = rows.join('\n');
    final lower = text.toLowerCase();
    final asyncFooter = _CodexAsyncInteractionParser.footer(rows, last);
    if (asyncFooter != null) {
      return _CodexAsyncInteractionParser.expanded(
        rows,
        last,
        cursorX,
        cursorY,
        previous,
        asyncFooter,
      );
    }
    final footer = rows.lastIndexWhere((s) => _footer.hasMatch(s));
    if (footer < 0 || last - footer > 3) return null;
    if (_insideFence(rows, footer)) return null;
    final footerText = rows.sublist(footer).join(' ').toLowerCase();
    var agent = agentHint;
    if (lower.contains('permission required') &&
        lower.contains('allow once') &&
        lower.contains('allow always')) {
      agent = 'opencode';
    } else if (lower.contains('tell codex what to do differently') ||
        RegExp(r'question \d+/\d+').hasMatch(lower) &&
            footerText.contains('to submit')) {
      agent = 'codex';
    } else if ((lower.contains('type something') ||
            previous?.agent == 'claude') &&
        footerText.contains('enter/space') &&
        footerText.contains('select')) {
      agent = 'claude';
    } else if (footerText.contains('↑↓') &&
        footerText.contains('select') &&
        footerText.contains('esc') &&
        footerText.contains('dismiss')) {
      agent = 'opencode';
    }
    if (!const {'claude', 'codex', 'opencode'}.contains(agent)) return null;
    if (agent == 'opencode' &&
        lower.contains('reject permission') &&
        lower.contains('tell opencode what to do differently')) {
      return TerminalInteraction(
        agent: agent,
        kind: TerminalInteractionKind.input,
        question: 'Reject permission\nTell OpenCode what to do differently',
        options: const [],
        identity: 'opencode:reject',
        editing: cursorY >= 0 && cursorY <= footer,
        cursor: cursor,
      );
    }
    if (agent == 'opencode' && lower.contains('permission required')) {
      final row = rows.lastIndexWhere(
        (s) =>
            s.contains('Allow once') &&
            s.contains('Allow always') &&
            s.contains('Reject'),
      );
      if (row < 0 || footer - row > 2) return null;
      const labels = ['Allow once', 'Allow always', 'Reject'];
      final styles = [
        for (final label in labels) styleAt?.call(row, raw[row].indexOf(label)),
      ];
      var selected = -1;
      if (styles[0] != null) {
        for (var i = 0; i < 3; i++) {
          final others = [
            for (var j = 0; j < 3; j++)
              if (i != j) styles[j],
          ];
          if (others[0] == others[1] && styles[i] != others[0]) selected = i;
        }
      }
      final start = rows.lastIndexWhere(
        (s) => s.contains('Permission required'),
      );
      final question = rows.sublist(start, row).join('\n').trim();
      return TerminalInteraction(
        agent: agent,
        kind: TerminalInteractionKind.choices,
        question: question,
        options: List.unmodifiable([
          for (var i = 0; i < 3; i++)
            TerminalInteractionOption(
              i + 1,
              labels[i],
              selected: i == selected,
            ),
        ]),
        identity: '$agent:permission:$question',
        horizontal: true,
        cursor: cursor,
      );
    }
    final optionRows = <int>[];
    final options = <TerminalInteractionOption>[];
    var checkboxes = false;
    for (var i = 0; i < footer; i++) {
      final match = _number.firstMatch(rows[i]);
      if (match == null) continue;
      final number = int.parse(match[2]!);
      if (number == 1) {
        options.clear();
        optionRows.clear();
      }
      if (number != options.length + 1 || options.length >= 12) continue;
      final content = match[3]!;
      final box = RegExp(r'^\[([ ✓xX])\]\s*').firstMatch(content);
      checkboxes |= box != null;
      final label = content.replaceFirst(RegExp(r'^\[[ ✓xX]\]\s*'), '').trim();
      options.add(
        TerminalInteractionOption(
          number,
          label,
          selected: match[1]!.isNotEmpty,
          checked: box != null && box[1]!.trim().isNotEmpty,
        ),
      );
      optionRows.add(i);
    }
    if (agent == 'claude' &&
        options.isNotEmpty &&
        footerText.contains('navigate')) {
      for (var row = optionRows.last + 1; row < footer; row++) {
        final submit = RegExp(
          r'^\s*([❯›>]?)\s*(Submit|Next)\s*$',
        ).firstMatch(rows[row]);
        if (submit == null) continue;
        options.add(
          TerminalInteractionOption(
            options.length + 1,
            submit[2]!,
            selected: submit[1]!.isNotEmpty,
          ),
        );
        optionRows.add(row);
        break;
      }
    }
    final isQuestion = RegExp(r'question \d+/\d+').hasMatch(lower);
    final review =
        agent == 'opencode' &&
        lower.contains('review') &&
        footerText.contains('enter') &&
        footerText.contains('submit');
    if (options.isEmpty && !isQuestion && !review) return null;
    // Numbered prose alone is never a clickable menu.
    if (options.isNotEmpty &&
        options.every((o) => !o.selected) &&
        agent != 'opencode') {
      return null;
    }
    final start = options.isEmpty
        ? (footer - 8).clamp(0, footer)
        : (optionRows.first - 6).clamp(0, footer);
    final composerRow = rows.indexWhere(
      (s) => RegExp(r'^\s*[›❯>]\s+(?!\d+[.)])').hasMatch(s),
      start,
    );
    final end =
        options.isEmpty &&
            isQuestion &&
            composerRow >= 0 &&
            composerRow < footer
        ? composerRow
        : options.isEmpty && isQuestion && cursorY >= start && cursorY < footer
        ? cursorY
        : options.isEmpty
        ? footer
        : optionRows.first;
    final header = rows
        .sublist(start, end)
        .where(
          (s) =>
              s.trim().isNotEmpty && !RegExp(r'^[─━╭╰╮╯┌└┐┘ ]+$').hasMatch(s),
        )
        .join('\n')
        .trim();
    final question = header.isEmpty ? '응답을 선택해 주세요.' : header;
    var inputText = '';
    // Claude's inline input replaces "Type something" with its draft. Preserve
    // that row's semantics only while the same question and other rows remain.
    if (agent == 'claude' &&
        previous?.agent == agent &&
        previous!.question == question &&
        previous.options.length == options.length) {
      final input = previous.options.indexWhere((o) => o.custom);
      if (input >= 0 &&
          options.asMap().entries.every(
            (e) =>
                e.key == input ||
                e.value.label == previous.options[e.key].label,
          )) {
        final option = options[input];
        if (!option.custom) inputText = option.label;
        options[input] = TerminalInteractionOption(
          option.number,
          previous.options[input].label,
          selected: option.selected,
          checked: option.checked,
        );
      }
    }
    final multiple =
        question.toLowerCase().contains('select all that apply') ||
        checkboxes ||
        footerText.contains('toggle');
    final notes =
        agent == 'codex' && footerText.contains('to add notes') ||
        agent == 'claude' &&
            footerText.contains('tab') &&
            footerText.contains('comment');
    // Cursor must actually be in an input region, never a highlighted option.
    final lastOption = optionRows.isEmpty ? -1 : optionRows.last;
    final editing =
        agent == 'claude' && options.any((o) => o.custom && o.selected) ||
        options.isEmpty && isQuestion ||
        cursorY > lastOption &&
            cursorY < footer &&
            (lower.contains('add notes') ||
                lower.contains('to clear notes') ||
                lower.contains('type your answer') ||
                options.any((o) => o.custom) ||
                lower.contains('comment'));
    if (editing && agent != 'claude') {
      final inputStart = options.isEmpty ? end : lastOption + 1;
      inputText = rows.sublist(inputStart, footer).join('\n');
    }
    return TerminalInteraction(
      agent: agent,
      kind: review
          ? TerminalInteractionKind.review
          : options.isEmpty
          ? TerminalInteractionKind.input
          : TerminalInteractionKind.choices,
      question: question,
      options: List.unmodifiable(options),
      identity:
          '$agent:$question:${options.map((o) => '${o.number}:${o.label}').join('|')}',
      multiple: multiple,
      canNavigateQuestions:
          footerText.contains('navigate questions') ||
          footerText.contains('change question') ||
          (agent == 'opencode' || agent == 'claude') &&
              footerText.contains('tab') &&
              footerText.contains('navigate') ||
          agent == 'opencode' && footerText.contains('tab'),
      canAddNotes: notes,
      editing: editing,
      cursor: cursor,
      inputText: inputText,
    );
  }
}
