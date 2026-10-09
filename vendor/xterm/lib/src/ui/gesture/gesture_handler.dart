import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/selection_auto_scroll.dart';
import 'package:xterm/src/ui/tui_scroll_stitcher.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
    this.onTouchSelectionChanged,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  final ValueChanged<bool>? onTouchSelectionChanged;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  bool _touchSelecting = false;

  /// Vibe Terminal patch: the drag anchor as a buffer cell (stable across
  /// scrolling) and the last pointer position, used to re-apply the selection
  /// after the viewport scrolls under a held mouse button.
  CellOffset? _dragAnchor;

  Offset? _lastDragLocalPosition;

  /// Vibe Terminal patch: unit a mouse drag extends by. A drag that starts on
  /// the second click selects whole words, on the third whole lines.
  _DragUnit _dragUnit = _DragUnit.character;

  // The word/line under the drag start; the selection always covers it.
  BufferRangeLine? _dragUnitAnchor;

  // Mouse clicks in the current quick sequence, counted from raw pointer
  // events: the tap recognizer loses the arena (and never reports the
  // double tap) when the second press starts dragging right away.
  int _clickCount = 0;
  Offset? _lastClickUpPosition;
  // Running while the next press still continues the sequence.
  Timer? _clickSequenceTimer;

  late final _autoScroller = SelectionAutoScroller(
    getScrollController: () => terminalView.scrollController,
    onScrolled: _applyDragSelection,
  );

  /// Vibe Terminal patch: stitches the screens of a full-screen TUI while a
  /// mouse drag selection scrolls it (see [TuiScrollStitcher]).
  TuiScrollStitcher? _stitcher;

  // The terminal is listened only while stitching; screens are processed
  // once the application stops writing for [_stitchQuietDelay].
  Timer? _stitchDebounce;
  Timer? _tuiAutoScrollTimer;
  int _tuiAutoScrollDirection = 0;
  // A scroll was sent to the application and its redraw is not yet stitched.
  DateTime? _tuiScrollPendingSince;
  int _tuiScrollEventsInFlight = 0;
  // Rows the pointer is dragged past the viewport edge; speeds up scrolling.
  int _tuiOvershootRows = 0;
  // Lines one scroll event moves the application, learned from redraws.
  // Starts at three (a common wheel step) and is only ever raised.
  int _tuiLinesPerScrollEvent = 3;

  static const _stitchQuietDelay = Duration(milliseconds: 20);
  static const _tuiAutoScrollInterval = Duration(milliseconds: 50);
  static const _tuiRedrawTimeout = Duration(milliseconds: 500);

  @override
  void dispose() {
    _clickSequenceTimer?.cancel();
    widget.terminalController.releaseViewport(this);
    _autoScroller.dispose();
    _stopStitching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _countClick,
      onPointerUp: _recordClickUp,
      onPointerCancel: (_) => _endTouchSelection(),
      onPointerSignal: _onPointerSignal,
      child: TerminalGestureDetector(
        onTapUp: widget.onTapUp,
        onSingleTapUp: onSingleTapUp,
        onTapDown: onTapDown,
        onSecondaryTapDown: onSecondaryTapDown,
        onSecondaryTapUp: onSecondaryTapUp,
        onTertiaryTapDown: onSecondaryTapDown,
        onTertiaryTapUp: onSecondaryTapUp,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressUp: _endTouchSelection,
        onLongPressCancel: _endTouchSelection,
        onDragStart: onDragStart,
        onDragUpdate: onDragUpdate,
        onDragEnd: (_) => _endDrag(),
        onDragCancel: _endDrag,
        onDoubleTapDown: onDoubleTapDown,
        onTripleTapDown: onTripleTapDown,
        child: widget.child,
      ),
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
  }

  void onTripleTapDown(TapDownDetails details) {
    renderTerminal.selectLine(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _touchSelecting = true;
    widget.onTouchSelectionChanged?.call(true);
    onDragStart(DragStartDetails(
      globalPosition: details.globalPosition,
      localPosition: details.localPosition,
      kind: PointerDeviceKind.touch,
    ));
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_touchSelecting) return;
    onDragUpdate(DragUpdateDetails(
      globalPosition: details.globalPosition,
      localPosition: details.localPosition,
    ));
  }

  void _endTouchSelection() {
    if (!_touchSelecting) return;
    _endDrag();
    _touchSelecting = false;
    widget.onTouchSelectionChanged?.call(false);
  }

  void _countClick(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final lastPosition = _lastClickUpPosition;
    final continues = (_clickSequenceTimer?.isActive ?? false) &&
        lastPosition != null &&
        (event.position - lastPosition).distance <= kDoubleTapSlop;
    _clickSequenceTimer?.cancel();
    _clickCount = continues ? (_clickCount % 3) + 1 : 1;
  }

  void _recordClickUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _lastClickUpPosition = event.position;
    _clickSequenceTimer?.cancel();
    _clickSequenceTimer = Timer(kDoubleTapTimeout, () {});
  }

  void onDragStart(DragStartDetails details) {
    final cell = renderTerminal.getCellOffset(details.localPosition);
    _dragAnchor = cell;
    _lastDragLocalPosition = details.localPosition;
    _autoScroller.begin();
    // Output arriving mid-drag must not move the text under the pointer.
    widget.terminalController.holdViewport(this);

    _dragIsMouse = details.kind == PointerDeviceKind.mouse;
    _dragUnit = !_dragIsMouse
        ? _DragUnit.character
        : switch (_clickCount) {
            2 => _DragUnit.word,
            3 => _DragUnit.line,
            _ => _DragUnit.character,
          };
    switch (_dragUnit) {
      case _DragUnit.word:
        _dragUnitAnchor = renderTerminal.wordRangeAt(cell);
        renderTerminal.selectRange(_dragUnitAnchor!);
      case _DragUnit.line:
        _dragUnitAnchor = renderTerminal.lineRangeAt(cell);
        renderTerminal.selectRange(_dragUnitAnchor!);
      case _DragUnit.character:
        _dragIsMouse
            ? renderTerminal.selectCharacters(details.localPosition)
            : renderTerminal.selectWord(details.localPosition);
    }
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragLocalPosition = details.localPosition;
    _applyDragSelection();
    if (_canStitch) {
      _updateTuiAutoScroll(details.localPosition);
      return;
    }
    _autoScroller.update(
      localY: details.localPosition.dy,
      viewportHeight: renderTerminal.size.height,
      lineHeight: renderTerminal.lineHeight,
      edgeExtent: _touchSelecting ? 32 : 0,
    );
  }

  void _applyDragSelection() {
    final anchor = _dragAnchor;
    final position = _lastDragLocalPosition;
    if (anchor == null || position == null || !mounted) return;
    final unitAnchor = _dragUnitAnchor;
    if (unitAnchor != null) {
      final cell = renderTerminal.getCellOffset(position);
      renderTerminal.selectRange(
        unitAnchor,
        _dragUnit == _DragUnit.line
            ? renderTerminal.lineRangeAt(cell)
            : renderTerminal.wordRangeAt(cell),
      );
      return;
    }
    final stitcher = _stitcher;
    if (stitcher != null && stitcher.hasScrolled) {
      _applyStitchedSelection(stitcher, position);
      return;
    }
    renderTerminal.selectCharactersFromCell(anchor, position);
  }

  void _endDrag() {
    // Stitch a redraw that arrived just before the release, so the copied
    // text ends where the screen shows the selection ending.
    if (_stitchDebounce?.isActive ?? false) {
      _stitchDebounce!.cancel();
      _stitchScreen();
    }
    final stitcher = _stitcher;
    final position = _lastDragLocalPosition;
    if (stitcher != null &&
        stitcher.hasScrolled &&
        !stitcher.failed &&
        position != null &&
        mounted) {
      final (row, col) = _stitchedPointerCell(stitcher, position);
      widget.terminalController.setSelectionTextOverride(
        stitcher.textTo(row: row, col: col),
      );
    }
    _stopStitching();
    _autoScroller.end();
    widget.terminalController.releaseViewport(this);
    _dragAnchor = null;
    _dragUnitAnchor = null;
    _dragUnit = _DragUnit.character;
    _lastDragLocalPosition = null;
    _dragIsMouse = false;
  }

  // --- Full-screen TUI stitching (Vibe Terminal patch) ---

  /// Whether the current drag is a mouse drag. Touch drags scroll instead of
  /// selecting; a touch long-press selection ([_touchSelecting]) stitches like
  /// a mouse drag.
  bool _dragIsMouse = false;

  /// Whether a scroll during the current drag should be stitched: a mouse
  /// drag over a TUI that owns scrolling, with the local viewport showing the
  /// live screen. Stitching starts lazily on the first scroll request, so a
  /// drag without scrolling behaves exactly like a normal selection even
  /// while the application keeps redrawing (spinners, streamed output).
  bool get _canStitch =>
      (_dragIsMouse || _touchSelecting) &&
      _dragAnchor != null &&
      _dragUnit == _DragUnit.character &&
      _isTuiScrolling &&
      _viewPinnedToBottom;

  /// Stitching reads the bottom `viewHeight` rows as "the screen". In the main
  /// buffer the user may have scrolled the local scrollback up (for example
  /// before the application enabled mouse reporting); those rows are not what
  /// is visible then.
  bool get _viewPinnedToBottom {
    if (terminalView.widget.terminal.isUsingAltBuffer) return true;
    final controller = terminalView.scrollController;
    if (!controller.hasClients) return true;
    final position = controller.position;
    return position.pixels >= position.maxScrollExtent - 1;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_canStitch) return;
    // The wheel is forwarded to the application after this listener runs, so
    // the screen captured here is the one before its redraw.
    if (_stitcher == null) _startStitching(_dragAnchor!);
  }

  /// Whether the wheel scrolls the application instead of local scrollback.
  bool get _isTuiScrolling {
    final terminal = terminalView.widget.terminal;
    return terminal.isUsingAltBuffer || terminal.mouseMode.reportScroll;
  }

  int get _screenTop {
    final terminal = terminalView.widget.terminal;
    return terminal.buffer.height - terminal.viewHeight;
  }

  /// Screen cell (row relative to the top of the viewport) under [local].
  CellOffset _screenCell(Offset local) {
    final cell = renderTerminal.getCellOffset(local);
    final terminal = terminalView.widget.terminal;
    return CellOffset(
      cell.x.clamp(0, terminal.viewWidth - 1),
      (cell.y - _screenTop).clamp(0, terminal.viewHeight - 1),
    );
  }

  List<List<String>> _captureScreen() {
    final terminal = terminalView.widget.terminal;
    final buffer = terminal.buffer;
    final top = _screenTop;
    return [
      for (var row = 0; row < terminal.viewHeight; row++)
        _rowCells(buffer.lines[top + row], terminal.viewWidth),
    ];
  }

  static List<String> _rowCells(BufferLine line, int width) {
    final cells = <String>[];
    var continuation = false;
    for (var col = 0; col < width; col++) {
      if (col >= line.length) {
        cells.add(' ');
        continue;
      }
      if (continuation) {
        // Trailing half of a wide character.
        cells.add('');
        continuation = false;
        continue;
      }
      final codePoint = line.getCodePoint(col);
      cells.add(codePoint == 0 ? ' ' : String.fromCharCode(codePoint));
      continuation = line.getWidth(col) == 2;
    }
    return cells;
  }

  void _startStitching(CellOffset anchor) {
    _stopStitching();
    final terminal = terminalView.widget.terminal;
    final row = anchor.y - _screenTop;
    if (row < 0 || row >= terminal.viewHeight) return;
    _stitcher = TuiScrollStitcher(
      screen: _captureScreen(),
      anchorRow: row,
      anchorCol: anchor.x.clamp(0, terminal.viewWidth - 1),
    );
    terminal.addListener(_onTerminalChangedWhileStitching);
  }

  void _stopStitching() {
    if (_stitcher != null) {
      terminalView.widget.terminal.removeListener(
        _onTerminalChangedWhileStitching,
      );
    }
    _stitcher = null;
    _stitchDebounce?.cancel();
    _stitchDebounce = null;
    _tuiAutoScrollTimer?.cancel();
    _tuiAutoScrollTimer = null;
    _tuiAutoScrollDirection = 0;
    _tuiScrollPendingSince = null;
    _tuiScrollEventsInFlight = 0;
    _tuiOvershootRows = 0;
    _tuiLinesPerScrollEvent = 3;
  }

  void _onTerminalChangedWhileStitching() {
    _stitchDebounce?.cancel();
    _stitchDebounce = Timer(_stitchQuietDelay, _stitchScreen);
  }

  void _stitchScreen() {
    final stitcher = _stitcher;
    if (stitcher == null || !mounted) return;
    if (!_isTuiScrolling) {
      // The application left full-screen mode mid-drag.
      _stopStitching();
      return;
    }
    final shift = stitcher.update(_captureScreen());
    // Learn how many lines one scroll event moves in this application
    // (arrow keys move one, many TUIs move three per wheel notch).
    // Only ever raise the estimate: a smaller shift may just mean the
    // application hit the end of its content.
    if (_tuiScrollEventsInFlight > 0) {
      final observed = (shift.abs() / _tuiScrollEventsInFlight).ceil();
      if (observed > _tuiLinesPerScrollEvent) {
        _tuiLinesPerScrollEvent = observed;
      }
    }
    _tuiScrollEventsInFlight = 0;
    _tuiScrollPendingSince = null;
    if (stitcher.failed) {
      // Could not follow the application's redraw: keep the selection that is
      // on screen now and stop extending it.
      _stopStitching();
      _dragAnchor = null;
      _lastDragLocalPosition = null;
      return;
    }
    _applyDragSelection();
  }

  void _applyStitchedSelection(TuiScrollStitcher stitcher, Offset position) {
    final terminal = terminalView.widget.terminal;
    final lastCol = terminal.viewWidth - 1;
    final (pointerRow, pointerCol) = _stitchedPointerCell(stitcher, position);
    final pointer = CellOffset(pointerCol, pointerRow);
    final pointerLine = stitcher.lineForRow(pointerRow);

    // The anchor may have scrolled out of view: pin it to the region edge.
    var anchorRow = stitcher.rowForLine(stitcher.anchorLine);
    var anchorCol = stitcher.anchorCol;
    if (anchorRow < stitcher.regionStart) {
      anchorRow = stitcher.regionStart;
      anchorCol = 0;
    } else if (anchorRow > stitcher.regionEnd) {
      anchorRow = stitcher.regionEnd;
      anchorCol = lastCol;
    }

    final anchorFirst = stitcher.anchorLine < pointerLine ||
        (stitcher.anchorLine == pointerLine && stitcher.anchorCol <= pointer.x);
    final top = _screenTop;
    final anchorCell = CellOffset(anchorCol, top + anchorRow);
    final pointerCell = CellOffset(pointer.x, top + pointerRow);
    final begin = anchorFirst ? anchorCell : pointerCell;
    final last = anchorFirst ? pointerCell : anchorCell;
    final buffer = terminal.buffer;
    widget.terminalController.setSelection(
      buffer.createAnchorFromOffset(begin),
      buffer.createAnchorFromOffset(CellOffset(last.x + 1, last.y)),
    );
  }

  /// Screen row/column of the pointer, clamped to the scrolling region. A
  /// pointer above the region selects from the start of its first row, one
  /// below it to the end of its last row.
  (int, int) _stitchedPointerCell(TuiScrollStitcher stitcher, Offset local) {
    final cell = _screenCell(local);
    final lastCol = terminalView.widget.terminal.viewWidth - 1;
    if (local.dy < 0 || cell.y < stitcher.regionStart) {
      return (stitcher.regionStart, 0);
    }
    if (local.dy > renderTerminal.size.height || cell.y > stitcher.regionEnd) {
      return (stitcher.regionEnd, lastCol);
    }
    return (cell.y, cell.x);
  }

  void _updateTuiAutoScroll(Offset local) {
    final stitcher = _stitcher;
    final height = renderTerminal.size.height;
    final row = _screenCell(local).y;
    final lastRow = terminalView.widget.terminal.viewHeight - 1;
    var direction = 0;
    if (local.dy < (_touchSelecting ? 32 : 0) || row <= 0) {
      direction = -1;
    } else if (local.dy > height - (_touchSelecting ? 32 : 0) ||
        row >= lastRow) {
      direction = 1;
    } else if (stitcher != null && stitcher.hasScrolled) {
      if (row < stitcher.regionStart) direction = -1;
      if (row > stitcher.regionEnd) direction = 1;
    }
    // Start stitching before recording the direction: starting resets the
    // auto-scroll state.
    if (direction != 0 && stitcher == null) {
      _startStitching(_dragAnchor!);
      if (_stitcher == null) return;
    }
    _tuiAutoScrollDirection = direction;
    final lineHeight = renderTerminal.lineHeight;
    _tuiOvershootRows = lineHeight <= 0
        ? 0
        : local.dy < 0
            ? (-local.dy / lineHeight).ceil()
            : local.dy > height
                ? ((local.dy - height) / lineHeight).ceil()
                : 0;
    if (direction == 0) {
      _tuiAutoScrollTimer?.cancel();
      _tuiAutoScrollTimer = null;
      return;
    }
    if (_tuiAutoScrollTimer != null) return;
    _tuiAutoScrollTimer = Timer.periodic(
      _tuiAutoScrollInterval,
      (_) => _tuiAutoScrollTick(),
    );
    _tuiAutoScrollTick();
  }

  void _tuiAutoScrollTick() {
    final stitcher = _stitcher;
    if (stitcher == null || _tuiAutoScrollDirection == 0 || !mounted) return;
    final pending = _tuiScrollPendingSince;
    // Wait until the previous scroll is redrawn and stitched: scrolling
    // further first could move the content beyond what can be aligned.
    if (pending != null &&
        DateTime.now().difference(pending) < _tuiRedrawTimeout) {
      return;
    }
    // Scroll faster the further the pointer is dragged past the edge, but
    // never move more than half of the scrolling region per redraw, so the
    // next screen still overlaps the previous one enough to be aligned.
    final regionHeight = stitcher.regionEnd - stitcher.regionStart + 1;
    final maxEvents = ((regionHeight ~/ 2) ~/ _tuiLinesPerScrollEvent).clamp(
      1,
      regionHeight,
    );
    final events = (1 + _tuiOvershootRows).clamp(1, maxEvents);
    _tuiScrollEventsInFlight = events;
    _tuiScrollPendingSince = DateTime.now();
    for (var i = 0; i < events; i++) {
      _sendTuiScroll(up: _tuiAutoScrollDirection < 0);
    }
  }

  /// Same conversion as the wheel in `TerminalScrollGestureHandler`.
  void _sendTuiScroll({required bool up}) {
    final terminal = terminalView.widget.terminal;
    final position = _lastDragLocalPosition;
    final cell = position == null
        ? const CellOffset(0, 0)
        : renderTerminal.getCellOffset(position);
    final handled = terminal.mouseInput(
      up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
      TerminalMouseButtonState.down,
      cell,
    );
    if (!handled && terminal.isUsingAltBuffer) {
      terminal.keyInput(up ? TerminalKey.arrowUp : TerminalKey.arrowDown);
    }
  }
}

/// Vibe Terminal patch: what a selection drag extends by.
enum _DragUnit { character, word, line }
