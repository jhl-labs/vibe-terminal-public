import 'dart:convert';

import 'agent_mailbox.dart';
import 'agent_session_inspector.dart' show AgentSessionInspector;
import 'agent_session_role.dart';

/// Agent Chat 오케스트레이션 loop의 도메인 모델.
///
/// 이 파일은 Flutter에 의존하지 않는 순수 Dart이다. LLM 응답 파싱, loop 상태,
/// 타임라인 이벤트를 정의하며 UI/엔진 양쪽에서 공유된다.

/// loop 전체 상태 기계의 단계.
enum AgentLoopStatus {
  idle,
  planning,
  dispatching,
  observing,
  evaluating,
  waitingApproval,
  waitingUser,
  paused,
  finished,
}

/// loop 종료 결과.
enum AgentLoopOutcome { achieved, partial, blocked, stopped, failed }

enum AgentPauseReason {
  user,
  budgetExhausted,
  recoverableError,
  runtimeBlocked,

  /// 하위 CLI의 승인·질문을 터미널에서 처리해야 한다. 자동 승인하지 않는다.
  sessionInput,

  /// 목표 계약의 마감 시각을 지났다. 마감을 연장하거나 중단해야 이어진다.
  deadlineReached,
}

/// loop가 달성해야 할 목표와 완료 판정 계약.
class AgentGoalSpec {
  const AgentGoalSpec({
    required this.objective,
    this.successCriteria = const [],
    this.verificationSteps = const [],
    this.constraints = const [],
    this.continuationContext,
    this.deadline,
  });

  final String objective;
  final List<String> successCriteria;
  final List<String> verificationSteps;
  final List<String> constraints;
  final String? continuationContext;

  /// 이 시각을 지나면 loop가 `deadlineReached`로 멈춘다. null이면 마감 없음.
  ///
  /// 플래너는 매 step 남은 시간을 받아 마감 전에 마무리하도록 계획한다.
  final DateTime? deadline;

  bool get hasContract =>
      successCriteria.isNotEmpty ||
      verificationSteps.isNotEmpty ||
      constraints.isNotEmpty ||
      continuationContext != null ||
      deadline != null;

  AgentGoalSpec normalized({String? objectiveOverride}) => AgentGoalSpec(
    objective: (objectiveOverride ?? objective).trim(),
    successCriteria: List.unmodifiable(_normalizeItems(successCriteria)),
    verificationSteps: List.unmodifiable(_normalizeItems(verificationSteps)),
    constraints: List.unmodifiable(_normalizeItems(constraints)),
    continuationContext: _normalizeOptional(continuationContext),
    deadline: deadline,
  );

  /// 마감만 바꾼 사본. null을 넘기면 마감을 지운다.
  AgentGoalSpec withDeadline(DateTime? value) => AgentGoalSpec(
    objective: objective,
    successCriteria: successCriteria,
    verificationSteps: verificationSteps,
    constraints: constraints,
    continuationContext: continuationContext,
    deadline: value,
  );

  static List<String> parseLines(String text) => _normalizeItems(
    text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^\s*[-*]\s+'), '')),
  );

  static List<String> _normalizeItems(Iterable<String> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (item.trim().isNotEmpty && seen.add(item.trim())) item.trim(),
    ];
  }

  static String? _normalizeOptional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// 세션별 표시 단계(SessionTaskBoard 렌더링용).
enum SessionTaskPhase { idle, dispatched, working, done, error, waitingInput }

/// 오케스트레이터 LLM이 내린 한 iteration의 결정.
class AgentDecision {
  const AgentDecision({
    required this.thought,
    required this.actions,
    required this.continueLoop,
  });

  final String thought;
  final List<AgentAction> actions;
  final bool continueLoop;

  /// finish 액션이 있으면 그 요약을, 없으면 null.
  AgentAction? get finishAction {
    for (final action in actions) {
      if (action.tool == 'finish') return action;
    }
    return null;
  }

  /// ask_user 액션이 있으면 반환.
  AgentAction? get askUserAction {
    for (final action in actions) {
      if (action.tool == 'ask_user') return action;
    }
    return null;
  }

  /// LLM 원문(마크다운 코드펜스 포함 가능)에서 JSON을 관대하게 파싱한다.
  /// 실패하면 null.
  static AgentDecision? tryParse(String raw) {
    final jsonText = extractJson(raw);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final actionsRaw = decoded['actions'];
      final actions = <AgentAction>[];
      if (actionsRaw is List) {
        for (final item in actionsRaw) {
          if (item is Map) {
            final action = AgentAction.fromJson(item);
            if (action != null) actions.add(action);
          }
        }
      } else if (actionsRaw is Map) {
        final action = AgentAction.fromJson(actionsRaw);
        if (action != null) actions.add(action);
      }
      return AgentDecision(
        thought: decoded['thought'] is String
            ? (decoded['thought'] as String).trim()
            : '',
        actions: actions,
        continueLoop: decoded['continue'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// LLM 응답에서 JSON 객체 텍스트만 추출한다. 코드펜스로 감싼 경우와
  /// 앞뒤 설명이 붙은 경우를 모두 처리한다.
  static String? extractJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('```')) {
      final lines = trimmed.split('\n');
      if (lines.length >= 3 && lines.last.trim() == '```') {
        final inner = lines.sublist(1, lines.length - 1).join('\n').trim();
        // 코드펜스 안에서 다시 JSON 경계를 찾는다.
        final start = inner.indexOf('{');
        final end = inner.lastIndexOf('}');
        if (start != -1 && end > start) {
          return inner.substring(start, end + 1);
        }
        return inner;
      }
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return trimmed.substring(start, end + 1);
  }
}

/// 오케스트레이터가 선택한 단일 도구 호출.
class AgentAction {
  const AgentAction({
    required this.tool,
    this.sessionId,
    this.sessionIds = const [],
    this.prompt,
    this.input,
    this.seconds,
    this.timeoutSeconds,
    this.risk,
    this.capability,
    this.reason,
    this.summary,
    this.markdown,
    this.question,
    this.status,
    this.toSessionId,
    this.fromSessionId,
    this.body,
    this.awaitCompletion,
    this.inMinutes,
    this.at,
    this.goal,
  });

  /// 정규화된 도구명(소문자). read_sessions/send_prompt/send_keys/wait/
  /// report/ask_user/finish/post_message/broadcast/read_inbox/schedule.
  final String tool;
  final String? sessionId;
  final List<String> sessionIds;

  /// send_prompt: 세션 내 에이전트에게 보낼 자연어 지시.
  final String? prompt;

  /// send_keys: 키 토큰 원시 입력(`<Esc>`, `<C-c>`, `\n` 등).
  final String? input;

  /// wait: 대기 초.
  final int? seconds;

  /// send_prompt: quiescence 대기 상한(초).
  final int? timeoutSeconds;

  /// LLM 자기 신고 위험도("safe" | "destructive").
  final String? risk;

  /// send_prompt: 플래너가 자기 신고한 작업 종류. 역할 정책 판단에 쓴다.
  final AgentCapability? capability;
  final String? reason;

  /// finish: 사용자 대면 요약.
  final String? summary;

  /// report: 타임라인에 게시할 마크다운.
  final String? markdown;

  /// ask_user: 사용자에게 던지는 질문.
  final String? question;

  /// finish: achieved | partial | blocked.
  final String? status;

  /// post_message: 수신 세션.
  final String? toSessionId;

  /// post_message/broadcast: 발신 세션. 없으면 오케스트레이터 자신.
  final String? fromSessionId;

  /// post_message/broadcast: 메시지 본문.
  final String? body;

  /// send_prompt: 이번 step에서 결과를 기다릴지.
  ///
  /// null이면 기다린다(기존 동작). false면 배경 관찰로 넘겨 loop가 다른 세션
  /// 계획을 계속 진행하고, 결과는 완료된 뒤의 step에서 회수한다.
  final bool? awaitCompletion;

  /// schedule: 지금부터 몇 분 뒤에 후속 목표를 실행할지.
  final int? inMinutes;

  /// schedule: 후속 목표를 실행할 절대 시각(로컬). [inMinutes]보다 우선한다.
  final DateTime? at;

  /// schedule: 후속 실행에 넘길 목표. 없으면 현재 목표를 이어간다.
  final String? goal;

  /// LLM이 destructive로 자기 신고했는지.
  bool get selfReportedDestructive =>
      (risk ?? '').trim().toLowerCase() == 'destructive';

  /// 결과를 기다리지 않고 배경으로 돌리는 전송인지.
  bool get isBackgroundSend => awaitCompletion == false;

  static AgentAction? fromJson(Map<dynamic, dynamic> json) {
    final tool = json['tool'];
    if (tool is! String || tool.trim().isEmpty) return null;
    final idsRaw = json['session_ids'];
    final sessionIds = idsRaw is List
        ? [
            for (final id in idsRaw)
              if (id is String && id.trim().isNotEmpty) id.trim(),
          ]
        : const <String>[];
    return AgentAction(
      tool: tool.trim().toLowerCase(),
      sessionId: _string(json['session_id']),
      sessionIds: sessionIds,
      prompt: _string(json['prompt']),
      input: _string(json['input']),
      seconds: _int(json['seconds']),
      timeoutSeconds: _int(json['timeout_s']) ?? _int(json['timeout_seconds']),
      risk: _string(json['risk']),
      capability: AgentSessionRole.capabilityFromWire(
        _string(json['capability']) ?? '',
      ),
      reason: _string(json['reason']),
      summary: _string(json['summary']),
      markdown: _string(json['markdown']),
      question: _string(json['question']),
      status: _string(json['status']),
      toSessionId: _string(json['to_session_id']) ?? _string(json['to']),
      fromSessionId: _string(json['from_session_id']) ?? _string(json['from']),
      body: _string(json['body']) ?? _string(json['message']),
      awaitCompletion: _bool(json['await']) ?? _bool(json['await_completion']),
      inMinutes: _int(json['in_minutes']) ?? _int(json['minutes']),
      at: _dateTime(json['at']),
      goal: _string(json['goal']),
    );
  }

  static DateTime? _dateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim())?.toLocal();
  }

  static bool? _bool(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

/// 평가자 LLM의 판정.
class AgentVerification {
  const AgentVerification({
    required this.verdict,
    required this.summary,
    required this.goalMet,
    required this.continueLoop,
  });

  /// progress | ok | mistake | stuck | uncertain.
  final String verdict;
  final String summary;
  final bool goalMet;
  final bool continueLoop;

  bool get isProblem => verdict == 'mistake' || verdict == 'stuck';

  static AgentVerification? tryParse(String raw) {
    final jsonText = AgentDecision.extractJson(raw);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final rawVerdict = decoded['verdict'] is String
          ? (decoded['verdict'] as String).trim().toLowerCase()
          : 'uncertain';
      final verdict = switch (rawVerdict) {
        'progress' || 'ok' || 'mistake' || 'stuck' || 'uncertain' => rawVerdict,
        _ => 'uncertain',
      };
      final summary = decoded['summary'] is String
          ? (decoded['summary'] as String).trim()
          : '';
      return AgentVerification(
        verdict: verdict,
        summary: summary.isEmpty ? '검증 요약이 없습니다.' : summary,
        goalMet: decoded['goal_met'] == true,
        continueLoop: decoded['continue'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 승인을 요청한 이유의 종류.
enum PendingApprovalKind {
  /// 파괴적 명령으로 분류됨(기본).
  destructive,

  /// 세션 역할이 맡지 않는 작업을 반복해서 보내려 함.
  rolePolicy,
}

/// 승인 대기 중인 입력.
class PendingApproval {
  const PendingApproval({
    required this.sessionId,
    required this.sessionName,
    required this.description,
    required this.reason,
    this.screenContext = '',
    this.kind = PendingApprovalKind.destructive,
    this.capability,
  });

  final String sessionId;
  final String sessionName;

  /// 보내려는 입력(프롬프트 또는 키).
  final String description;

  /// 위험으로 분류된 근거.
  final String reason;

  /// 승인 판단에 사용한 최근 터미널 화면. 입력과 함께 사용자에게 보여 준다.
  final String screenContext;

  /// 승인을 요청한 이유의 종류.
  final PendingApprovalKind kind;

  /// [PendingApprovalKind.rolePolicy]일 때 문제가 된 작업 종류.
  final AgentCapability? capability;
}

const Object _taskUnchanged = Object();

/// 세션별 표시 상태.
class SessionTaskView {
  const SessionTaskView({
    required this.sessionId,
    required this.displayName,
    required this.agentHint,
    required this.phase,
    this.role,
    this.lastInstruction,
    this.unreadMessages = 0,
    this.backgroundRunning = false,
    this.detectedModel,
  });

  final String sessionId;
  final String displayName;

  /// 화면에서 추정한 실행 중 에이전트("claude" | "codex" | ... | "unknown").
  final String agentHint;
  final SessionTaskPhase phase;
  final AgentSessionRole? role;
  final String? lastInstruction;

  /// 이 세션 우편함에 쌓였지만 아직 전달되지 않은 메시지 수.
  ///
  /// 화면에는 흔적이 없는 상태라, 표시해주지 않으면 사용자는 왜 다음 지시에
  /// 갑자기 다른 세션 이야기가 붙는지 알 수 없다.
  final int unreadMessages;

  /// await:false로 내보낸 작업이 아직 돌고 있는지.
  final bool backgroundRunning;

  /// 화면에서 감지한(confirmed) 모델 라벨. 없으면 null.
  final String? detectedModel;

  /// 역할에 선언된 모델 라벨. CLI 무관 자유 텍스트.
  String? get declaredModel => role?.declaredModel;

  /// 선언된 모델과 감지된 모델이 둘 다 있고 서로 불일치하는지.
  bool get modelMismatch {
    final declared = declaredModel;
    final detected = detectedModel;
    if (declared == null || declared.isEmpty || detected == null) return false;
    return !AgentSessionInspector.modelMatches(declared, detected);
  }

  /// [detectedModel]·[role]은 센티널을 쓴다. null을 "안 바꿈"으로 읽으면
  /// 한 번 감지된 모델이나 배정된 역할을 다시 지울 방법이 없다.
  SessionTaskView copyWith({
    String? agentHint,
    SessionTaskPhase? phase,
    String? lastInstruction,
    int? unreadMessages,
    bool? backgroundRunning,
    Object? detectedModel = _taskUnchanged,
    Object? role = _taskUnchanged,
  }) => SessionTaskView(
    sessionId: sessionId,
    displayName: displayName,
    agentHint: agentHint ?? this.agentHint,
    phase: phase ?? this.phase,
    role: identical(role, _taskUnchanged)
        ? this.role
        : role as AgentSessionRole?,
    lastInstruction: lastInstruction ?? this.lastInstruction,
    unreadMessages: unreadMessages ?? this.unreadMessages,
    backgroundRunning: backgroundRunning ?? this.backgroundRunning,
    detectedModel: identical(detectedModel, _taskUnchanged)
        ? this.detectedModel
        : detectedModel as String?,
  );
}

/// 타임라인의 단위 이벤트. UI는 이 목록만 그린다.
sealed class AgentEvent {
  const AgentEvent(this.at);
  final DateTime at;
}

class LoopStartedEvent extends AgentEvent {
  const LoopStartedEvent(
    super.at, {
    required this.goal,
    required this.scope,
    this.goalSpec,
  });
  final String goal;
  final String scope;
  final AgentGoalSpec? goalSpec;
}

class LoopFinishedEvent extends AgentEvent {
  const LoopFinishedEvent(
    super.at, {
    required this.outcome,
    required this.summary,
    required this.steps,
    required this.elapsed,
  });
  final AgentLoopOutcome outcome;
  final String summary;
  final int steps;
  final Duration elapsed;
}

class ThoughtEvent extends AgentEvent {
  const ThoughtEvent(super.at, {required this.step, required this.text});
  final int step;
  final String text;
}

class DispatchedEvent extends AgentEvent {
  const DispatchedEvent(
    super.at, {
    required this.sessionId,
    required this.sessionName,
    required this.kind,
    required this.payload,
    this.reason,
    this.capability,
  });
  final String sessionId;
  final String sessionName;

  /// "prompt" | "keys" | "wait".
  final String kind;
  final String payload;
  final String? reason;

  /// 이 지시가 어떤 작업 종류로 분류됐는지. 분류되지 않으면 null.
  final AgentCapability? capability;
}

class ObservedEvent extends AgentEvent {
  const ObservedEvent(
    super.at, {
    required this.sessionId,
    required this.sessionName,
    required this.delta,
    required this.quiescent,
    this.isSnapshot = false,
  });
  final String sessionId;
  final String sessionName;
  final String delta;
  final bool quiescent;
  final bool isSnapshot;
}

class VerifiedEvent extends AgentEvent {
  const VerifiedEvent(super.at, {required this.verdict, required this.summary});
  final String verdict;
  final String summary;
}

class ReportEvent extends AgentEvent {
  const ReportEvent(super.at, {required this.markdown});
  final String markdown;
}

class UserFeedbackEvent extends AgentEvent {
  const UserFeedbackEvent(super.at, {required this.text});
  final String text;
}

class ApprovalRequestedEvent extends AgentEvent {
  const ApprovalRequestedEvent(super.at, {required this.approval});
  final PendingApproval approval;
}

class ApprovalResolvedEvent extends AgentEvent {
  const ApprovalResolvedEvent(
    super.at, {
    required this.approved,
    required this.description,
  });
  final bool approved;
  final String description;
}

/// 관찰이 잠잠해진 직후 세션이 한 일의 요약.
///
/// 다음 스텝 프롬프트에 "이 세션 방금 뭘 했는지"를 실어 보내기 위한 것이라,
/// 델타 원문이 아니라 사람이 훑어볼 수 있는 꼬리 요약만 담는다.
class AgentHandoff {
  const AgentHandoff({
    required this.sessionId,
    required this.sessionName,
    required this.roleKind,
    required this.instruction,
    required this.summary,
    required this.at,
  });

  final String sessionId;
  final String sessionName;

  /// 역할이 없으면 custom.
  final AgentRoleKind roleKind;

  /// 이 세션에 보낸 지시(200자 이내로 잘림).
  final String instruction;

  /// 관찰된 화면 델타의 꼬리 요약(정규화된 마지막 줄들).
  final String summary;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'sessionName': sessionName,
    'roleKind': roleKind.name,
    'instruction': instruction,
    'summary': summary,
    'at': at.toUtc().toIso8601String(),
  };

  static AgentHandoff? fromJson(Object? value) {
    if (value is! Map) return null;
    final sessionId = value['sessionId'];
    final sessionName = value['sessionName'];
    final instruction = value['instruction'];
    final summary = value['summary'];
    final at = value['at'];
    if (sessionId is! String ||
        sessionName is! String ||
        instruction is! String ||
        summary is! String ||
        at is! String) {
      return null;
    }
    final parsedAt = DateTime.tryParse(at);
    if (parsedAt == null) return null;
    final roleKind = AgentRoleKind.values.firstWhere(
      (kind) => kind.name == value['roleKind'],
      orElse: () => AgentRoleKind.custom,
    );
    return AgentHandoff(
      sessionId: sessionId,
      sessionName: sessionName,
      roleKind: roleKind,
      instruction: instruction,
      summary: summary,
      at: parsedAt,
    );
  }
}

/// 인계 기록을 상한을 지켜 덧붙인다.
///
/// 오케스트레이터(실행 중 누적)와 Notifier(이벤트 스트림 누적)가 같은 상한을
/// 각자 구현하고 있었다. 규칙이 갈라지지 않도록 한 곳에 모은다.
///
/// [current]는 바꾸지 않고 새 리스트를 돌려준다. 같은 세션 것이 [perSession]을
/// 넘으면 그 세션 기록 중 오래된 것부터 지우고, 그래도 전체가 [total]을 넘으면
/// 세션과 무관하게 앞에서부터 지운다. 방금 넣은 [next]는 지우지 않는다.
List<AgentHandoff> appendHandoffWithCaps(
  List<AgentHandoff> current,
  AgentHandoff next, {
  int perSession = 2,
  int total = 12,
}) {
  final result = [...current, next];
  final forSession = result
      .where((handoff) => handoff.sessionId == next.sessionId)
      .length;
  if (forSession > perSession) {
    var remaining = forSession - perSession;
    result.removeWhere((handoff) {
      if (remaining <= 0) return false;
      if (handoff.sessionId != next.sessionId || identical(handoff, next)) {
        return false;
      }
      remaining--;
      return true;
    });
  }
  if (result.length > total) {
    result.removeRange(0, result.length - total);
  }
  return result;
}

/// 세션 관찰이 잠잠해진 뒤 인계 기록이 남았다.
class HandoffRecordedEvent extends AgentEvent {
  const HandoffRecordedEvent(super.at, {required this.handoff});
  final AgentHandoff handoff;
}

/// 세션 역할이 맡지 않는 작업이라 전송을 거부했다.
class RolePolicyRejectedEvent extends AgentEvent {
  const RolePolicyRejectedEvent(
    super.at, {
    required this.sessionId,
    required this.sessionName,
    required this.roleKind,
    required this.capability,
    required this.reason,
  });

  final String sessionId;
  final String sessionName;
  final AgentRoleKind roleKind;
  final AgentCapability capability;
  final String reason;
}

class AskUserEvent extends AgentEvent {
  const AskUserEvent(super.at, {required this.question});
  final String question;
}

/// 세션 간 메시지가 우편함에 들어갔다. 아직 배달은 되지 않았다.
class MessagePostedEvent extends AgentEvent {
  const MessagePostedEvent(
    super.at, {
    required this.from,
    required this.to,
    required this.body,
  });
  final String from;
  final String to;
  final String body;
}

/// 배달 전에 우편함에서 거둬들인 메시지.
class MessageWithdrawnEvent extends AgentEvent {
  const MessageWithdrawnEvent(
    super.at, {
    required this.from,
    required this.to,
    required this.body,
  });
  final String from;
  final String to;
  final String body;
}

/// 우편함의 메시지가 수신 세션 프롬프트에 실제로 주입되었다.
class MessageDeliveredEvent extends AgentEvent {
  const MessageDeliveredEvent(
    super.at, {
    required this.sessionId,
    required this.sessionName,
    required this.senders,
  });
  final String sessionId;
  final String sessionName;

  /// 이번에 배달된 메시지들의 발신자. 길이가 곧 배달 통수다.
  final List<String> senders;

  int get count => senders.length;
}

class LoopErrorEvent extends AgentEvent {
  const LoopErrorEvent(super.at, {required this.message});
  final String message;
}

/// 목표 계약의 마감 시각을 지나 loop가 멈췄다.
class DeadlineReachedEvent extends AgentEvent {
  const DeadlineReachedEvent(
    super.at, {
    required this.deadline,
    required this.overrun,
  });

  final DateTime deadline;

  /// 마감을 얼마나 넘겼는지. 마감 직후 감지되면 0에 가깝다.
  final Duration overrun;
}

/// 예약된 작업이 시각이 되어 loop를 시작했다.
///
/// 사용자가 시작 버튼을 누르지 않았는데 loop가 도는 이유를 타임라인이 설명한다.
class ScheduleTriggeredEvent extends AgentEvent {
  const ScheduleTriggeredEvent(
    super.at, {
    required this.taskId,
    required this.title,
    required this.triggerLabel,
    this.interruptedGoal,
  });

  final String taskId;
  final String title;

  /// "매일 09:30", "30분마다" 같은 트리거 설명.
  final String triggerLabel;

  /// 전환 정책으로 중단시킨 직전 목표. 없으면 null.
  final String? interruptedGoal;
}

/// 오케스트레이터가 후속 작업을 예약했다.
class ScheduleRequestedEvent extends AgentEvent {
  const ScheduleRequestedEvent(
    super.at, {
    required this.taskId,
    required this.title,
    required this.runAt,
    this.reason,
  });

  final String taskId;
  final String title;
  final DateTime runAt;
  final String? reason;
}

class TerminalRuntimeIssueEvent extends AgentEvent {
  const TerminalRuntimeIssueEvent(
    super.at, {
    required this.code,
    required this.sessionId,
    required this.sessionName,
    required this.message,
    required this.evidence,
  });

  final String code;
  final String sessionId;
  final String sessionName;
  final String message;
  final String evidence;
}

/// 오케스트레이터 LLM 호출이 일시적 오류로 실패해 자동 재시도를 예약했다.
///
/// loop는 멈추지 않는다. 사용자는 이 행으로 "왜 조용한지"와 "몇 번째 시도인지"를
/// 알 수 있고, 언제든 중단할 수 있다.
class LoopRetryEvent extends AgentEvent {
  const LoopRetryEvent(
    super.at, {
    required this.attempt,
    required this.delay,
    required this.message,
  });

  /// 1부터 세는 연속 재시도 횟수. 성공하면 0으로 돌아간다.
  final int attempt;
  final Duration delay;
  final String message;
}

/// 세션의 CLI 에이전트가 provider·네트워크 오류나 무응답으로 멈춰서
/// 오케스트레이터가 같은 작업을 이어가라고 자동으로 다시 지시했다.
class SessionRetryEvent extends AgentEvent {
  const SessionRetryEvent(
    super.at, {
    required this.sessionId,
    required this.sessionName,
    required this.attempt,
    required this.reason,
    required this.evidence,
  });

  final String sessionId;
  final String sessionName;
  final int attempt;

  /// 사람이 읽는 재시도 이유("LLM 서버 연결 오류", "응답 없음").
  final String reason;

  /// 화면에서 잡은 근거 문구. 비어 있을 수 있다.
  final String evidence;
}

/// 이전 이벤트가 접혔음을 나타내는 요약 행.
class CollapsedEvent extends AgentEvent {
  const CollapsedEvent(super.at, {required this.count});
  final int count;
}

/// 앱 수준 loop 상태 스냅샷.
class AgentLoopState {
  const AgentLoopState({
    required this.status,
    this.goal,
    this.goalSpec,
    this.step = 0,
    this.maxSteps = defaultMaxSteps,
    this.startedAt,
    this.allowedSessionIds = const [],
    this.sessionRoles = const {},
    this.sessionTasks = const {},
    this.events = const [],
    this.pendingApproval,
    this.pendingQuestion,
    this.pauseReason,
    this.pauseMessage,
    this.outcome,
    this.undeliveredMessages = const [],
    this.resetInProgress = false,
    this.handoffs = const [],
  });

  static const defaultMaxSteps = 25;
  static const maxEvents = 500;

  final AgentLoopStatus status;

  /// 삭제 트랜잭션 동안 새 실행을 막는 일시적 UI 상태. 디스크에는 저장하지 않는다.
  final bool resetInProgress;
  final String? goal;
  final AgentGoalSpec? goalSpec;
  final int step;
  final int maxSteps;
  final DateTime? startedAt;
  final List<String> allowedSessionIds;
  final Map<String, AgentSessionRole> sessionRoles;
  final Map<String, SessionTaskView> sessionTasks;
  final List<AgentEvent> events;
  final PendingApproval? pendingApproval;

  /// ask_user로 대기 중인 질문.
  final String? pendingQuestion;
  final AgentPauseReason? pauseReason;
  final String? pauseMessage;
  final AgentLoopOutcome? outcome;

  /// 우편함에 쌓였지만 아직 세션에 주입되지 않은 메시지.
  ///
  /// 우편함은 오케스트레이터 메모리에만 있어서, 여기 복제해 두지 않으면 앱을
  /// 재시작하거나 loop가 끝난 뒤 "같은 목표 이어가기"를 해도 미배달 메시지가
  /// 사라진다.
  final List<AgentMessage> undeliveredMessages;

  /// 세션별 최근 인계 기록. 세션당 최대 2개, 전체 최대 12개.
  final List<AgentHandoff> handoffs;

  static const idle = AgentLoopState(status: AgentLoopStatus.idle);

  bool get isRunning =>
      status != AgentLoopStatus.idle && status != AgentLoopStatus.finished;

  /// 사용자가 새 Goal을 시작할 수 있는 상태.
  bool get canStart =>
      !resetInProgress &&
      (status == AgentLoopStatus.idle || status == AgentLoopStatus.finished);

  AgentLoopState copyWith({
    bool? resetInProgress,
    AgentLoopStatus? status,
    String? goal,
    Object? goalSpec = _unchanged,
    int? step,
    int? maxSteps,
    DateTime? startedAt,
    List<String>? allowedSessionIds,
    Map<String, AgentSessionRole>? sessionRoles,
    Map<String, SessionTaskView>? sessionTasks,
    List<AgentEvent>? events,
    Object? pendingApproval = _unchanged,
    Object? pendingQuestion = _unchanged,
    Object? pauseReason = _unchanged,
    Object? pauseMessage = _unchanged,
    Object? outcome = _unchanged,
    List<AgentMessage>? undeliveredMessages,
    List<AgentHandoff>? handoffs,
  }) => AgentLoopState(
    resetInProgress: resetInProgress ?? this.resetInProgress,
    status: status ?? this.status,
    goal: goal ?? this.goal,
    goalSpec: identical(goalSpec, _unchanged)
        ? this.goalSpec
        : goalSpec as AgentGoalSpec?,
    step: step ?? this.step,
    maxSteps: maxSteps ?? this.maxSteps,
    startedAt: startedAt ?? this.startedAt,
    allowedSessionIds: allowedSessionIds ?? this.allowedSessionIds,
    sessionRoles: sessionRoles ?? this.sessionRoles,
    sessionTasks: sessionTasks ?? this.sessionTasks,
    events: events ?? this.events,
    pendingApproval: identical(pendingApproval, _unchanged)
        ? this.pendingApproval
        : pendingApproval as PendingApproval?,
    pendingQuestion: identical(pendingQuestion, _unchanged)
        ? this.pendingQuestion
        : pendingQuestion as String?,
    pauseReason: identical(pauseReason, _unchanged)
        ? this.pauseReason
        : pauseReason as AgentPauseReason?,
    pauseMessage: identical(pauseMessage, _unchanged)
        ? this.pauseMessage
        : pauseMessage as String?,
    outcome: identical(outcome, _unchanged)
        ? this.outcome
        : outcome as AgentLoopOutcome?,
    undeliveredMessages: undeliveredMessages ?? this.undeliveredMessages,
    handoffs: handoffs ?? this.handoffs,
  );

  static const Object _unchanged = Object();
}
