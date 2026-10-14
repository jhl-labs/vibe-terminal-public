import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'terminal_gui_document.dart';

class TerminalGuiController extends ChangeNotifier {
  TerminalGuiController(this.terminal)
    : document = TerminalGuiDocument.capture(terminal) {
    terminal.addListener(_changed);
  }

  final Terminal terminal;
  TerminalGuiDocument document;
  bool paused = false;
  bool pending = false;
  bool _enabled = true;
  Timer? _timer;

  void _changed() {
    if (!_enabled) {
      pending = true;
      return;
    }
    if (paused) {
      if (!pending) {
        pending = true;
        notifyListeners();
      }
      return;
    }
    _timer ??= Timer(const Duration(milliseconds: 180), refresh);
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _timer?.cancel();
      _timer = null;
    } else if (!paused) {
      refresh();
    }
  }

  void pause() {
    if (paused) return;
    _timer?.cancel();
    _timer = null;
    paused = true;
    notifyListeners();
  }

  void resume() {
    paused = false;
    refresh();
  }

  void refresh() {
    _timer?.cancel();
    _timer = null;
    final next = TerminalGuiDocument.capture(terminal);
    final changed = document != next || pending;
    document = next;
    pending = false;
    if (changed || !paused) notifyListeners();
  }

  @override
  void dispose() {
    terminal.removeListener(_changed);
    _timer?.cancel();
    super.dispose();
  }
}
