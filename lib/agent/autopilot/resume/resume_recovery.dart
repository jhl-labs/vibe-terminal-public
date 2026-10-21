import '../../agent_launcher.dart';
import '../../agent_native_session.dart';
import 'resume_prompts.dart';
import '../autopilot_state.dart';

/// 중단으로 판정된 세션을 어떻게 이어갈지. 순수 값이라 실행기와 분리해 검증한다.
class ResumeRecoveryPlan {
  const ResumeRecoveryPlan({
    required this.relaunchCommand,
    required this.prompt,
  });

  /// Agent 프로세스가 죽었을 때 먼저 셸에 제출할 재실행 명령. TUI가 살아 있으면 null.
  final String? relaunchCommand;

  /// TUI 입력창에 넣을 재개 지시.
  final String prompt;

  bool get needsRelaunch => relaunchCommand != null;
}

/// 판정 결과와 CLI 종류로 복구 계획을 만든다.
///
/// native 대화 ID를 알면 그 대화를 지정해 재실행하고, 모르면 각 CLI의 "마지막
/// 대화 이어가기" 옵션을 쓴다. 프로세스 상태를 모르면(unknown) 프로세스를 살아
/// 있는 것으로 보고 프롬프트만 보낸다 — 잘못 재실행하면 살아 있는 TUI 입력창에
/// 명령줄이 들어가 버리는데, 잘못 프롬프트만 보내면 셸이 무시할 뿐이라 덜 위험하다.
ResumeRecoveryPlan planResumeRecovery({
  required AgentCli cli,
  required ResumeVerdict verdict,
  required int attempt,
  String? nativeSessionId,
  String? lastPrompt,
}) {
  final prompt = ResumePrompts.continuation(
    reason: verdict.reason,
    attempt: attempt,
    lastPrompt: lastPrompt,
  );
  if (verdict.process != ResumeProcess.exited) {
    return ResumeRecoveryPlan(relaunchCommand: null, prompt: prompt);
  }
  return ResumeRecoveryPlan(
    relaunchCommand: resumeRelaunchCommand(cli, nativeSessionId),
    prompt: prompt,
  );
}

/// 죽은 Agent를 같은 대화로 다시 띄우는 셸 명령.
String resumeRelaunchCommand(AgentCli cli, String? nativeSessionId) {
  final id = nativeSessionId?.trim();
  if (id != null && id.isNotEmpty && isValidNativeAgentSessionId(id)) {
    return [
      cli.command,
      ...nativeAgentResumeArguments(cli, id, const []),
    ].join(' ');
  }
  return switch (cli) {
    AgentCli.opencode => 'opencode -c',
    AgentCli.claude => 'claude --continue',
    AgentCli.codex => 'codex resume --last',
  };
}
