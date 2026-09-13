import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'host.freezed.dart';

enum HostConnectionType { ssh, localShell, kubernetesSsh }

enum HostAuthType { password, publicKey, keyboardInteractive }

enum LocalShellType { powershell, cmd, wsl }

/// 원격 셸 프로세스의 수명 정책.
///
/// [tmux]는 SSH 연결과 별개로 원격 작업을 유지하고, 재연결 시 같은 작업에
/// 다시 붙는다. 전송 방식(SSH)과 세션 수명 정책을 분리해 이후 다른 지속성
/// 백엔드를 추가해도 Host/SessionManager가 구체 구현에 묶이지 않게 한다.
enum RemoteSessionPersistence { none, tmux }

extension HostConnectionTypeLabel on HostConnectionType {
  String get label => switch (this) {
    HostConnectionType.ssh => 'SSH',
    HostConnectionType.localShell => 'Local',
    HostConnectionType.kubernetesSsh => 'Kubernetes SSH',
  };
}

extension HostAuthTypeLabel on HostAuthType {
  String get label => switch (this) {
    HostAuthType.password => '비밀번호',
    HostAuthType.publicKey => '공개키',
    HostAuthType.keyboardInteractive => '키보드 인터랙티브',
  };
}

extension LocalShellTypeLabel on LocalShellType {
  String get label => switch (this) {
    LocalShellType.powershell => 'PowerShell',
    LocalShellType.cmd => 'Command Prompt',
    LocalShellType.wsl => 'WSL',
  };

  List<String> get arguments => switch (this) {
    LocalShellType.powershell => const ['-NoLogo'],
    LocalShellType.cmd => const [],
    LocalShellType.wsl => const [],
  };
}

@freezed
abstract class Host with _$Host {
  const Host._();

  const factory Host({
    required String id,
    required String alias,
    required String hostname,
    @Default(22) int port,
    required String username,
    @Default(HostConnectionType.ssh) HostConnectionType connectionType,
    @Default(HostAuthType.password) HostAuthType authType,
    @Default(LocalShellType.powershell) LocalShellType localShellType,
    String? workingDirectory,
    String? credentialRef,
    String? jumpHostId,
    String? kubernetesContext,
    String? kubernetesNamespace,
    String? kubernetesResource,
    @Default(22) int kubernetesSshPort,
    String? kubernetesUsername,
    @Default(HostAuthType.password) HostAuthType kubernetesAuthType,
    String? kubernetesCredentialRef,
    // 런타임 전용 SSH 접속 주소. kubectl이 만든 임시 로컬 포트로 연결하되
    // 호스트키는 안정적인 Kubernetes 리소스 식별자로 검증하기 위해 사용한다.
    String? transportHostname,
    int? transportPort,
    @Default(RemoteSessionPersistence.none)
    RemoteSessionPersistence remoteSessionPersistence,

    /// 공개키 인증에 사용한 키를 원격 세션의 SSH agent 요청에도 제공한다.
    /// 원격 프로세스에 서명 권한을 위임하는 민감 기능이므로 기본값은 꺼져 있다.
    @Default(false) bool agentForwarding,
    @Default(false) bool x11Forwarding,
    // 세션 연결 직후 자동으로 실행할 명령/스크립트(여러 줄 가능). 비우면 미실행.
    String? startupScript,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Host;

  bool get isLocalShell => connectionType == HostConnectionType.localShell;

  bool get isKubernetesSsh =>
      connectionType == HostConnectionType.kubernetesSsh;

  bool get keepsRemoteSession =>
      !isLocalShell &&
      remoteSessionPersistence == RemoteSessionPersistence.tmux;

  String get connectionLabel => switch (connectionType) {
    HostConnectionType.ssh => 'ssh',
    HostConnectionType.localShell => 'local',
    HostConnectionType.kubernetesSsh => 'kubernetes-ssh',
  };

  // 셸 종류(PowerShell/WSL 등)는 Windows에서만 의미가 있다.
  // 그 외 플랫폼에서는 기기의 기본 셸($SHELL)을 쓰므로 중립 라벨을 보여준다.
  String get localShellLabel =>
      Platform.isWindows ? localShellType.label : '로컬 셸';

  String get endpointLabel {
    if (isLocalShell) {
      final directory = workingDirectory?.trim();
      if (directory == null || directory.isEmpty) {
        return localShellLabel;
      }
      return '$localShellLabel · $directory';
    }
    if (isKubernetesSsh) {
      final resource = kubernetesResource?.trim();
      final namespace = kubernetesNamespace?.trim();
      final route = [
        if (namespace != null && namespace.isNotEmpty) namespace,
        if (resource != null && resource.isNotEmpty) resource,
      ].join('/');
      return route.isEmpty
          ? '$username@$hostname:$port'
          : '$username@$hostname:$port · $route 경유';
    }
    return '$username@$hostname:$port';
  }
}
