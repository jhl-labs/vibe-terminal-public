import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/core.dart';
import '../../core/atomic_file.dart';
import 'protocol.dart';
import 'background_schedule.dart';
import 'terminal_checkpoint.dart';
import '../../agent/agent_semantic_event.dart';

class LocalPtyDaemon {
  LocalPtyDaemon(this.directory);
  final Directory directory;
  final String generation = daemonToken();
  final String _token = daemonToken();
  final _sessions = <String, _PersistentPty>{};
  ServerSocket? _server;
  RandomAccessFile? _lock;
  bool _closing = false;
  Timer? _scheduleTimer;
  String? _scheduleError;
  late final BackgroundScheduleService schedules = BackgroundScheduleService(
    directory,
    _launchScheduled,
    isRunning: (id) =>
        _sessions[id]?.exitCode == null && _sessions.containsKey(id),
  );
  Future<String> _launchScheduled(Map<String, dynamic> spec) async {
    // 완료된 예약 출력은 최근 16개까지 보존한다. 사용자가 붙어 있는 세션은 정리하지 않는다.
    final completed = _sessions.values
        .where(
          (s) =>
              s.id.startsWith('background-') &&
              s.exitCode != null &&
              s._owner == null,
        )
        .toList();
    for (final old in completed.take(
      (completed.length - 15).clamp(0, completed.length),
    )) {
      await old.terminate();
      _sessions.remove(old.id);
      await old.journal.delete();
    }
    if (_sessions.length >= 32) throw StateError('로컬 세션 한도입니다. 종료된 세션을 정리하세요.');
    final id = 'background-${daemonToken().replaceAll('=', '')}';
    final session = _PersistentPty(
      id: id,
      hostId: spec['hostId'] as String,
      executable: spec['executable'] as String,
      arguments: (spec['arguments'] as List).cast<String>(),
      directory: spec['directory'] as String?,
      journal: File('${directory.path}/$id.journal'),
      cols: 120,
      rows: 32,
    );
    _sessions[id] = session;
    session.pty.exitCode
        .then((code) => schedules.recordExit(id, code))
        .catchError((Object error) {
          _scheduleError = '$error';
        });
    return id;
  }

  final _done = Completer<void>();
  Future<void> get done => _done.future;

  Future<void> start() async {
    await secureDaemonDirectory(directory);
    _lock = await File(
      '${directory.path}/daemon.lock',
    ).open(mode: FileMode.append);
    try {
      await _lock!.lock(FileLock.exclusive);
    } catch (_) {
      await _lock!.close();
      rethrow;
    }
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      await writeFileAtomically(
        File('${directory.path}/connection.json'),
        jsonEncode({
          'version': daemonProtocolVersion,
          'port': _server!.port,
          'token': _token,
          'generation': generation,
          'pid': pid,
        }),
      );
      _server!.listen((socket) => unawaited(_accept(socket)));
      try {
        await schedules.load();
      } catch (error) {
        _scheduleError = '$error';
      }
      _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_scheduleError == null) {
          unawaited(
            schedules.tick().catchError((Object error) {
              _scheduleError = '$error';
            }),
          );
        }
      });
    } catch (_) {
      await _lock!.close();
      rethrow;
    }
  }

  Future<void> _accept(Socket socket) async {
    final reader = StreamIterator(daemonMessages(socket));
    try {
      if (!await reader.moveNext().timeout(const Duration(seconds: 5))) return;
      if (_closing) throw StateError('Daemon is stopping');
      final request = reader.current;
      if (request['token'] != _token ||
          request['version'] != daemonProtocolVersion) {
        throw StateError('Authentication/protocol mismatch');
      }
      final action = request['method'];
      if (action == 'attach') {
        final id = request['id'];
        final session = _sessions[id];
        if (session == null) {
          throw StateError('실행 중인 로컬 세션이 없습니다. 새 세션을 열어 주세요.');
        }
        await session.attach(socket, reader, generation);
        return;
      }
      Object? result;
      switch (action) {
        case 'schedules.list':
          result = {'tasks': schedules.tasks, 'error': _scheduleError};
        case 'schedules.set':
          if (_scheduleError != null) {
            throw StateError('예약 저장소 복구가 필요합니다: $_scheduleError');
          }
          result = await schedules.set(
            Map<String, dynamic>.from(request['task'] as Map),
          );
        case 'schedules.remove':
          if (_scheduleError != null) throw StateError('예약 저장소 복구가 필요합니다');
          await schedules.remove(request['id'] as String);
          result = {'removed': true};
        case 'schedules.reload':
          await schedules.load();
          _scheduleError = null;
          result = {'reloaded': true};
        case 'ping':
          result = {'generation': generation};
        case 'list':
          result = [for (final session in _sessions.values) session.describe()];
        case 'open':
          final id = request['id'];
          if (id is! String ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,160}$').hasMatch(id)) {
            throw ArgumentError('Invalid session ID');
          }
          final existing = _sessions[id];
          if (existing != null) {
            result = {...existing.describe(), 'resumed': true};
            break;
          }
          if (request['create'] != true) {
            throw StateError('이전 daemon 세션이 종료되었습니다. 새 대화로 열기를 선택하세요.');
          }
          if (_sessions.length >= 32) {
            throw StateError('백그라운드 세션은 최대 32개입니다. 종료된 세션을 정리하세요.');
          }
          final executable = request['executable'];
          final args = request['arguments'];
          if (executable is! String ||
              executable.isEmpty ||
              args is! List ||
              args.any((arg) => arg is! String)) {
            throw ArgumentError('Invalid launch specification');
          }
          final session = _PersistentPty(
            id: id,
            hostId: request['hostId'] as String,
            executable: executable,
            arguments: args.cast<String>(),
            directory: request['directory'] as String?,
            journal: File('${directory.path}/$id.journal'),
            cols: _dimension(request['cols']),
            rows: _dimension(request['rows']),
          );
          _sessions[id] = session;
          result = {...session.describe(), 'resumed': false};
        case 'terminate':
          final session = _sessions[request['id']];
          if (session == null) throw StateError('Session not found');
          await session.terminate();
          _sessions.remove(session.id);
          await session.journal.delete();
          result = {'terminated': true};
        case 'shutdown':
          if (schedules.tasks.any((task) => task['enabled'] == true)) {
            throw StateError('활성 예약을 먼저 해제하세요.');
          }
          if (_sessions.values.any((s) => s.exitCode == null)) {
            throw StateError('실행 중인 세션을 먼저 종료하세요.');
          }
          result = {'stopped': true};
          Timer(const Duration(milliseconds: 100), () => unawaited(close()));
        default:
          throw ArgumentError('Unknown method');
      }
      socket.write(daemonFrame({'result': result}));
      await socket.flush();
    } catch (error) {
      try {
        socket.write(daemonFrame({'error': '$error'}));
        await socket.flush();
      } catch (_) {}
    } finally {
      await reader.cancel();
      socket.destroy();
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _scheduleTimer?.cancel();
    await _server?.close();
    for (final session in _sessions.values) {
      await session.terminate();
    }
    final file = File('${directory.path}/connection.json');
    try {
      if ((jsonDecode(await file.readAsString()) as Map)['generation'] ==
          generation) {
        await file.delete();
      }
    } catch (_) {}
    await _lock?.close();
    if (!_done.isCompleted) _done.complete();
  }
}

int _dimension(Object? value) => value is int ? value.clamp(2, 1000) : 80;

class _PersistentPty {
  _PersistentPty({
    required this.id,
    required this.hostId,
    required this.executable,
    required this.arguments,
    required this.directory,
    required this.journal,
    required int cols,
    required int rows,
  }) {
    journal.writeAsStringSync('');
    _journal = journal.openSync(mode: FileMode.append);
    _record({'type': 'resize', 'cols': cols, 'rows': rows});
    try {
      pty = Pty.start(
        executable,
        arguments: arguments,
        workingDirectory: directory,
        environment: Platform.environment,
        columns: cols,
        rows: rows,
      );
    } catch (_) {
      _journal.closeSync();
      rethrow;
    }
    terminal.resize(cols, rows);
    terminal.onPrivateOSC = (code, args) {
      if (code != '777' ||
          args.length != 2 ||
          args[0] != AgentSemanticEvent.sidebandChannel) {
        return;
      }
      final event = AgentSemanticEvent.tryParseSideband(args[1]);
      if (event != null) _semantic[event.provider] = event.toSidebandSequence();
    };
    terminal.onOutput = (data) {
      final corrected = data.replaceAllMapped(
        RegExp(r'\x1b\[(\d+);(\d+)R'),
        (m) => '\x1b[${int.parse(m[1]!) + 1};${int.parse(m[2]!) + 1}R',
      );
      if (exitCode == null) {
        pty.write(Uint8List.fromList(utf8.encode(corrected)));
      }
    };
    final decoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(
          StringConversionSink.from(_TextSink(terminal.write)),
        );
    pty.output.listen(
      (data) {
        decoder.add(data);
        _record({'type': 'output', 'data': base64Encode(data)});
      },
      onDone: decoder.close,
      onError: (Object error) =>
          _record({'type': 'notice', 'message': 'PTY output error: $error'}),
    );
    pty.exitCode.then((code) {
      exitCode = code;
      _record({'type': 'exit', 'code': code});
    });
  }
  final String id, hostId, executable;
  final List<String> arguments;
  final String? directory;
  final File journal;
  late final RandomAccessFile _journal;
  late final Pty pty;
  final terminal = Terminal(maxLines: 10000);
  final _semantic = <String, String>{};
  int? exitCode;
  int _sequence = 0;
  int _bytes = 0;
  bool _truncated = false;
  bool _disposed = false;
  Socket? _owner;
  Future<void>? _termination;
  final _events = StreamController<String>.broadcast(sync: true);
  Map<String, Object?> describe() => {
    'id': id,
    'hostId': hostId,
    'executable': executable,
    'directory': directory,
    'pid': pty.pid,
    'exitCode': exitCode,
    'attached': _owner != null,
    'journalTruncated': _truncated,
  };
  void _record(Map<String, Object?> record) {
    if (_disposed) return;
    final line = daemonFrame({...record, 'seq': ++_sequence});
    final data = utf8.encode(line);
    if (_bytes + data.length <= 256 * 1024 * 1024) {
      try {
        _journal.writeFromSync(data);
        _bytes += data.length;
      } on FileSystemException {
        _truncated = true;
      }
    } else {
      _truncated = true;
    }
    _events.add(line);
  }

  Future<void> attach(
    Socket socket,
    StreamIterator<Map<String, dynamic>> reader,
    String generation,
  ) async {
    _owner?.destroy();
    _owner = socket;
    final queued = <String>[];
    var queuedBytes = 0;
    var replay = true;
    var overflow = false;
    var draining = false;
    Future<void> drain() async {
      if (draining || replay) return;
      draining = true;
      try {
        while (queued.isNotEmpty) {
          final line = queued.removeAt(0);
          queuedBytes -= line.length;
          socket.write(line);
          await socket.flush();
        }
      } catch (_) {
        socket.destroy();
      } finally {
        draining = false;
      }
    }

    final live = _events.stream.listen((line) {
      queued.add(line);
      queuedBytes += line.length;
      if (queuedBytes > 4 * 1024 * 1024) {
        overflow = true;
        socket.destroy();
        return;
      }
      if (!replay) unawaited(drain());
    });
    try {
      if (!_truncated) _journal.flushSync();
      final length = _truncated ? 0 : journal.lengthSync();
      socket.write(
        daemonFrame({
          'type': 'replayStart',
          'generation': generation,
          'truncated': _truncated,
        }),
      );
      if (_truncated) {
        socket.write(
          daemonFrame({
            'type': 'resize',
            'cols': terminal.viewWidth,
            'rows': terminal.viewHeight,
          }),
        );
        final checkpoint = utf8.encode(terminalCheckpoint(terminal));
        for (var offset = 0; offset < checkpoint.length; offset += 32768) {
          socket.write(
            daemonFrame({
              'type': 'output',
              'data': base64Encode(
                checkpoint.sublist(
                  offset,
                  (offset + 32768).clamp(0, checkpoint.length),
                ),
              ),
            }),
          );
        }
        if (exitCode != null) {
          socket.write(daemonFrame({'type': 'exit', 'code': exitCode}));
        }
      } else {
        await socket
            .addStream(journal.openRead(0, length))
            .timeout(const Duration(seconds: 30));
      }
      for (final line in queued) {
        socket.write(line);
      }
      replay = false;
      queued.clear();
      queuedBytes = 0;
      if (overflow) throw StateError('Replay reader too slow');
      for (final wire in _semantic.values) {
        socket.write(
          daemonFrame({
            'type': 'semantic',
            'data': base64Encode(utf8.encode(wire)),
          }),
        );
      }
      socket.write(daemonFrame({'type': 'ready', 'generation': generation}));
      await socket.flush();
      while (await reader.moveNext()) {
        if (!identical(_owner, socket)) break;
        final request = reader.current;
        if (request['generation'] != generation) {
          throw StateError('Stale daemon generation');
        }
        switch (request['method']) {
          case 'input':
            final data = base64Decode(request['data'] as String);
            if (data.length > 65536) throw ArgumentError('Input too large');
            if (exitCode != null) throw StateError('프로세스가 종료됐습니다.');
            pty.write(Uint8List.fromList(data));
          case 'resize':
            final cols = _dimension(request['cols']),
                rows = _dimension(request['rows']);
            terminal.resize(cols, rows);
            if (exitCode == null) pty.resize(rows, cols);
            _record({'type': 'resize', 'cols': cols, 'rows': rows});
          case 'detach':
            return;
          default:
            throw ArgumentError('Unknown attachment method');
        }
      }
    } finally {
      await live.cancel();
      if (identical(_owner, socket)) _owner = null;
    }
  }

  Future<void> terminate() => _termination ??= _terminate();
  Future<void> _terminate() async {
    _owner?.destroy();
    _owner = null;
    if (exitCode == null) {
      if (Platform.isWindows) {
        await Process.run('taskkill.exe', [
          '/PID',
          '${pty.pid}',
          '/T',
          '/F',
        ]).timeout(const Duration(seconds: 5));
      } else {
        Process.killPid(-pty.pid, ProcessSignal.sighup);
        pty.kill(ProcessSignal.sighup);
      }
      try {
        await pty.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        if (!Platform.isWindows) {
          Process.killPid(-pty.pid, ProcessSignal.sigkill);
        }
        pty.kill(ProcessSignal.sigkill);
        await pty.exitCode.timeout(const Duration(seconds: 3));
      }
    }
    _disposed = true;
    _journal.closeSync();
    await _events.close();
  }
}

class _TextSink implements Sink<String> {
  _TextSink(this.write);
  final void Function(String) write;
  @override
  void add(String data) => write(data);
  @override
  void close() {}
}
