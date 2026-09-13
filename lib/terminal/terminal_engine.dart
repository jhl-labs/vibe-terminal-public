import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:xterm/xterm.dart';

import 'terminal_session_handle.dart';
import 'terminal_sideband.dart';

/// xterm [Terminal]을 SSH/로컬 PTY 세션 핸들에 연결하는 엔진.
///
/// - `handle.output` (UTF-8 bytes) → `terminal.write` (String)
/// - `terminal.onOutput` (String) → `handle.write` (UTF-8 bytes)
/// - `terminal.onResize` (w, h, pw, ph) → `handle.resize` (cols, rows)
class TerminalEngine {
  TerminalEngine({int maxLines = 5000})
    : terminal = Terminal(maxLines: maxLines);

  static const _clearSessionScreen = '\x1b[?1049l\x1b[2J\x1b[3J\x1b[H';

  final Terminal terminal;

  /// 서버 출력이 도착할 때마다 호출된다(busy/idle 활동 추적용).
  VoidCallback? onOutputActivity;

  /// 화면에 그리지 않는 OSC sideband 메시지를 수신한다.
  ValueChanged<TerminalSidebandMessage>? onSidebandMessage;

  /// 터미널에서 세션 핸들로 전송되는 입력.
  ValueChanged<String>? onInput;

  StreamSubscription<String>? _outputSub;
  TerminalSessionHandle? _handle;

  // 출력 코얼레싱 버퍼.
  //
  // 매 PTY/SSH 청크마다 `terminal.write`를 호출하면 write가 곧바로
  // `notifyListeners()`를 부른다(vendor xterm terminal.dart). 세션이 20개 넘게
  // 붙어 claude/codex가 동시에 화면을 재그리면, 이 notify 폭주가 메인
  // 아이솔레이트를 포화시켜 키 입력 이벤트 처리가 밀린다(빠른 타이핑 누락).
  //
  // 청크를 모아 한 프레임 간격으로 한 번에 write해 write/notify 횟수를
  // 프레임당 1회로 제한한다. 파서는 스트리밍이라
  // `write(a); write(b)` == `write(a + b)`이므로 화면 결과는 동일하고,
  // swarm은 버퍼를 온디맨드로 읽고(quiescence 안정 창은 초 단위) idle 판정은
  // 1500ms라 16ms 배칭은 영향이 없다.
  static const _outputCoalesceWindow = Duration(milliseconds: 16);
  final List<String> _pendingOutput = [];
  Timer? _outputFlushTimer;
  final TerminalSidebandDecoder _sidebandDecoder = TerminalSidebandDecoder();

  /// [handle]을 터미널에 연결한다. 출력·입력·리사이즈를 양방향 연결한다.
  /// [onClosed]는 출력 스트림이 종료(연결 끊김)되면 호출된다.
  void attach(TerminalSessionHandle handle, {VoidCallback? onClosed}) {
    // 재attach 방어: 기존 구독 정리.
    final isReattach = _handle != null;
    _outputSub?.cancel();
    // 이전 세션의 미flush 청크는 아래에서 화면을 지우므로 버린다.
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    _pendingOutput.clear();
    _sidebandDecoder.reset();
    _handle = handle;
    if (isReattach) {
      // SSH 자동 재연결처럼 새 PTY가 같은 TerminalEngine에 붙을 때, 이전
      // 커서 위치와 스크롤백이 남으면 새 로그인 출력이 과거 화면 위에 덮인다.
      terminal.write(_clearSessionScreen);
    }

    // 서버 → 터미널. SSH/PTY 청크는 UTF-8 문자 경계와 무관하게 나뉠 수 있으므로
    // 상태를 유지하는 스트림 디코더를 사용한다. 청크마다 utf8.decode를 호출하면
    // 경계에 걸친 한글·박스 문자·emoji가 대체 문자로 바뀌고, TUI가 계산한 셀 폭과
    // 로컬 버퍼의 셀 폭이 달라져 커서와 레이아웃이 무너질 수 있다.
    _outputSub = handle.output
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (data) {
            for (final message in _sidebandDecoder.add(data)) {
              onSidebandMessage?.call(message);
            }
            _pendingOutput.add(data);
            _outputFlushTimer ??= Timer(
              _outputCoalesceWindow,
              _flushPendingOutput,
            );
          },
          // 스트림 종료 전에 남은 출력을 먼저 반영한 뒤 종료를 알린다.
          onDone: () {
            _flushPendingOutput();
            onClosed?.call();
          },
        );

    // 터미널 입력 → 서버 (UTF-8 인코드). 단, xterm 4.0.0의 커서 위치 보고(CPR)
    // off-by-one을 1-based로 보정한다(아래 _correctCursorReport 참고).
    terminal.onOutput = (String data) {
      final corrected = _correctCursorReport(data);
      onInput?.call(corrected);
      handle.write(utf8.encode(corrected));
    };

    // 터미널 리사이즈 → 서버 (pixelWidth/pixelHeight 무시)
    terminal.onResize = (int w, int h, int pw, int ph) => handle.resize(w, h);
    handle.resize(terminal.viewWidth, terminal.viewHeight);
  }

  // CPR(Cursor Position Report) 응답: `ESC [ row ; col R`.
  static final _cprPattern = RegExp(r'\x1b\[(\d+);(\d+)R');

  /// xterm 4.0.0은 커서 위치 보고를 0-based로 내보낸다(`ESC[0;0R`). DSR-CPR
  /// 스펙은 1-based(`ESC[1;1R`)이며, codex 등 인라인 모드 TUI는 이 값으로
  /// 커서/레이아웃을 계산하므로 0-based면 응답 표시 후 멈출 수 있다.
  /// 서버로 보내기 직전에 행·열을 +1 보정한다.
  static String _correctCursorReport(String data) {
    if (!data.contains('R')) return data; // 대부분의 입력은 빠르게 통과.
    return data.replaceAllMapped(_cprPattern, (m) {
      final row = int.parse(m[1]!) + 1;
      final col = int.parse(m[2]!) + 1;
      return '\x1b[$row;${col}R';
    });
  }

  /// 모아 둔 출력 청크를 한 번에 터미널에 반영한다(코얼레싱 flush).
  void _flushPendingOutput() {
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    if (_pendingOutput.isEmpty) return;
    final data = _pendingOutput.join();
    _pendingOutput.clear();
    terminal.write(data);
    onOutputActivity?.call();
  }

  /// 스트림 구독을 취소하고 SSH 세션을 닫는다.
  void dispose() {
    _outputFlushTimer?.cancel();
    _outputSub?.cancel();
    _handle?.close();
  }

  /// AI 패널에 넘길 최근 터미널 텍스트.
  ///
  /// xterm 버퍼의 마지막 줄이 현재 프롬프트/에러 상태일 가능성이 가장 높으므로,
  /// 호출자는 이 문자열의 마지막 줄을 우선 컨텍스트로 취급한다.
  String recentPlainText({int maxLines = 500}) {
    // 복원 스냅샷이나 AI 관찰이 코얼레싱 창 안에 실행되더라도 방금 도착한
    // 출력까지 포함해야 한다. 출력 버퍼의 소유자인 엔진에서 먼저 flush해
    // 호출자가 배칭 구현을 알 필요가 없게 한다.
    //
    // 단, 위젯 build/layout/paint(persistentCallbacks) 도중에는 flush하면
    // terminal.write→notifyListeners가 아직 레이아웃되지 않은 RenderTerminal의
    // size를 읽어 assert가 터진다(AiChatPanel.build가 recentPlainText를 호출하는
    // 경로). 그 단계에서는 flush를 건너뛰고, 최신 출력은 다음 정상 flush(≤16ms)에
    // 맡긴다 — AI 컨텍스트·복원 스냅샷엔 그 정도 지연이 무의미하다.
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _flushPendingOutput();
    }
    final safeLines = maxLines.clamp(1, terminal.buffer.height).toInt();
    final startLine = terminal.buffer.height - safeLines;
    final range = BufferRangeLine(
      CellOffset(0, startLine),
      CellOffset(terminal.buffer.viewWidth - 1, terminal.buffer.height - 1),
    );
    return terminal.buffer.getText(range).trimRight();
  }

  /// 복원 스냅샷에 저장해 둔 최근 평문 화면을 터미널 버퍼에 되살린다.
  ///
  /// 실제 셸 프로세스에는 입력하지 않고 화면 버퍼에만 기록한다.
  void restorePlainText(String? text) {
    final cleaned = text?.trimRight();
    if (cleaned == null || cleaned.isEmpty) return;
    final normalized = cleaned
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '\r\n');
    terminal.write('$normalized\r\n');
  }
}
