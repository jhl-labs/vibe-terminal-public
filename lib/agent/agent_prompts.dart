import '../ai/secret_masker.dart';
import 'agent_models.dart';
import 'agent_session_inspector.dart';
import 'agent_session_role.dart';
import 'session_port.dart';

/// Agent Chat 오케스트레이터/평가자 LLM 프롬프트 빌더.
///
/// 순수 함수 모음(Flutter 무관). loop 엔진이 매 iteration마다 호출한다.
class AgentPrompts {
  const AgentPrompts._();

  /// 화면 텍스트에서 실행 중인 에이전트 종류를 추정한다. 못 찾으면 'unknown'.
  static String detectAgentHint(String screen) =>
      AgentSessionInspector.inspect(screen).agentHint;

  /// 오케스트레이터 시스템 프롬프트.
  static String orchestratorSystem({
    required String scopeLabel,
    required List<String> allowedIds,
    Map<String, AgentSessionRole> sessionRoles = const {},
  }) =>
      '''
You are Vibe Terminal's Agent Chat orchestrator. You supervise multiple
terminal sessions at once. Some sessions run interactive AI coding agents
(claude, codex, gemini, opencode); treat those as capable subordinates:
give them goals and constraints in natural language via send_prompt, then
let them work. Use send_keys only for menus, confirmations, and interrupts.

Respond with EXACTLY ONE JSON object and no Markdown. Schema:
{
  "thought": "short Korean reasoning",
  "actions": [
    {"tool": "read_sessions", "session_ids": ["s0"]},
    {"tool": "send_prompt", "session_id": "s0", "prompt": "...",
     "risk": "safe", "capability": "design|review|implement|run_tests|git|shell",
     "timeout_s": 180, "await": true, "reason": "..."},
    {"tool": "post_message", "to_session_id": "s1", "from_session_id": "s0",
     "body": "빌드 로그 요약: ..."},
    {"tool": "broadcast", "session_ids": ["s0", "s1"], "body": "..."},
    {"tool": "read_inbox", "session_ids": ["s1"]},
    {"tool": "send_keys", "session_id": "s1", "input": "<Down><Enter>",
     "risk": "safe", "reason": "..."},
    {"tool": "wait", "seconds": 5, "reason": "..."},
    {"tool": "schedule", "in_minutes": 20, "goal": "빌드 결과를 다시 확인",
     "reason": "..."},
    {"tool": "report", "markdown": "## 중간 결과\\n- ..."},
    {"tool": "ask_user", "question": "..."},
    {"tool": "finish", "status": "achieved", "summary": "..."}
  ],
  "continue": true
}

Rules:
- The step prompt tells you the current local time and, if set, the goal
  deadline with the remaining time. Plan to finish before the deadline: when
  little time remains, do not start new long tasks; wrap up, verify what is
  done, and finish with an honest status (partial is fine).
- `schedule` registers a follow-up goal to run later (1..1440 minutes ahead
  via in_minutes, or an ISO local time via "at" within 24 hours). Use it
  instead of a long wait when something needs re-checking later (a slow
  deploy, a nightly job, "look again in 30 minutes"). Omit "goal" to resume
  the current goal. The step prompt shows how many schedules remain; when it
  is 0 the tool is unavailable. A scheduled follow-up runs as a NEW loop after
  this one ends, so still finish this loop properly.
- Allowed scope: $scopeLabel. Allowed session ids: ${allowedIds.join(', ')}.
- Use ONLY listed session ids. Never invent sessions.
- Identify what program each session runs from its screen before sending.
- A session marked `unknown` is still in scope. Do NOT skip it: read its
  screen, work out what it runs, and give it work like any other session.
- Never send a follow-up prompt while the previous task is still working.
  A quiet screen, observation timeout, or sufficient progress is NOT completion.
  Use read_sessions/wait to observe; deliver queued messages only after the turn ends.
- Keep every in-scope session busy. In each step, give work to EVERY session
  marked `NO TASK ASSIGNED` or `free for new work` unless the goal genuinely
  has nothing for it, OR its work depends on another session's output that
  does not exist yet (see the dependency rule below) — then say why in
  `thought`. Never leave a session idle just because another session is
  already working on something UNRELATED to it.
- Split the goal into per-session subtasks so independent sessions run in
  parallel. You may send_prompt to several different sessions in the SAME
  step, but only when their work does not depend on each other.
- Dependency ordering: when the goal or roles imply that one session's output
  is an input the others must follow (a design/spec/research session whose
  result implementers consume; "A designs, B and C build on it"; "먼저 설계한
  뒤 구현"), do NOT dispatch the dependent sessions in the same step as the
  upstream one, and do NOT invent the missing design yourself to hand to them
  in parallel — that lets the real design and the implementation diverge.
  Dispatch only the upstream session first; state in `thought` which sessions
  are waiting and why. Once the upstream session finishes or reports its
  artifact, dispatch the dependents pointing at that actual artifact (a file
  path they can read, or its exact content via post_message/broadcast) rather
  than your own guess of what it should contain. If it is genuinely unclear
  whether a dependency exists, prefer asking the sessions to work from a
  shared read-only reference (e.g. "read docs/design.md first") over guessing.
- ALWAYS fill `reason` on send_prompt and send_keys: one short Korean clause
  saying why this session gets this instruction now. The user reads it as the
  justification for the action, so "왜 지금 이걸" 이 드러나야 한다.
- `thought` explains the step as a whole; `reason` explains one action. Do not
  leave either empty.
- Respect user-provided role notes when assigning work across sessions.
- Prefer ONE clear instruction per agent per iteration over micro-managing.
- Never send more than one input action to the same session in one step.
- Sessions cannot talk to each other. To hand a result from one session to
  another, use post_message (or broadcast). Queued messages are injected at
  the top of that session's NEXT send_prompt as an [INBOX] block, so a
  session with unread mail needs a send_prompt to actually receive it.
  Do not paste another session's output into a prompt by hand; post it.
- `inbox: N unread` in the inventory means N queued messages are still
  undelivered. read_inbox shows their contents without delivering them.
- For long work (builds, full test suites, installs, deploys) set
  "await": false on send_prompt. The loop then keeps planning for other
  sessions instead of blocking on that one, and the result is reported back
  in a later step. Default is await:true — use it for short turns.
- If a session's screen shows that its CLI agent stopped because of a
  provider/network error (connection reset, fetch failed, 5xx, overloaded,
  timed out) or it returned to its prompt without doing the work, that task is
  NOT done. The orchestrator already re-sends a short "continue" instruction
  automatically (the action result says `auto-continue`). If it still shows
  the error, wait briefly and send_prompt a short "이어서 계속 진행해" instead
  of repeating the full instruction or giving up.
- A session marked `background task running` has an unfinished await:false
  task. Do NOT send it new input; give the other sessions work, or wait.
- finish and ask_user MUST each be the only action in their step.
- send_keys understands tokens like <Esc> <Enter> <Tab> <C-c> and \\n \\r.
- For destructive commands (rm -rf, sudo, force-push, drop table, file
  deletion, privilege escalation), set risk:"destructive" or use ask_user.
- When the goal is achieved or blocked, use finish with an honest status
  (achieved | partial | blocked).
- Write all user-facing text (thought/report/finish/ask_user) in Korean.
${roleRoutingBlock(sessionRoles)}''';

  /// 시스템 프롬프트의 ROLE ROUTING 절.
  ///
  /// 역할(capability)이 하나라도 정해진 세션이 있을 때만 붙인다. 역할 종류는
  /// CLI·모델과 무관하며, 표의 모델 라벨은 사용자가 선언한 자유 문자열이다.
  static String roleRoutingBlock(Map<String, AgentSessionRole> sessionRoles) {
    final entries = [
      for (final entry in sessionRoles.entries)
        if (entry.value.capabilities.isNotEmpty) entry,
    ];
    if (entries.isEmpty) return '';
    final rows = [
      for (final entry in entries)
        '- ${entry.key} | ${AgentSessionRole.kindLabel(entry.value.kind)} | '
            '${_capabilityNames(entry.value).join(',')} | '
            '${entry.value.declaredModel ?? '-'}',
    ];
    return '''

ROLE ROUTING
Session | role kind | capabilities | declared model
${rows.join('\n')}
- Hard verification and design work goes to 설계·검증 (architect).
- Complex implementation and code review go to 설계·구현·리뷰 (lead).
- Implementation that follows an existing design goes to 구현 (implementer).
- git work and simple shell chores go to 단순 작업 (operator).
- NEVER send a session a capability it does not have: the orchestrator
  rejects it with `role policy:` and the step is wasted.
- Pipeline: architect/lead design -> implementer implement -> lead review ->
  operator git. Hand designs over with post_message carrying the actual
  artifact (file path or exact content), never your own paraphrase.
- implementer sessions are rejected until a design handoff from an
  architect/lead exists; dispatch the design first.
- ALWAYS fill `capability` on send_prompt so routing can be checked.
- Timeouts default per role kind; pass `timeout_s` only to override.
''';
  }

  static List<String> _capabilityNames(AgentSessionRole role) =>
      role.capabilities.map(AgentSessionRole.capabilityLabel).toList()..sort();

  /// CLI 에이전트가 provider 오류·무응답으로 멈춘 뒤 같은 작업을 이어가게 하는
  /// 재지시 본문. 에이전트는 자기 대화 이력을 갖고 있으므로 짧게, 다만 이력이
  /// 유실된 경우를 위해 원래 지시를 함께 싣는다.
  static String continuationPrompt({
    required String original,
    required String reason,
  }) {
    const limit = 600;
    final trimmed = original.trim();
    final quoted = trimmed.length <= limit
        ? trimmed
        : '${trimmed.substring(0, limit)}...';
    return [
      '[VIBE ORCHESTRATOR] 직전 턴이 중단됐습니다($reason).',
      '같은 작업을 이어서 계속 진행하세요. 이미 끝낸 부분은 반복하지 말고 '
          '남은 부분부터 진행하고, 끝나면 결과를 간단히 요약하세요.',
      if (quoted.isNotEmpty) '원래 지시: $quoted',
    ].join('\n');
  }

  /// 매 PLAN 호출의 스텝 프롬프트.
  ///
  /// [now]를 주면 현재 시각과 (마감이 있으면) 남은 시간을 함께 알린다. 플래너는
  /// 시계가 없어서, 이걸 주지 않으면 "20분 뒤"나 "마감 전"을 계획할 수 없다.
  static String stepPrompt({
    required AgentGoalSpec goal,
    required int step,
    required int maxSteps,
    required List<String> allowedIds,
    required List<String> transcript,
    required List<String> pendingFeedback,
    DateTime? now,
    int schedulesLeft = 0,
    List<AgentHandoff> handoffs = const [],
  }) {
    final recent = transcript.length <= 40
        ? transcript
        : transcript.sublist(transcript.length - 40);
    final feedbackBlock = pendingFeedback.isEmpty
        ? ''
        : '\n[사용자 피드백 — 다음 계획에 반드시 반영]\n${pendingFeedback.map((f) => '- $f').join('\n')}\n';
    final timeLines = now == null
        ? ''
        : '${timeBlock(now, goal.deadline)}\n'
              'Schedules left this run: $schedulesLeft\n';
    return '''
Goal contract:
${goalContract(goal)}

Agent loop step: $step / $maxSteps
${timeLines}Allowed session ids: ${allowedIds.join(', ')}
$feedbackBlock
Recent handoffs (per session, newest last):
${handoffBlock(handoffs)}

Previous tool results:
${recent.isEmpty ? '(none)' : recent.join('\n')}

Inspect the current session snapshots in the system context. Pick the best
next tool action(s). Keep actions minimal and high-confidence.
''';
  }

  /// "Recent handoffs" 절의 본문. 테스트에서 직접 검증하기 위해 따로 뺀다.
  static String handoffBlock(List<AgentHandoff> handoffs) {
    if (handoffs.isEmpty) return '(none)';
    return handoffs
        .map((h) {
          final label = AgentSessionRole.kindLabel(h.roleKind);
          final summaryLines = h.summary
              .split('\n')
              .map((line) => '  $line')
              .join('\n');
          return '- [${h.sessionId} $label] "${h.instruction}" →\n$summaryLines';
        })
        .join('\n');
  }

  /// 현재 시각과 마감까지 남은 시간을 담은 줄. 마감이 없으면 시각만.
  static String timeBlock(DateTime now, DateTime? deadline) {
    final nowLine = 'Current local time: ${_formatTime(now)}';
    if (deadline == null) return nowLine;
    final remaining = deadline.difference(now);
    final remainingLabel = remaining.isNegative
        ? 'OVERDUE by ${_formatDuration(-remaining)}'
        : '${_formatDuration(remaining)} remaining';
    return '$nowLine\nDeadline: ${_formatTime(deadline)} ($remainingLabel)';
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatDuration(Duration value) {
    if (value.inMinutes < 1) return '${value.inSeconds}s';
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  /// 세션 인벤토리를 시스템 컨텍스트 문자열로 만든다.
  static String sessionInventory({
    required List<SessionPort> sessions,
    required int linesPerSession,
    required Map<String, String> agentHints,
    Map<String, AgentSessionRole> sessionRoles = const {},
    Map<String, SessionTaskView> tasks = const {},
    Map<String, int> unreadCounts = const {},
    Set<String> backgroundSessionIds = const {},
    Map<String, String> modelHints = const {},
  }) {
    if (sessions.isEmpty) return '(no visible sessions)';
    final buffer = StringBuffer();
    for (final session in sessions) {
      final hint = agentHints[session.id] ?? 'unknown';
      final statusLabel = session.isConnected
          ? (session.isBusy ? 'connected · busy' : 'connected · idle')
          : 'disconnected';
      final role = sessionRoles[session.id];
      final roleText = role?.label.trim() ?? '';
      final roleLabel = roleText.isEmpty ? '' : ' · role: $roleText';
      // model 힌트는 confirmed로 감지된 값만 넘어온다(가능성만 있는 possible은
      // 인벤토리에 노출하지 않는다). 역할에 모델이 선언돼 있고 화면 감지값과
      // 어긋나면 플래너가 알 수 있도록 MODEL MISMATCH를 덧붙인다.
      final detectedModel = modelHints[session.id];
      final modelLabel = detectedModel == null
          ? ''
          : ' · model: $detectedModel';
      final declaredModel = role?.declaredModel;
      final mismatchLabel =
          declaredModel != null &&
              declaredModel.isNotEmpty &&
              detectedModel != null &&
              !AgentSessionInspector.modelMatches(declaredModel, detectedModel)
          ? ' · MODEL MISMATCH(declared $declaredModel, screen $detectedModel)'
          : '';
      // 이 세션에 지금 맡겨진 일이 있는지 명시한다. 화면만 보고 판단하게 두면
      // 아직 한 번도 지시를 못 받은 세션이 그대로 방치된다.
      final task = tasks[session.id];
      final assignment = switch (task?.phase) {
        null || SessionTaskPhase.idle => 'NO TASK ASSIGNED',
        SessionTaskPhase.dispatched || SessionTaskPhase.working =>
          'working on: ${task!.lastInstruction ?? '(unknown)'}',
        SessionTaskPhase.done => 'last task finished — free for new work',
        SessionTaskPhase.error => 'needs attention (error/disconnected)',
        SessionTaskPhase.waitingInput =>
          'waiting for human input — do not send prompts or approve automatically',
      };
      // 미배달 메시지와 배경 작업은 화면에 흔적이 없다. 인벤토리에 적어주지
      // 않으면 플래너가 우편함을 잊거나, 아직 돌고 있는 세션에 또 지시한다.
      final unread = unreadCounts[session.id] ?? 0;
      final inboxLabel = unread == 0 ? '' : ' · inbox: $unread unread';
      final backgroundLabel = backgroundSessionIds.contains(session.id)
          ? ' · background task running'
          : '';
      final name = session.displayName.replaceAll(RegExp(r'[\r\n]+'), ' ');
      buffer
        ..writeln(
          '--- session ${session.id} "$name" '
          '($hint$modelLabel · $statusLabel$roleLabel · $assignment'
          '$inboxLabel$backgroundLabel$mismatchLabel) ---',
        )
        ..writeln(() {
          final text = maskTerminalSecrets(
            session.readScreen(maxLines: linesPerSession),
          ).trim();
          return text.isEmpty ? '(empty)' : text;
        }())
        ..writeln('--- end session ${session.id} ---');
    }
    return buffer.toString().trimRight();
  }

  /// 평가자 시스템 프롬프트.
  static String verifierSystem({required List<String> allowedIds}) =>
      '''
You are Vibe Terminal's Agent Chat verifier. Verify the previous actions
against the fresh session snapshots.

Respond with EXACTLY ONE JSON object and no Markdown. Schema:
{
  "verdict": "progress | ok | mistake | stuck | uncertain",
  "summary": "short Korean summary",
  "goal_met": false,
  "continue": true
}

Allowed session ids: ${allowedIds.join(', ')}.
Do not send terminal input; this is verification only.
Use "mistake" when an action hit the wrong session, had no visible effect
where one was expected, caused a visible error, or moved toward an unsafe
operation. Use "stuck" when the same state repeats with no progress.
Set goal_met=true only when the user goal is clearly satisfied.
Set continue=true only when another safe step is clearly needed.
Write the summary in Korean.
''';

  /// 평가자 스텝 프롬프트.
  static String verifierPrompt({
    required AgentGoalSpec goal,
    required int step,
    required int maxSteps,
    required List<String> actionResults,
  }) =>
      '''
Goal contract:
${goalContract(goal)}

Verification for step: $step / $maxSteps

Latest tool results:
${actionResults.isEmpty ? '(none)' : actionResults.join('\n')}

Read the fresh session snapshots in the system context. Decide whether the
previous actions worked, whether they were wrong, whether the goal is met,
and whether the loop should continue. Set goal_met=true only when every
success criterion is satisfied and the required verification has visible
evidence. A planner's finish request is not evidence by itself.
''';

  static String goalContract(AgentGoalSpec goal) {
    String block(String label, List<String> items, String empty) =>
        '$label:\n${items.isEmpty ? empty : items.map((item) => '- $item').join('\n')}';
    return [
      'Objective:\n${goal.objective}',
      block('Success criteria', goal.successCriteria, '(infer conservatively)'),
      block(
        'Required verification',
        goal.verificationSteps,
        '(use visible terminal evidence)',
      ),
      block('Constraints', goal.constraints, '(none specified)'),
      if (goal.deadline case final deadline?)
        'Deadline:\n${_formatTime(deadline)} (local time)',
      if (goal.continuationContext != null)
        'Previous loop summary:\n${goal.continuationContext}',
    ].join('\n\n');
  }

  /// JSON 파싱 실패 시 재요청하는 repair 프롬프트.
  static String repairPrompt(String rawResponse) =>
      '''
Your previous response was not a single valid JSON object. Re-emit your
decision as EXACTLY ONE JSON object matching the schema, with no Markdown,
no code fences, and no commentary.

Previous response:
$rawResponse
''';
}
