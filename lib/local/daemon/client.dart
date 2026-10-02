import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../terminal/terminal_session_handle.dart';
import 'protocol.dart';

class LocalDaemonClient {
  LocalDaemonClient(this.directory, {this.executable, this.library});
  final Directory directory;
  final String? executable, library;
  Future<void>? _starting;
  Future<Map<String, dynamic>> _connection() async {
    final json =
        jsonDecode(
              await File('${directory.path}/connection.json').readAsString(),
            )
            as Map<String, dynamic>;
    if (json['version'] != daemonProtocolVersion ||
        json['port'] is! int ||
        json['token'] is! String) {
      throw StateError('Unsupported daemon connection');
    }
    return json;
  }

  Future<Object?> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final connection = await _connection();
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      connection['port'] as int,
      timeout: const Duration(seconds: 3),
    );
    try {
      socket.write(
        daemonFrame({
          ...params,
          'version': daemonProtocolVersion,
          'token': connection['token'],
          'method': method,
        }),
      );
      final result = await daemonMessages(
        socket,
      ).first.timeout(const Duration(seconds: 10));
      if (result['error'] != null) throw StateError('${result['error']}');
      return result['result'];
    } finally {
      socket.destroy();
    }
  }

  Future<void> ensureStarted() =>
      _starting ??= _start().whenComplete(() => _starting = null);
  Future<void> _start() async {
    try {
      await call('ping');
      return;
    } catch (_) {}
    if (executable == null || !await File(executable!).exists()) {
      throw StateError('로컬 daemon 실행 파일이 없습니다. 데스크톱 전체 빌드를 실행하세요.');
    }
    await secureDaemonDirectory(directory);
    await Process.start(
      executable!,
      [directory.path],
      mode: ProcessStartMode.detached,
      workingDirectory: File(executable!).parent.path,
      environment: {'VIBE_PTY_LIBRARY': ?library},
    );
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        await call('ping');
        return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('로컬 daemon 시작을 확인하지 못했습니다.');
  }

  Future<DaemonTerminalHandle> open({
    required String id,
    required String hostId,
    required String command,
    required List<String> arguments,
    required String? workingDirectory,
    required int cols,
    required int rows,
    required bool create,
  }) async {
    await ensureStarted();
    final opened =
        await call('open', {
              'id': id,
              'hostId': hostId,
              'executable': command,
              'arguments': arguments,
              'directory': workingDirectory,
              'cols': cols,
              'rows': rows,
              'create': create,
            })
            as Map;
    final connection = await _connection();
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      connection['port'] as int,
      timeout: const Duration(seconds: 3),
    );
    socket.write(
      daemonFrame({
        'method': 'attach',
        'id': id,
        'version': daemonProtocolVersion,
        'token': connection['token'],
      }),
    );
    return DaemonTerminalHandle(
      socket,
      connection['generation'] as String,
      resumed: opened['resumed'] == true,
      pid: opened['pid'] is int ? opened['pid'] as int : null,
    );
  }
}

class DaemonTerminalHandle
    implements
        TerminalReplaySessionHandle,
        PersistentLocalProcessSessionHandle {
  DaemonTerminalHandle(
    this.socket,
    this.generation, {
    required this.resumed,
    this.pid,
  });
  final Socket socket;
  final String generation;
  final bool resumed;
  @override
  final int? pid;
  final _ready = Completer<void>();
  Future<void> get ready => _ready.future;
  bool _attached = false;
  bool _closed = false;
  bool _processExited = false;
  @override
  bool get processExited => _processExited;
  @override
  bool get handlesTerminalQueries => true;
  @override
  Stream<TerminalReplayFrame> get frames => _frames();
  Stream<TerminalReplayFrame> _frames() async* {
    var exited = false;
    try {
      await for (final frame in daemonMessages(socket)) {
        if (frame['error'] != null) throw StateError('${frame['error']}');
        switch (frame['type']) {
          case 'replayStart':
            if (frame['generation'] != generation) {
              throw StateError('Daemon generation changed');
            }
            yield const TerminalReplayFrame('replayStart');
            if (frame['truncated'] == true) {
              yield const TerminalReplayFrame(
                'notice',
                message: '일부 과거 화면 기록을 보존하지 못했습니다. 현재 화면과 입력 모드를 복원합니다.',
              );
            }
          case 'semantic':
            yield TerminalReplayFrame(
              'semantic',
              data: base64Decode(frame['data'] as String),
            );
          case 'output':
            yield TerminalReplayFrame(
              'output',
              data: base64Decode(frame['data'] as String),
            );
          case 'resize':
            yield TerminalReplayFrame(
              'resize',
              cols: frame['cols'] as int,
              rows: frame['rows'] as int,
            );
          case 'notice':
            yield TerminalReplayFrame(
              'notice',
              message: frame['message'] as String,
            );
          case 'exit':
            exited = true;
            _processExited = true;
            if (_attached) return;
          case 'ready':
            _attached = true;
            yield const TerminalReplayFrame('ready');
            if (!_ready.isCompleted) _ready.complete();
            if (exited) return;
        }
      }
    } catch (error, stack) {
      if (!_ready.isCompleted) _ready.completeError(error, stack);
      rethrow;
    } finally {
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('Daemon attachment closed'));
      }
      _closed = true;
      socket.destroy();
    }
  }

  @override
  Stream<List<int>> get output =>
      frames.where((f) => f.type == 'output').map((f) => f.data);
  void _send(Map<String, Object?> request) {
    if (_closed || !_attached) return;
    socket.write(daemonFrame({...request, 'generation': generation}));
  }

  @override
  void write(List<int> data) =>
      _send({'method': 'input', 'data': base64Encode(data)});
  @override
  void resize(int cols, int rows) =>
      _send({'method': 'resize', 'cols': cols, 'rows': rows});
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      socket.write(daemonFrame({'method': 'detach', 'generation': generation}));
      await socket.flush();
    } catch (_) {
      // 프로세스 종료나 전송 단절 뒤에는 detach 요청을 보낼 수 없다.
    } finally {
      socket.destroy();
    }
  }
}
