import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xterm/xterm.dart';

import '../../agent/agent_session_inspector.dart';
import 'terminal_gui_document.dart';
import 'terminal_interaction.dart';

/// Shared by both presentations of one session; never persisted or sent to AI.
class TerminalAutoReplyHistory {
  final _attempted = <String>{};

  bool claim(String key) {
    if (!_attempted.add(key)) return false;
    if (_attempted.length > 32) _attempted.remove(_attempted.first);
    return true;
  }
}

/// Only a quiet, recognizable input prompt can trigger an automatic request.
/// Output callbacks only reset a timer; screen projection happens after quiet.
class TerminalAutoReply {
  TerminalAutoReply(
    this.terminal, {
    required this.onReady,
    required this.canSuggest,
    this.title,
    TerminalAutoReplyHistory? history,
    this.quietDelay = const Duration(milliseconds: 1500),
  }) : history = history ?? TerminalAutoReplyHistory();

  final Terminal terminal;
  final Future<void> Function(bool Function() current) onReady;
  final bool Function() canSuggest;
  final String Function()? title;
  final TerminalAutoReplyHistory history;
  final Duration quietDelay;
  Timer? _timer;
  bool _enabled = false;
  bool _disposed = false;
  bool _inputPending = false;
  String? _inputKey;
  int _generation = 0;
  int _inputGeneration = 0;
  int _activation = 0;

  static final _working = RegExp(
    r'esc to (?:interrupt|cancel)|(?:thinking|working|generating|compacting)\s*[.…]|'
    r'[✻✶✳✽✢].*[.…]|(?:usage|rate) limit|reconnecting|connection (?:lost|error)',
    caseSensitive: false,
  );
  static final _emptyPrompt = RegExp(
    r'^\s*(?:[❯›>]\s*|›\s+Ask Codex to do anything\s*)$',
  );

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    _activation++;
    _generation++;
    _timer?.cancel();
    if (enabled) {
      terminal.addListener(_changed);
      _changed();
    } else {
      terminal.removeListener(_changed);
    }
  }

  void _changed() {
    if (!_enabled || _disposed) return;
    _generation++;
    _timer?.cancel();
    _timer = Timer(quietDelay, _settled);
  }

  /// Called for local edits, before slow network echo reaches the terminal.
  void userInput() {
    if (!_enabled || _disposed) return;
    // Capture once per typing burst, never once per keystroke. A quick Agent
    // response after Enter is a new context and must still receive suggestions.
    if (!_inputPending) _inputKey = _waitingKey();
    _inputPending = true;
    _inputGeneration++;
    _changed();
  }

  void dismiss() => userInput();

  String? _waitingKey() {
    if (terminal.viewWidth * terminal.viewHeight > 200000) return null;
    final screen = TerminalGuiDocument.capture(
      terminal,
      maxLines: terminal.viewHeight.clamp(1, 200),
      maxCharacters: 12000,
    ).text;
    final prompt = TerminalInteraction.capture(
      terminal,
      title: title?.call() ?? '',
    );
    // A queued Codex question can coexist with a working spinner. Opening it
    // still requires an explicit click; this scheduler never sends Shift+Left.
    if (prompt != null) {
      if (prompt.editing && prompt.inputText.trim().isNotEmpty) return null;
      return 'question:${prompt.identity}';
    }
    final inspection = AgentSessionInspector.inspect(
      screen,
      title: title?.call() ?? '',
      liveSession: true,
    );
    if (!inspection.isConfirmedAgent ||
        AgentSessionInspector.hasShellPrompt(screen) ||
        _working.hasMatch(screen)) {
      return null;
    }
    final rows = screen
        .split('\n')
        .where((row) => row.trim().isNotEmpty)
        .toList();
    // CLI footers may follow the composer. Never infer readiness from silence
    // alone, and never complete a user's partially typed command.
    final tail = rows.skip(rows.length > 6 ? rows.length - 6 : 0);
    if (!tail.any(_emptyPrompt.hasMatch) || rows.length < 3) return null;
    return 'conversation:${sha256.convert(utf8.encode(screen))}';
  }

  void _settled() {
    _timer = null;
    if (!_enabled || _disposed) return;
    final key = _waitingKey();
    final inputPending = _inputPending;
    _inputPending = false;
    if (key == null) return;
    if (inputPending && key == _inputKey) {
      history.claim(key);
      return;
    }
    if (!canSuggest() || !history.claim(key)) return;
    final generation = _generation;
    final inputGeneration = _inputGeneration;
    final activation = _activation;
    bool current() =>
        !_disposed &&
        _enabled &&
        activation == _activation &&
        inputGeneration == _inputGeneration &&
        (generation == _generation || _waitingKey() == key);
    unawaited(onReady(current));
  }

  void dispose() {
    setEnabled(false);
    _disposed = true;
    _generation++;
    _timer?.cancel();
  }
}
