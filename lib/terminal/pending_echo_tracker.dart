import 'package:clock/clock.dart';
import 'package:xterm/xterm.dart';

import 'terminal_cell_width.dart';

/// [PendingEchoTracker]가 읽는 터미널 화면 상태. 읽기 전용이다.
abstract interface class PendingEchoScreen {
  /// 커서가 있는 줄. 줄 객체의 동일성으로 "같은 줄에 머무는지"를 판단한다
  /// (스크롤·화면 지우기·리사이즈는 다른 줄 객체를 만든다).
  BufferLine get cursorLine;
  int get cursorX;
  int get viewWidth;
  bool get usesAltBuffer;
  bool get cursorVisible;
}

/// xterm [Terminal]을 [PendingEchoScreen]으로 노출한다.
class TerminalPendingEchoScreen implements PendingEchoScreen {
  const TerminalPendingEchoScreen(this.terminal);

  final Terminal terminal;

  @override
  BufferLine get cursorLine => terminal.buffer.currentLine;
  @override
  int get cursorX => terminal.buffer.cursorX;
  @override
  int get viewWidth => terminal.viewWidth;
  @override
  bool get usesAltBuffer => terminal.isUsingAltBuffer;
  @override
  bool get cursorVisible => terminal.cursorVisibleMode;
}

/// 원격으로 보냈지만 아직 화면에 에코되지 않은 입력을 추적한다(표시 전용).
///
/// 지연이 큰 연결에서 확정된 한글 음절은 왕복 시간만큼 화면에 나타나지 않는다.
/// 그동안 다음 음절의 조합 오버레이가 원격 커서(= 아직 비어 있는 칸)에 그려지면
/// 에코가 그 아래로 도착하며 글자가 겹치거나 튄다. 이 모델은 "어디에 무엇이
/// 나타날 것인지"를 기억해 뷰가 대기 텍스트를 그 자리에 미리 보여 주고, 조합
/// 오버레이를 그 뒤에 그리게 한다.
///
/// 안전 규칙:
/// - 터미널 버퍼를 바꾸거나 바이트를 보내지 않는다. 뷰가 보낸 입력을
///   [recordSent]/[recordBackspace]/[recordUntrackedSend]로 알려 줄 뿐이다.
/// - 예측이 틀릴 기미(다른 줄로 이동, 커서가 예측 범위를 벗어남, 예측 칸에
///   예상 밖 글자, 대체 화면, 리사이즈, 시간 초과)가 보이면 즉시 전부 버린다.
///   버려진 뒤에는 기존처럼 원격 커서 위치에만 조합을 그린다.
/// - 예측 칸부터 줄 끝까지가 모두 비어 있을 때만 예측한다. 오른쪽에 글자가
///   있으면(줄 중간 삽입, zsh 자동 제안, 오른쪽 프롬프트) 예측하지 않는다.
///   오른쪽 프롬프트를 쓰는 셸은 일부러 미리 보기 없이 커서를 따라가는 조합
///   오버레이만 쓴다(docs/terminal-hangul-pending-echo.md).
/// - 다음 글자가 들어갈 자리가 없으면(오른쪽 글자, 줄 끝) 대기 텍스트를 버리고
///   원격 커서에 조합만 그린다. 거절한 글자가 차지할 칸에 대기 텍스트와 조합이
///   겹쳐 그려지지 않게 한다.
class PendingEchoTracker {
  PendingEchoTracker({
    DateTime Function()? now,
    this.timeout = const Duration(milliseconds: 1500),
  }) : _clock = now ?? (() => clock.now());

  /// 이 시간 동안 진전(새 입력 또는 에코 확인)이 없으면 대기 텍스트를 버린다.
  /// 에코를 끈 프롬프트(비밀번호)나 에코를 다른 곳에 그리는 앱에서 예측이
  /// 남아 있지 않게 한다.
  final Duration timeout;
  final DateTime Function() _clock;

  BufferLine? _line;
  int _col = 0;
  int _viewWidth = 0;
  final List<int> _pending = [];
  // 이번 입력 묶음에서 에코가 확인된 글자(열, 문자). 확인된 글자를 백스페이스로
  // 되돌릴 때 예측 시작 위치를 되돌리는 데 쓴다.
  final List<(int, int)> _confirmed = [];
  // 백스페이스로 취소했지만 에코가 늦게 도착할 수 있는 글자(열 → 문자).
  // Windows IME의 "백스페이스 + 새 음절" 재전송에서 옛 음절이 잠깐 보여도
  // 예상 밖 글자로 오인하지 않는다.
  final Map<int, int> _retracted = {};
  DateTime? _lastProgressAt;
  // 추적하지 않는 입력(Enter·방향키·Ctrl 조합 등)을 보낸 뒤 원격 응답(화면
  // 변화)을 아직 보지 못했다. 그 사이에 새 예측을 시작하면 응답이 그릴 자리를
  // 짐작할 수 없으므로 시작하지 않는다.
  DateTime? _blockedSince;

  /// 에코를 기다리는 텍스트가 있는지.
  bool get hasPending => _pending.isNotEmpty;

  /// 에코를 기다리는 텍스트.
  String get pendingText => String.fromCharCodes(_pending);

  /// 대기 텍스트가 시작되는 열. [hasPending]일 때만 의미가 있다.
  int get anchorCol => _col;

  /// 대기 텍스트가 시작되는 줄.
  BufferLine? get anchorLine => _line;

  /// 대기 텍스트가 차지하는 셀 수.
  int get pendingCells => terminalRunesCells(_pending);

  /// 다음 시간 초과 판정까지 남은 시간. 판정할 대상이 없으면 null.
  Duration? get timeUntilExpiry {
    final progress = _pending.isEmpty ? null : _lastProgressAt;
    final starts = [?progress, ?_blockedSince];
    if (starts.isEmpty) return null;
    starts.sort();
    final left = starts.first.add(timeout).difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// 대기 텍스트를 화면에 보여 줄지. 한글 중심 정책이다:
  /// - 대체 화면(전체 화면 TUI)이나 커서를 숨긴 앱에서는 보이지 않는다.
  /// - ASCII만 기다리는 중이면 기존 터미널처럼 예측하지 않는다. 비ASCII가
  ///   섞였거나 바로 뒤에 조합 중인 글자가 있을 때만 보인다(그래야 조합
  ///   오버레이가 대기 텍스트 뒤 올바른 칸에 놓인다).
  bool shouldDisplay(PendingEchoScreen screen, {required bool composing}) {
    if (_pending.isEmpty || screen.usesAltBuffer || !screen.cursorVisible) {
      return false;
    }
    if (!identical(screen.cursorLine, _line)) return false;
    return composing || _pending.any((rune) => rune > 0x7e);
  }

  /// 원격으로 보낸 텍스트를 기록한다. 출력 가능한 문자는 대기 텍스트에 붙고,
  /// DEL/BS는 백스페이스로, 그 밖의 제어 문자는 추적 불가 입력으로 처리한다.
  void recordSent(String data, PendingEchoScreen screen) {
    for (final rune in data.runes) {
      if (rune == 0x7f || rune == 0x08) {
        recordBackspace();
        continue;
      }
      final width = terminalRuneCells(rune);
      if (width == 0) {
        // 제어 문자(Enter·ESC 시퀀스)와 결합 문자는 커서 위치를 예측할 수 없다.
        recordUntrackedSend();
        continue;
      }
      _append(rune, width, screen);
    }
  }

  /// 원격으로 백스페이스 하나를 보냈다.
  void recordBackspace() {
    if (_isBlocked) {
      _block();
      return;
    }
    if (_pending.isNotEmpty) {
      final rune = _pending.removeLast();
      _retracted[_col + terminalRunesCells(_pending)] = rune;
      _lastProgressAt = _clock();
      return;
    }
    if (_line != null && _confirmed.isNotEmpty) {
      final (col, rune) = _confirmed.removeLast();
      _col = col;
      _retracted[col] = rune;
      _lastProgressAt = _clock();
      return;
    }
    // 이번 묶음 이전의 글자를 지웠다. 그 폭을 모르므로 예측을 멈춘다.
    _block();
  }

  /// 커서를 옮기거나 줄 맥락을 바꾸는 입력(Enter·방향키·Ctrl/Alt 조합·붙여넣기
  /// 등)을 보냈다. 원격 응답이 화면에 반영될 때까지 새 예측을 시작하지 않는다.
  void recordUntrackedSend() => _block();

  /// 화면 상태를 기다리지 않고 모든 예측을 버린다(세션 전환·포커스 해제 등).
  void reset() {
    _clearRun();
    _blockedSince = null;
  }

  /// 터미널 출력이 반영된 뒤 호출한다. 에코된 앞부분을 확인해 지우고, 예측이
  /// 깨졌으면 버린다. 표시 상태가 바뀌었을 수 있으면 true.
  bool onScreenChanged(PendingEchoScreen screen) {
    _blockedSince = null;
    final line = _line;
    if (line == null) return false;
    if (screen.usesAltBuffer ||
        screen.viewWidth != _viewWidth ||
        !identical(screen.cursorLine, line)) {
      _clearRun();
      return true;
    }
    var changed = false;
    while (_pending.isNotEmpty) {
      final rune = _pending.first;
      final width = terminalRuneCells(rune);
      if (_col >= line.length ||
          line.getCodePoint(_col) != rune ||
          line.getWidth(_col) != width) {
        break;
      }
      _pending.removeAt(0);
      _confirmed.add((_col, rune));
      _retracted.remove(_col);
      _col += width;
      _lastProgressAt = _clock();
      changed = true;
    }
    final cursor = screen.cursorX;
    if (cursor < _col ||
        cursor > _expectedCursorLimit() ||
        _hasForeignGlyph(line)) {
      _clearRun();
      return true;
    }
    // 에코 전에 대기 텍스트 오른쪽에 글자(zsh 자동 제안, 오른쪽 프롬프트 다시
    // 그리기)가 나타나면 미리 보기를 버리고 원격 커서에 조합을 그린다.
    // 확인할 대기 텍스트가 있을 때만 줄을 본다.
    if (_pending.isNotEmpty &&
        !_blankFrom(
          line,
          _col + terminalRunesCells(_pending),
          screen.viewWidth,
        )) {
      _clearRun();
      return true;
    }
    if (_confirmed.length > 64) {
      _confirmed.removeRange(0, _confirmed.length - 64);
    }
    return changed;
  }

  /// 시간 초과를 판정한다. 대기 텍스트를 버렸으면 true.
  bool expire() {
    final now = _clock();
    final blocked = _blockedSince;
    if (blocked != null && now.difference(blocked) >= timeout) {
      _blockedSince = null;
    }
    final progress = _lastProgressAt;
    if (_pending.isEmpty ||
        progress == null ||
        now.difference(progress) < timeout) {
      return false;
    }
    _clearRun();
    return true;
  }

  bool get _isBlocked => _blockedSince != null;

  void _block() {
    _clearRun();
    _blockedSince = _clock();
  }

  void _clearRun() {
    _line = null;
    _col = 0;
    _pending.clear();
    _confirmed.clear();
    _retracted.clear();
    _lastProgressAt = null;
  }

  void _append(int rune, int width, PendingEchoScreen screen) {
    if (_isBlocked) {
      // 응답을 기다리는 동안 친 글자도 위치를 모르므로 응답 뒤로 미룬다.
      _block();
      return;
    }
    final line = screen.cursorLine;
    if (_line == null || !identical(_line, line)) {
      _startRun(screen);
    } else if (_pending.isEmpty &&
        (screen.cursorX < _col || screen.cursorX > _expectedCursorLimit())) {
      // 대기 텍스트가 모두 확인된 뒤 커서가 다른 곳에 있다면 새로 시작한다.
      // (확인된 글자를 백스페이스로 되돌린 직후에는 그 에코 끝까지 허용한다.)
      _startRun(screen);
    }
    final col = _col + terminalRunesCells(_pending);
    // 줄 상태는 글자를 붙일 때만(글자 하나에 한 번) 본다. 화면이 바뀔 때마다
    // 줄을 다시 훑지 않는다. 에코와 함께 오른쪽에 나타난 글자(zsh 자동 제안
    // 등)도 다음 글자를 붙일 때 이 검사에 걸린다.
    final viewWidth = screen.viewWidth;
    if (col + width > viewWidth || !_blankFrom(line, col, viewWidth)) {
      // 오른쪽 글자나 줄 끝에 닿았다. 대기 텍스트를 두면 이 글자의 에코 자리에
      // 조합이 겹쳐 그려지므로 버리고 원격 커서 기준으로 돌아간다.
      _block();
      return;
    }
    _pending.add(rune);
    _lastProgressAt = _clock();
  }

  void _startRun(PendingEchoScreen screen) {
    _clearRun();
    _line = screen.cursorLine;
    _col = screen.cursorX;
    _viewWidth = screen.viewWidth;
  }

  static bool _isBlankGlyph(int glyph) => glyph == 0 || glyph == 0x20;

  /// [from]부터 줄 끝까지 모든 칸이 비어 있는지.
  bool _blankFrom(BufferLine line, int from, int viewWidth) {
    final end = viewWidth < line.length ? viewWidth : line.length;
    return _cellsFree(line, from, end - from);
  }

  /// [x] 칸에 글자가 있는지. 공백·빈 칸과 이번 묶음에서 취소된 글자의 늦은
  /// 에코는 빈 칸이다. 2칸 글자의 둘째 칸은 코드포인트가 0이지만 앞 칸의
  /// 글자가 차지하므로 글자가 있는 칸이다.
  bool _occupied(BufferLine line, int x) {
    if (x >= line.length) return false;
    final glyph = line.getCodePoint(x);
    if (!_isBlankGlyph(glyph)) return _retracted[x] != glyph;
    if (glyph != 0 || x == 0 || line.getWidth(x - 1) != 2) return false;
    final lead = line.getCodePoint(x - 1);
    return !_isBlankGlyph(lead) && _retracted[x - 1] != lead;
  }

  /// [col]부터 [width]칸이 모두 비어 있는지([_occupied] 기준).
  bool _cellsFree(BufferLine line, int col, int width) {
    for (var x = col; x < col + width; x++) {
      if (_occupied(line, x)) return false;
    }
    return true;
  }

  /// 예측 칸에 대기 문자도, 취소된 문자의 늦은 에코도 아닌 글자가 나타났는지.
  bool _hasForeignGlyph(BufferLine line) {
    var col = _col;
    for (final rune in _pending) {
      final width = terminalRuneCells(rune);
      if (col < line.length) {
        final glyph = line.getCodePoint(col);
        if (glyph != rune && !_cellsFree(line, col, width)) return true;
      }
      col += width;
    }
    return false;
  }

  /// 커서가 있어도 되는 오른쪽 한계. 대기 텍스트 끝까지, 그리고 취소된 글자의
  /// 늦은 에코가 커서를 잠시 더 밀 수 있는 곳까지다.
  int _expectedCursorLimit() {
    var limit = _col + terminalRunesCells(_pending);
    for (final entry in _retracted.entries) {
      final end = entry.key + terminalRuneCells(entry.value);
      if (end > limit) limit = end;
    }
    return limit;
  }
}
