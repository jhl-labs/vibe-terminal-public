import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'terminal_interaction.dart';

/// Human actions use the existing terminal transport and require live redraws.
class TerminalInteractionController extends ChangeNotifier {
  TerminalInteractionController(this.terminal, {this.title}) {
    terminal.addListener(_changed);
    refresh();
  }
  final Terminal terminal;
  final String Function()? title;
  TerminalInteraction? prompt;
  bool busy = false;
  String? error;
  bool _enabled = true;
  bool _disposed = false;
  int _generation = 0;
  int _updates = 0;
  Timer? _timer;
  Completer<void>? _redraw;

  TerminalInteraction? _capture() => TerminalInteraction.capture(
    terminal,
    title: title?.call() ?? '',
    previous: prompt,
  );
  void _changed() {
    _updates++;
    _redraw?.complete();
    _redraw = null;
    if (_enabled) _timer ??= Timer(const Duration(milliseconds: 80), refresh);
  }

  void refresh() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    final next = _enabled ? _capture() : null;
    if (prompt?.revision != next?.revision) {
      prompt = next;
      error = null;
      notifyListeners();
    }
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _generation++;
    _redraw?.complete();
    _redraw = null;
    refresh();
  }

  bool _valid(TerminalInteraction expected, int generation) =>
      !_disposed &&
      _enabled &&
      generation == _generation &&
      _capture()?.identity == expected.identity;

  Future<void> _waitFor(
    bool Function(TerminalInteraction?) condition,
    int generation,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!_disposed && _enabled && generation == _generation) {
      if (condition(_capture())) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      _redraw ??= Completer<void>();
      var expired = false;
      await _redraw!.future.timeout(
        remaining,
        onTimeout: () {
          expired = true;
        },
      );
      if (expired) break;
    }
    throw StateError('화면이 바뀌었거나 응답을 확인하지 못했습니다. 현재 화면에서 다시 선택해 주세요.');
  }

  Future<bool> _run(
    TerminalInteraction expected,
    Future<void> Function(int generation) action,
  ) async {
    if (busy ||
        !_enabled ||
        _disposed ||
        !identical(prompt, expected) ||
        _capture()?.revision != expected.revision) {
      return false;
    }
    busy = true;
    error = null;
    final generation = ++_generation;
    notifyListeners();
    try {
      await action(generation);
      return true;
    } on StateError catch (e) {
      error = e.message.toString();
      return false;
    } finally {
      busy = false;
      if (!_disposed) {
        refresh();
        notifyListeners();
      }
    }
  }

  Future<void> _keyAndRedraw(
    TerminalKey key,
    int generation, {
    bool shift = false,
    bool ctrl = false,
  }) async {
    final updates = _updates;
    final encoded = terminal.keyInput(key, shift: shift, ctrl: ctrl);
    if (!encoded) {
      // xterm's default keytab omits Shift+Left outside the alternate buffer.
      // Codex's inline question opener uses the same standard CSI sequence.
      if (key == TerminalKey.arrowLeft && shift && !ctrl) {
        terminal.textInput('\x1b[1;2D');
      } else {
        throw StateError('이 키를 전송할 수 없습니다. 터미널 모드에서 입력해 주세요.');
      }
    }
    await _waitFor((_) => _updates > updates, generation);
  }

  Future<bool> choose(
    TerminalInteraction expected,
    int index,
  ) => _run(expected, (generation) async {
    if (index < 0 ||
        index >= expected.options.length ||
        expected.editing && expected.agent != 'claude') {
      throw StateError('현재 입력란을 먼저 완료해 주세요.');
    }
    // OpenCode explicitly binds digits to pick/toggle, independent of ANSI color.
    if (expected.agent == 'opencode' && !expected.horizontal && index < 9) {
      final updates = _updates;
      terminal.textInput('${index + 1}');
      await _waitFor((_) => _updates > updates, generation);
      return;
    }
    var live = _capture();
    if (live?.selected == -1) {
      throw StateError('선택 위치를 확인할 수 없습니다. 아래 방향키로 이동해 주세요.');
    }
    var steps = 0;
    while (live != null && live.selected != index) {
      if (!_valid(expected, generation) ||
          live.selected < 0 ||
          steps++ >= expected.options.length) {
        throw StateError('질문이 변경되었습니다. 다시 선택해 주세요.');
      }
      final previous = live.selected;
      final forwards = index > previous;
      terminal.keyInput(
        expected.horizontal
            ? (forwards ? TerminalKey.arrowRight : TerminalKey.arrowLeft)
            : (forwards ? TerminalKey.arrowDown : TerminalKey.arrowUp),
      );
      await _waitFor(
        (p) => p?.identity != expected.identity || p?.selected != previous,
        generation,
      );
      live = _capture();
    }
    if (!_valid(expected, generation)) {
      throw StateError('질문이 변경되었습니다. 다시 선택해 주세요.');
    }
    // Claude's "Type something" is already an editor when it gains focus.
    if (expected.agent == 'claude' && expected.options[index].custom) return;
    if (expected.multiple &&
        expected.agent == 'claude' &&
        !const {'Submit', 'Next'}.contains(expected.options[index].label)) {
      final updates = _updates;
      terminal.textInput(' ');
      await _waitFor((_) => _updates > updates, generation);
    } else {
      await _keyAndRedraw(TerminalKey.enter, generation);
    }
  });

  Future<bool> key(
    TerminalInteraction expected,
    TerminalKey key, {
    bool shift = false,
    bool ctrl = false,
  }) => _run(
    expected,
    (generation) => _keyAndRedraw(key, generation, shift: shift, ctrl: ctrl),
  );

  Future<bool> sendText(TerminalInteraction expected, String text) => _run(
    expected,
    (generation) async {
      if (!expected.editing ||
          text.trim().isEmpty ||
          RegExp(r'[\x00-\x08\x0b-\x1f\x7f]').hasMatch(text)) {
        throw StateError('현재 질문의 직접 입력란을 먼저 열어 주세요.');
      }
      // Without bracketed paste a newline can submit halfway through a message.
      if (text.contains('\n') && !terminal.bracketedPasteMode) {
        throw StateError('이 입력란은 한 줄 답변을 지원합니다. 줄바꿈을 제거해 주세요.');
      }
      if (!_valid(expected, generation)) throw StateError('질문이 변경되었습니다.');
      final updates = _updates;
      terminal.paste(text);
      // A synchronous transport redraw may already have closed the question.
      if (!_valid(expected, generation)) {
        throw StateError('입력 중 질문이 변경되었습니다. 현재 화면을 확인해 주세요.');
      }
      if (expected.agent == 'claude' && expected.multiple) {
        // Typing checks the custom row. Enter here would uncheck it; the human
        // explicitly chooses Next/Submit after applying the text instead.
        await _waitFor((_) => _updates > updates, generation);
      } else {
        await _keyAndRedraw(TerminalKey.enter, generation);
      }
    },
  );

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    terminal.removeListener(_changed);
    _timer?.cancel();
    _redraw?.complete();
    _redraw = null;
    super.dispose();
  }
}
