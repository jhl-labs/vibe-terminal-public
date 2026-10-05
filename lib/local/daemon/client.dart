import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../terminal/terminal_session_handle.dart';
import 'protocol.dart';

/// 데몬 프로세스는 살아 있지만 요청에 응답하지 않는 상태.
///
/// 이 데몬이 `daemon.lock`을 쥐고 있어 새 데몬도 뜰 수 없으므로, 사용자가
/// 확인한 뒤 [LocalDaemonClient.restartUnresponsive]로만 복구한다.
class LocalDaemonUnresponsiveException implements Exception {
  const LocalDaemonUnresponsiveException(this.pid);
  final int pid;

  @override
  String toString() => '로컬 daemon(pid $pid)이 실행 중이지만 응답하지 않습니다.';
}

class LocalDaemonStartException implements Exception {
  const LocalDaemonStartException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LocalDaemonClient {
  LocalDaemonClient(this.directory, {this.executable, this.library});
  final Directory directory;
  final String? executable, library;
  Future<void>? _starting;

  /// ping은 즉시 응답해야 한다. 멈춘 데몬에 매번 10초씩 기다리면 오류 표시가
  /// 30초 넘게 늦어진다.
  static const _pingTimeout = Duration(seconds: 3);
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
    Duration timeout = const Duration(seconds: 10),
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
      final result = await daemonMessages(socket).first.timeout(timeout);
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
      await call('ping', const {}, _pingTimeout);
      return;
    } catch (_) {}
    if (executable == null || !await File(executable!).exists()) {
      throw const LocalDaemonStartException(
        '로컬 daemon 실행 파일이 없습니다. 데스크톱 전체 빌드를 실행하세요.',
      );
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
        await call('ping', const {}, _pingTimeout);
        return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final stuck = await _recordedDaemonPid();
    if (stuck != null) throw LocalDaemonUnresponsiveException(stuck);
    throw const LocalDaemonStartException('로컬 daemon 시작을 확인하지 못했습니다.');
  }

  /// `connection.json`에 기록된 pid가 아직 살아 있는 데몬 프로세스이면 반환한다.
  Future<int?> _recordedDaemonPid() async {
    final int pid;
    try {
      final recorded = (await _connection())['pid'];
      if (recorded is! int || recorded <= 0) return null;
      pid = recorded;
    } catch (_) {
      return null;
    }
    return await _isDaemonProcess(pid) ? pid : null;
  }

  /// pid가 재사용됐을 수 있으므로 실행 파일 이름까지 확인한다.
  Future<bool> _isDaemonProcess(int pid) async {
    final name =
        (executable == null
                ? (Platform.isWindows ? 'vibe-daemon.exe' : 'vibe-daemon')
                : executable!.split(RegExp(r'[\\/]')).last)
            .toLowerCase();
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist.exe', [
          '/FI',
          'PID eq $pid',
          '/FO',
          'CSV',
          '/NH',
        ]).timeout(const Duration(seconds: 5));
        return '${result.stdout}'.toLowerCase().contains('"$name"');
      }
      final result = await Process.run('ps', [
        '-p',
        '$pid',
        '-o',
        'comm=',
      ]).timeout(const Duration(seconds: 5));
      final command = '${result.stdout}'.trim().toLowerCase();
      return result.exitCode == 0 && command.split('/').last == name;
    } catch (_) {
      return false;
    }
  }

  /// 응답하지 않는 데몬을 강제 종료하고 새 데몬을 시작한다.
  ///
  /// 데몬이 맡은 로컬 셸도 모두 종료된다. Windows는 데몬이 쥔 Job Object가
  /// 닫히며, Unix는 PTY master가 닫히며(SIGHUP) 자식이 정리된다.
  Future<void> restartUnresponsive() async {
    try {
      await call('ping', const {}, _pingTimeout);
      return; // 그 사이 회복됐으면 세션을 건드리지 않는다.
    } catch (_) {}
    final pid = await _recordedDaemonPid();
    if (pid != null) {
      Process.killPid(pid, ProcessSignal.sigkill);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (await _isDaemonProcess(pid)) {
        if (DateTime.now().isAfter(deadline)) {
          throw LocalDaemonStartException('로컬 daemon(pid $pid)을 종료하지 못했습니다.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    await ensureStarted();
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
