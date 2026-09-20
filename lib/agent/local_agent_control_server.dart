import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../core/atomic_file.dart';
import '../local/daemon/protocol.dart' show secureDaemonDirectory;
import 'session_port.dart';

typedef AgentControlApproval =
    Future<bool> Function(String action, String target, String content);
typedef AgentControlSpawner =
    Future<String> Function(String sourceId, Map<String, Object?> parameters);

/// `agent.spawn`의 선택 인자 `model`을 검사하고 정규화한다.
///
/// 실행 다이얼로그와 같은 규칙이다. 값은 CLI 인자로 그대로 넘어가므로 셸
/// 메타문자·개행이 섞이면 거부한다. 없거나 빈 값이면 null(=CLI 기본 모델).
String? validateSpawnModel(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('model은 문자열이어야 합니다.');
  }
  final model = raw.trim();
  if (model.isEmpty) return null;
  if (model.length > 200) {
    throw const FormatException('model은 200자 이하여야 합니다.');
  }
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/:-]*$').hasMatch(model)) {
    throw const FormatException('model에 사용할 수 없는 문자가 있습니다.');
  }
  return model;
}

/// 명시적으로 켠 로컬 제어면. 앱 내부 SessionPort와 승인 경계를 재사용한다.
class LocalAgentControlServer {
  LocalAgentControlServer({
    required this.registry,
    required this.approve,
    required this.spawn,
    required this.status,
  });
  final SessionPortRegistry registry;
  final AgentControlApproval approve;
  final AgentControlSpawner spawn;
  final String Function(String id) status;
  HttpServer? _server;
  File? _connectionFile;
  String? _token;
  int _requests = 0;
  Timer? _eventTimer;
  int _eventSequence = 0;
  String _eventGeneration = _randomToken();
  final _events = <Map<String, Object?>>[];
  final _lastStatuses = <String, String>{};
  void _captureEvents() {
    final current = <String>{};
    for (final session in registry.sessions()) {
      current.add(session.id);
      final value = _describe(session);
      final encoded = jsonEncode(value);
      if (_lastStatuses[session.id] == encoded) continue;
      _lastStatuses[session.id] = encoded;
      _appendEvent('session.changed', value);
    }
    for (final id in _lastStatuses.keys.toList()) {
      if (current.contains(id)) continue;
      _lastStatuses.remove(id);
      _connections.remove(id);
      _appendEvent('session.removed', {'id': id});
    }
  }

  void _appendEvent(String type, Map<String, Object?> data) {
    _events.add({'sequence': ++_eventSequence, 'type': type, 'data': data});
    if (_events.length > 256) _events.removeAt(0);
  }

  bool _approvalPending = false;
  final _connections = <String, ({Object identity, String token})>{};
  bool get running => _server != null;
  int? get port => _server?.port;
  String? get connectionFilePath => _connectionFile?.path;
  static String _randomToken() =>
      base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256)));

  Future<void> start(File connectionFile) async {
    if (running) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      await secureDaemonDirectory(connectionFile.parent);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', [
          '700',
          connectionFile.parent.path,
        ]);
        if (result.exitCode != 0) {
          throw StateError('제어 자격증명 폴더 권한을 제한하지 못했습니다.');
        }
      }
      _token = _randomToken();
      _eventGeneration = _randomToken();
      await writeFileAtomically(
        connectionFile,
        jsonEncode({
          'version': 1,
          'url': 'http://127.0.0.1:${server.port}/v1',
          'token': _token,
          'pid': pid,
        }),
      );
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', connectionFile.path]);
        if (result.exitCode != 0) {
          throw StateError('제어 자격증명 파일 권한을 제한하지 못했습니다.');
        }
      }
      _server = server;
      _connectionFile = connectionFile;
      server.listen(_handle);
      _captureEvents();
      _eventTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        try {
          _captureEvents();
        } catch (_) {
          /* provider teardown */
        }
      });
    } catch (_) {
      await server.close(force: true);
      try {
        if (await connectionFile.exists()) {
          final written = jsonDecode(await connectionFile.readAsString());
          if (written is Map && written['token'] == _token) {
            await connectionFile.delete();
          }
        }
      } catch (_) {}
      _token = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _eventTimer?.cancel();
    _eventTimer = null;
    _events.clear();
    _lastStatuses.clear();
    final file = _connectionFile;
    _connectionFile = null;
    final token = _token;
    _token = null;
    await server?.close(force: true);
    _connections.clear();
    if (file != null && await file.exists()) {
      try {
        final value = jsonDecode(await file.readAsString());
        if (value is Map && value['token'] == token) await file.delete();
      } catch (_) {
        /* 다른 인스턴스의 파일은 지우지 않는다. */
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'POST' || request.uri.path != '/v1') {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      if (!running ||
          request.headers.value('origin') != null ||
          request.headers.value('authorization') != 'Bearer $_token' ||
          request.headers.value('host') != '127.0.0.1:$port') {
        request.response.statusCode = HttpStatus.unauthorized;
        return;
      }
      if (_requests >= 8) {
        request.response.statusCode = HttpStatus.tooManyRequests;
        return;
      }
      _requests++;
      try {
        final bytes = <int>[];
        final body = StreamIterator<List<int>>(request);
        final watch = Stopwatch()..start();
        try {
          while (true) {
            final remaining = const Duration(seconds: 5) - watch.elapsed;
            if (remaining <= Duration.zero) {
              throw TimeoutException('요청 본문 수신 시간 초과');
            }
            if (!await body.moveNext().timeout(remaining)) break;
            final chunk = body.current;
            if (bytes.length + chunk.length > 65536) {
              throw const FormatException('요청이 너무 큽니다.');
            }
            bytes.addAll(chunk);
          }
        } finally {
          await body.cancel();
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map || decoded['method'] is! String) {
          throw const FormatException('잘못된 요청입니다.');
        }
        final params = decoded['params'];
        final result = await dispatch(
          decoded['method'] as String,
          params is Map ? Map<String, Object?>.from(params) : {},
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'result': result}));
      } on Object catch (error) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': '$error'}));
      } finally {
        _requests--;
      }
    } finally {
      try {
        await request.response.close();
      } catch (_) {
        /* 요청자 연결 종료 */
      }
    }
  }

  String _connectionToken(SessionPort session) {
    final previous = _connections[session.id];
    if (previous != null && previous.identity == session.connectionIdentity) {
      return previous.token;
    }
    final token = _randomToken();
    _connections[session.id] = (
      identity: session.connectionIdentity,
      token: token,
    );
    return token;
  }

  Map<String, Object?> _describe(SessionPort session) => {
    'id': session.id,
    'name': session.displayName,
    'connected': session.isConnected,
    'status': status(session.id),
    'connectionToken': _connectionToken(session),
  };

  SessionPort _resolve(Map<String, Object?> parameters) {
    final id = parameters['sessionId'];
    final session = id is String ? registry.byId(id) : null;
    if (session == null || !session.isConnected) {
      throw StateError('연결된 대상 세션이 없습니다.');
    }
    if (parameters['connectionToken'] != _connectionToken(session)) {
      throw StateError('대상 연결이 변경되었습니다. 세션 목록을 다시 조회하세요.');
    }
    return session;
  }

  Future<Object?> dispatch(
    String method,
    Map<String, Object?> parameters,
  ) async {
    if (!running) throw StateError('외부 제어가 중지되었습니다.');
    if (method == 'sessions.list') {
      return registry.sessions().map(_describe).toList();
    }
    if (method == 'schema') {
      return {
        'version': 1,
        'methods': [
          'sessions.list',
          'screen.read',
          'input.send',
          'agent.spawn',
          'status.wait',
          'events.poll',
        ],
        'agent.spawn':
            'sessionId, connectionToken, cli, arguments, branch, '
            'isolated, model(선택)',
        'mutations': '입력·생성마다 앱에서 사용자 확인 필요',
      };
    }
    if (method == 'events.poll') {
      final after = parameters['after'];
      final requestedTimeout = parameters['timeoutMs'];
      if (after is! int || after < 0) {
        throw const FormatException('after must be a nonnegative sequence');
      }
      final timeout = requestedTimeout is int
          ? requestedTimeout.clamp(0, 50000)
          : 30000;
      final clock = Stopwatch()..start();
      do {
        if (!running) throw StateError('외부 제어가 중지되었습니다.');
        _captureEvents();
        if ((after > 0 && parameters['generation'] != _eventGeneration) ||
            _eventSequence > after ||
            after > _eventSequence ||
            clock.elapsedMilliseconds >= timeout) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } while (true);
      final reset =
          (after > 0 && parameters['generation'] != _eventGeneration) ||
          after > _eventSequence ||
          (_events.isNotEmpty &&
              after < (_events.first['sequence'] as int) - 1);
      return {
        'cursor': _eventSequence,
        'generation': _eventGeneration,
        'reset': reset,
        if (reset) 'sessions': registry.sessions().map(_describe).toList(),
        'events': [
          for (final event in _events)
            if ((event['sequence'] as int) > after) event,
        ],
      };
    }
    final session = _resolve(parameters);
    final identity = session.connectionIdentity;
    if (method == 'screen.read') {
      final rawLines = parameters['maxLines'];
      final lines = rawLines is int ? rawLines.clamp(1, 400) : 120;
      final text = session.readScreen(maxLines: lines);
      return {
        'text': text.length > 65536
            ? text.substring(text.length - 65536)
            : text,
      };
    }
    if (method == 'status.wait') {
      final wanted = parameters['status'];
      if (wanted is! String ||
          !{'working', 'blocked', 'done', 'idle'}.contains(wanted)) {
        throw const FormatException(
          '상태는 working/blocked/done/idle 중 하나여야 합니다.',
        );
      }
      final raw = parameters['timeoutMs'];
      final timeout = raw is int ? raw.clamp(0, 50000) : 30000;
      final deadline = Stopwatch()..start();
      while (running &&
          status(session.id) != wanted &&
          deadline.elapsedMilliseconds < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        _resolve(parameters);
      }
      if (!running) throw StateError('외부 제어가 중지되었습니다.');
      return {'matched': status(session.id) == wanted, ..._describe(session)};
    }
    if (method != 'input.send' && method != 'agent.spawn') {
      throw const FormatException('지원하지 않는 메서드입니다.');
    }
    if (_approvalPending) throw StateError('다른 외부 요청이 사용자 확인을 기다리고 있습니다.');
    final text = parameters['text'];
    if (method == 'input.send' &&
        (text is! String || text.length > 8192 || text.contains('\u0000'))) {
      throw const FormatException('입력은 8,192자 이하 문자열이어야 합니다.');
    }
    // 모델은 승인 카드에 보여 주기 전에 거른다. 인자로 그대로 넘어가므로
    // 실행 다이얼로그와 같은 규칙으로 셸 메타문자·개행을 막는다.
    if (method == 'agent.spawn') validateSpawnModel(parameters['model']);
    _approvalPending = true;
    try {
      if (!await approve(
        method,
        session.displayName,
        method == 'input.send' ? text as String : jsonEncode(parameters),
      )) {
        throw StateError('사용자가 외부 요청을 취소했습니다.');
      }
      if (!running || _resolve(parameters).connectionIdentity != identity) {
        throw StateError('확인 중 대상 연결이 바뀌었습니다.');
      }
      if (method == 'agent.spawn') {
        return {'sessionId': await spawn(session.id, parameters)};
      }
      session.sendText(text as String);
      if (parameters['submit'] == true) session.submit();
      return {'sent': true};
    } finally {
      _approvalPending = false;
    }
  }
}
