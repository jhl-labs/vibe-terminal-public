import 'dart:async';

import 'terminal_session_handle.dart';

/// 대량 출력/재생에서도 입력·프레임·SSH 타이머가 실행될 기회를 보장한다.
/// 프레임 순서는 유지하고 바이트만 나누므로 UTF-8은 소비자의 상태형 디코더로
/// 복원한다. async*의 pause 전파로 다음 프레임을 미리 쌓지 않는다.
Stream<TerminalReplayFrame> paceTerminalFrames(
  Stream<TerminalReplayFrame> source,
) async* {
  const byteBudget = 32 * 1024;
  var remaining = byteBudget;
  await for (final frame in source) {
    if (frame.type != 'output') {
      yield frame;
      continue;
    }
    var offset = 0;
    while (offset < frame.data.length) {
      final end = (offset + remaining).clamp(0, frame.data.length);
      yield TerminalReplayFrame(
        'output',
        data: frame.data.sublist(offset, end),
      );
      remaining -= end - offset;
      offset = end;
      if (remaining == 0) {
        // A microtask alone does not yield to timers or platform input.
        await Future<void>.delayed(Duration.zero);
        remaining = byteBudget;
      }
    }
  }
}
