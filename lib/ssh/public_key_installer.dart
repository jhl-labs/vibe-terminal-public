import 'dart:async';
import 'dart:convert';

import '../core/result.dart';
import '../data/models/host.dart';
import '../data/models/ssh_key.dart';
import '../data/repositories/host_repository.dart';
import '../data/repositories/identity_repository.dart';
import '../data/repositories/ssh_key_repository.dart';
import 'jump_chain.dart';
import 'ssh_service.dart';

/// 공개키 등록이 실패한 단계. fallback 안내 문구를 고르는 기준이 된다.
enum PublicKeyInstallStage { connect, command, verify }

sealed class PublicKeyInstallResult {
  const PublicKeyInstallResult();
}

class PublicKeyInstalled extends PublicKeyInstallResult {
  const PublicKeyInstalled();
}

class PublicKeyInstallFailed extends PublicKeyInstallResult {
  const PublicKeyInstallFailed(this.stage, this.message);
  final PublicKeyInstallStage stage;
  final String message;
}

/// 비밀번호로 한 번 접속해 공개키를 `~/.ssh/authorized_keys`에 넣고, 같은 키로
/// 재접속이 되는지 확인한 뒤 호스트 인증을 공개키로 바꾼다(ssh-copy-id와 같다).
class PublicKeyInstaller {
  PublicKeyInstaller({
    required this.sshService,
    required this.hostRepository,
    required this.identityRepository,
    required this.sshKeyRepository,
  });

  final SshService sshService;
  final HostRepository hostRepository;
  final IdentityRepository identityRepository;
  final SshKeyRepository sshKeyRepository;

  static String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// authorized_keys에 [publicKeyLine]을 한 번만 추가하는 셸 명령.
  /// 이미 같은 줄이 있으면 건드리지 않고, 권한은 ssh가 요구하는 대로 맞춘다.
  static String authorizedKeysCommand(String publicKeyLine) {
    final quoted = _shellQuote(publicKeyLine.trim());
    return 'umask 077; mkdir -p ~/.ssh; '
        'grep -qF $quoted ~/.ssh/authorized_keys 2>/dev/null '
        '|| printf \'%s\\n\' $quoted >> ~/.ssh/authorized_keys; '
        'chmod 600 ~/.ssh/authorized_keys';
  }

  /// 데스크톱 fallback 안내용 ssh-copy-id 예시.
  static String sshCopyIdHint({
    required String username,
    required String hostname,
    required int port,
  }) => 'ssh-copy-id -p $port -i ~/.ssh/<키파일>.pub $username@$hostname';

  /// 원격 authorized_keys 명령을 기다리는 최대 시간.
  static const commandTimeout = Duration(seconds: 30);

  Future<PublicKeyInstallResult> install({
    required Host host,
    required SshKey key,
    required String password,
    required HostKeyApproval onHostKey,
    KeyboardInteractivePrompt? onKeyboardInteractive,
  }) async {
    // 예기치 않은 예외(SecureStore PlatformException, DB 쓰기 실패 등)도
    // 진행 중이던 단계의 실패로 돌려보내 UI가 항상 종료 상태를 받게 한다.
    var stage = PublicKeyInstallStage.connect;
    try {
      return await _install(
        host: host,
        key: key,
        password: password,
        onHostKey: onHostKey,
        onKeyboardInteractive: onKeyboardInteractive,
        onStage: (next) => stage = next,
      );
    } on TimeoutException {
      return const PublicKeyInstallFailed(
        PublicKeyInstallStage.command,
        '원격 명령이 30초 안에 끝나지 않았습니다',
      );
    } catch (e) {
      return PublicKeyInstallFailed(stage, e.toString());
    }
  }

  Future<PublicKeyInstallResult> _install({
    required Host host,
    required SshKey key,
    required String password,
    required HostKeyApproval onHostKey,
    required KeyboardInteractivePrompt? onKeyboardInteractive,
    required void Function(PublicKeyInstallStage) onStage,
  }) async {
    onStage(PublicKeyInstallStage.connect);
    final List<Host> jumpHosts;
    switch (await resolveJumpChain(host, hostRepository.getById)) {
      case Ok(:final value):
        jumpHosts = value;
      case Err(:final failure):
        return PublicKeyInstallFailed(
          PublicKeyInstallStage.connect,
          failure.message,
        );
    }

    // 1) 비밀번호로 접속. 저장된 자격증명을 건드리지 않도록 임시 ref를 쓰고,
    //    성공/실패와 무관하게 finally에서 지운다.
    final tempRef = 'install-${DateTime.now().microsecondsSinceEpoch}';
    await sshService.secureStore.writeSecret(tempRef, password);
    final passwordHost = host.copyWith(
      authType: HostAuthType.password,
      credentialRef: tempRef,
    );
    try {
      final SshClientConnection connection;
      switch (await sshService.connectClient(
        host: passwordHost,
        onHostKey: onHostKey,
        onKeyboardInteractive: onKeyboardInteractive,
        jumpHosts: jumpHosts,
      )) {
        case Ok(:final value):
          connection = value;
        case Err(:final failure):
          return PublicKeyInstallFailed(
            PublicKeyInstallStage.connect,
            failure.message,
          );
      }

      // 2) authorized_keys 갱신.
      onStage(PublicKeyInstallStage.command);
      try {
        final session = await connection.client.execute(
          authorizedKeysCommand(key.publicKey),
        );
        // stdout도 소비해야 채널이 정상적으로 닫힌다. 셸이 멈추면 30초 뒤
        // TimeoutException으로 빠져나온다(바깥에서 command 실패로 변환).
        final outputs = await Future.wait([
          utf8.decodeStream(session.stdout),
          utf8.decodeStream(session.stderr),
          session.done,
        ]).timeout(commandTimeout);
        final stderr = (outputs[1] as String).trim();
        if (session.exitCode != 0) {
          return PublicKeyInstallFailed(
            PublicKeyInstallStage.command,
            stderr.isEmpty ? 'exit ${session.exitCode}' : stderr,
          );
        }
      } finally {
        await connection.close();
      }
    } finally {
      // 임시 비밀 삭제 실패가 본래 결과를 가리지 않도록 삼킨다. 임시 ref는
      // 이 흐름 밖에서 참조되지 않으므로 남아도 접속에 쓰이지 않는다.
      try {
        await sshService.secureStore.deleteSecret(tempRef);
      } catch (_) {}
    }

    // 3) 같은 키로 재접속 검증.
    onStage(PublicKeyInstallStage.verify);
    final keyHost = host.copyWith(
      authType: HostAuthType.publicKey,
      credentialRef: key.secretRef,
    );
    switch (await sshService.connectClient(
      host: keyHost,
      onHostKey: onHostKey,
      jumpHosts: jumpHosts,
    )) {
      case Ok(:final value):
        await value.close();
      case Err(:final failure):
        return PublicKeyInstallFailed(
          PublicKeyInstallStage.verify,
          failure.message,
        );
    }

    // 4) 호스트 인증을 공개키로 전환.
    await _switchHostToKey(host, key);
    return const PublicKeyInstalled();
  }

  Future<void> _switchHostToKey(Host host, SshKey key) async {
    final scopedId = 'host-${host.id}';
    final identityId = host.identityId;
    final identity = identityId == null
        ? null
        : await identityRepository.getById(identityId);
    if (identity != null && identity.id == scopedId) {
      // 전용 Identity는 제자리에서 공개키로 바꾼다. 저장소가 옛 비밀번호 비밀을
      // 정리하지 않는 경우를 대비해 여기서도 지운다.
      final oldSecret = identity.authType == HostAuthType.password
          ? identity.secretRef
          : null;
      await identityRepository.upsert(
        identity.copyWith(
          authType: HostAuthType.publicKey,
          keyId: key.id,
          secretRef: null,
          updatedAt: DateTime.now(),
        ),
      );
      if (oldSecret != null) {
        await sshService.secureStore.deleteSecret(oldSecret);
      }
      return;
    }
    // 공유 Identity를 쓰던 호스트는 전용 Identity로 갈아탄다(공유 쪽은 그대로).
    // identityId를 null로 넘기면 저장소가 host-<id> Identity를 만들어 연결한다.
    await hostRepository.upsert(
      host.copyWith(
        identityId: null,
        authType: HostAuthType.publicKey,
        credentialRef: key.secretRef,
        updatedAt: DateTime.now(),
      ),
    );
  }
}
