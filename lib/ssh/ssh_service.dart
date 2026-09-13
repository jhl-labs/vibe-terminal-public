import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/result.dart';
import '../data/models/host.dart';
import '../security/host_key_store.dart';
import '../security/secure_store.dart';
import '../terminal/terminal_session_handle.dart';
import 'ssh_credentials.dart';
import 'remote_terminal_launcher.dart';

/// dartssh2가 onVerifyHostKey 콜백에서 제공하는 fingerprint 바이트를
/// `SHA256:<base64-no-padding>` 형식 문자열로 변환한다.
String _fpBytesToString(Uint8List fpBytes) => utf8.decode(fpBytes);

/// 호스트키 승인 콜백. jump 체인에서 홉마다 호출되므로 어느 호스트의 키인지
/// 알 수 있도록 [hostAlias]를 함께 전달한다.
typedef HostKeyApproval =
    Future<bool> Function(
      String hostAlias,
      String keyType,
      String fingerprint,
      HostKeyVerdict verdict,
    );

/// keyboard-interactive 인증 요청을 사용자 UI로 전달한다.
///
/// null은 사용자가 취소했거나 현재 UI에서 응답할 수 없음을 뜻한다. 응답은
/// 메모리에서 한 번 사용하고 저장하지 않는다.
class KeyboardInteractiveRequest {
  const KeyboardInteractiveRequest({
    required this.name,
    required this.instruction,
    required this.prompts,
  });

  final String name;
  final String instruction;
  final List<KeyboardInteractiveQuestion> prompts;
}

class KeyboardInteractiveQuestion {
  const KeyboardInteractiveQuestion({required this.text, required this.echo});

  final String text;
  final bool echo;
}

typedef KeyboardInteractivePrompt =
    Future<List<String>?> Function(
      String hostAlias,
      KeyboardInteractiveRequest request,
    );

/// PTY 세션 핸들. TerminalEngine/TerminalPage가 소비한다.
/// 체인 중간 홉의 실패에 "어느 홉이었는지"를 붙인다.
///
/// 3홉 체인에서 그냥 "인증 실패"만 보이면 사용자는 어느 서버 이야기인지 알 수
/// 없다. 다만 호스트키 불일치는 UI가 지문 비교 화면으로 분기하므로 타입을
/// 그대로 둔다.
Failure labelJumpHopFailure(Host hop, Failure failure) => switch (failure) {
  HostKeyMismatchFailure() => failure,
  _ => JumpChainFailure('jump 호스트 ${hop.alias}: ${failure.message}'),
};

class SshSessionHandle implements TerminalSessionHandle {
  SshSessionHandle._(
    this._client,
    this._session,
    this._jumpClients, {
    this.persistentSessionName,
    this.resumedPersistentSession = false,
    this.fellBackToDirectSsh = false,
  }) : _output = _sessionOutput(_session);

  final SSHClient _client;
  final SSHSession _session;

  final Stream<List<int>> _output;

  /// null이 아니면 앱 전용 tmux 서버의 세션에 붙어 있다.
  final String? persistentSessionName;

  /// 이번 연결에서 이미 실행 중이던 원격 작업에 다시 붙었는지 여부.
  final bool resumedPersistentSession;

  /// 작업 이어가기를 요청했지만 tmux가 없어 일반 SSH 셸로 연결했는지 여부.
  final bool fellBackToDirectSsh;

  bool _remoteProcessExited = false;

  bool get isPersistent => persistentSessionName != null;

  /// SSH 전송 단절이 아니라 원격 셸/tmux client가 종료 코드를 보고하고 끝났는지.
  bool get remoteProcessExited => _remoteProcessExited;

  /// 이 세션이 jump 체인을 거쳐 열렸다면, 거쳐 온 중간 jump 클라이언트들
  /// (바깥쪽 먼저). 세션 종료 시 함께 닫아 리소스 누수를 막는다.
  final List<SSHClient> _jumpClients;

  /// 같은 인증 연결 위에서 SFTP 등 추가 채널을 열기 위해 클라이언트를 노출한다.
  SSHClient get client => _client;

  /// 서버에서 수신한 출력 스트림.
  @override
  Stream<List<int>> get output => _output.transform(
    StreamTransformer.fromHandlers(
      handleDone: (sink) {
        _remoteProcessExited =
            _session.exitCode != null || _session.exitSignal != null;
        sink.close();
      },
    ),
  );

  static Stream<List<int>> _sessionOutput(SSHSession session) async* {
    await for (final data in session.stdout) {
      yield data;
    }
    // exit-status가 stdout 종료와 별도 SSH request로 도착할 수 있으므로 channel
    // 종료까지 기다린 뒤 소비자의 onDone을 호출한다.
    await session.done;
  }

  /// 서버 stdin에 데이터를 쓴다.
  @override
  void write(List<int> data) => _session.write(Uint8List.fromList(data));

  /// 터미널 크기를 변경한다.
  @override
  void resize(int cols, int rows) => _session.resizeTerminal(cols, rows);

  /// 세션과 클라이언트를 닫는다. jump 체인을 거쳤다면 안쪽(타깃에 가까운)
  /// 홉부터 바깥쪽으로 함께 닫는다.
  @override
  Future<void> close() async {
    _session.close();
    _client.close();
    for (final c in _jumpClients.reversed) {
      c.close();
    }
  }

  /// 사용자가 명시적으로 탭을 닫을 때 앱 전용 원격 작업도 종료한다.
  /// 네트워크 단절/앱 종료 경로에서는 호출하지 않아 tmux 세션이 남게 한다.
  Future<bool> terminatePersistentSession() async {
    final name = persistentSessionName;
    if (name == null) return true;
    try {
      final result = await _client
          .runWithResult(TmuxRemoteTerminalLauncher.killCommandFor(name))
          .timeout(const Duration(seconds: 5));
      return result.exitCode == 0 ||
          result.exitCode == TmuxRemoteTerminalLauncher.sessionNotFoundExitCode;
    } catch (_) {
      return false;
    }
  }
}

/// SSH 연결 서비스.
///
/// TOFU 정책(홉마다 독립 적용). 세 경우 모두 **인증 정보를 보내기 전에**,
/// 즉 onVerifyHostKey 콜백 안에서 결론을 낸다. 승인 전에 핸드셰이크를 끝내면
/// 첫 연결을 가로챈 MITM에게 비밀번호가 그대로 넘어가기 때문이다.
/// - 핀된 키와 일치 → 즉시 신뢰.
/// - 핀된 키와 불일치 → false 반환해 즉시 차단, HostKeyMismatchFailure.
/// - 알 수 없는 키 → onHostKey 콜백으로 사용자 승인을 await 한다.
///   승인 시 그 자리에서 pin 하고 계속, 거부 시 false 반환해 인증을 시작하지
///   않고 차단한다(OpenSSH가 known_hosts를 다루는 순서와 같다).
class SshService {
  SshService({
    required this.secureStore,
    required this.hostKeyStore,
    RemoteTerminalLauncher? directTerminalLauncher,
    RemoteTerminalLauncher? tmuxTerminalLauncher,
    RemoteTerminalFallbackPolicy? remoteTerminalFallbackPolicy,
  }) : directTerminalLauncher =
           directTerminalLauncher ?? const DirectRemoteTerminalLauncher(),
       tmuxTerminalLauncher =
           tmuxTerminalLauncher ?? const TmuxRemoteTerminalLauncher(),
       remoteTerminalFallbackPolicy =
           remoteTerminalFallbackPolicy ?? const RemoteTerminalFallbackPolicy();

  final SecureStore secureStore;
  final HostKeyStore hostKeyStore;
  final RemoteTerminalLauncher directTerminalLauncher;
  final RemoteTerminalLauncher tmuxTerminalLauncher;
  final RemoteTerminalFallbackPolicy remoteTerminalFallbackPolicy;

  /// [host]에 연결해 PTY 셸 세션을 연다.
  ///
  /// [jumpHosts]가 비어 있지 않으면 그 호스트들을 바깥쪽부터 차례로 중계해
  /// (폰 → jumpHosts[0] → … → host) 최종적으로 [host]의 셸을 연다.
  Future<Result<SshSessionHandle>> connect({
    required Host host,
    required int cols,
    required int rows,
    required HostKeyApproval onHostKey,
    KeyboardInteractivePrompt? onKeyboardInteractive,
    List<Host> jumpHosts = const [],
    String? remoteSessionId,
  }) async {
    final fullChain = [...jumpHosts, host];
    final established = <SSHClient>[];
    try {
      for (var i = 0; i < fullChain.length; i++) {
        final hop = fullChain[i];
        final SSHSocket socket;
        try {
          if (i == 0) {
            socket = await SSHSocket.connect(
              hop.transportHostname ?? hop.hostname,
              hop.transportPort ?? hop.port,
              timeout: const Duration(seconds: 15),
            );
          } else {
            // 직전 홉의 SSH 연결 위에서 다음 홉으로 TCP를 중계한다.
            socket = await established[i - 1].forwardLocal(
              hop.hostname,
              hop.port,
            );
          }
        } catch (e) {
          await _closeAll(established);
          final message = '${hop.alias} 연결 실패: $e';
          return Err(
            i == fullChain.length - 1
                ? NetworkFailure(message)
                : JumpChainFailure('jump 호스트 $message'),
          );
        }

        final result = await _establishClient(
          host: hop,
          socket: socket,
          onHostKey: onHostKey,
          onKeyboardInteractive: onKeyboardInteractive,
        );
        switch (result) {
          case Ok(:final value):
            established.add(value);
          case Err(:final failure):
            await _closeAll(established);
            return Err(
              i == fullChain.length - 1
                  ? failure
                  : labelJumpHopFailure(hop, failure),
            );
        }
      }

      final targetClient = established.last;
      final pty = SSHPtyConfig(
        type: 'xterm-256color',
        width: cols,
        height: rows,
      );
      final launcher = host.keepsRemoteSession
          ? tmuxTerminalLauncher
          : directTerminalLauncher;
      var launchResult = await launcher.launch(
        client: targetClient,
        pty: pty,

        remoteSessionId: remoteSessionId,
      );
      var fellBackToDirectSsh = false;
      // tmux가 명시적으로 없는 경우에만 인증된 같은 SSH 연결에서 일반 셸을
      // 연다. tmux 준비/attach 실패는 원격 작업이 이미 생성됐을 수 있으므로
      // 폴백하면 중복 작업을 만들 위험이 있어 기존처럼 오류로 처리한다.
      if (host.keepsRemoteSession &&
          launchResult is Err<RemoteTerminalLaunch>) {
        final failure = launchResult.failure;
        if (remoteTerminalFallbackPolicy.shouldUseDirectSsh(failure)) {
          launchResult = await directTerminalLauncher.launch(
            client: targetClient,
            pty: pty,

            remoteSessionId: remoteSessionId,
          );
          fellBackToDirectSsh = launchResult is Ok<RemoteTerminalLaunch>;
        }
      }
      final RemoteTerminalLaunch launch;
      switch (launchResult) {
        case Ok(:final value):
          launch = value;
        case Err(:final failure):
          await _closeAll(established);
          return Err(failure);
      }
      final jumpClients = established.sublist(0, established.length - 1);
      return Ok(
        SshSessionHandle._(
          targetClient,
          launch.session,
          jumpClients,
          persistentSessionName: launch.persistentSessionName,
          resumedPersistentSession: launch.resumedPersistentSession,
          fellBackToDirectSsh: fellBackToDirectSsh,
        ),
      );
    } catch (e) {
      await _closeAll(established);
      return Err(UnknownFailure(e.toString()));
    }
  }

  Future<void> _closeAll(List<SSHClient> clients) async {
    for (final c in clients.reversed) {
      c.close();
    }
  }

  /// 단일 홉에 대해 호스트키 검증과 인증까지 마친 SSHClient를 반환한다.
  /// 셸은 열지 않는다. 실패 시 [socket]/client를 닫고 Err를 반환한다.
  Future<Result<SSHClient>> _establishClient({
    required Host host,
    required SSHSocket socket,
    required HostKeyApproval onHostKey,
    KeyboardInteractivePrompt? onKeyboardInteractive,
  }) async {
    // client 생성 전 예외는 socket을, 생성 후 예외는 client를 닫기 위한 추적용.
    SSHClient? createdClient;
    try {
      final knownFp = await hostKeyStore.storedFingerprint(
        hostname: host.hostname,
        port: host.port,
      );

      String? presentedFp;
      bool? hostkeyPassed;
      // 핀된 키와 달라 막힌 경우와, 새 키를 사용자가 거부한 경우를 구분한다.
      var hostKeyRejectedByUser = false;

      String? password;
      List<SSHKeyPair>? identities;
      if (host.authType == HostAuthType.keyboardInteractive &&
          onKeyboardInteractive == null) {
        await socket.close();
        return const Err(AuthFailure('keyboard-interactive 응답 UI를 사용할 수 없습니다'));
      }
      if (host.credentialRef == null) {
        switch (host.authType) {
          case HostAuthType.password:
            break;
          case HostAuthType.publicKey:
            await socket.close();
            return const Err(AuthFailure('private key is missing'));
          case HostAuthType.keyboardInteractive:
            break;
        }
      }
      if (host.credentialRef != null) {
        final secret = await secureStore.readSecret(host.credentialRef!);
        switch (host.authType) {
          case HostAuthType.password:
            password = secret ?? '';
          case HostAuthType.publicKey:
            if (secret == null || secret.isEmpty) {
              await socket.close();
              return const Err(AuthFailure('private key is missing'));
            }
            try {
              final credential = SshCredentialPayload.publicKeyFromSecret(
                secret,
              );
              identities = SSHKeyPair.fromPem(
                credential.privateKeyPem,
                credential.passphrase,
              );
            } catch (e) {
              await socket.close();
              return Err(AuthFailure('invalid private key: $e'));
            }
          case HostAuthType.keyboardInteractive:
            break;
        }
      }

      final client = SSHClient(
        socket,
        username: host.username,
        identities: identities,
        agentHandler: host.agentForwarding && identities != null
            ? SSHKeyPairAgent(
                identities,
                comment: 'Vibe Terminal · ${host.alias}',
              )
            : null,
        keepAliveInterval: const Duration(seconds: 15),
        onPasswordRequest: host.authType == HostAuthType.password
            ? () => password ?? ''
            : null,
        onUserInfoRequest: host.authType == HostAuthType.keyboardInteractive
            ? (request) => onKeyboardInteractive!(
                host.alias,
                KeyboardInteractiveRequest(
                  name: request.name,
                  instruction: request.instruction,
                  prompts: [
                    for (final prompt in request.prompts)
                      KeyboardInteractiveQuestion(
                        text: prompt.promptText,
                        echo: prompt.echo,
                      ),
                  ],
                ),
              )
            : null,
        onVerifyHostKey: (String keyType, Uint8List fpBytes) async {
          final fp = _fpBytesToString(fpBytes);
          presentedFp = fp;

          if (knownFp != null) {
            final matches = fp == knownFp;
            hostkeyPassed = matches;
            return matches;
          }

          // 알 수 없는 키. 여기서 사용자 승인을 기다린다. 이 콜백이 완료되기
          // 전에는 dartssh2가 인증 단계로 넘어가지 않으므로, 거부하면 비밀번호
          // 나 공개키 서명이 서버로 전혀 나가지 않는다.
          bool approved;
          try {
            approved = await onHostKey(
              host.alias,
              keyType,
              fp,
              HostKeyVerdict.trustedNew,
            );
          } catch (_) {
            // 승인 UI가 사라졌거나 실패하면 신뢰하지 않는 쪽으로 판단한다.
            approved = false;
          }

          if (!approved) {
            hostkeyPassed = false;
            hostKeyRejectedByUser = true;
            return false;
          }

          // 승인 직후 핀한다. 이후 인증이 실패하더라도 사용자가 이 키를
          // 확인했다는 사실은 유지된다(OpenSSH known_hosts와 같은 시점).
          await hostKeyStore.pin(
            hostname: host.hostname,
            port: host.port,
            keyType: keyType,
            fingerprint: fp,
          );
          hostkeyPassed = true;
          return true;
        },
      );
      createdClient = client;

      try {
        await client.authenticated;
      } catch (e) {
        if (hostkeyPassed == false) {
          client.close();
          return _hostKeyFailure(
            rejectedByUser: hostKeyRejectedByUser,
            knownFp: knownFp,
            presentedFp: presentedFp,
          );
        }
        if (e is SSHAuthError) {
          client.close();
          return Err(AuthFailure(e.message));
        }
        if (e is SSHError) {
          client.close();
          return Err(NetworkFailure(e.toString()));
        }
        client.close();
        rethrow;
      }

      if (hostkeyPassed == false) {
        client.close();
        return _hostKeyFailure(
          rejectedByUser: hostKeyRejectedByUser,
          knownFp: knownFp,
          presentedFp: presentedFp,
        );
      }
      if (hostkeyPassed == null) {
        client.close();
        return const Err(UnknownFailure('host key was not verified'));
      }

      return Ok(client);
    } on SSHAuthError catch (e) {
      await _disposeHop(createdClient, socket);
      return Err(AuthFailure(e.message));
    } on SSHError catch (e) {
      await _disposeHop(createdClient, socket);
      return Err(NetworkFailure(e.toString()));
    } catch (e) {
      await _disposeHop(createdClient, socket);
      return Err(UnknownFailure(e.toString()));
    }
  }

  /// 호스트키 검증에서 막힌 이유를 실패 값으로 옮긴다. 사용자가 새 키를
  /// 거부한 것과, 핀된 키와 지문이 달라 차단된 것은 사용자에게 완전히 다른
  /// 의미이므로 구분한다.
  Result<SSHClient> _hostKeyFailure({
    required bool rejectedByUser,
    required String? knownFp,
    required String? presentedFp,
  }) {
    if (rejectedByUser) {
      return const Err(AuthFailure('host key rejected by user'));
    }
    if (knownFp != null && presentedFp != null) {
      return Err(HostKeyMismatchFailure(knownFp, presentedFp));
    }
    return const Err(UnknownFailure('host key verification failed'));
  }

  /// 홉 수립 실패 시 자원 정리. client가 생성됐으면 client를 닫고(소켓도 함께
  /// 닫힌다), 아직 없으면 socket을 직접 닫는다.
  Future<void> _disposeHop(SSHClient? client, SSHSocket socket) async {
    if (client != null) {
      client.close();
    } else {
      await socket.close();
    }
  }
}
