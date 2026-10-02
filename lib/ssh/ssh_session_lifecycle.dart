/// SSH 세션 출력이 끝난 원인을 구분한다.
enum SshSessionEnd { processExited, transportLost, attachmentFailed }

/// exit-status를 주지 않는 서버도 있으므로 채널 종료 시 SSH 전송 상태를
/// 함께 확인한다. 채널만 닫히고 연결이 살아 있으면 원격 셸은 끝난 것이다.
SshSessionEnd classifySshSessionEnd({
  required int? exitCode,
  required bool hasExitSignal,
  required bool transportClosed,
  bool isPersistent = false,
}) {
  // tmux attach is a client of the persistent job, not the job itself.
  // A failed client must leave the tab available for diagnosis and retry.
  if (isPersistent && (hasExitSignal || (exitCode != null && exitCode != 0))) {
    return SshSessionEnd.attachmentFailed;
  }
  if (isPersistent && exitCode == null && !transportClosed) {
    return SshSessionEnd.attachmentFailed;
  }
  if (exitCode != null || hasExitSignal || !transportClosed) {
    return SshSessionEnd.processExited;
  }
  return SshSessionEnd.transportLost;
}
