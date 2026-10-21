/// 자동 재개 판정에 쓰는 LLM 프롬프트와 재개 시 Agent에 보내는 문구.
///
/// 판정 LLM은 Agent 자신의 LLM과 별개 서버(앱 AI 설정)다. Agent 쪽 서버가
/// 불안정한 상황이 전제이므로 판정 서버가 분리돼 있어야 의미가 있다.
class ResumePrompts {
  const ResumePrompts._();

  /// 화면을 얼마나 보여 줄지. 상태 표시줄은 하단에 있으므로 꼬리만 준다.
  static const screenLineLimit = 120;

  static const judgeSystem = '''
당신은 터미널 화면만 보고 CLI 코딩 에이전트(OpenCode, Claude Code, Codex 등)의
마지막 턴이 어떻게 끝났는지 판정하는 감시자입니다. 에이전트에게 지시하지 않고,
사람 대신 "이어서 계속할지"만 결정합니다.

status를 다음 중 하나로 고르세요.
- completed: 턴이 정상적으로 끝났다. 근거: 결과·요약 보고, 다음 행동 제안, 질문으로 끝남,
  입력창이 비어 있고 마지막 응답이 완결된 문장.
- interrupted: 서버·네트워크 문제 등으로 턴이 중간에 끊겼다. 근거: 문장·코드 블록·도구 호출이
  중간에 잘림, 결과가 없는 tool call, 연결/타임아웃/5xx/rate limit 오류 문구, 요약 없이 끝남,
  에이전트 프로세스가 죽어 셸 프롬프트로 돌아감.
- waiting_user: 에이전트가 승인(y/n, allow, approve)이나 사용자의 답을 기다린다.
- working: 아직 작업 중이다(스피너, "esc to interrupt", 진행률).
- unknown: 확신할 수 없다.

process는 tui_alive(에이전트 화면이 살아 있음) / exited(셸 프롬프트로 돌아감) / unknown.

반드시 아래 JSON 객체 하나만 출력하세요. 코드 펜스·설명을 덧붙이지 마세요.
{"status":"completed|interrupted|waiting_user|working|unknown","confidence":0.0,"process":"tui_alive|exited|unknown","reason":"한 문장","evidence":"화면에 실제로 있는 한 줄을 그대로 인용"}

evidence는 화면 텍스트에서 글자 그대로 복사해야 합니다. 확신이 없으면 unknown과 낮은 confidence를 주세요.
''';

  static String judgeUser({
    required String screen,
    required Duration idleFor,
    required int attempt,
    String? lastPrompt,
  }) {
    final trimmedPrompt = lastPrompt?.trim();
    return [
      '출력이 멈춘 지 ${idleFor.inSeconds}초. 이번 작업에서 자동 재개 $attempt회 수행.',
      if (trimmedPrompt != null && trimmedPrompt.isNotEmpty)
        '마지막 사용자 지시(추정): ${_truncate(trimmedPrompt, 400)}',
      '',
      '=== 터미널 화면(마지막 $screenLineLimit줄, 스피너·경과시간 제거) ===',
      screen,
      '=== 화면 끝 ===',
    ].join('\n');
  }

  /// JSON 파싱 실패 시 한 번만 재요청한다.
  static String repair(String raw) =>
      '아래 답변은 JSON 객체 하나가 아니었습니다. 같은 판정을 JSON 객체 하나로만 다시 출력하세요.\n'
      '---\n${_truncate(raw, 1200)}\n---';

  /// 재개 시 입력창에 넣는 문구. 사용자가 정한 고정 문구다.
  static const continuationText = '계속 진행해';

  static String continuation({
    required String reason,
    required int attempt,
    String? lastPrompt,
  }) => continuationText;

  static String _truncate(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}...';
}
