/// AI Chat의 단발 터미널 tool call.
///
/// 모델이 JSON 액션(`send_input` / `read_sessions` / `wait` / `finish`)을 돌려주면
/// 이 모듈이 해석·실행한다. 패널(사용자 요청)과 헤드리스 실행(예약 루틴, 능동
/// 감시)이 같은 스키마·실행기·안전장치를 쓰도록 UI와 분리했다. 파괴적 입력의
/// 승인 방식만 [TerminalToolApproval]로 호출자가 정한다.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../agent/risk_classifier.dart';
import '../session/session.dart';
import '../settings/app_settings.dart';
import '../terminal/terminal_input_codec.dart';
import 'ai_chat_service.dart';
import 'secret_masker.dart';

/// 모델이 돌려준 결정 한 건.
class TerminalToolDecision {
  const TerminalToolDecision({
    required this.thought,
    required this.actions,
    required this.continueLoop,
  });

  final String thought;
  final List<TerminalToolAction> actions;
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
  static TerminalToolDecision? tryParse(
    String raw, {
    void Function(String reason)? onFailure,
  }) {
    void fail(String reason) {
      debugPrint('TerminalToolDecision: parse failed: $reason');
      onFailure?.call(reason);
    }

    final jsonText = extractJson(raw);
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
      final actions = <TerminalToolAction>[];
      if (actionsRaw is List) {
        for (final item in actionsRaw) {
          if (item is Map) {
            final action = TerminalToolAction.fromJson(item);
            if (action != null) actions.add(action);
          }
        }
      } else if (actionsRaw is Map) {
        final action = TerminalToolAction.fromJson(actionsRaw);
        if (action != null) actions.add(action);
      }
      return TerminalToolDecision(
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

  /// 코드 펜스나 앞뒤 설명이 붙어도 첫 `{`부터 마지막 `}`까지를 JSON으로 본다.
  static String? extractJson(String raw) {
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

class TerminalToolAction {
  const TerminalToolAction({
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

  static TerminalToolAction? fromJson(Map<dynamic, dynamic> json) {
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
    return TerminalToolAction(
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

/// 모델이 읽고 입력할 수 있는 세션 범위.
class TerminalToolScope {
  const TerminalToolScope({required this.sessionIds, required this.label});

  /// 세션 하나만 허용하는 범위.
  TerminalToolScope.single(String sessionId, {String label = '현재 활성 세션'})
    : this(sessionIds: [sessionId], label: label);

  final List<String> sessionIds;
  final String label;

  bool get multiSession => sessionIds.length > 1;

  String get idsLabel => sessionIds.join(', ');

  bool allows(String sessionId) => sessionIds.contains(sessionId);
}

/// 파괴적으로 분류된 입력을 보낼지 결정한다. true면 보낸다.
///
/// 패널은 승인 다이얼로그를 띄우고, 헤드리스 실행은 보내지 않는 대신 사용자에게
/// 제안으로 남긴다. 승인 프롬프트(y/n)에 대신 답하는 정책은 여기서 만들지 않는다.
typedef TerminalToolApproval =
    Future<bool> Function(
      SessionInfo session,
      String input,
      RiskVerdict verdict,
    );

/// 액션 실행기. 세션 목록은 매번 [sessions]로 다시 읽어 닫힌 세션에 보내지 않는다.
class TerminalToolExecutor {
  const TerminalToolExecutor({
    required this.sessions,
    required this.approveRisky,
    this.observationDelay = const Duration(milliseconds: 650),
    this.readSessionMaxLines = 60,
    this.riskClassifier = const RiskClassifier(),
    this.inputBlockReason,
  });

  final List<SessionInfo> Function() sessions;
  final TerminalToolApproval approveRisky;

  /// send_input 뒤 화면이 반영되기를 기다리는 시간.
  final Duration observationDelay;

  /// read_sessions가 세션당 돌려주는 최대 줄 수.
  final int readSessionMaxLines;
  final RiskClassifier riskClassifier;

  /// 헤드리스 호출자가 전송 직전 현재 승인 대기·사용자 조작 등을 재검사한다.
  final String? Function(SessionInfo session)? inputBlockReason;

  /// 파괴적 입력을 절대 보내지 않는 승인 정책(헤드리스 기본값).
  static Future<bool> denyRisky(
    SessionInfo session,
    String input,
    RiskVerdict verdict,
  ) async => false;

  SessionInfo? findSession(String? sessionId) {
    for (final session in sessions()) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  /// 범위 안의 세션만 반환한다. 홈 세션도 권한 범위 밖이면 제외한다.
  List<SessionInfo> visibleSessions({
    required String homeSessionId,
    required TerminalToolScope scope,
  }) {
    final visible = [
      for (final session in sessions())
        if (scope.allows(session.id)) session,
    ];
    return visible;
  }

  Future<String> execute(
    TerminalToolAction action, {
    required String homeSessionId,
    required TerminalToolScope scope,
    AiCancelToken? cancelToken,
    Object? expectedConnectionIdentity,
  }) async {
    cancelToken?.throwIfCancelled();
    switch (action.tool) {
      case 'read_sessions':
      case 'read_session':
        final visible = visibleSessions(
          homeSessionId: homeSessionId,
          scope: scope,
        );
        final ids = action.sessionIds;
        final selected = ids.isEmpty
            ? visible
            : visible.where((session) => ids.contains(session.id)).toList();
        if (selected.isEmpty) {
          return 'read_sessions rejected: no session in permission scope '
              'matches ${ids.join(', ')}';
        }
        return observe(selected);
      case 'send_input':
        final visible = visibleSessions(
          homeSessionId: homeSessionId,
          scope: scope,
        );
        SessionInfo? session;
        for (final candidate in visible) {
          if (candidate.id == action.sessionId) session = candidate;
        }
        if (session == null) {
          return 'send_input rejected: session ${action.sessionId ?? '(missing)'} is outside permission scope';
        }
        if (session.status != SessionStatus.connected) {
          return 'send_input rejected: session ${session.id} is ${session.status.name}';
        }
        final identity = (session.engine, session.connectedAt);
        if (expectedConnectionIdentity != null &&
            expectedConnectionIdentity != identity) {
          return 'send_input rejected: session connection changed';
        }
        final blocked = inputBlockReason?.call(session);
        if (blocked != null) return 'send_input rejected: $blocked';
        final input = action.input;
        if (input == null || input.isEmpty) {
          return 'send_input rejected: empty input for ${session.id}';
        }
        // 모델이 만든 입력을 살아 있는 터미널에 그대로 보내는 지점이다.
        // 모델 컨텍스트에는 원격 서버가 출력한 내용이 들어가므로, 서버가
        // 모델을 유도해 파괴적인 명령을 만들어 낼 수 있다. Agent Chat과 같은
        // 기준으로 분류하고, 위험하면 호출자의 승인 정책을 거친다.
        final verdict = riskClassifier.classify(
          input,
          screenContext: session.engine.recentPlainText(maxLines: 40),
        );
        if (verdict.destructive &&
            !await approveRisky(session, input, verdict)) {
          return 'send_input rejected: user declined a destructive command for '
              '${session.id}';
        }
        // 승인 대기 중 취소·종료·재연결될 수 있다. 예전 연결에 대한 승인을
        // 같은 id의 새 연결로 넘기지 않는다.
        cancelToken?.throwIfCancelled();
        final live = findSession(session.id);
        if (live == null ||
            live.status != SessionStatus.connected ||
            (live.engine, live.connectedAt) != identity) {
          return 'send_input rejected: session connection changed';
        }
        final blockedNow = inputBlockReason?.call(live);
        if (blockedNow != null) return 'send_input rejected: $blockedNow';
        final text = action.submit
            ? normalizeTerminalInput(input)
            : TerminalInputCodec.decode(input).text;
        live.engine.terminal.textInput(text);
        await Future<void>.delayed(observationDelay);
        cancelToken?.throwIfCancelled();
        return 'send_input ${session.id}: ${action.reason ?? '(no reason)'}';
      case 'wait':
        final milliseconds = (action.milliseconds ?? 1000)
            .clamp(100, 5000)
            .toInt();
        await Future<void>.delayed(Duration(milliseconds: milliseconds));
        cancelToken?.throwIfCancelled();
        return 'waited ${milliseconds}ms: ${action.reason ?? '(no reason)'}';
      case 'finish':
        return 'finish: ${action.summary ?? action.reason ?? ''}';
      default:
        return 'tool rejected: unsupported tool `${action.tool}`';
    }
  }

  /// 각 세션의 최근 화면(최대 [readSessionMaxLines]줄)을 모델용 관찰 텍스트로
  /// 만든다. provider로 나가는 터미널 텍스트이므로 비밀값을 가린다.
  String observe(List<SessionInfo> selected) {
    final buffer = StringBuffer()
      ..writeln(
        'read_sessions observed ${selected.map((s) => s.id).join(', ')}',
      );
    for (final session in selected) {
      final screen = maskTerminalSecrets(
        session.engine.recentPlainText(maxLines: readSessionMaxLines),
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

  /// 코드 블록·모델 입력을 터미널로 보낼 형태로 만든다. 명시적 키 시퀀스가
  /// 있으면 그대로, 아니면 끝에 Enter(`\r`)를 하나만 붙인다.
  static String normalizeTerminalInput(String input) {
    final decoded = TerminalInputCodec.decode(input);
    if (decoded.sawExplicitKey) return decoded.text;
    return ensureTerminalSubmit(decoded.text);
  }

  static String ensureTerminalSubmit(String input) {
    final withoutTerminator = input.endsWith('\r\n')
        ? input.substring(0, input.length - 2)
        : input.endsWith('\r') || input.endsWith('\n')
        ? input.substring(0, input.length - 1)
        : input;
    return '$withoutTerminator\r';
  }
}

/// 단발 tool call 프롬프트. 패널과 헤드리스 실행이 같은 문구를 쓴다.
class TerminalToolPrompts {
  const TerminalToolPrompts._();

  static String system(String sessionId) =>
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

  static String userGoal(String goal, String sessionId) =>
      '''
User asked for direct terminal input:
$goal

Choose exactly one terminal tool action for active session `$sessionId`.
Do not answer in prose except inside the JSON fields.
''';

  static String observation(String observation) =>
      '''
Tool result:
${fence(observation)}

Now choose exactly one `send_input` or `finish` action as JSON. Do not call read_sessions again.
''';

  static String finished(TerminalToolAction action, String result) {
    final input = action.input ?? '';
    final submitLabel = action.submit ? '입력 후 Enter' : '입력만';
    return '''
터미널 tool call을 실행했습니다. ($submitLabel)

입력 내용:
${fence(input)}

$result
'''
        .trimRight();
  }

  static String fence(String text) {
    final marker = text.contains('```') ? '````' : '```';
    return '$marker text\n$text\n$marker';
  }
}

/// 사용자 목표 하나를 tool call 한 번(최대 [maxRounds]회 왕복)으로 처리한다.
///
/// 모델이 먼저 read_sessions로 화면을 읽겠다고 하면 관찰 결과를 붙여 한 번만
/// 더 묻는다. 그 이상은 Agent Chat의 몫이다.
class TerminalToolCallRunner {
  const TerminalToolCallRunner({
    required this.service,
    required this.executor,
    this.maxRounds = 2,
  });

  final AiChatService service;
  final TerminalToolExecutor executor;
  final int maxRounds;

  Future<String> run({
    required AiSettings settings,
    required SessionInfo session,
    required String userGoal,
    required List<AiChatMessage> requestMessages,
    AiCancelToken? cancelToken,
  }) async {
    final scope = TerminalToolScope.single(session.id);
    final identity = (session.engine, session.connectedAt);
    final conversation = [
      ...requestMessages,
      AiChatMessage(
        role: AiChatRole.user,
        content: TerminalToolPrompts.userGoal(userGoal, session.id),
        createdAt: DateTime.now(),
      ),
    ];

    for (var round = 1; round <= maxRounds; round += 1) {
      final raw = await service.complete(
        settings: settings,
        sessionLabel: session.displayName,
        terminalContext: session.engine.recentPlainText(
          maxLines: settings.maxContextLines,
        ),
        messages: conversation,
        cancelToken: cancelToken,
        additionalSystemPrompt: TerminalToolPrompts.system(session.id),
      );
      String? parseFailure;
      final decision = TerminalToolDecision.tryParse(
        raw,
        onFailure: (reason) => parseFailure = reason,
      );
      if (decision == null) {
        throw AiChatException(
          '터미널 tool call JSON을 해석하지 못했습니다. '
          '(${parseFailure ?? 'unknown'})\n\n'
          '${TerminalToolPrompts.fence(raw)}',
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
        final result = await executor.execute(
          action,
          homeSessionId: session.id,
          scope: scope,
          cancelToken: cancelToken,
          expectedConnectionIdentity: identity,
        );
        if (result.startsWith('send_input rejected')) {
          return '터미널 tool call이 거부되었습니다.\n\n$result';
        }
        return TerminalToolPrompts.finished(action, result);
      }

      final readActions = decision.actions
          .where(
            (action) =>
                action.tool == 'read_sessions' || action.tool == 'read_session',
          )
          .toList();
      if (readActions.isNotEmpty && round < maxRounds) {
        final observation = await executor.execute(
          readActions.first,
          homeSessionId: session.id,
          scope: scope,
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
              content: TerminalToolPrompts.observation(observation),
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
}
