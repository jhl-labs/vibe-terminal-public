import 'agent_launcher.dart';

/// native 대화 참조는 실행 파일/경로가 아닌 opaque ID만 허용한다.
bool isValidNativeAgentSessionId(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,159}$').hasMatch(value);

List<String> nativeAgentResumeArguments(
  AgentCli cli,
  String id,
  List<String> arguments,
) {
  if (!isValidNativeAgentSessionId(id)) {
    throw ArgumentError('Agent 대화 ID가 올바르지 않습니다.');
  }
  const conflicting = {
    'resume',
    '--resume',
    '--session',
    '--session-id',
    '--continue',
    '-c',
    '-s',
  };
  if (arguments.any((arg) => conflicting.contains(arg.split('=').first))) {
    throw StateError('저장된 실행 인자의 resume/session 옵션을 제거한 뒤 대화를 재개하세요.');
  }
  return switch (cli) {
    AgentCli.codex => ['resume', id, ...arguments],
    AgentCli.claude => [...arguments, '--resume', id],
    AgentCli.opencode => [...arguments, '--session', id],
  };
}
