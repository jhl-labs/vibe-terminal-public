import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../cli_config/wsl_cli_config_home.dart';
import '../core/result.dart';
import '../local/login_shell_path.dart';

/// Pod 안에서 최종 대상까지 TCP를 중계할 `kubectl exec` 명세.
///
/// 릴레이는 Pod에 sshd가 없어도 되고, `nc`·`socat`·`bash` 중 하나만 있으면
/// 된다. 그 stdin/stdout이 그대로 대상 SSH 서버와의 소켓이 된다.
class KubernetesRelaySpec {
  const KubernetesRelaySpec({
    this.context,
    required this.namespace,
    required this.resource,
    this.container,
    required this.targetHost,
    required this.targetPort,
  });

  final String? context;
  final String namespace;

  /// `pod-name` 또는 `deployment/name`처럼 `kubectl exec`가 받는 표기.
  final String resource;
  final String? container;
  final String targetHost;
  final int targetPort;

  String get podLabel => '$namespace/$resource';

  /// 입력 오류 메시지. 문제가 없으면 null.
  String? validate() {
    if (namespace.trim().isEmpty) return 'Kubernetes namespace를 입력하세요.';
    if (resource.trim().isEmpty) return '릴레이를 실행할 Pod를 입력하세요.';
    for (final (label, value) in [
      ('context', context),
      ('namespace', namespace),
      ('Pod', resource),
      ('container', container),
    ]) {
      final text = value?.trim();
      if (text == null || text.isEmpty) continue;
      if (text.startsWith('-') || _hasControlOrSpace(text)) {
        return 'Kubernetes $label 값이 올바르지 않습니다: $text';
      }
    }
    if (!isValidRelayTargetHost(targetHost)) {
      return '최종 SSH 주소가 올바르지 않습니다: $targetHost';
    }
    if (targetPort < 1 || targetPort > 65535) {
      return '최종 SSH 포트는 1~65535 사이여야 합니다.';
    }
    return null;
  }

  static bool _hasControlOrSpace(String text) =>
      text.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7f);
}

/// 릴레이 대상 주소로 허용하는 형식. 호스트명·IPv4·IPv6만 받고, `-`로 시작하는
/// 값은 Pod 안에서 nc 옵션으로 해석될 수 있어 거부한다.
bool isValidRelayTargetHost(String host) =>
    RegExp(r'^[A-Za-z0-9:][A-Za-z0-9._:\-]*$').hasMatch(host);

/// Pod 안에서 실행할 릴레이 스크립트.
///
/// 대상 주소·포트를 `sh -c`의 추가 인자로 전달하지 않는다. WSL과 kubectl을
/// 거치는 동안 위치 인자가 유실되는 환경에서도 검증된 값을 스크립트 안에서
/// 바로 설정할 수 있게 한다. nc → socat → bash(/dev/tcp) 순으로 첫 번째로
/// 발견한 도구를 사용한다.
String kubernetesRelayScript(KubernetesRelaySpec spec) {
  final targetHost = shellQuote(spec.targetHost.trim());
  final targetPort = shellQuote('${spec.targetPort}');
  return 'h=$targetHost; p=$targetPort\n'
      'if [ -z "\$h" ] || [ -z "\$p" ]; then '
      'echo "vibe-terminal relay: final SSH host or port is empty" >&2; '
      'exit 64; fi\n'
      'if command -v nc >/dev/null 2>&1; then exec nc "\$h" "\$p"; fi\n'
      'if command -v socat >/dev/null 2>&1; then exec socat - "TCP:\$h:\$p"; fi\n'
      'if command -v bash >/dev/null 2>&1; then '
      'exec bash -c "exec 3<>/dev/tcp/\\\$0/\\\$1 || exit 1; '
      'cat <&3 & cat >&3; kill \\\$! 2>/dev/null" "\$h" "\$p"; fi\n'
      'echo "vibe-terminal relay: nc, socat or bash is required in the pod" >&2\n'
      'exit 127\n';
}

/// 게이트웨이(로컬/SSH)의 셸이 kubectl을 찾도록 PATH를 보강하는 접두어.
/// 로그인 셸(`-l`)은 프로필이 stdout에 출력할 수 있어 릴레이 스트림을
/// 오염시키므로 쓰지 않는다.
const _kubectlPathPrefix =
    'PATH="\$PATH:\$HOME/.local/bin:\$HOME/bin:/usr/local/bin:/snap/bin:'
    '/opt/homebrew/bin"';

/// `kubectl` 뒤에 붙는 인자 목록. 실행 파일은 게이트웨이마다 다르게 고른다.
List<String> kubectlRelayArguments(KubernetesRelaySpec spec) => [
  if (spec.context?.trim().isNotEmpty ?? false) ...[
    '--context',
    spec.context!.trim(),
  ],
  '--namespace',
  spec.namespace.trim(),
  'exec',
  '-i',
  if (spec.container?.trim().isNotEmpty ?? false) ...[
    '-c',
    spec.container!.trim(),
  ],
  spec.resource.trim(),
  '--',
  'sh',
  '-c',
  kubernetesRelayScript(spec),
];

/// POSIX 셸(`sh -c`)에서 실행할 한 줄 명령. WSL과 SSH 게이트웨이가 쓴다.
String kubectlRelayCommandLine(KubernetesRelaySpec spec) {
  final args = ['kubectl', ...kubectlRelayArguments(spec)];
  return '$_kubectlPathPrefix exec ${args.map(shellQuote).join(' ')}';
}

/// Windows의 WSL 게이트웨이에 넘길 인자. 이 목록 자체를 검증해 Windows의
/// 인자 직렬화 경로에서 릴레이 명령이 바뀌지 않도록 한다.
List<String> wslRelayArguments(KubernetesRelaySpec spec) => [
  '--',
  'sh',
  '-c',
  kubectlRelayCommandLine(spec),
];

/// POSIX 셸 단어 인용.
String shellQuote(String value) {
  if (value.isNotEmpty &&
      RegExp(r'^[A-Za-z0-9_@%+=:,./\-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

/// kubectl을 실행할 위치.
sealed class KubernetesRelayGateway {
  const KubernetesRelayGateway();

  String get label;
}

/// 이 기기에서 kubectl을 직접 실행한다.
class LocalKubectlGateway extends KubernetesRelayGateway {
  const LocalKubectlGateway();

  @override
  String get label => '이 기기';
}

/// Windows 기본 WSL 배포판 안에서 kubectl을 실행한다.
class WslKubectlGateway extends KubernetesRelayGateway {
  const WslKubectlGateway();

  @override
  String get label => 'WSL';
}

/// 이미 인증된 SSH 연결 위에서 kubectl을 실행한다.
class SshKubectlGateway extends KubernetesRelayGateway {
  const SshKubectlGateway(this.client, {required this.alias});

  final SSHClient client;
  final String alias;

  @override
  String get label => 'SSH 호스트 $alias';
}

abstract interface class KubernetesRelayService {
  /// [gateway]에서 kubectl exec 릴레이를 띄우고, 대상 SSH 서버의 첫 응답이
  /// 도착하면 그 스트림을 [SSHSocket]으로 돌려준다.
  Future<Result<SSHSocket>> open(
    KubernetesRelaySpec spec,
    KubernetesRelayGateway gateway,
  );
}

typedef RelayProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

typedef KubectlLocator = Future<String?> Function();

class ProcessKubernetesRelayService implements KubernetesRelayService {
  ProcessKubernetesRelayService({
    RelayProcessStarter? processStarter,
    KubectlLocator? kubectlLocator,
    this.readyTimeout = const Duration(seconds: 20),
  }) : _processStarter = processStarter ?? _startProcess,
       _kubectlLocator = kubectlLocator ?? locateLocalKubectl;

  final RelayProcessStarter _processStarter;
  final KubectlLocator _kubectlLocator;
  final Duration readyTimeout;
  String? _cachedKubectl;

  static Future<Process> _startProcess(
    String executable,
    List<String> arguments,
  ) => Process.start(executable, arguments, runInShell: false);

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Future<Result<SSHSocket>> open(
    KubernetesRelaySpec spec,
    KubernetesRelayGateway gateway,
  ) async {
    final validation = spec.validate();
    if (validation != null) return Err(KubernetesFailure(validation));
    final contextLabel = spec.context?.trim().isNotEmpty ?? false
        ? spec.context!.trim()
        : '현재 kubeconfig';
    final containerLabel = spec.container?.trim().isNotEmpty ?? false
        ? spec.container!.trim()
        : 'Pod 기본 컨테이너';
    final where =
        '${gateway.label}에서 ${spec.podLabel} 경유 '
        '${spec.targetHost}:${spec.targetPort} '
        '(context: $contextLabel, container: $containerLabel)';

    final _RelayEndpoint endpoint;
    try {
      switch (gateway) {
        case LocalKubectlGateway():
          if (!_isDesktop) {
            return const Err(
              KubernetesFailure(
                '이 기기에서 kubectl을 실행하는 방식은 데스크톱에서만 지원합니다. '
                'kubectl 실행 위치를 SSH 호스트로 바꾸세요.',
              ),
            );
          }
          final kubectl = _cachedKubectl ??= await _kubectlLocator();
          if (kubectl == null) {
            return const Err(
              KubernetesFailure(
                '이 기기에서 kubectl을 찾지 못했습니다. kubectl을 설치했거나 PATH에 '
                '있는지 확인하세요.',
              ),
            );
          }
          endpoint = _ProcessRelayEndpoint(
            await _processStarter(kubectl, kubectlRelayArguments(spec)),
          );
        case WslKubectlGateway():
          if (!Platform.isWindows) {
            return const Err(
              KubernetesFailure('WSL에서 kubectl 실행은 Windows에서만 지원합니다.'),
            );
          }
          endpoint = _ProcessRelayEndpoint(
            await _processStarter(
              WslCliConfigLocator.wslExecutable(),
              wslRelayArguments(spec),
            ),
          );
        case SshKubectlGateway(:final client):
          endpoint = _SessionRelayEndpoint(
            await client.execute(
              'sh -c ${shellQuote(kubectlRelayCommandLine(spec))}',
            ),
          );
      }
    } on ProcessException catch (error) {
      return Err(
        KubernetesFailure(
          '${gateway.label}에서 ${p.basename(error.executable)}을(를) 실행할 수 '
          '없습니다: ${error.message}',
        ),
      );
    } catch (error) {
      return Err(KubernetesFailure('$where 릴레이를 시작하지 못했습니다: $error'));
    }

    return _awaitReady(endpoint, where);
  }

  /// 대상 SSH 서버는 접속 직후 자기 버전 문자열을 먼저 보낸다. 그 첫 바이트가
  /// 도착하면 릴레이가 실제로 대상까지 이어졌다고 본다. 그 전에 프로세스가
  /// 끝나면 stderr(kubectl 오류, nc 접속 실패 등)를 그대로 실패 이유로 쓴다.
  Future<Result<SSHSocket>> _awaitReady(
    _RelayEndpoint endpoint,
    String where,
  ) async {
    final socket = RelaySshSocket._(endpoint);
    try {
      final ready = await Future.any<bool>([
        socket.firstData.then((_) => true),
        endpoint.exited.then((_) => false),
      ]).timeout(readyTimeout);
      if (ready) return Ok(socket);
      final code = await endpoint.exited;
      final detail = endpoint.stderrLines.isEmpty
          ? 'kubectl exec가 대상에 연결되기 전에 종료되었습니다 (exit $code).'
          : endpoint.stderrLines.join('\n');
      await socket.close();
      return Err(KubernetesFailure('$where 연결 실패\n$detail'));
    } on TimeoutException {
      await socket.close();
      final detail = endpoint.stderrLines.isEmpty
          ? ''
          : '\n${endpoint.stderrLines.join('\n')}';
      return Err(
        KubernetesFailure(
          '$where 릴레이가 ${readyTimeout.inSeconds}초 안에 응답하지 않았습니다. '
          '대상 주소·포트와 Pod의 nc/socat/bash 설치 여부를 확인하세요.$detail',
        ),
      );
    } catch (error) {
      await socket.close();
      return Err(KubernetesFailure('$where 릴레이 준비 실패: $error'));
    }
  }
}

/// 이 기기에서 kubectl 실행 파일을 찾는다.
///
/// Finder/Dock에서 실행한 앱은 PATH가 빈약하므로 관례적인 설치 위치와
/// 로그인 셸의 PATH도 함께 훑는다. Windows는 CreateProcess가 PATH를 찾으므로
/// 이름만 돌려준다.
Future<String?> locateLocalKubectl({
  Map<String, String>? environment,
  Future<String?> Function()? loginShellPath,
}) async {
  if (Platform.isWindows) return 'kubectl';
  final env = environment ?? Platform.environment;
  final home = env['HOME'];
  final directories = <String>[
    ...?env['PATH']?.split(':'),
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    '/bin',
    '/snap/bin',
    if (home != null) ...[p.join(home, '.local', 'bin'), p.join(home, 'bin')],
  ];
  try {
    final shellPath = await (loginShellPath ?? readLoginShellPath)();
    if (shellPath != null) directories.addAll(shellPath.split(':'));
  } on Exception {
    // 로그인 셸이 없어도 관례적인 위치는 그대로 확인한다.
  }
  for (final directory in directories) {
    if (!p.isAbsolute(directory)) continue;
    final candidate = p.join(directory, 'kubectl');
    final stat = await File(candidate).stat();
    if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
      return candidate;
    }
  }
  return null;
}

/// 릴레이 프로세스/세션의 공통 인터페이스.
abstract class _RelayEndpoint {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int?> get exited;
  void write(Uint8List data);
  Future<void> closeStdin();
  void kill();

  final stderrLines = <String>[];

  void recordStderr(String line) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) return;
    stderrLines.add(trimmed);
    if (stderrLines.length > 12) stderrLines.removeAt(0);
    debugPrint('[kubectl relay] $trimmed');
  }
}

class _ProcessRelayEndpoint extends _RelayEndpoint {
  _ProcessRelayEndpoint(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int?> get exited => _process.exitCode;

  @override
  void write(Uint8List data) => _process.stdin.add(data);

  @override
  Future<void> closeStdin() => _process.stdin.close();

  @override
  void kill() => _process.kill();
}

class _SessionRelayEndpoint extends _RelayEndpoint {
  _SessionRelayEndpoint(this._session);

  final SSHSession _session;

  @override
  Stream<List<int>> get stdout => _session.stdout;

  @override
  Stream<List<int>> get stderr => _session.stderr;

  @override
  Future<int?> get exited => _session.done.then((_) => _session.exitCode);

  @override
  void write(Uint8List data) => _session.stdin.add(data);

  @override
  Future<void> closeStdin() => _session.stdin.close();

  @override
  void kill() => _session.close();
}

/// 릴레이 endpoint의 stdout/stdin을 dartssh2 [SSHSocket]으로 감싼다.
///
/// [firstData]는 대상이 보낸 첫 바이트가 도착하면 완료된다. 그 바이트는
/// 버퍼에 남아 있다가 [stream] 구독자(SSHClient)에게 그대로 전달된다.
class RelaySshSocket implements SSHSocket {
  RelaySshSocket._(this._endpoint) {
    _stdoutSubscription = _endpoint.stdout.listen(
      (data) {
        final bytes = data is Uint8List ? data : Uint8List.fromList(data);
        if (!_firstData.isCompleted) _firstData.complete();
        if (!_output.isClosed) _output.add(bytes);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_output.isClosed) _output.addError(error, stackTrace);
      },
      onDone: () => unawaited(close()),
      cancelOnError: false,
    );
    _stderrSubscription = _endpoint.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_endpoint.recordStderr);
    _inputSubscription = _input.stream.listen((data) {
      if (_closed) return;
      _endpoint.write(data is Uint8List ? data : Uint8List.fromList(data));
    }, onDone: () => unawaited(close()));
    unawaited(
      _endpoint.exited.then((_) => close(), onError: (Object _) => close()),
    );
  }

  final _RelayEndpoint _endpoint;
  final _output = StreamController<Uint8List>();
  final _input = StreamController<List<int>>();
  final _firstData = Completer<void>();
  final _done = Completer<void>();
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  late final StreamSubscription<List<int>> _inputSubscription;
  var _closed = false;

  Future<void> get firstData => _firstData.future;

  @override
  Stream<Uint8List> get stream => _output.stream;

  @override
  StreamSink<List<int>> get sink => _input.sink;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (_closed) return _done.future;
    _closed = true;
    try {
      await _endpoint.closeStdin();
    } catch (_) {
      // 이미 끝난 프로세스/채널이면 무시한다.
    }
    _endpoint.kill();
    await _inputSubscription.cancel();
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    // 아직 아무도 구독하지 않은 컨트롤러의 close()는 구독자가 생길 때까지
    // 완료되지 않으므로 기다리지 않는다.
    if (!_output.isClosed) unawaited(_output.close());
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void destroy() => unawaited(close());

  @override
  Future<void> flush() async {}
}
