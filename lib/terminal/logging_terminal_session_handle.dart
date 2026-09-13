import 'dart:async';

import '../data/repositories/session_log_repository.dart';
import 'terminal_session_handle.dart';

class LoggingTerminalSessionHandle implements TerminalSessionHandle {
  LoggingTerminalSessionHandle({required this.inner, required this.writer}) {
    _output = _loggedOutput();
  }

  final TerminalSessionHandle inner;
  final SessionLogWriter writer;

  late final Stream<List<int>> _output;
  bool _closing = false;

  @override
  Stream<List<int>> get output => _output;

  @override
  void write(List<int> data) {
    writer.writeInput(data);
    inner.write(data);
  }

  @override
  void resize(int cols, int rows) => inner.resize(cols, rows);

  @override
  Future<void> close() async {
    _closing = true;
    try {
      await inner.close();
    } finally {
      await writer.finish('closed');
    }
  }

  Stream<List<int>> _loggedOutput() async* {
    try {
      await for (final data in inner.output) {
        writer.write(data);
        yield data;
      }
      await writer.finish(_closing ? 'closed' : 'disconnected');
    } catch (e, stackTrace) {
      await writer.finish('error');
      Error.throwWithStackTrace(e, stackTrace);
    }
  }
}
