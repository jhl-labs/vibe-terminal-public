import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/core.dart';
import 'package:xterm/src/ui/infinite_scroll_view.dart';

/// Handles scrolling gestures in the alternate screen buffer. In alternate
/// screen buffer, the terminal don't have a scrollback buffer, instead, the
/// scroll gestures are converted to escape sequences based on the current
/// report mode declared by the application.
class TerminalScrollGestureHandler extends StatefulWidget {
  const TerminalScrollGestureHandler({
    super.key,
    required this.terminal,
    required this.getCellOffset,
    required this.getLineHeight,
    this.simulateScroll = true,
    required this.child,
  });

  final Terminal terminal;

  /// Returns the cell offset for the pixel offset.
  final CellOffset Function(Offset) getCellOffset;

  /// Returns the pixel height of lines in the terminal.
  final double Function() getLineHeight;

  /// Whether to simulate scroll events in the terminal when the application
  /// doesn't declare it supports mouse wheel events. true by default as it
  /// is the default behavior of most terminals.
  final bool simulateScroll;

  final Widget child;

  @override
  State<TerminalScrollGestureHandler> createState() =>
      _TerminalScrollGestureHandlerState();
}

class _TerminalScrollGestureHandlerState
    extends State<TerminalScrollGestureHandler> {
  static const _touchDevices = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  /// Whether the application is in alternate screen buffer.
  var isAltBuffer = false;

  /// Whether the application asked for mouse wheel reports (DECSET 1000/1002/
  /// 1003). Vibe Terminal patch: inline TUIs such as codex enable mouse
  /// tracking in the main buffer, so wheel events must reach the application
  /// instead of scrolling the local scrollback.
  var reportsScroll = false;

  /// Whether this widget should intercept scroll gestures at all.
  bool get _active => isAltBuffer || reportsScroll;

  /// The variable that tracks the line offset in last scroll event. Used to
  /// determine how many the scroll events should be sent to the terminal.
  var lastLineOffset = 0;

  /// This variable tracks the last offset where the scroll gesture started.
  /// Used to calculate the cell offset of the terminal mouse event.
  var lastPointerPosition = Offset.zero;

  /// Touch drag is observed directly instead of relying on [Scrollable]'s
  /// gesture recognizer. A parent horizontal gesture (for example mobile
  /// session switching) can win Flutter's gesture arena before a slightly
  /// diagonal vertical swipe is recognized, in which case the TUI used to
  /// receive no wheel event at all.
  final _touchScrolls = <int, _TouchScrollTracker>{};

  @override
  void initState() {
    widget.terminal.addListener(_onTerminalUpdated);
    isAltBuffer = widget.terminal.isUsingAltBuffer;
    reportsScroll = widget.terminal.mouseMode.reportScroll;
    super.initState();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalUpdated);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TerminalScrollGestureHandler oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalUpdated);
      widget.terminal.addListener(_onTerminalUpdated);
      isAltBuffer = widget.terminal.isUsingAltBuffer;
      reportsScroll = widget.terminal.mouseMode.reportScroll;
      _touchScrolls.clear();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _onTerminalUpdated() {
    final altBuffer = widget.terminal.isUsingAltBuffer;
    final scrollReports = widget.terminal.mouseMode.reportScroll;
    if (isAltBuffer != altBuffer || reportsScroll != scrollReports) {
      isAltBuffer = altBuffer;
      reportsScroll = scrollReports;
      if (!altBuffer && !scrollReports) {
        // The Listener disappears when forwarding becomes inactive, so it
        // would not receive the matching pointer-up event.
        _touchScrolls.clear();
      }
      setState(() {});
    }
  }

  /// Send a single scroll event to the terminal. If [simulateScroll] is true,
  /// then if the application doesn't recognize mouse wheel events, this method
  /// will simulate scroll events by sending up/down arrow keys.
  void _sendScrollEvent(bool up) {
    final position = widget.getCellOffset(lastPointerPosition);

    final handled = widget.terminal.mouseInput(
      up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
      TerminalMouseButtonState.down,
      position,
    );

    // Arrow-key simulation only makes sense where there is no scrollback to
    // scroll, i.e. in the alternate buffer.
    if (!handled && widget.simulateScroll && isAltBuffer) {
      widget.terminal.keyInput(
        up ? TerminalKey.arrowUp : TerminalKey.arrowDown,
      );
    }
  }

  void _onScroll(double offset) {
    final currentLineOffset = offset ~/ widget.getLineHeight();

    final delta = currentLineOffset - lastLineOffset;

    for (var i = 0; i < delta.abs(); i++) {
      _sendScrollEvent(delta < 0);
    }

    lastLineOffset = currentLineOffset;
  }

  void _onPointerDown(PointerDownEvent event) {
    lastPointerPosition = event.position;
    if (!_touchDevices.contains(event.kind)) return;

    _touchScrolls[event.pointer] = _TouchScrollTracker(event.position);
    if (_touchScrolls.length > 1) {
      // A multi-touch gesture belongs to pinch zoom or another higher-level
      // action. Keep every participating pointer suppressed until it ends so
      // lifting one finger does not unexpectedly start terminal scrolling.
      for (final tracker in _touchScrolls.values) {
        tracker.suppressed = true;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final tracker = _touchScrolls[event.pointer];
    if (tracker == null) return;

    final delta = event.position - tracker.lastPosition;
    tracker.lastPosition = event.position;
    lastPointerPosition = event.position;
    if (tracker.suppressed || _touchScrolls.length != 1) return;

    if (!tracker.isVerticalScroll) {
      final total = event.position - tracker.origin;
      if (total.distance < kTouchSlop || total.dy.abs() <= total.dx.abs()) {
        return;
      }
      tracker.isVerticalScroll = true;
      tracker.pendingDy = total.dy;
    } else {
      tracker.pendingDy += delta.dy;
    }

    _drainTouchScroll(tracker);
  }

  void _drainTouchScroll(_TouchScrollTracker tracker) {
    final lineHeight = widget.getLineHeight();
    if (lineHeight <= 0) return;

    final lines = (tracker.pendingDy.abs() / lineHeight).floor();
    if (lines == 0) return;
    final up = tracker.pendingDy > 0;
    for (var i = 0; i < lines; i++) {
      _sendScrollEvent(up);
    }
    tracker.pendingDy -= (up ? 1 : -1) * lines * lineHeight;
  }

  void _onPointerEnd(PointerEvent event) {
    _touchScrolls.remove(event.pointer);
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) {
      return widget.child;
    }

    final scrollBehavior = ScrollConfiguration.of(context);
    return Listener(
      onPointerSignal: (event) {
        lastPointerPosition = event.position;
      },
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: ScrollConfiguration(
        // Touch is handled by the passive Listener above so it cannot lose to
        // an ancestor's gesture recognizer. Wheel and trackpad scrolling keep
        // using Scrollable, including its platform-specific momentum.
        behavior: scrollBehavior.copyWith(
          dragDevices: scrollBehavior.dragDevices.difference(_touchDevices),
        ),
        child: InfiniteScrollView(
          onScroll: _onScroll,
          child: widget.child,
        ),
      ),
    );
  }
}

class _TouchScrollTracker {
  _TouchScrollTracker(this.origin) : lastPosition = origin;

  final Offset origin;
  Offset lastPosition;
  bool isVerticalScroll = false;
  bool suppressed = false;
  double pendingDy = 0;
}
