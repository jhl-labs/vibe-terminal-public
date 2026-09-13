import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/result.dart';

class KubernetesPortForwardSpec {
  const KubernetesPortForwardSpec({
    required this.namespace,
    required this.resource,
    required this.remotePort,
    this.context,
  });

  final String? context;
  final String namespace;
  final String resource;
  final int remotePort;
}

abstract interface class KubernetesPortForwardHandle {
  String get localHost;
  int get localPort;
  Future<void> close();
}

abstract interface class KubernetesPortForwardService {
  Future<Result<KubernetesPortForwardHandle>> start(
    KubernetesPortForwardSpec spec,
  );
}

typedef KubectlProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

class ProcessKubernetesPortForwardService
    implements KubernetesPortForwardService {
  ProcessKubernetesPortForwardService({
    KubectlProcessStarter? processStarter,
    this.readyTimeout = const Duration(seconds: 20),
  }) : _processStarter = processStarter ?? _startProcess;

  final KubectlProcessStarter _processStarter;
  final Duration readyTimeout;

  static Future<Process> _startProcess(
    String executable,
    List<String> arguments,
  ) => Process.start(executable, arguments, runInShell: false);

  @override
  Future<Result<KubernetesPortForwardHandle>> start(
    KubernetesPortForwardSpec spec,
  ) async {
    final validation = _validate(spec);
    if (validation != null) return Err(KubernetesFailure(validation));
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const Err(KubernetesFailure('Kubernetes SSH 연결은 데스크톱에서만 지원합니다.'));
    }

    Process? process;
    final messages = <String>[];
    final ready = Completer<int>();
    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;
    try {
      final args = <String>[
        if (spec.context?.trim().isNotEmpty ?? false) ...[
          '--context',
          spec.context!.trim(),
        ],
        '--namespace',
        spec.namespace.trim(),
        'port-forward',
        '--address',
        '127.0.0.1',
        spec.resource.trim(),
        ':${spec.remotePort}',
      ];
      process = await _processStarter('kubectl', args);

      void inspectLine(String line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          messages.add(trimmed);
          if (messages.length > 12) messages.removeAt(0);
          debugPrint('[kubectl port-forward] $trimmed');
        }
        final port = parseKubectlForwardedPort(line);
        if (port != null && !ready.isCompleted) ready.complete(port);
      }

      stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(inspectLine);
      stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(inspectLine);
      unawaited(
        process.exitCode.then((code) {
          if (!ready.isCompleted) {
            final detail = messages.isEmpty
                ? 'kubectl이 준비되기 전에 종료되었습니다 (exit $code).'
                : messages.join('\n');
            ready.completeError(StateError(detail));
          }
        }),
      );

      final localPort = await ready.future.timeout(readyTimeout);
      return Ok(
        _ProcessKubernetesPortForwardHandle(
          process,
          stdoutSubscription,
          stderrSubscription,
          localPort: localPort,
        ),
      );
    } on ProcessException catch (error) {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      process?.kill();
      return Err(
        KubernetesFailure(
          'kubectl을 실행할 수 없습니다. 설치 여부와 PATH를 확인하세요: '
          '${error.message}',
        ),
      );
    } on TimeoutException {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      process?.kill();
      return const Err(
        KubernetesFailure('kubectl port-forward가 제한 시간 안에 준비되지 않았습니다.'),
      );
    } catch (error) {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      process?.kill();
      return Err(KubernetesFailure(_errorMessage(error)));
    }
  }

  String? _validate(KubernetesPortForwardSpec spec) {
    if (spec.namespace.trim().isEmpty) return 'Kubernetes namespace를 입력하세요.';
    if (spec.resource.trim().isEmpty) return 'Kubernetes 리소스를 입력하세요.';
    if (spec.remotePort <= 0 || spec.remotePort > 65535) {
      return 'Pod SSH 포트는 1~65535 사이여야 합니다.';
    }
    return null;
  }

  static String _errorMessage(Object error) {
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }
}

int? parseKubectlForwardedPort(String line) {
  final match = RegExp(
    r'Forwarding from (?:127\.0\.0\.1|\[::1\]):(\d+)\s+->\s+\d+',
  ).firstMatch(line);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

class _ProcessKubernetesPortForwardHandle
    implements KubernetesPortForwardHandle {
  _ProcessKubernetesPortForwardHandle(
    this._process,
    this._stdoutSubscription,
    this._stderrSubscription, {
    required this.localPort,
  });

  final Process _process;
  final StreamSubscription<String> _stdoutSubscription;
  final StreamSubscription<String> _stderrSubscription;
  var _closed = false;

  @override
  String get localHost => '127.0.0.1';

  @override
  final int localPort;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _process.kill();
    try {
      await _process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
    } finally {
      await _stdoutSubscription.cancel();
      await _stderrSubscription.cancel();
    }
  }
}
