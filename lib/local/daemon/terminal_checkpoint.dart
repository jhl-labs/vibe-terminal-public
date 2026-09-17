import 'package:xterm/core.dart';

/// Bounded-journal fallback: restore both visible buffers, styling and input modes.
/// Historical scrollback beyond the journal limit is intentionally not recreated.
String terminalCheckpoint(Terminal terminal) {
  final out = StringBuffer('\x1bc\x1b[?7l');
  void buffer(Buffer buffer) {
    out.write('\x1b[0m\x1b[2J\x1b[H');
    final cell = CellData.empty();
    for (var y = 0; y < terminal.viewHeight; y++) {
      final line = buffer.lines[buffer.scrollBack + y];
      for (var x = 0; x < terminal.viewWidth && x < line.length; x++) {
        line.getCellData(x, cell);
        final code = cell.content & CellContent.codepointMask;
        if (line.getWidth(x) == 0 && code != 0) continue;
        out.write(
          '\x1b[${y + 1};${x + 1}H${_style(cell.foreground, cell.background, cell.flags)}',
        );
        out.write(code == 0 ? ' ' : String.fromCharCode(code));
        if (line.getWidth(x) == 2) x++;
      }
    }
    out.write('\x1b[${buffer.marginTop + 1};${buffer.marginBottom + 1}r');
    out.write('\x1b[${buffer.cursorY + 1};${buffer.cursorX + 1}H');
  }

  buffer(terminal.mainBuffer);
  if (terminal.isUsingAltBuffer) {
    out.write('\x1b[?1049h\x1b[?7l');
    buffer(terminal.altBuffer);
  }
  void mode(int code, bool enabled) =>
      out.write('\x1b[?$code${enabled ? 'h' : 'l'}');
  mode(1, terminal.cursorKeysMode);
  mode(5, terminal.reverseDisplayMode);
  mode(7, terminal.autoWrapMode);
  mode(12, terminal.cursorBlinkMode);
  mode(25, terminal.cursorVisibleMode);
  mode(1004, terminal.reportFocusMode);
  mode(1007, terminal.altBufferMouseScrollMode);
  mode(2004, terminal.bracketedPasteMode);
  final mouse = switch (terminal.mouseMode) {
    MouseMode.none => null,
    MouseMode.clickOnly => 9,
    MouseMode.upDownScroll => 1000,
    MouseMode.upDownScrollDrag => 1002,
    MouseMode.upDownScrollMove => 1003,
  };
  if (mouse != null) mode(mouse, true);
  final report = switch (terminal.mouseReportMode) {
    MouseReportMode.normal => null,
    MouseReportMode.utf => 1005,
    MouseReportMode.sgr => 1006,
    MouseReportMode.urxvt => 1015,
  };
  if (report != null) mode(report, true);
  out.write(terminal.appKeypadMode ? '\x1b=' : '\x1b>');
  out.write(
    '\x1b[4${terminal.insertMode ? 'h' : 'l'}\x1b[20${terminal.lineFeedMode ? 'h' : 'l'}',
  );
  // Origin mode changes cursor coordinates, so position again after enabling it.
  mode(6, terminal.originMode);
  final active = terminal.buffer;
  out.write(
    '\x1b[${active.cursorY + 1 - (terminal.originMode ? active.marginTop : 0)};${active.cursorX + 1}H',
  );
  out.write(
    _style(
      terminal.cursor.foreground,
      terminal.cursor.background,
      terminal.cursor.attrs,
    ),
  );
  return out.toString();
}

String _style(int foreground, int background, int flags) {
  final values = <int>[0];
  const attributes = [
    CellAttr.bold,
    CellAttr.faint,
    CellAttr.italic,
    CellAttr.underline,
    CellAttr.blink,
    CellAttr.inverse,
    CellAttr.invisible,
    CellAttr.strikethrough,
  ];
  const sgr = [1, 2, 3, 4, 5, 7, 8, 9];
  for (var i = 0; i < attributes.length; i++) {
    if (flags & attributes[i] != 0) values.add(sgr[i]);
  }
  void color(int encoded, int prefix) {
    final type = encoded & CellColor.typeMask,
        value = encoded & CellColor.valueMask;
    if (type == CellColor.rgb) {
      values.addAll([
        prefix,
        2,
        (value >> 16) & 255,
        (value >> 8) & 255,
        value & 255,
      ]);
    } else if (type == CellColor.named || type == CellColor.palette) {
      values.addAll([prefix, 5, value]);
    }
  }

  color(foreground, 38);
  color(background, 48);
  return '\x1b[${values.join(';')}m';
}
