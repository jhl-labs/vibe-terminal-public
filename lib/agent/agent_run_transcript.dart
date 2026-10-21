import 'agent_models.dart';

abstract final class AgentRunTranscript {
  static String format(AgentLoopState state, List<AgentEvent> events) {
    final buffer = StringBuffer()
      ..writeln('Agent Chat 실행 기록')
      ..writeln('목표: ${state.goal ?? '(없음)'}')
      ..writeln('상태: ${state.status.name}')
      ..writeln('Step: ${state.step}/${state.maxSteps}')
      ..writeln('세션: ${state.allowedSessionIds.join(', ')}');
    if (state.sessionRoles.isNotEmpty) {
      buffer.writeln(
        '역할: ${state.sessionRoles.entries.map((entry) => '${entry.key}=${entry.value.label}').join(', ')}',
      );
    }
    buffer.writeln();

    for (final event in events.where((event) => event is! CollapsedEvent)) {
      buffer
        ..writeln('[${_time(event.at)}] ${_title(event)}')
        ..writeln(_body(event).trimRight())
        ..writeln();
    }
    return buffer.toString().trimRight();
  }

  static String _title(AgentEvent event) => switch (event) {
    LoopStartedEvent(:final scope) => '목표 시작 · $scope',
    LoopFinishedEvent(:final outcome) => 'Loop 종료 · ${outcome.name}',
    ThoughtEvent(:final step) => 'Step $step 계획',
    DispatchedEvent(:final sessionName, :final kind) =>
      '$sessionName · ${kind == 'prompt' ? '지시' : '키 입력'}',
    ObservedEvent(:final sessionName, :final isSnapshot) =>
      '$sessionName · ${isSnapshot ? '화면 확인' : '관찰'}',
    VerifiedEvent(:final verdict) => '평가 · $verdict',
    ReportEvent() => '보고',
    UserFeedbackEvent() => '사용자 피드백',
    ApprovalRequestedEvent(:final approval) =>
      '승인 요청 · ${approval.sessionName}',
    ApprovalResolvedEvent(:final approved) => approved ? '승인됨' : '거부됨',
    RolePolicyRejectedEvent(:final sessionName) => '역할 정책 거부 · $sessionName',
    HandoffRecordedEvent(:final handoff) => '인계 기록 · ${handoff.sessionName}',
    AskUserEvent() => '사용자 질문',
    MessagePostedEvent(:final from, :final to) => '메시지 · $from → $to',
    MessageWithdrawnEvent(:final from, :final to) => '메시지 회수 · $from → $to',
    MessageDeliveredEvent(:final sessionName, :final count) =>
      '$sessionName · 메시지 $count건 전달',
    LoopErrorEvent() => '오류',
    LoopRetryEvent(:final attempt) => 'LLM 재시도 · $attempt회',
    SessionRetryEvent(:final sessionName, :final attempt) =>
      '$sessionName · 작업 속행 재지시 · $attempt회',
    TerminalRuntimeIssueEvent(:final sessionName) => '복구 필요 · $sessionName',
    DeadlineReachedEvent() => '마감 도달',
    ScheduleTriggeredEvent(:final triggerLabel) => '예약 실행 · $triggerLabel',
    ScheduleRequestedEvent() => '후속 작업 예약',
    CollapsedEvent(:final count) => '이전 이벤트 $count개 생략',
  };

  static String _body(AgentEvent event) => switch (event) {
    LoopStartedEvent(:final goal) => goal,
    LoopFinishedEvent(:final summary, :final steps, :final elapsed) =>
      '$summary\n$steps step · ${_duration(elapsed)}',
    ThoughtEvent(:final text) => text,
    DispatchedEvent(:final payload, :final reason) => [
      payload,
      if (reason != null && reason.trim().isNotEmpty) reason,
    ].join('\n'),
    ObservedEvent(:final delta, :final quiescent) =>
      '${quiescent ? '' : '(관찰 타임아웃)\n'}$delta',
    VerifiedEvent(:final summary) => summary,
    ReportEvent(:final markdown) => markdown,
    UserFeedbackEvent(:final text) => text,
    ApprovalRequestedEvent(:final approval) => [
      approval.reason,
      if (approval.screenContext.trim().isNotEmpty)
        '현재 터미널:\n${approval.screenContext}',
      '보낼 입력:\n${approval.description}',
    ].join('\n'),
    ApprovalResolvedEvent(:final description) => description,
    RolePolicyRejectedEvent(:final reason) => reason,
    HandoffRecordedEvent(:final handoff) =>
      '인계 기록: ${handoff.sessionName} — ${handoff.summary.split('\n').first}',
    AskUserEvent(:final question) => question,
    MessagePostedEvent(:final body) => body,
    MessageWithdrawnEvent(:final body) => body,
    MessageDeliveredEvent(:final senders) => '발신: ${senders.join(', ')}',
    LoopErrorEvent(:final message) => message,
    LoopRetryEvent(:final message, :final delay) =>
      '$message · ${_duration(delay)} 후 다시 시도',
    SessionRetryEvent(:final reason, :final evidence) => [
      reason,
      if (evidence.trim().isNotEmpty) evidence,
    ].join('\n'),
    TerminalRuntimeIssueEvent(:final message, :final evidence) => [
      message,
      if (evidence.trim().isNotEmpty) evidence,
    ].join('\n'),
    DeadlineReachedEvent(:final deadline, :final overrun) =>
      '마감 ${_clock(deadline)} · ${_duration(overrun)} 초과',
    ScheduleTriggeredEvent(:final title, :final interruptedGoal) => [
      title,
      if (interruptedGoal != null) '중단한 목표: $interruptedGoal',
    ].join('\n'),
    ScheduleRequestedEvent(:final title, :final runAt, :final reason) => [
      '$title · ${_clock(runAt)}',
      if (reason != null && reason.trim().isNotEmpty) reason,
    ].join('\n'),
    CollapsedEvent() => '',
  };

  static String _clock(DateTime value) {
    final local = value.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$mm-$dd ${_time(local).substring(0, 5)}';
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  static String _duration(Duration value) {
    final mm = value.inMinutes.toString().padLeft(2, '0');
    final ss = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}
