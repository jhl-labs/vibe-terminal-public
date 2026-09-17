import 'dart:async';

/// Sends the first resize immediately and merges bursts, including their tail.
class TerminalResizeDispatcher {
  TerminalResizeDispatcher(this.send);
  final void Function(int, int) send;
  bool _disposed = false;
  Timer? _timer;
  (int, int)? _last, _pending;
  void reset({(int, int)? last}) {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _last = last;
  }

  void resize(int cols, int rows) {
    if (_disposed || cols <= 0 || rows <= 0) return;
    final size = (cols, rows);
    _pending = size;
    if (_timer == null) _flush();
  }

  void _flush() {
    _timer = null;
    final size = _pending;
    _pending = null;
    if (size == null || size == _last) return;
    _last = size;
    send(size.$1, size.$2);
    _timer = Timer(const Duration(milliseconds: 34), _flush);
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
