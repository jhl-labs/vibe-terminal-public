import 'dart:async';

import 'package:flutter/widgets.dart';

/// Vibe Terminal patch: keeps a drag selection usable when the pointer leaves
/// the viewport or the user scrolls the wheel mid-drag.
///
/// While a drag is active ([begin] .. [end]) this helper
///
/// * scrolls the terminal towards the pointer whenever [update] reports a
///   position above or below the viewport, at a speed that grows with the
///   overshoot, and
/// * calls [onScrolled] after every scroll offset change (auto-scroll or
///   wheel), so the owner can re-apply the selection against the cells that
///   are now under the pointer.
///
/// The owner must keep its selection anchor as a buffer cell, not as a pixel
/// offset: pixels map to different cells once the offset changes.
class SelectionAutoScroller {
  SelectionAutoScroller({
    required this.getScrollController,
    required this.onScrolled,
    this.interval = const Duration(milliseconds: 50),
    this.maxLinesPerTick = 4,
  });

  final ScrollController? Function() getScrollController;

  /// Invoked whenever the scroll offset changes during an active drag.
  final VoidCallback onScrolled;

  final Duration interval;

  /// Upper bound of lines scrolled per [interval] at large overshoots.
  final int maxLinesPerTick;

  Timer? _timer;
  bool _ticking = false;
  ScrollController? _listened;
  double _overshoot = 0;
  double _lineHeight = 0;

  bool get isActive => _listened != null;

  bool get isAutoScrolling => _timer != null;

  /// Starts observing scroll offset changes for the current drag.
  void begin() {
    if (_listened != null) return;
    final controller = getScrollController();
    if (controller == null) return;
    controller.addListener(onScrolled);
    _listened = controller;
  }

  /// Reports the pointer's vertical position in the viewport's local space.
  /// Positions outside `0..viewportHeight` start (or keep) auto-scrolling.
  void update({
    required double localY,
    required double viewportHeight,
    required double lineHeight,
  }) {
    _lineHeight = lineHeight;
    if (localY < 0) {
      _overshoot = localY;
    } else if (localY > viewportHeight) {
      _overshoot = localY - viewportHeight;
    } else {
      _overshoot = 0;
    }
    if (_overshoot == 0 || _lineHeight <= 0) {
      _stopTimer();
      return;
    }
    if (_timer != null) return;
    // Assign the timer before the first tick: [onScrolled] may synchronously
    // call [update] again, which must see an active timer instead of starting
    // another one.
    _timer = Timer.periodic(interval, (_) => _tick());
    _tick();
  }

  /// Stops auto-scrolling and scroll observation. Safe to call repeatedly.
  void end() {
    _stopTimer();
    _listened?.removeListener(onScrolled);
    _listened = null;
    _overshoot = 0;
  }

  void dispose() => end();

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (_ticking) return;
    final controller = getScrollController();
    if (controller == null || !controller.hasClients || _overshoot == 0) {
      _stopTimer();
      return;
    }
    final position = controller.position;
    final lines = (1 + _overshoot.abs() ~/ _lineHeight).clamp(
      1,
      maxLinesPerTick,
    );
    final delta = _overshoot.sign * lines * _lineHeight;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    // jumpTo notifies the controller, which re-applies the selection through
    // [onScrolled].
    _ticking = true;
    try {
      position.jumpTo(target);
    } finally {
      _ticking = false;
    }
  }
}
