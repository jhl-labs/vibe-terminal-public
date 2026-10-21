/// Agent Chat 예약 실행의 도메인 모델.
///
/// 순수 Dart(Flutter 무관). "언제 실행할지"(트리거)와 "무엇을 실행할지"(목표 계약과
/// 세션 범위)를 한 건의 예약으로 묶고, JSON으로 저장·복원한다. 시각 계산은 모두
/// 로컬 시간을 기준으로 하며, 실제 타이머와 실행은 [AgentScheduler]가 맡는다.
library;

import 'agent_models.dart';
import 'agent_session_role.dart';
import 'cron_expression.dart';

/// 예약이 반복되는 방식.
enum AgentScheduleKind {
  /// 지정한 시각에 한 번.
  once,

  /// 매일 같은 시:분.
  daily,

  /// 마지막 실행(또는 등록) 뒤 일정 간격마다.
  interval,

  /// cron 표현식(`분 시 일 월 요일`)이 맞는 매 분.
  cron,
}

/// 예약 시각이 되었을 때 loop가 이미 돌고 있으면 어떻게 할지.
enum AgentScheduleConflictPolicy {
  /// 현재 loop가 끝난 뒤 시작한다. 시각은 지났지만 놓치지 않는다.
  wait,

  /// 현재 loop를 중단하고 예약된 목표로 전환한다. 시간 기반 업무 전환용.
  interrupt,
}

/// 누가 예약을 등록했는지.
enum AgentScheduleOrigin { user, orchestrator }

/// 예약이 시각이 되었을 때 하는 일.
enum AgentScheduleTaskKind {
  /// 목표 계약으로 새 loop를 시작한다.
  goal,

  /// 실행 중인 loop의 세션 우편함에 메시지를 넣는다. loop가 없으면 그 세션을
  /// 포함한 loop가 시작될 때까지 기다린다.
  message,

  /// AI Chat 루틴: 세션 하나에 저장된 프롬프트로 AI Chat 턴을 헤드리스로
  /// 돌리고 결과를 그 세션의 AI Chat 대화에 남긴다. Agent Chat loop와 무관하다.
  aiChat,
}

/// 예약이 시작한 loop 한 번의 결과. 예약 항목에 최근 몇 회를 남긴다.
class AgentScheduleRunRecord {
  const AgentScheduleRunRecord({
    required this.startedAt,
    required this.finishedAt,
    required this.outcome,
    required this.summary,
    required this.steps,
    this.runId,
  });

  final DateTime startedAt;
  final DateTime finishedAt;

  /// achieved | partial | blocked | stopped | failed | delivered.
  final String outcome;
  final String summary;
  final int steps;

  /// 실행 기록 파일(`agent_chat/history/<runId>.jsonl`)의 id. 없으면 null.
  final String? runId;

  Duration get elapsed {
    final value = finishedAt.difference(startedAt);
    return value.isNegative ? Duration.zero : value;
  }

  Map<String, Object?> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'outcome': outcome,
    'summary': summary,
    'steps': steps,
    'runId': runId,
  };

  static AgentScheduleRunRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final startedAt = DateTime.tryParse(value['startedAt']?.toString() ?? '');
    final finishedAt = DateTime.tryParse(value['finishedAt']?.toString() ?? '');
    final outcome = value['outcome'];
    if (startedAt == null || finishedAt == null || outcome is! String) {
      return null;
    }
    return AgentScheduleRunRecord(
      startedAt: startedAt.toLocal(),
      finishedAt: finishedAt.toLocal(),
      outcome: outcome,
      summary: _string(value['summary']) ?? '',
      steps: _integer(value['steps']) ?? 0,
      runId: _string(value['runId']),
    );
  }
}

/// 실행 시점 규칙.
class AgentScheduleTrigger {
  const AgentScheduleTrigger._({
    required this.kind,
    this.at,
    this.hour,
    this.minute,
    this.every,
    this.cron,
  });

  /// [at]에 한 번 실행한다.
  const AgentScheduleTrigger.once(DateTime at)
    : this._(kind: AgentScheduleKind.once, at: at);

  /// 매일 [hour]:[minute]에 실행한다.
  const AgentScheduleTrigger.daily({required int hour, required int minute})
    : this._(kind: AgentScheduleKind.daily, hour: hour, minute: minute);

  /// [every] 간격으로 반복한다.
  const AgentScheduleTrigger.interval(Duration every)
    : this._(kind: AgentScheduleKind.interval, every: every);

  /// [cron] 표현식이 맞는 매 분에 실행한다.
  AgentScheduleTrigger.cron(CronExpression cron)
    : this._(kind: AgentScheduleKind.cron, cron: cron);

  final AgentScheduleKind kind;
  final DateTime? at;
  final int? hour;
  final int? minute;
  final Duration? every;
  final CronExpression? cron;

  /// 최소 반복 간격. 이보다 짧으면 LLM 호출이 쉴 새 없이 이어진다.
  static const minInterval = Duration(minutes: 1);

  bool get isRecurring => kind != AgentScheduleKind.once;

  /// [now] 이후 처음 실행할 시각. 더 실행할 게 없으면 null.
  ///
  /// [anchor]는 간격 반복의 기준점(마지막 실행 또는 등록 시각)이다.
  DateTime? nextAfter(DateTime now, {DateTime? anchor}) {
    switch (kind) {
      case AgentScheduleKind.once:
        final target = at;
        if (target == null || !target.isAfter(now)) return null;
        return target;
      case AgentScheduleKind.daily:
        final candidate = DateTime(
          now.year,
          now.month,
          now.day,
          hour ?? 0,
          minute ?? 0,
        );
        if (candidate.isAfter(now)) return candidate;
        return DateTime(
          now.year,
          now.month,
          now.day + 1,
          hour ?? 0,
          minute ?? 0,
        );
      case AgentScheduleKind.interval:
        final step = every;
        if (step == null || step < minInterval) return null;
        final base = anchor ?? now;
        final first = base.add(step);
        if (first.isAfter(now)) return first;
        // 기준점이 오래됐으면 지난 회차를 모두 건너뛰고 다음 정각 회차로 간다.
        final elapsed = now.difference(base).inMicroseconds;
        final skipped = elapsed ~/ step.inMicroseconds + 1;
        return base.add(step * skipped);
      case AgentScheduleKind.cron:
        return cron?.nextAfter(now);
    }
  }

  /// 사용자에게 보여줄 짧은 설명.
  String get label => switch (kind) {
    AgentScheduleKind.once => at == null ? '1회' : '${formatDateTime(at!)} 1회',
    AgentScheduleKind.daily =>
      '매일 ${_twoDigits(hour ?? 0)}:${_twoDigits(minute ?? 0)}',
    AgentScheduleKind.interval => '${formatDuration(every ?? Duration.zero)}마다',
    AgentScheduleKind.cron => cron?.label ?? 'cron',
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (at != null) 'at': at!.toUtc().toIso8601String(),
    if (hour != null) 'hour': hour,
    if (minute != null) 'minute': minute,
    if (every != null) 'everyMs': every!.inMilliseconds,
    if (cron != null) 'cron': cron!.source,
  };

  static AgentScheduleTrigger? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = _enumByName(AgentScheduleKind.values, value['kind']);
    switch (kind) {
      case AgentScheduleKind.once:
        final at = DateTime.tryParse(value['at']?.toString() ?? '');
        return at == null ? null : AgentScheduleTrigger.once(at.toLocal());
      case AgentScheduleKind.daily:
        final hour = _integer(value['hour']);
        final minute = _integer(value['minute']);
        if (hour == null || minute == null) return null;
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
        return AgentScheduleTrigger.daily(hour: hour, minute: minute);
      case AgentScheduleKind.interval:
        final ms = _integer(value['everyMs']);
        if (ms == null || ms <= 0) return null;
        return AgentScheduleTrigger.interval(Duration(milliseconds: ms));
      case AgentScheduleKind.cron:
        final parsed = CronExpression.tryParse(value['cron']?.toString() ?? '');
        return parsed == null ? null : AgentScheduleTrigger.cron(parsed);
      case null:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AgentScheduleTrigger &&
      other.kind == kind &&
      other.at == at &&
      other.hour == hour &&
      other.minute == minute &&
      other.every == every &&
      other.cron == cron;

  @override
  int get hashCode => Object.hash(kind, at, hour, minute, every, cron);

  /// `2026-09-07 15:00` 형태의 로컬 시각.
  static String formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }

  /// `1시간 30분`, `45분`, `30초` 형태.
  static String formatDuration(Duration value) {
    if (value.inSeconds < 60) return '${value.inSeconds}초';
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    if (hours == 0) return '$minutes분';
    if (minutes == 0) return '$hours시간';
    return '$hours시간 $minutes분';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

/// 예약 한 건. 불변 값이며 변경은 [copyWith]로 새 인스턴스를 만든다.
class AgentScheduledTask {
  const AgentScheduledTask({
    required this.id,
    required this.goalSpec,
    required this.allowedSessionIds,
    this.sessionBindings = const {},
    required this.trigger,
    required this.createdAt,
    this.sessionRoles = const {},
    this.conflictPolicy = AgentScheduleConflictPolicy.wait,
    this.origin = AgentScheduleOrigin.user,
    this.enabled = true,
    this.nextRunAt,
    this.lastRunAt,
    this.lastResult,
    this.runCount = 0,
    this.timeBudget,
    this.reason,
    this.kind = AgentScheduleTaskKind.goal,
    this.messageBody,
    this.terminalToolCall = false,
    this.history = const [],
  });

  /// 예약 항목에 남기는 최근 실행 기록 수.
  static const maxHistory = 10;

  final String id;
  final AgentGoalSpec goalSpec;
  final List<String> allowedSessionIds;
  final Map<String, String> sessionBindings;
  final Map<String, AgentSessionRole> sessionRoles;
  final AgentScheduleTrigger trigger;
  final AgentScheduleConflictPolicy conflictPolicy;
  final AgentScheduleOrigin origin;
  final bool enabled;
  final DateTime createdAt;

  /// 다음 실행 예정 시각. null이면 더 실행할 회차가 없다.
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;

  /// 마지막 실행/건너뜀에 대한 짧은 설명. UI 목록에 보여준다.
  final String? lastResult;
  final int runCount;

  /// 실행 시점에 목표 마감으로 환산할 시간 예산. 반복 예약은 절대 시각 마감을
  /// 둘 수 없으므로 상대 시간으로 보관한다.
  final Duration? timeBudget;

  /// 오케스트레이터가 예약했을 때 남긴 이유.
  final String? reason;

  final AgentScheduleTaskKind kind;

  /// [AgentScheduleTaskKind.message]일 때 넣을 본문, [AgentScheduleTaskKind.aiChat]일
  /// 때 AI Chat에 보낼 프롬프트. 대상 세션은 [allowedSessionIds]의 첫 항목이다.
  final String? messageBody;

  /// AI Chat 루틴이 답변만 하지 않고 터미널 tool call(send_input)까지 허용하는지.
  final bool terminalToolCall;

  /// 최근 실행 기록. 최신이 앞이다.
  final List<AgentScheduleRunRecord> history;

  bool get isMessage => kind == AgentScheduleTaskKind.message;

  bool get isAiChat => kind == AgentScheduleTaskKind.aiChat;

  /// 메시지 예약의 수신 세션.
  String? get messageSessionId => isMessage && allowedSessionIds.isNotEmpty
      ? allowedSessionIds.first
      : null;

  /// AI Chat 루틴이 붙는 세션.
  String? get aiChatSessionId =>
      isAiChat && allowedSessionIds.isNotEmpty ? allowedSessionIds.first : null;

  /// 목록에 보여줄 한 줄 제목. 목표(또는 메시지·프롬프트 본문)의 첫 줄을 80자로 자른다.
  String get title {
    final source = isMessage || isAiChat
        ? (messageBody ?? '')
        : goalSpec.objective;
    final firstLine = source.trim().split('\n').first.trim();
    return firstLine.length <= 80
        ? firstLine
        : '${firstLine.substring(0, 80)}…';
  }

  /// [record]를 맨 앞에 넣은 사본. [maxHistory]개만 남긴다.
  AgentScheduledTask withRunRecord(AgentScheduleRunRecord record) => copyWith(
    history: List.unmodifiable([record, ...history].take(maxHistory)),
  );

  bool get isDue => enabled && nextRunAt != null;

  /// 예약 id. 시각과 카운터를 섞어 같은 밀리초에 여러 건이 등록돼도 겹치지 않는다.
  static String newId(DateTime now, int counter) =>
      'sched-${now.toUtc().microsecondsSinceEpoch}-$counter';

  AgentScheduledTask copyWith({
    AgentGoalSpec? goalSpec,
    List<String>? allowedSessionIds,
    Map<String, String>? sessionBindings,
    Map<String, AgentSessionRole>? sessionRoles,
    AgentScheduleTrigger? trigger,
    AgentScheduleConflictPolicy? conflictPolicy,
    bool? enabled,
    Object? nextRunAt = _unchanged,
    Object? lastRunAt = _unchanged,
    Object? lastResult = _unchanged,
    int? runCount,
    Object? timeBudget = _unchanged,
    Object? messageBody = _unchanged,
    bool? terminalToolCall,
    List<AgentScheduleRunRecord>? history,
  }) => AgentScheduledTask(
    id: id,
    goalSpec: goalSpec ?? this.goalSpec,
    allowedSessionIds: allowedSessionIds ?? this.allowedSessionIds,
    sessionBindings: sessionBindings ?? this.sessionBindings,
    sessionRoles: sessionRoles ?? this.sessionRoles,
    trigger: trigger ?? this.trigger,
    conflictPolicy: conflictPolicy ?? this.conflictPolicy,
    origin: origin,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
    nextRunAt: identical(nextRunAt, _unchanged)
        ? this.nextRunAt
        : nextRunAt as DateTime?,
    lastRunAt: identical(lastRunAt, _unchanged)
        ? this.lastRunAt
        : lastRunAt as DateTime?,
    lastResult: identical(lastResult, _unchanged)
        ? this.lastResult
        : lastResult as String?,
    runCount: runCount ?? this.runCount,
    timeBudget: identical(timeBudget, _unchanged)
        ? this.timeBudget
        : timeBudget as Duration?,
    reason: reason,
    kind: kind,
    messageBody: identical(messageBody, _unchanged)
        ? this.messageBody
        : messageBody as String?,
    terminalToolCall: terminalToolCall ?? this.terminalToolCall,
    history: history ?? this.history,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'messageBody': messageBody,
    'terminalToolCall': terminalToolCall,
    'history': [for (final record in history) record.toJson()],
    'goalSpec': {
      'objective': goalSpec.objective,
      'successCriteria': goalSpec.successCriteria,
      'verificationSteps': goalSpec.verificationSteps,
      'constraints': goalSpec.constraints,
      'continuationContext': goalSpec.continuationContext,
    },
    'allowedSessionIds': allowedSessionIds,
    'sessionBindings': sessionBindings,
    'sessionRoles': sessionRolesToJson(sessionRoles),
    'trigger': trigger.toJson(),
    'conflictPolicy': conflictPolicy.name,
    'origin': origin.name,
    'enabled': enabled,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'nextRunAt': nextRunAt?.toUtc().toIso8601String(),
    'lastRunAt': lastRunAt?.toUtc().toIso8601String(),
    'lastResult': lastResult,
    'runCount': runCount,
    'timeBudgetMs': timeBudget?.inMilliseconds,
    'reason': reason,
  };

  static AgentScheduledTask? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final rawGoal = value['goalSpec'];
    final trigger = AgentScheduleTrigger.fromJson(value['trigger']);
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    if (id is! String ||
        id.isEmpty ||
        rawGoal is! Map ||
        rawGoal['objective'] is! String ||
        trigger == null ||
        createdAt == null) {
      return null;
    }
    final budgetMs = _integer(value['timeBudgetMs']);
    return AgentScheduledTask(
      id: id,
      goalSpec: AgentGoalSpec(
        objective: rawGoal['objective'] as String,
        successCriteria: _stringList(rawGoal['successCriteria']),
        verificationSteps: _stringList(rawGoal['verificationSteps']),
        constraints: _stringList(rawGoal['constraints']),
        continuationContext: _string(rawGoal['continuationContext']),
      ).normalized(),
      allowedSessionIds: _stringList(value['allowedSessionIds']),
      sessionBindings: {
        if (value['sessionBindings'] is Map)
          for (final entry in (value['sessionBindings'] as Map).entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
      sessionRoles: sessionRolesFromJson(value['sessionRoles']),
      trigger: trigger,
      conflictPolicy:
          _enumByName(
            AgentScheduleConflictPolicy.values,
            value['conflictPolicy'],
          ) ??
          AgentScheduleConflictPolicy.wait,
      origin:
          _enumByName(AgentScheduleOrigin.values, value['origin']) ??
          AgentScheduleOrigin.user,
      enabled: value['enabled'] != false,
      createdAt: createdAt.toLocal(),
      nextRunAt: DateTime.tryParse(
        value['nextRunAt']?.toString() ?? '',
      )?.toLocal(),
      lastRunAt: DateTime.tryParse(
        value['lastRunAt']?.toString() ?? '',
      )?.toLocal(),
      lastResult: _string(value['lastResult']),
      runCount: _integer(value['runCount']) ?? 0,
      timeBudget: budgetMs == null || budgetMs <= 0
          ? null
          : Duration(milliseconds: budgetMs),
      reason: _string(value['reason']),
      kind:
          _enumByName(AgentScheduleTaskKind.values, value['kind']) ??
          AgentScheduleTaskKind.goal,
      messageBody: _string(value['messageBody']),
      terminalToolCall: value['terminalToolCall'] == true,
      history: value['history'] is List
          ? List.unmodifiable(
              [
                for (final item in value['history'] as List)
                  ?AgentScheduleRunRecord.fromJson(item),
              ].take(maxHistory),
            )
          : const [],
    );
  }

  static const Object _unchanged = Object();
}

/// 예약이 loop를 시작시켰음을 Notifier에 알리는 값. 타임라인 카드가 된다.
class AgentScheduledStart {
  const AgentScheduledStart({
    required this.taskId,
    required this.title,
    required this.triggerLabel,
    this.interruptedGoal,
  });

  final String taskId;
  final String title;
  final String triggerLabel;

  /// 전환 정책으로 중단시킨 직전 목표.
  final String? interruptedGoal;
}

/// 오케스트레이터가 loop 안에서 후속 작업 예약을 요청할 때 넘기는 값.
///
/// 오케스트레이터는 스케줄러 구현을 모르고 이 요청만 만든다. 등록 여부와
/// 결과 id는 콜백이 돌려준다.
class AgentScheduleRequest {
  const AgentScheduleRequest({
    required this.goal,
    required this.runAt,
    required this.allowedSessionIds,
    this.sessionRoles = const {},
    this.reason,
    this.timeBudget,
  });

  final AgentGoalSpec goal;
  final DateTime runAt;
  final List<String> allowedSessionIds;
  final Map<String, AgentSessionRole> sessionRoles;
  final String? reason;
  final Duration? timeBudget;
}

T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}

int? _integer(Object? value) => switch (value) {
  int() => value,
  num() => value.round(),
  String() => int.tryParse(value),
  _ => null,
};

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

List<String> _stringList(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is String) item,
      ]
    : const [];
