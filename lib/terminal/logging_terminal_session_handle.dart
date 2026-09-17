import 'dart:async';

import '../data/repositories/session_log_repository.dart';
import 'terminal_session_handle.dart';

class LoggingTerminalSessionHandle implements TerminalReplaySessionHandle {
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
  bool get handlesTerminalQueries =>
      inner is TerminalReplaySessionHandle &&
      (inner as TerminalReplaySessionHandle).handlesTerminalQueries;
  @override
  Stream<TerminalReplayFrame> get frames async* {
    final source = inner;
    if (source is! TerminalReplaySessionHandle) {
      await for (final data in _output) {
        yield TerminalReplayFrame('output', data: data);
      }
      return;
    }
    var replaying = false;
    try {
      await for (final frame in source.frames) {
        if (frame.type == 'replayStart') replaying = true;
        if (frame.type == 'ready') replaying = false;
        if (!replaying && frame.type == 'output') writer.write(frame.data);
        yield frame;
      }
      await writer.finish(_closing ? 'closed' : 'disconnected');
    } catch (error, stack) {
      await writer.finish('error');
      Error.throwWithStackTrace(error, stack);
    }
  }

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
