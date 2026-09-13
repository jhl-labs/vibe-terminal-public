import 'dart:async';

abstract interface class TerminalSessionHandle {
  Stream<List<int>> get output;

  void write(List<int> data);

  void resize(int cols, int rows);

  FutureOr<void> close();
}
