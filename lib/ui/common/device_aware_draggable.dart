import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Mouse movement starts a drag; touch/stylus holds first to preserve scrolling.
/// The pointer kind, rather than the app's platform or screen size, decides.
class DeviceAwareDraggable<T extends Object> extends Draggable<T> {
  const DeviceAwareDraggable({
    super.key,
    required super.data,
    required super.child,
    required super.feedback,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragUpdate,
    super.onDragEnd,
    super.onDragCompleted,
    super.onDraggableCanceled,
    this.onDragStartAt,
  }) : super(maxSimultaneousDrags: 1);

  final void Function(Offset position, bool longPress)? onDragStartAt;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    Drag? start(Offset position, bool longPress) {
      final drag = onStart(position);
      if (drag != null) {
        onDragStartAt?.call(position, longPress);
        if (longPress) HapticFeedback.selectionClick();
      }
      return drag;
    }

    return _DeviceAwareDragRecognizer(
      mouseStart: (position) => start(position, false),
      touchStart: (position) => start(position, true),
    );
  }
}

class _DeviceAwareDragRecognizer extends ImmediateMultiDragGestureRecognizer {
  _DeviceAwareDragRecognizer({
    required GestureMultiDragStartCallback mouseStart,
    required GestureMultiDragStartCallback touchStart,
  }) {
    onStart = mouseStart;
    _touch.onStart = touchStart;
  }

  final _touch = DelayedMultiDragGestureRecognizer();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      super.addAllowedPointer(event);
    } else {
      _touch.gestureSettings = gestureSettings;
      _touch.addPointer(event);
    }
  }

  @override
  void dispose() {
    _touch.dispose();
    super.dispose();
  }
}
