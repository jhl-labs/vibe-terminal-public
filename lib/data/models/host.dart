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

/// Kubernetes 경유 SSH에서 `kubectl`을 실행하는 위치.
///
/// Pod 안에서 최종 대상까지 TCP를 중계하므로, kubectl과 클러스터 자격증명이
/// 있는 곳이면 어디든 게이트웨이가 될 수 있다.
enum KubernetesGateway {
  /// 이 기기에서 kubectl을 직접 실행한다.
  local,

  /// Windows의 기본 WSL 배포판 안에서 kubectl을 실행한다.
  wsl,

  /// 저장된 SSH 호스트에 접속한 뒤 그곳에서 kubectl을 실행한다.
  sshHost,
}

extension KubernetesGatewayLabel on KubernetesGateway {
  String get label => switch (this) {
    KubernetesGateway.local => '이 기기',
    KubernetesGateway.wsl => 'WSL',
    KubernetesGateway.sshHost => 'SSH 호스트',
  };
}

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

    /// 인증 원본 Identity. null이면 로컬 셸이거나 아직 Identity로 옮기지
    /// 않은 호스트라 username/authType/credentialRef를 그대로 쓴다.
    String? identityId,
    String? jumpHostId,

    /// kubectl을 실행할 위치. [KubernetesGateway.sshHost]면
    /// [kubernetesGatewayHostId]의 SSH 프로필을 먼저 연결한다.
    @Default(KubernetesGateway.local) KubernetesGateway kubernetesGateway,
    String? kubernetesGatewayHostId,
    String? kubernetesContext,
    String? kubernetesNamespace,

    /// 릴레이를 실행할 Pod. `pod-name` 또는 `deployment/name`처럼
    /// `kubectl exec`가 받는 리소스 표기를 그대로 쓴다.
    String? kubernetesResource,
    String? kubernetesContainer,
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
      final route = kubernetesPodLabel;
      return route.isEmpty
          ? '$username@$hostname:$port'
          : '$username@$hostname:$port · $route 경유';
    }
    return '$username@$hostname:$port';
  }

  /// `namespace/pod` 형태의 릴레이 Pod 표기. 비어 있으면 빈 문자열.
  String get kubernetesPodLabel {
    final resource = kubernetesResource?.trim();
    final namespace = kubernetesNamespace?.trim();
    return [
      if (namespace != null && namespace.isNotEmpty) namespace,
      if (resource != null && resource.isNotEmpty) resource,
    ].join('/');
  }
}
