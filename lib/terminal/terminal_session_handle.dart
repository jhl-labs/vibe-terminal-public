import 'dart:async';

abstract interface class TerminalSessionHandle {
  Stream<List<int>> get output;

  void write(List<int> data);

  void resize(int cols, int rows);

  FutureOr<void> close();
}

/// 로컬 프로세스를 직접 소유하는 핸들. 셸의 실제 상태(작업 디렉터리 등)를
/// OS에서 조회하려면 프로세스 ID가 필요하다.
abstract interface class LocalProcessSessionHandle
    implements TerminalSessionHandle {
  /// 셸 프로세스 ID. 아직 시작되지 않았거나 알 수 없으면 null.
  int? get pid;
}

/// 앱과 별도 수명으로 실행되는 로컬 PTY에 붙은 핸들.
/// 출력 스트림 종료가 프로세스 종료인지 전송 분리인지 구분한다.
abstract interface class PersistentLocalProcessSessionHandle
    implements LocalProcessSessionHandle {
  bool get processExited;
}

/// PTY journal 재생 시 화면 크기와 입력 억제 경계를 보존한다.
class TerminalReplayFrame {
  const TerminalReplayFrame(
    this.type, {
    this.data = const [],
    this.cols,
    this.rows,
    this.message,
  });
  final String type;
  final List<int> data;
  final int? cols, rows;
  final String? message;
}

abstract interface class TerminalReplaySessionHandle
    implements TerminalSessionHandle {
  Stream<TerminalReplayFrame> get frames;
  bool get handlesTerminalQueries;
}
