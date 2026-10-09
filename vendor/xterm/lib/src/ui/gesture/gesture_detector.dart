import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class TerminalGestureDetector extends StatefulWidget {
  const TerminalGestureDetector({
    super.key,
    this.child,
    this.onSingleTapUp,
    this.onTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressUp,
    this.onLongPressCancel,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.onDoubleTapDown,
    this.onTripleTapDown,
  });

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onDoubleTapDown;

  /// Vibe Terminal patch: third tap of a quick tap sequence.
  final GestureTapDownCallback? onTripleTapDown;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final GestureLongPressStartCallback? onLongPressStart;

  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  final GestureLongPressUpCallback? onLongPressUp;

  final GestureLongPressCancelCallback? onLongPressCancel;

  final GestureDragStartCallback? onDragStart;

  final GestureDragUpdateCallback? onDragUpdate;

  final GestureDragEndCallback? onDragEnd;

  final GestureDragCancelCallback? onDragCancel;

  @override
  State<TerminalGestureDetector> createState() =>
      _TerminalGestureDetectorState();
}

class _TerminalGestureDetectorState extends State<TerminalGestureDetector> {
  Timer? _doubleTapTimer;

  Offset? _lastTapOffset;

  // True if a second tap down of a double tap is detected. Used to discard
  // subsequent tap up / tap hold of the same tap.
  bool _isDoubleTap = false;

  // Taps in the current quick sequence (Vibe Terminal patch: triple tap).
  int _tapCount = 0;

  // The down handler is force-run on success of a single tap and optimistically
  // run before a long press success.
  void _handleTapDown(TapDownDetails details) {
    widget.onTapDown?.call(details);

    if (_doubleTapTimer != null &&
        _isWithinDoubleTapTolerance(details.globalPosition)) {
      // If there was already a previous tap, the second down hold/tap is a
      // double tap down; the third is a triple tap down.
      _tapCount++;
      if (_tapCount >= 3) {
        widget.onTripleTapDown?.call(details);
        _tapCount = 0;
      } else {
        widget.onDoubleTapDown?.call(details);
      }

      _doubleTapTimer!.cancel();
      _doubleTapTimer = null;
      _isDoubleTap = true;
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (!_isDoubleTap) {
      widget.onSingleTapUp?.call(details);
      _tapCount = 1;
    }
    _isDoubleTap = false;
    if (_tapCount == 0) {
      _doubleTapTimeout();
      return;
    }
    // Keep the sequence open so the next tap can extend it.
    _lastTapOffset = details.globalPosition;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(kDoubleTapTimeout, _doubleTapTimeout);
  }

  void _doubleTapTimeout() {
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    _lastTapOffset = null;
    _tapCount = 0;
  }

  bool _isWithinDoubleTapTolerance(Offset secondTapOffset) {
    if (_lastTapOffset == null) {
      return false;
    }

    final Offset difference = secondTapOffset - _lastTapOffset!;
    return difference.distance <= kDoubleTapSlop;
  }

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};

    gestures[TapGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
      () => TapGestureRecognizer(debugOwner: this),
      (TapGestureRecognizer instance) {
        instance
          ..onTapDown = _handleTapDown
          ..onTapUp = _handleTapUp
          ..onSecondaryTapDown = widget.onSecondaryTapDown
          ..onSecondaryTapUp = widget.onSecondaryTapUp
          ..onTertiaryTapDown = widget.onTertiaryTapDown
          ..onTertiaryTapUp = widget.onTertiaryTapUp;
      },
    );

    gestures[LongPressGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
      () => LongPressGestureRecognizer(
        debugOwner: this,
        supportedDevices: {
          PointerDeviceKind.touch,
          // PointerDeviceKind.mouse, // for debugging purposes only
        },
      ),
      (LongPressGestureRecognizer instance) {
        instance
          ..onLongPressStart = widget.onLongPressStart
          ..onLongPressMoveUpdate = widget.onLongPressMoveUpdate
          ..onLongPressUp = widget.onLongPressUp
          ..onLongPressCancel = widget.onLongPressCancel;
      },
    );

    gestures[PanGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
      () => PanGestureRecognizer(
        debugOwner: this,
        supportedDevices: <PointerDeviceKind>{PointerDeviceKind.mouse},
      ),
      (PanGestureRecognizer instance) {
        instance
          ..dragStartBehavior = DragStartBehavior.down
          ..onStart = widget.onDragStart
          ..onUpdate = widget.onDragUpdate
          ..onEnd = widget.onDragEnd
          ..onCancel = widget.onDragCancel;
      },
    );

    return RawGestureDetector(
      gestures: gestures,
      excludeFromSemantics: true,
      child: widget.child,
    );
  }
}
