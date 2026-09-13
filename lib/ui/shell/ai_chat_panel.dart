import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/risk_classifier.dart';
import '../../ai/ai_chat_service.dart';
import '../../ai/secret_masker.dart';
import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../session/session.dart';
import '../../settings/app_settings.dart';
import '../../state/providers.dart';
import '../../terminal/terminal_input_codec.dart';
import 'ai_message_renderer.dart';

class AiChatPanel extends ConsumerStatefulWidget {
  const AiChatPanel({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends ConsumerState<AiChatPanel> {
  static const _terminalObservationDelay = Duration(milliseconds: 700);
  static const _maxSubmittedInputEcho = 2000;
  static const _agentActionObservationDelay = Duration(milliseconds: 650);
  static const _readSessionMaxLines = 60;
  static const _maxTerminalToolCallRounds = 2;

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _sendingSessionIds = <String>{};
  final Map<String, AiCancelToken> _cancelTokens = <String, AiCancelToken>{};

  /// 세션별로 마지막 실패 요청. 오류 말풍선의 '다시 시도'가 이를 재실행한다.
  final Map<String, _RetryableRequest> _retryRequests =
      <String, _RetryableRequest>{};

  /// 전송 중에 들어온 터미널 관찰 요청. 현재 전송이 끝나면 하나만 이어서
  /// 실행한다(세션당 마지막 것만 보관).
  final Map<String, String> _pendingObservations = <String, String>{};

  /// '터미널로 보내기' 토글. 켜면 키워드 판정 없이 terminal tool call 경로로
  /// 보낸다. 패널이 살아 있는 동안만 유지된다.
  bool _forceTerminalToolCall = false;

  /// 터미널 내용이 AI provider로 전송된다는 안내를 닫았는지. 패널 수명 동안만
  /// 기억한다.
  bool _secretNoticeDismissed = false;

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  SessionInfo? _activeSession() {
    final sessions = ref.read(sessionManagerProvider);
    final activeId = ref.read(activeSessionIdProvider);
    for (final session in sessions) {
      if (session.id == activeId) return session;
    }
    return null;
  }

  SessionInfo? _findSession(List<SessionInfo> sessions, String? activeId) {
    for (final session in sessions) {
      if (session.id == activeId) return session;
    }
    return null;
  }

  String _terminalContext(SessionInfo? session, AiSettings settings) {
    if (session == null) return '';
    return session.engine.recentPlainText(maxLines: settings.maxContextLines);
  }

  bool _isSending(String? sessionId) =>
      sessionId != null && _sendingSessionIds.contains(sessionId);

  void _cancel(String? sessionId) {
    if (sessionId == null) return;
    _cancelTokens.remove(sessionId)?.cancel();
    if (mounted) {
      setState(() => _sendingSessionIds.remove(sessionId));
    }
  }

  int _lineCount(String text) {
    if (text.trim().isEmpty) return 0;
    return '\n'.allMatches(text).length + 1;
  }

  String _errorText(Object error) =>
      error is AiChatException ? error.message : error.toString();

  /// 실패를 오류 말풍선으로 남기고, [retry]가 있으면 '다시 시도'로 같은 요청을
  /// 재실행할 수 있게 기억한다.
  void _reportFailure({
    required String sessionId,
    required Object error,
    Future<void> Function()? retry,
  }) {
    final message = AiChatMessage(
      role: AiChatRole.assistant,
      content: _errorText(error),
      createdAt: DateTime.now(),
      isError: true,
    );
    ref.read(aiChatMessagesProvider(sessionId).notifier).add(message);
    if (retry == null) {
      _retryRequests.remove(sessionId);
    } else {
      _retryRequests[sessionId] = _RetryableRequest(
        errorMessage: message,
        run: retry,
      );
    }
  }

  /// 오류 말풍선을 지우고 마지막 실패 요청을 다시 보낸다.
  void _retry(String sessionId) {
    if (_isSending(sessionId)) return;
    final request = _retryRequests.remove(sessionId);
    if (request == null) return;
    _removeMessage(sessionId, request.errorMessage);
    unawaited(request.run());
  }

  /// notifier는 add/clear만 제공하므로, 해당 메시지만 뺀 목록으로 다시 채운다.
  void _removeMessage(String sessionId, AiChatMessage message) {
    final chat = ref.read(aiChatMessagesProvider(sessionId).notifier);
    final kept = ref
        .read(aiChatMessagesProvider(sessionId))
        .where((existing) => !identical(existing, message))
        .toList();
    chat.clear();
    for (final existing in kept) {
      chat.add(existing);
    }
  }

  /// 전송 시작 상태를 기록한다.
  void _beginSending(String sessionId, AiCancelToken cancelToken) {
    setState(() {
      _sendingSessionIds.add(sessionId);
      _cancelTokens[sessionId] = cancelToken;
    });
    _scrollToEndSoon(sessionId);
  }

  /// 전송 종료 상태를 기록하고, 전송 중에 밀려 있던 터미널 관찰이 있으면
  /// 이어서 실행한다.
  void _finishSending(String sessionId) {
    _cancelTokens.remove(sessionId);
    if (!mounted) return;
    setState(() => _sendingSessionIds.remove(sessionId));
    _scrollToEndSoon(sessionId);
    _drainPendingObservation(sessionId);
  }

  void _drainPendingObservation(String sessionId) {
    final submittedInput = _pendingObservations.remove(sessionId);
    if (submittedInput == null) return;
    final session = _findSession(ref.read(sessionManagerProvider), sessionId);
    if (session == null || session.status != SessionStatus.connected) return;
    unawaited(
      _observeTerminalAfterSubmit(
        session: session,
        submittedInput: submittedInput,
      ),
    );
  }

  void _submitToActiveSession(String input) {
    final session = _activeSession();
    if (session == null || session.status != SessionStatus.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결된 활성 세션이 없습니다')));
      return;
    }
    session.engine.terminal.textInput(_normalizeTerminalInput(input));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('활성 세션에 전송했습니다')));
    unawaited(
      _observeTerminalAfterSubmit(session: session, submittedInput: input),
    );
  }

  Future<void> _summarizeRestoredHistory(SessionInfo session) async {
    final context = session.restoredContext;
    final logId = context?.logId;
    if (context == null || logId == null || logId.trim().isEmpty) return;

    final settings = ref.read(appSettingsProvider).ai;
    if (!settings.isConfigured || _isSending(session.id)) return;

    final sessionId = session.id;
    final userMessage = AiChatMessage(
      role: AiChatRole.user,
      content: '이전 작업 내역을 요약해줘.',
      createdAt: DateTime.now(),
    );
    final requestMessages = [
      ...ref.read(aiChatMessagesProvider(sessionId)),
      userMessage,
    ];
    ref.read(aiChatMessagesProvider(sessionId).notifier).add(userMessage);
    await _runRestoredHistorySummary(
      sessionId: sessionId,
      logId: logId,
      restoredContext: context,
      requestMessages: requestMessages,
    );
  }

  /// 복원 요약 요청 본체. 실패하면 같은 인자로 '다시 시도'할 수 있다.
  Future<void> _runRestoredHistorySummary({
    required String sessionId,
    required String logId,
    required RestoredSessionContext restoredContext,
    required List<AiChatMessage> requestMessages,
  }) async {
    if (_isSending(sessionId)) return;
    final settings = ref.read(appSettingsProvider).ai;
    if (!settings.isConfigured) return;
    final chat = ref.read(aiChatMessagesProvider(sessionId).notifier);
    final service = ref.read(aiChatServiceProvider);
    final cancelToken = AiCancelToken();
    _beginSending(sessionId, cancelToken);

    try {
      final logText = await ref
          .read(sessionLogRepositoryProvider)
          .readPlainTextTailById(logId, maxLines: 500);
      cancelToken.throwIfCancelled();
      if (logText.trim().isEmpty) {
        // 로그가 없는 경우는 다시 시도해도 같으므로 재시도 없이 알린다.
        _reportFailure(
          sessionId: sessionId,
          error: AiChatException('이전 세션 로그를 찾지 못했거나 로그가 비어 있습니다.'),
        );
        ref
            .read(sessionManagerProvider.notifier)
            .markRestoreSummaryDismissed(sessionId);
        return;
      }

      final currentSession = _findSession(
        ref.read(sessionManagerProvider),
        sessionId,
      );
      if (currentSession == null) return;
      final reply = await service.complete(
        settings: settings,
        sessionLabel: '${currentSession.displayName} previous work',
        terminalContext: _restoredHistoryContext(
          session: currentSession,
          restoredContext: restoredContext,
          previousLogTail: logText,
          settings: settings,
        ),
        messages: requestMessages,
        cancelToken: cancelToken,
        additionalSystemPrompt: _restoredHistorySystemPrompt(),
      );
      chat.add(
        AiChatMessage(
          role: AiChatRole.assistant,
          content: reply,
          createdAt: DateTime.now(),
        ),
      );
      ref
          .read(sessionManagerProvider.notifier)
          .markRestoreSummaryCompleted(sessionId);
    } on AiChatCancelledException {
      // 사용자가 중단한 요청은 오류 말풍선을 남기지 않는다.
    } catch (e) {
      _reportFailure(
        sessionId: sessionId,
        error: e,
        retry: () => _runRestoredHistorySummary(
          sessionId: sessionId,
          logId: logId,
          restoredContext: restoredContext,
          requestMessages: requestMessages,
        ),
      );
    } finally {
      _finishSending(sessionId);
    }
  }

  String _restoredHistoryContext({
    required SessionInfo session,
    required RestoredSessionContext restoredContext,
    required String previousLogTail,
    required AiSettings settings,
  }) {
    final buffer = StringBuffer()
      ..writeln('Restored session previous log tail (last 500 lines)')
      ..writeln('Session: ${session.displayName}')
      ..writeln(
        'Previous working directory: ${restoredContext.workingDirectory ?? '(unknown)'}',
      )
      ..writeln('--- previous log begin ---')
      ..writeln(previousLogTail.trimRight())
      ..writeln('--- previous log end ---')
      ..writeln()
      ..writeln('Current restored terminal screen')
      ..writeln('--- current screen begin ---')
      ..writeln(_terminalContext(session, settings))
      ..writeln('--- current screen end ---');
    return buffer.toString();
  }

  String _restoredHistorySystemPrompt() => '''
You are summarizing a restored terminal session for the user.
Use the previous session log tail as the primary source. It may contain both terminal output and lines prefixed with `[input]`, which are user-entered terminal input.
Produce a concise Korean summary with:
- what the user was working on
- important files/directories/commands/errors
- current likely state
- 1-3 safe next steps
Do not invent facts that are not visible in the log. Mention uncertainty clearly.
Do not suggest destructive commands unless the log makes the user's intent explicit.
''';

  void _dismissRestoredHistory(SessionInfo session) {
    ref
        .read(sessionManagerProvider.notifier)
        .markRestoreSummaryDismissed(session.id);
  }

  void _dismissRestoredPath(SessionInfo session) {
    ref
        .read(sessionManagerProvider.notifier)
        .markRestorePathDismissed(session.id);
  }

  void _restoreWorkingDirectory(SessionInfo session) {
    final path = session.restoredContext?.workingDirectory?.trim();
    if (path == null || path.isEmpty) return;
    if (session.status != SessionStatus.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('세션이 아직 연결되지 않았습니다')));
      return;
    }
    final command = _restoreDirectoryCommand(session, path);
    session.engine.terminal.textInput(_ensureTerminalSubmit(command));
    ref
        .read(sessionManagerProvider.notifier)
        .markRestorePathCompleted(session.id);
    ref
        .read(aiChatMessagesProvider(session.id).notifier)
        .add(
          AiChatMessage(
            role: AiChatRole.assistant,
            content: '이전 작업 경로로 이동하는 명령을 전송했습니다.\n\n```text\n$command\n```',
            createdAt: DateTime.now(),
          ),
        );
    _scrollToEndSoon(session.id);
  }

  String _restoreDirectoryCommand(SessionInfo session, String path) {
    if (!session.host.isLocalShell) {
      return 'cd ${_shQuote(path)}';
    }
    return switch (session.host.localShellType) {
      LocalShellType.powershell =>
        'Set-Location -LiteralPath ${_powerShellQuote(path)}',
      LocalShellType.cmd => 'cd /d "${path.replaceAll('"', r'\"')}"',
      LocalShellType.wsl => 'cd ${_shQuote(path)}',
    };
  }

  String _shQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  String _powerShellQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<void> _observeTerminalAfterSubmit({
    required SessionInfo session,
    required String submittedInput,
  }) async {
    final settings = ref.read(appSettingsProvider).ai;
    if (!settings.isConfigured) return;
    if (_isSending(session.id)) {
      // 지금 보내는 요청이 끝나면 이어서 관찰한다. 여러 번 눌렀으면 마지막
      // 입력 하나만 관찰한다.
      _pendingObservations[session.id] = submittedInput;
      return;
    }
    await _runTerminalObservation(
      sessionId: session.id,
      submittedInput: submittedInput,
    );
  }

  /// 터미널 관찰 요청 본체. 실패하면 같은 입력으로 '다시 시도'할 수 있다.
  Future<void> _runTerminalObservation({
    required String sessionId,
    required String submittedInput,
  }) async {
    if (_isSending(sessionId)) return;
    final settings = ref.read(appSettingsProvider).ai;
    if (!settings.isConfigured) return;
    final chat = ref.read(aiChatMessagesProvider(sessionId).notifier);
    final service = ref.read(aiChatServiceProvider);
    final cancelToken = AiCancelToken();
    _beginSending(sessionId, cancelToken);

    try {
      await Future<void>.delayed(_terminalObservationDelay);
      cancelToken.throwIfCancelled();

      final currentSession = _findSession(
        ref.read(sessionManagerProvider),
        sessionId,
      );
      if (currentSession == null) return;

      final terminalContext = _terminalContext(currentSession, settings);
      final requestMessages = [
        ...ref.read(aiChatMessagesProvider(sessionId)),
        AiChatMessage(
          role: AiChatRole.user,
          content: _terminalObservationPrompt(submittedInput),
          createdAt: DateTime.now(),
        ),
      ];
      final reply = await service.complete(
        settings: settings,
        sessionLabel: currentSession.displayName,
        terminalContext: terminalContext,
        messages: requestMessages,
        cancelToken: cancelToken,
      );
      chat.add(
        AiChatMessage(
          role: AiChatRole.assistant,
          content: reply,
          createdAt: DateTime.now(),
        ),
      );
    } on AiChatCancelledException {
      // 사용자가 중단한 요청은 오류 말풍선을 남기지 않는다.
    } catch (e) {
      _reportFailure(
        sessionId: sessionId,
        error: e,
        retry: () => _runTerminalObservation(
          sessionId: sessionId,
          submittedInput: submittedInput,
        ),
      );
    } finally {
      _finishSending(sessionId);
    }
  }

  String _terminalObservationPrompt(String submittedInput) {
    final trimmed = maskTerminalSecrets(submittedInput.trimRight());
    final safeEcho = trimmed.replaceAll('```', '` ` `');
    final echoed = safeEcho.length <= _maxSubmittedInputEcho
        ? safeEcho
        : '${safeEcho.substring(0, _maxSubmittedInputEcho)}\n...';
    return '''
The user pressed OK and Vibe Terminal sent this input to the active terminal:

```terminal
$echoed
```

Read the current terminal context again as the observation after that action. Tell the user whether the action appears to have worked. If another step is needed, propose exactly one next `terminal` block for the user to approve. Do not claim success unless the terminal context shows it. Do not save or quit vim/nano unless the user explicitly asked.
''';
  }

  String _normalizeTerminalInput(String input) {
    final decoded = TerminalInputCodec.decode(input);
    if (decoded.sawExplicitKey) {
      return decoded.text;
    }
    return _ensureTerminalSubmit(decoded.text);
  }

  String _ensureTerminalSubmit(String input) {
    final withoutTerminator = input.endsWith('\r\n')
        ? input.substring(0, input.length - 2)
        : input.endsWith('\r') || input.endsWith('\n')
        ? input.substring(0, input.length - 1)
        : input;
    return '$withoutTerminator\r';
  }

  bool _wantsTerminalToolCall(String text) {
    final lowered = text.toLowerCase();
    final mentionsTerminal =
        text.contains('터미널') || lowered.contains('terminal');
    final sendCommand =
        text.contains('입력해') ||
        text.contains('입력 해') ||
        text.contains('보내') ||
        text.contains('전송') ||
        text.contains('타이핑') ||
        text.contains('쳐줘') ||
        text.contains('붙여넣') ||
        text.contains('실행해') ||
        lowered.contains('type') ||
        lowered.contains('send') ||
        lowered.contains('input') ||
        lowered.contains('paste') ||
        lowered.contains('enter');
    final answerTarget =
        text.contains('너의 답변') ||
        text.contains('네 답변') ||
        text.contains('AI 답변') ||
        text.contains('답변을 그대로') ||
        text.contains('응답을 그대로') ||
        text.contains('그대로') ||
        lowered.contains('your answer') ||
        lowered.contains('your response') ||
        lowered.contains('your reply') ||
        lowered.contains('verbatim');
    final toolIntent =
        text.contains('툴') ||
        text.contains('함수') ||
        lowered.contains('tool') ||
        lowered.contains('function');
    return mentionsTerminal && sendCommand && (answerTarget || toolIntent);
  }

  Future<String> _runTerminalToolCall({
    required AiSettings settings,
    required SessionInfo session,
    required String userGoal,
    required List<AiChatMessage> requestMessages,
    required AiChatService service,
    required AiCancelToken cancelToken,
  }) async {
    final permissionScope = _AgentPermissionScope(
      sessionIds: [session.id],
      label: '현재 활성 세션',
    );
    final conversation = [
      ...requestMessages,
      AiChatMessage(
        role: AiChatRole.user,
        content: _terminalToolCallPrompt(userGoal, session.id),
        createdAt: DateTime.now(),
      ),
    ];

    // 모델이 먼저 read_sessions로 화면을 읽겠다고 하면 관찰 결과를 붙여 한
    // 번만 더 묻는다. 그 이상은 Agent Chat의 몫이다.
    for (var round = 1; round <= _maxTerminalToolCallRounds; round += 1) {
      final raw = await service.complete(
        settings: settings,
        sessionLabel: session.displayName,
        terminalContext: _terminalContext(session, settings),
        messages: conversation,
        cancelToken: cancelToken,
        additionalSystemPrompt: _terminalToolCallSystemPrompt(session.id),
      );
      String? parseFailure;
      final decision = _AgentDecision.tryParse(
        raw,
        onFailure: (reason) => parseFailure = reason,
      );
      if (decision == null) {
        throw AiChatException(
          '터미널 tool call JSON을 해석하지 못했습니다. '
          '(${parseFailure ?? 'unknown'})\n\n'
          '${_textFence(raw)}',
          kind: AiChatFailureKind.invalidResponse,
        );
      }

      final finish = decision.finishSummary;
      if (finish != null) return finish;

      final sendActions = decision.actions
          .where((action) => action.tool == 'send_input')
          .toList();
      if (sendActions.isNotEmpty) {
        final action = sendActions.first;
        final result = await _executeAgentAction(
          action,
          homeSessionId: session.id,
          permissionScope: permissionScope,
          settings: settings,
          cancelToken: cancelToken,
        );
        if (result.startsWith('send_input rejected')) {
          return '터미널 tool call이 거부되었습니다.\n\n$result';
        }
        return _terminalToolCallFinishedMessage(action, result);
      }

      final readActions = decision.actions
          .where(
            (action) =>
                action.tool == 'read_sessions' || action.tool == 'read_session',
          )
          .toList();
      if (readActions.isNotEmpty && round < _maxTerminalToolCallRounds) {
        final observation = await _executeAgentAction(
          readActions.first,
          homeSessionId: session.id,
          permissionScope: permissionScope,
          settings: settings,
          cancelToken: cancelToken,
        );
        conversation
          ..add(
            AiChatMessage(
              role: AiChatRole.assistant,
              content: raw,
              createdAt: DateTime.now(),
            ),
          )
          ..add(
            AiChatMessage(
              role: AiChatRole.user,
              content: _terminalToolCallObservationPrompt(observation),
              createdAt: DateTime.now(),
            ),
          );
        continue;
      }

      final fallback = decision.thought.trim();
      if (fallback.isNotEmpty) return fallback;
      throw AiChatException(
        '모델이 실행할 terminal tool call을 선택하지 않았습니다. '
        '(actions: ${decision.actions.map((a) => a.tool).join(', ')})',
        kind: AiChatFailureKind.invalidResponse,
      );
    }
    throw AiChatException(
      '모델이 실행할 terminal tool call을 선택하지 않았습니다. '
      '(read_sessions 이후에도 send_input/finish가 없음)',
      kind: AiChatFailureKind.invalidResponse,
    );
  }

  String _terminalToolCallObservationPrompt(String observation) =>
      '''
Tool result:
${_textFence(observation)}

Now choose exactly one `send_input` or `finish` action as JSON. Do not call read_sessions again.
''';

  String _terminalToolCallSystemPrompt(String sessionId) =>
      '''
You are Vibe Terminal's single terminal tool dispatcher. The user explicitly wants your generated answer to be sent into the active terminal through a tool call.

Return exactly one JSON object and no Markdown. Schema:
{
  "thought": "short Korean reasoning summary",
  "actions": [
    {"tool": "send_input", "session_id": "$sessionId", "input": "exact terminal input", "submit": true, "reason": "why this is the requested terminal input"},
    {"tool": "read_sessions", "session_ids": ["$sessionId"], "reason": "only when the terminal context above is not enough; returns the latest screen text"},
    {"tool": "finish", "summary": "Korean message when you cannot safely send input"}
  ],
  "continue": false
}

Allowed session id: $sessionId.
Use send_input only for the active session id above.
Prefer send_input or finish directly; use read_sessions at most once.
The input field must contain the answer/input the user asked you to put into the terminal.
Set submit=true for shell commands or answers that should be submitted with Enter. Set submit=false only when the user clearly wants text typed without Enter.
For destructive commands, privilege escalation, saving, quitting, deleting files, or irreversible choices, use finish unless the user explicitly requested that exact action.
If the user's request is ambiguous, use finish with a concise Korean clarification instead of send_input.
''';

  String _terminalToolCallPrompt(String userGoal, String sessionId) =>
      '''
User asked for direct terminal input:
$userGoal

Choose exactly one terminal tool action for active session `$sessionId`.
Do not answer in prose except inside the JSON fields.
''';

  String _terminalToolCallFinishedMessage(_AgentAction action, String result) {
    final input = action.input ?? '';
    final submitLabel = action.submit ? '입력 후 Enter' : '입력만';
    return '''
터미널 tool call을 실행했습니다. ($submitLabel)

입력 내용:
${_textFence(input)}

$result
'''
        .trimRight();
  }

  String _textFence(String text) {
    final fence = text.contains('```') ? '````' : '```';
    return '$fence text\n$text\n$fence';
  }

  List<SessionInfo> _agentVisibleSessions({
    required String homeSessionId,
    required _AgentPermissionScope permissionScope,
  }) {
    final sessions = ref.read(sessionManagerProvider);
    final visible = [
      for (final session in sessions)
        if (permissionScope.allows(session.id)) session,
    ];
    if (visible.isNotEmpty) return visible;
    final home = _findSession(sessions, homeSessionId);
    return home == null ? const [] : [home];
  }

  Future<String> _executeAgentAction(
    _AgentAction action, {
    required String homeSessionId,
    required _AgentPermissionScope permissionScope,
    required AiSettings settings,
    required AiCancelToken cancelToken,
  }) async {
    switch (action.tool) {
      case 'read_sessions':
      case 'read_session':
        final sessions = _agentVisibleSessions(
          homeSessionId: homeSessionId,
          permissionScope: permissionScope,
        );
        final ids = action.sessionIds;
        final selected = ids.isEmpty
            ? sessions
            : sessions.where((session) => ids.contains(session.id)).toList();
        if (selected.isEmpty) {
          return 'read_sessions rejected: no session in permission scope '
              'matches ${ids.join(', ')}';
        }
        return _readSessionsObservation(selected);
      case 'send_input':
        final session = _findSession(
          _agentVisibleSessions(
            homeSessionId: homeSessionId,
            permissionScope: permissionScope,
          ),
          action.sessionId,
        );
        if (session == null) {
          return 'send_input rejected: session ${action.sessionId ?? '(missing)'} is outside permission scope';
        }
        if (session.status != SessionStatus.connected) {
          return 'send_input rejected: session ${session.id} is ${session.status.name}';
        }
        if (action.input == null || action.input!.isEmpty) {
          return 'send_input rejected: empty input for ${session.id}';
        }
        // 모델이 만든 입력을 살아 있는 터미널에 그대로 보내는 지점이다.
        // 모델 컨텍스트에는 원격 서버가 출력한 내용이 들어가므로, 서버가
        // 모델을 유도해 파괴적인 명령을 만들어 낼 수 있다. Agent Chat과 같은
        // 기준으로 분류하고, 위험하면 사용자 승인을 받는다.
        final approved = await _confirmRiskyTerminalInput(
          session: session,
          input: action.input!,
        );
        if (!approved) {
          return 'send_input rejected: user declined a destructive command for '
              '${session.id}';
        }
        final input = action.submit
            ? _normalizeTerminalInput(action.input!)
            : TerminalInputCodec.decode(action.input!).text;
        session.engine.terminal.textInput(input);
        await Future<void>.delayed(_agentActionObservationDelay);
        cancelToken.throwIfCancelled();
        return 'send_input ${session.id}: ${action.reason ?? '(no reason)'}';
      case 'wait':
        final milliseconds = (action.milliseconds ?? 1000)
            .clamp(100, 5000)
            .toInt();
        await Future<void>.delayed(Duration(milliseconds: milliseconds));
        cancelToken.throwIfCancelled();
        return 'waited ${milliseconds}ms: ${action.reason ?? '(no reason)'}';
      case 'finish':
        return 'finish: ${action.summary ?? action.reason ?? ''}';
      default:
        return 'tool rejected: unsupported tool `${action.tool}`';
    }
  }

  /// 각 세션의 최근 화면(최대 [_readSessionMaxLines]줄)을 모델용 관찰 텍스트로
  /// 만든다. provider로 나가는 터미널 텍스트이므로 비밀값을 가린다.
  String _readSessionsObservation(List<SessionInfo> sessions) {
    final buffer = StringBuffer()
      ..writeln(
        'read_sessions observed ${sessions.map((s) => s.id).join(', ')}',
      );
    for (final session in sessions) {
      final screen = maskTerminalSecrets(
        session.engine.recentPlainText(maxLines: _readSessionMaxLines),
      ).trimRight();
      buffer
        ..writeln()
        ..writeln(
          '[session ${session.id} · ${session.displayName} · ${session.status.name}]',
        )
        ..writeln(screen.isEmpty ? '(empty screen)' : screen);
    }
    return buffer.toString().trimRight();
  }

  Future<void> _send([String? quickPrompt]) async {
    final text = (quickPrompt ?? _inputController.text).trim();
    if (text.isEmpty) return;

    final session = _activeSession();
    if (session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('활성 터미널 세션이 없습니다')));
      return;
    }
    final sessionId = session.id;
    if (_isSending(sessionId)) return;
    final userMessage = AiChatMessage(
      role: AiChatRole.user,
      content: text,
      createdAt: DateTime.now(),
    );
    final requestMessages = [
      ...ref.read(aiChatMessagesProvider(sessionId)),
      userMessage,
    ];
    ref.read(aiChatMessagesProvider(sessionId).notifier).add(userMessage);
    if (quickPrompt == null) {
      setState(_inputController.clear);
    }
    // 토글이 켜져 있으면 키워드 판정 없이 tool call 경로로 보낸다. 꺼져 있으면
    // 기존 키워드 판정을 그대로 쓴다.
    final useToolCall = _forceTerminalToolCall || _wantsTerminalToolCall(text);
    await _runChatRequest(
      sessionId: sessionId,
      text: text,
      requestMessages: requestMessages,
      useToolCall: useToolCall,
    );
  }

  /// 채팅 요청 본체. 실패하면 같은 인자로 '다시 시도'할 수 있다.
  Future<void> _runChatRequest({
    required String sessionId,
    required String text,
    required List<AiChatMessage> requestMessages,
    required bool useToolCall,
  }) async {
    if (_isSending(sessionId)) return;
    final session = _findSession(ref.read(sessionManagerProvider), sessionId);
    if (session == null) return;
    final settings = ref.read(appSettingsProvider).ai;
    final terminalContext = _terminalContext(session, settings);
    // 대화 히스토리·서비스 참조는 패널이 닫혀도 유효하도록 provider/notifier로
    // 보관·참조한다. ref는 위젯 dispose 후 무효이므로 비동기 전에 잡아둔다.
    final chat = ref.read(aiChatMessagesProvider(sessionId).notifier);
    final service = ref.read(aiChatServiceProvider);
    final cancelToken = AiCancelToken();
    _beginSending(sessionId, cancelToken);

    try {
      // 다중 세션 오케스트레이션(agent loop)은 Agent Chat 패널로 이관됨.
      // AI Chat은 단일 세션 질의응답과 단발 terminal tool call 보조에 집중한다.
      final reply = useToolCall
          ? await _runTerminalToolCall(
              settings: settings,
              session: session,
              userGoal: text,
              requestMessages: requestMessages,
              service: service,
              cancelToken: cancelToken,
            )
          : await service.complete(
              settings: settings,
              sessionLabel: session.displayName,
              terminalContext: terminalContext,
              messages: requestMessages,
              cancelToken: cancelToken,
            );
      // 패널이 닫혔어도(notifier는 유효) 응답을 저장해 맥락을 유지한다.
      chat.add(
        AiChatMessage(
          role: AiChatRole.assistant,
          content: reply,
          createdAt: DateTime.now(),
        ),
      );
    } on AiChatCancelledException {
      // 사용자가 중단한 요청은 오류 말풍선을 남기지 않는다.
    } catch (e) {
      _reportFailure(
        sessionId: sessionId,
        error: e,
        retry: () => _runChatRequest(
          sessionId: sessionId,
          text: text,
          requestMessages: requestMessages,
          useToolCall: useToolCall,
        ),
      );
    } finally {
      _finishSending(sessionId);
    }
  }

  /// 모델이 보내려는 터미널 입력이 파괴적인지 판정하고, 그렇다면 사용자
  /// 승인을 받는다. 위험하지 않으면 묻지 않고 true.
  ///
  /// [RiskClassifier]는 보안 경계가 아니라 실수·유도를 걸러내는 그물이다.
  /// 그래도 이 경로에는 반드시 있어야 한다. 여기로 들어오는 입력은 원격
  /// 서버의 화면 내용을 읽은 모델이 만들어 낸 것이라, 사용자가 한 번도 보지
  /// 못한 명령이 그대로 실행될 수 있기 때문이다.
  Future<bool> _confirmRiskyTerminalInput({
    required SessionInfo session,
    required String input,
  }) async {
    final verdict = const RiskClassifier().classify(
      input,
      screenContext: session.engine.recentPlainText(maxLines: 40),
    );
    if (!verdict.destructive) return true;
    if (!mounted) return false;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('파괴적인 명령 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI가 ${session.displayName} 세션에 아래 입력을 보내려 합니다.'),
            const SizedBox(height: 12),
            SelectableText(
              input,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Text(
              '판정 근거: ${verdict.reason ?? '파괴적일 수 있는 명령'}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('보내지 않기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('실행'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  /// 대화 히스토리를 비우고 새 대화를 시작한다(확인 후). 맥락이 사라지므로
  /// 실수 방지로 확인 다이얼로그를 거친다.
  Future<void> _startNewChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('새 대화'),
        content: const Text('현재 대화를 지우고 새로 시작할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('새 대화'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = _activeSession();
    if (session == null) return;
    ref.read(aiChatMessagesProvider(session.id).notifier).clear();
    _inputController.clear();
  }

  void _scrollToEndSoon(String sessionId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeSession()?.id != sessionId) return;
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _adjustChatFontSize(double delta) {
    final current = ref.read(appSettingsProvider).ai.chatFontSize;
    final next = (current + delta)
        .clamp(AiSettings.minChatFontSize, AiSettings.maxChatFontSize)
        .toDouble();
    if (next == current) return;
    ref.read(appSettingsProvider.notifier).setAiChatFontSize(next);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).ai;
    final sessions = ref.watch(sessionManagerProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final session = _findSession(sessions, activeId);
    final sessionId = session?.id;
    final terminalContext = _terminalContext(session, settings);
    final contextLines = _lineCount(terminalContext);
    final messages = sessionId == null
        ? const <AiChatMessage>[]
        : ref.watch(aiChatMessagesProvider(sessionId));
    final sending = _isSending(sessionId);
    final restoredContext = session?.restoredContext;
    final showRestoreSummaryOffer =
        settings.isConfigured &&
        session != null &&
        restoredContext?.shouldOfferSummary == true;
    final showRestorePathOffer =
        session != null && restoredContext?.shouldOfferPathRestore == true;
    return ColoredBox(
      color: VibeColors.surface,
      child: Column(
        children: [
          _AiPanelHeader(
            session: session,
            contextLines: contextLines,
            onOpenSettings: widget.onOpenSettings,
            chatFontSize: settings.chatFontSize,
            onDecreaseFontSize:
                settings.chatFontSize <= AiSettings.minChatFontSize
                ? null
                : () => _adjustChatFontSize(-1),
            onIncreaseFontSize:
                settings.chatFontSize >= AiSettings.maxChatFontSize
                ? null
                : () => _adjustChatFontSize(1),
            // 대화가 있고 전송 중이 아닐 때만 '새 대화' 버튼 노출.
            onNewChat: messages.isEmpty || sending ? null : _startNewChat,
          ),
          if (!settings.isConfigured)
            _AiNotice(
              icon: Icons.key_off_outlined,
              text: 'AI 설정에서 provider, model, API token을 입력하세요.',
              actionLabel: widget.onOpenSettings == null ? null : '설정',
              onAction: widget.onOpenSettings,
            )
          else if (session == null)
            const _AiNotice(
              icon: Icons.terminal_outlined,
              text: '활성 터미널 세션이 없습니다.',
            )
          else if (!_secretNoticeDismissed)
            _AiNotice(
              icon: Icons.privacy_tip_outlined,
              text:
                  '터미널 화면 내용이 설정된 AI provider로 전송됩니다. '
                  'API 키·토큰·비밀번호 같은 흔한 비밀값은 전송 전에 가려집니다.',
              actionLabel: '확인',
              onAction: () => setState(() => _secretNoticeDismissed = true),
            ),
          if (showRestoreSummaryOffer)
            _RestoreSessionHistoryCard(
              onAccept: sending
                  ? null
                  : () => unawaited(_summarizeRestoredHistory(session)),
              onDismiss: sending
                  ? null
                  : () => _dismissRestoredHistory(session),
            )
          else if (showRestorePathOffer)
            _RestoreWorkingDirectoryCard(
              path: restoredContext!.workingDirectory!,
              onAccept: sending
                  ? null
                  : () => _restoreWorkingDirectory(session),
              onDismiss: sending ? null : () => _dismissRestoredPath(session),
            ),
          Expanded(
            child: messages.isEmpty
                ? _AiEmptyState(onPrompt: _send)
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    itemCount: messages.length + (sending ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (sending && index == messages.length) {
                        return const _ThinkingBubble();
                      }
                      final message = messages[index];
                      final retryable =
                          sessionId != null &&
                          message.isError &&
                          identical(
                            _retryRequests[sessionId]?.errorMessage,
                            message,
                          );
                      return _MessageBubble(
                        message: message,
                        onSubmitTerminalInput: _submitToActiveSession,
                        onRetry: retryable && !sending
                            ? () => _retry(sessionId)
                            : null,
                        fontFamily: settings.chatFontFamily,
                        fontFallback: settings.fontFallback,
                        fontSize: settings.chatFontSize,
                      );
                    },
                  ),
          ),
          _AiInputBar(
            controller: _inputController,
            sending: sending,
            onSend: () => _send(),
            onCancel: () => _cancel(sessionId),
            forceTerminalToolCall: _forceTerminalToolCall,
            onToggleTerminalToolCall: (value) =>
                setState(() => _forceTerminalToolCall = value),
            fontFamily: settings.chatFontFamily,
            fontFallback: settings.fontFallback,
            fontSize: settings.chatFontSize,
          ),
        ],
      ),
    );
  }
}

/// 오류 말풍선 하나와, 그 말풍선을 만든 요청을 다시 보내는 함수.
class _RetryableRequest {
  const _RetryableRequest({required this.errorMessage, required this.run});

  final AiChatMessage errorMessage;
  final Future<void> Function() run;
}

class _AgentPermissionScope {
  const _AgentPermissionScope({required this.sessionIds, required this.label});

  final List<String> sessionIds;
  final String label;

  bool get multiSession => sessionIds.length > 1;

  String get idsLabel => sessionIds.join(', ');

  bool allows(String sessionId) => sessionIds.contains(sessionId);
}

class _AgentDecision {
  const _AgentDecision({
    required this.thought,
    required this.actions,
    required this.continueLoop,
  });

  final String thought;
  final List<_AgentAction> actions;
  final bool continueLoop;

  String? get finishSummary {
    for (final action in actions) {
      if (action.tool == 'finish') {
        final summary = action.summary ?? action.reason ?? thought;
        return summary.trim().isEmpty ? 'Agent loop가 완료되었습니다.' : summary;
      }
    }
    return null;
  }

  /// 해석에 실패하면 null. 실패 이유는 debugPrint로 남기고 [onFailure]로도
  /// 알려서 오류 말풍선에 짧은 힌트를 붙일 수 있게 한다.
  static _AgentDecision? tryParse(
    String raw, {
    void Function(String reason)? onFailure,
  }) {
    void fail(String reason) {
      debugPrint('AiChatPanel: agent decision parse failed: $reason');
      onFailure?.call(reason);
    }

    final jsonText = _extractJson(raw);
    if (jsonText == null) {
      fail('응답에서 JSON 객체를 찾지 못함');
      return null;
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        fail('JSON 최상위가 객체가 아님: ${decoded.runtimeType}');
        return null;
      }
      final actionsRaw = decoded['actions'];
      final actions = <_AgentAction>[];
      if (actionsRaw is List) {
        for (final item in actionsRaw) {
          if (item is Map) {
            final action = _AgentAction.fromJson(item);
            if (action != null) actions.add(action);
          }
        }
      } else if (actionsRaw is Map) {
        final action = _AgentAction.fromJson(actionsRaw);
        if (action != null) actions.add(action);
      }
      return _AgentDecision(
        thought: decoded['thought'] is String
            ? decoded['thought'] as String
            : '',
        actions: actions,
        continueLoop: decoded['continue'] == true,
      );
    } on FormatException catch (e) {
      fail('JSON 문법 오류: ${e.message}');
      return null;
    } catch (e) {
      fail('JSON 해석 중 예외: $e');
      return null;
    }
  }

  static String? _extractJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('```')) {
      final lines = trimmed.split('\n');
      if (lines.length >= 3 && lines.last.trim() == '```') {
        return lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return trimmed.substring(start, end + 1);
  }
}

class _AgentAction {
  const _AgentAction({
    required this.tool,
    this.sessionId,
    this.sessionIds = const [],
    this.input,
    this.submit = true,
    this.milliseconds,
    this.reason,
    this.summary,
  });

  final String tool;
  final String? sessionId;
  final List<String> sessionIds;
  final String? input;
  final bool submit;
  final int? milliseconds;
  final String? reason;
  final String? summary;

  bool get needsVerification => tool == 'send_input' || tool == 'wait';

  static _AgentAction? fromJson(Map<dynamic, dynamic> json) {
    final tool = json['tool'];
    if (tool is! String || tool.trim().isEmpty) return null;
    final idsRaw = json['session_ids'];
    final sessionIds = idsRaw is List
        ? [
            for (final id in idsRaw)
              if (id is String && id.trim().isNotEmpty) id.trim(),
          ]
        : const <String>[];
    final milliseconds = json['milliseconds'];
    return _AgentAction(
      tool: tool.trim().toLowerCase(),
      sessionId: json['session_id'] is String
          ? (json['session_id'] as String).trim()
          : null,
      sessionIds: sessionIds,
      input: json['input'] is String ? json['input'] as String : null,
      submit: json['submit'] is bool ? json['submit'] as bool : true,
      milliseconds: milliseconds is int ? milliseconds : null,
      reason: json['reason'] is String ? json['reason'] as String : null,
      summary: json['summary'] is String ? json['summary'] as String : null,
    );
  }
}

class _AiPanelHeader extends StatelessWidget {
  const _AiPanelHeader({
    required this.session,
    required this.contextLines,
    required this.onOpenSettings,
    required this.chatFontSize,
    required this.onDecreaseFontSize,
    required this.onIncreaseFontSize,
    required this.onNewChat,
  });

  final SessionInfo? session;
  final int contextLines;
  final VoidCallback? onOpenSettings;
  final double chatFontSize;
  final VoidCallback? onDecreaseFontSize;
  final VoidCallback? onIncreaseFontSize;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: VibeColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Chat',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session == null
                      ? 'no active session'
                      : '${session!.displayName} · $contextLines lines',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (onNewChat != null)
            _AiHeaderIconButton(
              tooltip: '새 대화',
              onPressed: onNewChat,
              icon: const Icon(Icons.add_comment_outlined, size: 18),
            ),
          _AiHeaderIconButton(
            tooltip: 'AI Chat 글자 작게 (${chatFontSize.toStringAsFixed(0)}pt)',
            onPressed: onDecreaseFontSize,
            icon: const Icon(Icons.zoom_out, size: 18),
          ),
          _AiHeaderIconButton(
            tooltip: 'AI Chat 글자 크게 (${chatFontSize.toStringAsFixed(0)}pt)',
            onPressed: onIncreaseFontSize,
            icon: const Icon(Icons.zoom_in, size: 18),
          ),
          if (onOpenSettings != null)
            _AiHeaderIconButton(
              tooltip: 'AI 설정',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune, size: 18),
            ),
        ],
      ),
    );
  }
}

class _AiHeaderIconButton extends StatelessWidget {
  const _AiHeaderIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RestoreSessionHistoryCard extends StatelessWidget {
  const _RestoreSessionHistoryCard({
    required this.onAccept,
    required this.onDismiss,
  });

  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return _RestoreActionCard(
      icon: Icons.history,
      title: '이전에 작업하던 내역이 있습니다.',
      text: '마지막 세션 로그를 읽고 현재 상태를 요약해드릴까요?',
      primaryLabel: '알려줘',
      secondaryLabel: '묻지 않기',
      onPrimary: onAccept,
      onSecondary: onDismiss,
    );
  }
}

class _RestoreWorkingDirectoryCard extends StatelessWidget {
  const _RestoreWorkingDirectoryCard({
    required this.path,
    required this.onAccept,
    required this.onDismiss,
  });

  final String path;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return _RestoreActionCard(
      icon: Icons.drive_file_move_outline,
      title: '이전 경로로 복구하시겠습니까?',
      text: path,
      primaryLabel: 'Yes',
      secondaryLabel: 'No',
      onPrimary: onAccept,
      onSecondary: onDismiss,
      monoText: true,
    );
  }
}

class _RestoreActionCard extends StatelessWidget {
  const _RestoreActionCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.monoText = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final bool monoText;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: VibeColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: VibeColors.onSurfaceMuted,
                        fontFamily: monoText ? kMonoFontFamily : null,
                        fontFamilyFallback: monoText ? kMonoFontFallback : null,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
              const SizedBox(width: 8),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiNotice extends StatelessWidget {
  const _AiNotice({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: VibeColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 12,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _AiEmptyState extends StatelessWidget {
  const _AiEmptyState({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    // 안내 카드·입력창이 세로 공간을 차지해도 넘치지 않도록 스크롤 가능하게.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.terminal,
              color: VibeColors.onSurfaceDim,
              size: 32,
            ),
            const SizedBox(height: 12),
            const Text(
              '현재 터미널 상태를 기준으로 물어보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: VibeColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _PromptChip(
              label: '현재 화면 요약',
              onTap: () => onPrompt('현재 터미널 화면을 읽고 핵심 상태를 요약해줘.'),
            ),
            const SizedBox(height: 8),
            _PromptChip(
              label: '마지막 오류 원인 분석',
              onTap: () => onPrompt('마지막 오류의 원인과 해결 절차를 정리해줘.'),
            ),
            const SizedBox(height: 8),
            _PromptChip(
              label: '다음 명령 추천',
              onTap: () => onPrompt('현재 터미널 상태에서 다음에 실행할 명령을 추천해줘.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.north_east, size: 15),
      label: Text(label),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onSubmitTerminalInput,
    required this.fontFamily,
    required this.fontFallback,
    required this.fontSize,
    this.onRetry,
  });

  final AiChatMessage message;
  final ValueChanged<String> onSubmitTerminalInput;

  /// 오류 말풍선에서 같은 요청을 다시 보내는 동작. null이면 버튼을 숨긴다.
  final VoidCallback? onRetry;
  final String fontFamily;
  final List<String> fontFallback;
  final double fontSize;

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('AI 메시지를 복사했습니다')));
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiChatRole.user;
    final color = message.isError
        ? VibeColors.statusError.withValues(alpha: 0.14)
        : isUser
        ? VibeColors.accentSoft
        : VibeColors.surfaceHigh;
    final borderColor = message.isError
        ? VibeColors.statusError.withValues(alpha: 0.45)
        : isUser
        ? VibeColors.accent.withValues(alpha: 0.40)
        : VibeColors.borderSoft;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = isUser
            ? constraints.maxWidth * 0.86
            : constraints.maxWidth;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isUser)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: '메시지 전체 복사',
                          onPressed: () => unawaited(_copyMessage(context)),
                          icon: const Icon(Icons.content_copy, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 30,
                            height: 30,
                          ),
                        ),
                      ),
                    AiMessageRenderer(
                      markdown: message.content,
                      isAssistant: message.role == AiChatRole.assistant,
                      isError: message.isError,
                      onSubmitTerminalInput: onSubmitTerminalInput,
                      fontFamily: fontFamily,
                      fontFallback: fontFallback,
                      fontSize: fontSize,
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('다시 시도'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'thinking',
              style: TextStyle(
                color: VibeColors.onSurfaceDim,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiInputBar extends StatefulWidget {
  const _AiInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onCancel,
    required this.forceTerminalToolCall,
    required this.onToggleTerminalToolCall,
    required this.fontFamily,
    required this.fontFallback,
    required this.fontSize,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  /// '터미널로 보내기' 토글 상태와 변경 콜백.
  final bool forceTerminalToolCall;
  final ValueChanged<bool> onToggleTerminalToolCall;
  final String fontFamily;
  final List<String> fontFallback;
  final double fontSize;

  @override
  State<_AiInputBar> createState() => _AiInputBarState();
}

class _AiInputBarState extends State<_AiInputBar> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestInputFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _requestInputFocus() {
    if (!mounted || !_focusNode.canRequestFocus) return;
    _focusNode.requestFocus();
  }

  void _sendIfReady() {
    if (!widget.sending) widget.onSend();
  }

  void _insertNewline() {
    final value = widget.controller.value;
    final text = value.text;
    final selection = value.selection;
    final rawStart = selection.isValid ? selection.start : text.length;
    final rawEnd = selection.isValid ? selection.end : text.length;
    final start = rawStart < 0
        ? 0
        : rawStart > text.length
        ? text.length
        : rawStart;
    final end = rawEnd < 0
        ? 0
        : rawEnd > text.length
        ? text.length
        : rawEnd;
    final nextText = text.replaceRange(start, end, '\n');
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: VibeColors.borderSoft)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: widget.forceTerminalToolCall
                    ? '켜짐: 답변을 터미널 tool call로 바로 입력합니다'
                    : '켜면 키워드 판정 없이 답변을 터미널에 바로 입력합니다',
                child: FilterChip(
                  label: const Text('터미널로 보내기'),
                  avatar: Icon(
                    Icons.terminal,
                    size: 15,
                    color: widget.forceTerminalToolCall
                        ? VibeColors.onAccent
                        : VibeColors.onSurfaceDim,
                  ),
                  selected: widget.forceTerminalToolCall,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: widget.forceTerminalToolCall
                        ? VibeColors.onAccent
                        : VibeColors.onSurfaceMuted,
                  ),
                  selectedColor: VibeColors.accent,
                  onSelected: widget.sending
                      ? null
                      : widget.onToggleTerminalToolCall,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter):
                          _sendIfReady,
                      const SingleActivator(LogicalKeyboardKey.numpadEnter):
                          _sendIfReady,
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        shift: true,
                      ): _insertNewline,
                      const SingleActivator(
                        LogicalKeyboardKey.numpadEnter,
                        shift: true,
                      ): _insertNewline,
                    },
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      style: TextStyle(
                        fontFamily: widget.fontFamily,
                        fontFamilyFallback: widget.fontFallback,
                        fontSize: widget.fontSize,
                      ),
                      decoration: const InputDecoration(
                        hintText: '터미널 상태에 대해 질문',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                      onTap: _requestInputFocus,
                      onSubmitted: (_) => _sendIfReady(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 40,
                  child: IconButton.filled(
                    tooltip: widget.sending ? '응답 중단' : '보내기',
                    style: IconButton.styleFrom(
                      backgroundColor: widget.sending
                          ? VibeColors.statusError
                          : VibeColors.accent,
                      foregroundColor: widget.sending
                          ? Colors.white
                          : VibeColors.onAccent,
                      hoverColor: widget.sending
                          ? const Color(0xFFFF8C8C)
                          : const Color(0xFF7FF4E5),
                      focusColor: widget.sending
                          ? const Color(0xFFFF8C8C)
                          : const Color(0xFF7FF4E5),
                      highlightColor: widget.sending
                          ? const Color(0xFFDB4D4D)
                          : const Color(0xFF2FB9A8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: widget.sending ? widget.onCancel : widget.onSend,
                    icon: Icon(
                      widget.sending ? Icons.stop_rounded : Icons.arrow_upward,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
