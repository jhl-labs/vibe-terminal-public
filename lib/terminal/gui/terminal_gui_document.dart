import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

@immutable
class TerminalGuiRun {
  const TerminalGuiRun(this.text, this.foreground, this.background, this.flags);

  final String text;
  final int foreground;
  final int background;
  final int flags;

  TerminalGuiRun withText(String value) =>
      TerminalGuiRun(value, foreground, background, flags);

  bool sameStyle(TerminalGuiRun other) =>
      foreground == other.foreground &&
      background == other.background &&
      flags == other.flags;

  @override
  bool operator ==(Object other) =>
      other is TerminalGuiRun && text == other.text && sameStyle(other);

  @override
  int get hashCode => Object.hash(text, foreground, background, flags);
}

/// A bounded, immutable projection of the interpreted screen, never raw ANSI.
@immutable
class TerminalGuiDocument {
  const TerminalGuiDocument(this.runs, {required this.truncated});

  final List<TerminalGuiRun> runs;
  final bool truncated;
  String get text => runs.map((run) => run.text).join();

  factory TerminalGuiDocument.capture(
    Terminal terminal, {
    int maxLines = 2000,
    int maxCharacters = 200000,
  }) {
    assert(maxLines > 0 && maxCharacters > 0);
    final buffer = terminal.buffer;
    final start = (buffer.height - maxLines).clamp(0, buffer.height);
    final runs = <TerminalGuiRun>[];
    var characters = 0;
    TerminalGuiRun? style;
    var content = StringBuffer();
    void flushRun() {
      if (style != null && content.isNotEmpty) {
        runs.add(style!.withText(content.toString()));
        content = StringBuffer();
      }
    }

    void append(TerminalGuiRun run) {
      if (run.text.isEmpty) return;
      characters += run.text.length;
      if (style != null && !style!.sameStyle(run)) flushRun();
      style = run;
      content.write(run.text);
    }

    for (var y = start; y < buffer.height; y++) {
      final line = buffer.lines[y];
      if (y > start && !line.isWrapped) {
        append(const TerminalGuiRun('\n', 0, 0, 0));
      }
      var end = line.length;
      final continues = y + 1 < buffer.height && buffer.lines[y + 1].isWrapped;
      // Drop terminal padding, keeping spaces inside tables and wide-cell tails.
      while (end > 0) {
        final code = line.getCodePoint(end - 1);
        if (code != 0 && (code != 32 || continues)) break;
        end--;
      }
      for (var x = 0; x < end; x++) {
        final code = line.getCodePoint(x);
        if (code == 0 &&
            x > 0 &&
            line.getWidth(x - 1) == 2 &&
            line.getCodePoint(x - 1) != 0) {
          continue;
        }
        final flags = line.getAttributes(x);
        final concealed = flags & CellFlags.invisible != 0;
        append(
          TerminalGuiRun(
            concealed
                ? ' '
                : code == 0
                ? ' '
                : String.fromCharCode(code),
            line.getForeground(x),
            line.getBackground(x),
            flags,
          ),
        );
      }
    }
    flushRun();
    // A terminal allocates blank viewport rows; they are not document paragraphs.
    while (runs.isNotEmpty) {
      final last = runs.last;
      final trimmed = last.text.trimRight();
      characters -= last.text.length - trimmed.length;
      if (trimmed.isEmpty) {
        runs.removeLast();
      } else {
        runs[runs.length - 1] = last.withText(trimmed);
        break;
      }
    }
    var discard = (characters - maxCharacters).clamp(0, characters);
    final truncated = start > 0 || discard > 0;
    while (discard > 0 && runs.isNotEmpty) {
      final first = runs.first;
      if (discard >= first.text.length) {
        discard -= first.text.length;
        runs.removeAt(0);
      } else {
        // Keep a Unicode scalar intact at the truncation boundary.
        final unit = first.text.codeUnitAt(discard);
        if (unit >= 0xDC00 && unit <= 0xDFFF) discard++;
        runs[0] = first.withText(first.text.substring(discard));
        discard = 0;
      }
    }
    return TerminalGuiDocument(List.unmodifiable(runs), truncated: truncated);
  }

  List<TerminalGuiRun> range(int start, int end) {
    final result = <TerminalGuiRun>[];
    var offset = 0;
    for (final run in runs) {
      final next = offset + run.text.length;
      if (next > start && offset < end) {
        result.add(
          run.withText(
            run.text.substring(
              (start - offset).clamp(0, run.text.length),
              (end - offset).clamp(0, run.text.length),
            ),
          ),
        );
      }
      if (next >= end) break;
      offset = next;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is TerminalGuiDocument &&
      truncated == other.truncated &&
      listEquals(runs, other.runs);

  @override
  int get hashCode => Object.hash(truncated, Object.hashAll(runs));
}

enum TerminalGuiBlockKind { text, markdown, code }

@immutable
class TerminalGuiBlock {
  const TerminalGuiBlock(this.kind, this.runs, {this.language = ''});
  final TerminalGuiBlockKind kind;
  final List<TerminalGuiRun> runs;
  final String language;
  String get text => runs.map((run) => run.text).join();
}

/// Only explicit Markdown is formatted. Ordinary CLI rows retain their spacing.
List<TerminalGuiBlock> terminalGuiBlocks(TerminalGuiDocument document) {
  final text = document.text;
  final blocks = <TerminalGuiBlock>[];
  final lines = text.split('\n');
  var offset = 0;
  var begin = 0;
  String? fence;
  var language = '';
  final markdown = RegExp(
    r'(^|\n)(#{1,6} |[-*+] |\d+\. |> )|\*\*\S|\[[^\]\n]+\]\(https?://',
    caseSensitive: false,
  );
  void emit(int end, {bool code = false}) {
    if (end <= begin) return;
    final body = text.substring(begin, end);
    blocks.add(
      TerminalGuiBlock(
        code
            ? TerminalGuiBlockKind.code
            : markdown.hasMatch(body)
            ? TerminalGuiBlockKind.markdown
            : TerminalGuiBlockKind.text,
        document.range(begin, end),
        language: language,
      ),
    );
  }

  for (final line in lines) {
    final marker = RegExp(r'^\s*(`{3,}|~{3,})([^\s]*)\s*$').firstMatch(line);
    if (fence == null && marker != null) {
      emit(offset > begin ? offset - 1 : offset);
      fence = marker[1]!;
      language = marker[2]!;
      begin = offset + line.length + 1;
    } else if (fence != null && line.trim() == fence) {
      emit(offset > begin ? offset - 1 : offset, code: true);
      fence = null;
      language = '';
      begin = offset + line.length + 1;
    } else if (fence == null && line.trim().isEmpty) {
      emit(offset > begin ? offset - 1 : offset);
      begin = offset + line.length + 1;
    }
    offset += line.length + 1;
  }
  emit(text.length, code: fence != null);
  return List.unmodifiable(blocks);
}
