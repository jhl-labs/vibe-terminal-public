/// Vibe Terminal patch: keeps a mouse drag selection growing while a
/// full-screen TUI (alternate screen or mouse-wheel reporting) scrolls its own
/// content.
///
/// Such applications have no local scrollback: the terminal forwards the wheel
/// to the application, which redraws the screen. To select beyond the visible
/// screen, this class compares each stable screen with the previous one, finds
/// how many lines the scrolling region moved, and stitches the revealed lines
/// into a virtual document. Rows that do not move (a header, an input box or a
/// status line) are excluded from the document once the scrolling region is
/// known.
///
/// Rows are lists of cell strings (one entry per terminal column, `''` for the
/// trailing half of a wide character) so that selections keep the column
/// semantics of the terminal.
class TuiScrollStitcher {
  TuiScrollStitcher({
    required List<List<String>> screen,
    required int anchorRow,
    required int anchorCol,
  }) : _screen = screen,
       _lines = [...screen],
       _regionStart = 0,
       _regionEnd = screen.length - 1,
       _anchorLine = anchorRow,
       _anchorCol = anchorCol;

  /// Minimum number of non-blank rows that must line up before a shift is
  /// trusted.
  static const minMatchedRows = 2;

  List<List<String>> _screen;
  List<List<String>> _lines;
  int _regionStart;
  int _regionEnd;
  // Document index shown at screen row [_regionStart].
  int _viewTop = 0;
  bool _regionKnown = false;
  bool _failed = false;
  int _anchorLine;
  final int _anchorCol;

  /// Whether stitching gave up (layout change, anchor outside the scrolling
  /// region, or a redraw that could not be aligned).
  bool get failed => _failed;

  /// Whether any scroll has been stitched, i.e. the selection may extend
  /// beyond the visible screen.
  bool get hasScrolled => _regionKnown;

  /// First and last screen rows of the scrolling region (inclusive).
  int get regionStart => _regionStart;
  int get regionEnd => _regionEnd;

  /// Document line of the drag anchor.
  int get anchorLine => _anchorLine;
  int get anchorCol => _anchorCol;

  /// The stitched document, oldest line first.
  List<List<String>> get lines => List.unmodifiable(_lines);

  /// Processes a new stable screen and returns the detected shift: positive
  /// when the content moved up (scrolled toward the end), negative when it
  /// moved down, zero when it did not move.
  int update(List<List<String>> screen) {
    if (_failed) return 0;
    if (screen.length != _screen.length) {
      _failed = true;
      return 0;
    }
    final oldKeys = [for (final row in _screen) _key(row)];
    final newKeys = [for (final row in screen) _key(row)];

    // Only rows that changed can tell how far the content moved: fixed rows
    // (header, input box, status line) would otherwise always vote for "no
    // movement".
    final (first, last) = _regionKnown
        ? (_regionStart, _regionEnd)
        : (0, screen.length - 1);
    var bestShift = 0;
    var bestScore = minMatchedRows - 1;
    for (var distance = 1; distance <= last - first; distance++) {
      for (final shift in [distance, -distance]) {
        final score = _score(oldKeys, newKeys, shift, first, last);
        if (score > bestScore) {
          bestScore = score;
          bestShift = shift;
        }
      }
    }

    if (bestShift != 0) {
      _applyShift(bestShift, oldKeys, newKeys);
      if (_failed) return 0;
    }
    _screen = screen;
    _refreshView();
    return bestShift;
  }

  /// Document line for a screen row. Rows outside the scrolling region are
  /// clamped to its edges.
  int lineForRow(int row) {
    final clamped = row.clamp(_regionStart, _regionEnd);
    return _viewTop + clamped - _regionStart;
  }

  /// Screen row for a document line. May lie outside the scrolling region
  /// when the line is currently scrolled out of view.
  int rowForLine(int line) => _regionStart + line - _viewTop;

  /// Text between the anchor and ([row], [col]) on the screen, inclusive of
  /// both end cells, lines joined with `\n` and trailing spaces trimmed.
  String textTo({required int row, required int col}) {
    final line = lineForRow(row);
    var (startLine, startCol, endLine, endCol) =
        (line < _anchorLine || (line == _anchorLine && col < _anchorCol))
        ? (line, col, _anchorLine, _anchorCol)
        : (_anchorLine, _anchorCol, line, col);
    final buffer = StringBuffer();
    for (var i = startLine; i <= endLine; i++) {
      final cells = i >= 0 && i < _lines.length ? _lines[i] : const <String>[];
      final from = i == startLine ? startCol.clamp(0, cells.length) : 0;
      final to = i == endLine
          ? (endCol + 1).clamp(from, cells.length)
          : cells.length;
      buffer.write(cells.sublist(from, to).join().trimRight());
      if (i != endLine) buffer.write('\n');
    }
    return buffer.toString();
  }

  void _applyShift(int shift, List<String> oldKeys, List<String> newKeys) {
    if (!_regionKnown) {
      var minMatched = -1;
      var maxMatched = -1;
      for (var i = 0; i < newKeys.length; i++) {
        final j = i + shift;
        if (j < 0 || j >= oldKeys.length) continue;
        if (newKeys[i].isEmpty || newKeys[i] != oldKeys[j]) continue;
        if (minMatched < 0) minMatched = i;
        maxMatched = i;
      }
      final last = newKeys.length - 1;
      final start = shift > 0 ? minMatched : (minMatched + shift).clamp(0, last);
      final end = shift > 0 ? (maxMatched + shift).clamp(0, last) : maxMatched;
      if (_anchorLine < start || _anchorLine > end) {
        // The drag started in a fixed row (header/input box); there is
        // nothing to stitch.
        _failed = true;
        return;
      }
      // The document so far mirrors the whole screen. Keep only the rows of
      // the scrolling region, as they were before this shift.
      _lines = _lines.sublist(start, end + 1);
      _anchorLine -= start;
      _viewTop = 0;
      _regionStart = start;
      _regionEnd = end;
      _regionKnown = true;
    }
    _viewTop += shift;
    if (_viewTop < 0) {
      final missing = -_viewTop;
      _lines.insertAll(0, List.generate(missing, (_) => const <String>[]));
      _anchorLine += missing;
      _viewTop = 0;
    }
  }

  void _refreshView() {
    for (var row = _regionStart; row <= _regionEnd; row++) {
      final index = _viewTop + row - _regionStart;
      while (_lines.length < index) {
        _lines.add(const <String>[]);
      }
      if (index < _lines.length) {
        _lines[index] = _screen[row];
      } else {
        _lines.add(_screen[row]);
      }
    }
  }

  /// Number of changed, non-blank rows in [first]..[last] whose new content is
  /// the old content of the row [shift] lines below (above when negative).
  static int _score(
    List<String> oldKeys,
    List<String> newKeys,
    int shift,
    int first,
    int last,
  ) {
    var score = 0;
    for (var i = first; i <= last; i++) {
      final j = i + shift;
      if (j < first || j > last) continue;
      final key = newKeys[i];
      if (key.isEmpty || key == oldKeys[i]) continue;
      if (key == oldKeys[j]) score++;
    }
    return score;
  }

  static String _key(List<String> row) => row.join().trimRight();
}
