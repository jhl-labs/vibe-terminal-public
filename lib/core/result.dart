sealed class Failure {
  const Failure(this.message);
  final String message;
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class HostKeyMismatchFailure extends Failure {
  const HostKeyMismatchFailure(this.expected, this.actual)
    : super('host key mismatch');
  final String expected;
  final String actual;
}

class JumpChainFailure extends Failure {
  const JumpChainFailure(super.message);
}

class KubernetesFailure extends Failure {
  const KubernetesFailure(super.message);
}

class RemoteSessionFailure extends Failure {
  const RemoteSessionFailure(super.message);
}

/// 원격 작업 유지에 필요한 실행 파일이 서버에 없음을 나타낸다.
///
/// 일반적인 tmux 준비 실패와 구분해, 이 경우에만 일반 SSH 셸로 안전하게
/// 폴백할 수 있도록 타입으로 표현한다.
class RemoteSessionToolMissingFailure extends RemoteSessionFailure {
  const RemoteSessionToolMissingFailure({
    required this.tool,
    required String message,
  }) : super(message);

  final String tool;
}

class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

class LocalShellMissingExecutableFailure extends Failure {
  const LocalShellMissingExecutableFailure({
    required this.shellLabel,
    required this.executable,
    required this.guidance,
  }) : super('로컬 셸 실행 파일을 찾지 못했습니다.');

  final String shellLabel;
  final String executable;
  final String guidance;
}

/// 로컬 daemon 프로세스가 살아 있지만 응답하지 않는다.
///
/// 이 데몬이 잠금을 쥐고 있어 새 데몬도 뜰 수 없으므로, 사용자가 확인한 뒤
/// 데몬을 강제로 재시작해야 복구된다.
class LocalDaemonUnresponsiveFailure extends Failure {
  const LocalDaemonUnresponsiveFailure(this.pid)
    : super('로컬 daemon이 응답하지 않습니다.');

  final int pid;
}

sealed class Result<T> {
  const Result();
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

extension ResultX<T> on Result<T> {
  bool get isOk => this is Ok<T>;
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };
}
