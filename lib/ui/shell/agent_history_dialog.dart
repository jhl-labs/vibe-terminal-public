import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_chat_notifier.dart';
import '../../agent/agent_models.dart';
import '../../agent/agent_run_transcript.dart';
import '../../agent/agent_schedule.dart';
import '../../app/theme.dart';

/// 히스토리 필터. 오케스트레이터 관점과 세션별 관점을 오간다.
const _filterAll = '__all__';
const _filterOrchestrator = '__orchestrator__';

/// "오케스트레이터가 무엇을 지시했고, 각 세션은 무엇을 해 왔는가"를 시간순으로
/// 보여 주는 화면.
///
/// 타임라인 패널은 최신 흐름을 따라가는 용도라 지난 지시를 되짚기 어렵다. 이
/// 화면은 필터로 한 세션의 이력만 남기고, 오케스트레이터의 계획·지시·평가를
/// step 단위로 묶어 진행 상황을 파악하게 한다.
class AgentHistoryDialog extends ConsumerStatefulWidget {
  const AgentHistoryDialog({super.key, required this.onOpenSession});

  final ValueChanged<String> onOpenSession;

  @override
  ConsumerState<AgentHistoryDialog> createState() => _AgentHistoryDialogState();
}

class _AgentHistoryDialogState extends ConsumerState<AgentHistoryDialog> {
  String _filter = _filterAll;
  List<AgentEvent>? _storedEvents;

  @override
  void initState() {
    super.initState();
    // 메모리 타임라인은 500개에서 접힌다. 접힌 앞부분은 디스크에서 채운다.
    ref.read(agentChatProvider.notifier).loadCurrentRunEvents().then((events) {
      if (mounted) setState(() => _storedEvents = events);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loop = ref.watch(agentChatProvider);
    final stored = _storedEvents;
    final events = stored != null && stored.length > loop.events.length
        ? stored
        : loop.events;
    final entries = AgentHistoryEntry.fromEvents(events);
    final sessions = _sessionsIn(loop, entries);
    final visible = [
      for (final entry in entries)
        if (entry.matches(_filter)) entry,
    ];
    final selectedTask = loop.sessionTasks[_filter];
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: VibeColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              loop: loop,
              onCopy: () => _copy(loop, visible),
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1, color: VibeColors.borderSoft),
            _FilterBar(
              sessions: sessions,
              selected: _filter,
              onSelected: (value) => setState(() => _filter = value),
              counts: {
                _filterAll: entries.length,
                _filterOrchestrator: entries
                    .where((e) => e.matches(_filterOrchestrator))
                    .length,
                for (final session in sessions)
                  session.id: entries
                      .where((e) => e.matches(session.id))
                      .length,
              },
            ),
            if (selectedTask != null || _filter == _filterOrchestrator)
              _SummaryStrip(loop: loop, task: selectedTask, entries: visible),
            const Divider(height: 1, color: VibeColors.borderSoft),
            Flexible(
              child: visible.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          '아직 기록된 이벤트가 없습니다.',
                          style: TextStyle(color: VibeColors.onSurfaceDim),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('agent-history-list'),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: visible.length,
                      separatorBuilder: (_, index) =>
                          visible[index + 1].startsStep
                          ? const SizedBox(height: 10)
                          : const SizedBox(height: 4),
                      itemBuilder: (_, index) => _HistoryRow(
                        entry: visible[index],
                        showSession:
                            _filter == _filterAll ||
                            _filter == _filterOrchestrator,
                        onOpenSession: widget.onOpenSession,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SessionRef> _sessionsIn(
    AgentLoopState loop,
    List<AgentHistoryEntry> entries,
  ) {
    final byId = <String, String>{};
    for (final task in loop.sessionTasks.values) {
      byId[task.sessionId] = task.displayName;
    }
    for (final entry in entries) {
      final id = entry.sessionId;
      if (id != null && !byId.containsKey(id)) {
        byId[id] = entry.sessionName ?? id;
      }
    }
    return [
      for (final e in byId.entries)
        _SessionRef(id: e.key, name: e.value, task: loop.sessionTasks[e.key]),
    ];
  }

  Future<void> _copy(
    AgentLoopState loop,
    List<AgentHistoryEntry> visible,
  ) async {
    final text = AgentRunTranscript.format(loop, [
      for (final entry in visible) entry.event,
    ]);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('히스토리를 복사했습니다.')));
  }
}

class _SessionRef {
  const _SessionRef({required this.id, required this.name, this.task});
  final String id;
  final String name;
  final SessionTaskView? task;
}

/// 히스토리 한 행. 어떤 관점(오케스트레이터/세션)에 속하는지와 표시 방법을 안다.
///
/// 순수 Dart라 위젯 없이 테스트할 수 있다.
class AgentHistoryEntry {
  const AgentHistoryEntry({
    required this.event,
    required this.actor,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    this.sessionId,
    this.sessionName,
    this.step,
    this.startsStep = false,
  });

  final AgentEvent event;

  /// "orchestrator" | "session" | "user" | "system".
  final String actor;
  final String title;
  final String body;
  final IconData icon;
  final AgentHistoryTone tone;
  final String? sessionId;
  final String? sessionName;
  final int? step;

  /// 새 step의 시작(계획) 행. 목록에서 여백으로 구분한다.
  final bool startsStep;

  bool matches(String filter) {
    if (filter == _filterAll) return true;
    if (filter == _filterOrchestrator) {
      return actor == 'orchestrator' || actor == 'user' || actor == 'system';
    }
    return sessionId == filter;
  }

  static List<AgentHistoryEntry> fromEvents(List<AgentEvent> events) {
    var step = 0;
    return [
      for (final event in events)
        () {
          if (event is ThoughtEvent) step = event.step;
          return _fromEvent(event, step);
        }(),
    ];
  }

  static AgentHistoryEntry _fromEvent(AgentEvent event, int step) {
    return switch (event) {
      LoopStartedEvent(:final goal, :final scope) => AgentHistoryEntry(
        event: event,
        actor: 'system',
        title: '목표 시작 · $scope',
        body: goal,
        icon: Icons.flag_outlined,
        tone: AgentHistoryTone.accent,
        startsStep: true,
      ),
      LoopFinishedEvent(:final outcome, :final summary, :final steps) =>
        AgentHistoryEntry(
          event: event,
          actor: 'system',
          title: '종료 · ${_outcomeLabel(outcome)} · $steps step',
          body: summary,
          icon: Icons.sports_score,
          tone: outcome == AgentLoopOutcome.achieved
              ? AgentHistoryTone.success
              : outcome == AgentLoopOutcome.failed
              ? AgentHistoryTone.error
              : AgentHistoryTone.muted,
          startsStep: true,
        ),
      ThoughtEvent(:final text) => AgentHistoryEntry(
        event: event,
        actor: 'orchestrator',
        title: 'Step $step · 계획',
        body: text,
        icon: Icons.psychology_outlined,
        tone: AgentHistoryTone.accent,
        step: step,
        startsStep: true,
      ),
      DispatchedEvent(
        :final sessionId,
        :final sessionName,
        :final kind,
        :final payload,
        :final reason,
      ) =>
        AgentHistoryEntry(
          event: event,
          actor: 'orchestrator',
          title: '${kind == 'prompt' ? '지시' : '키 입력'} → $sessionName',
          body: reason == null || reason.trim().isEmpty
              ? payload
              : '$payload\n— $reason',
          icon: Icons.play_arrow,
          tone: AgentHistoryTone.accent,
          sessionId: sessionId,
          sessionName: sessionName,
          step: step,
        ),
      ObservedEvent(
        :final sessionId,
        :final sessionName,
        :final delta,
        :final quiescent,
        :final isSnapshot,
      ) =>
        AgentHistoryEntry(
          event: event,
          actor: 'session',
          title: isSnapshot
              ? '$sessionName · 화면 확인'
              : '$sessionName · ${quiescent ? '응답 완료' : '관찰 타임아웃'}',
          body: delta,
          icon: isSnapshot
              ? Icons.visibility_outlined
              : quiescent
              ? Icons.tv_outlined
              : Icons.hourglass_empty,
          tone: quiescent || isSnapshot
              ? AgentHistoryTone.muted
              : AgentHistoryTone.warning,
          sessionId: sessionId,
          sessionName: sessionName,
          step: step,
        ),
      VerifiedEvent(:final verdict, :final summary) => AgentHistoryEntry(
        event: event,
        actor: 'orchestrator',
        title: '평가 · $verdict',
        body: summary,
        icon: Icons.fact_check_outlined,
        tone: verdict == 'ok'
            ? AgentHistoryTone.success
            : AgentHistoryTone.warning,
        step: step,
      ),
      ReportEvent(:final markdown) => AgentHistoryEntry(
        event: event,
        actor: 'orchestrator',
        title: '보고',
        body: markdown,
        icon: Icons.summarize_outlined,
        tone: AgentHistoryTone.secondary,
        step: step,
      ),
      UserFeedbackEvent(:final text) => AgentHistoryEntry(
        event: event,
        actor: 'user',
        title: '사용자 피드백',
        body: text,
        icon: Icons.person_outline,
        tone: AgentHistoryTone.secondary,
        step: step,
      ),
      ApprovalRequestedEvent(:final approval) => AgentHistoryEntry(
        event: event,
        actor: 'orchestrator',
        title: '승인 요청 · ${approval.sessionName}',
        body: '${approval.reason}\n${approval.description}',
        icon: Icons.gpp_maybe_outlined,
        tone: AgentHistoryTone.warning,
        sessionId: approval.sessionId,
        sessionName: approval.sessionName,
        step: step,
      ),
      ApprovalResolvedEvent(:final approved, :final description) =>
        AgentHistoryEntry(
          event: event,
          actor: 'user',
          title: approved ? '승인됨' : '거부됨',
          body: description,
          icon: approved ? Icons.check_circle_outline : Icons.block,
          tone: approved ? AgentHistoryTone.success : AgentHistoryTone.error,
          step: step,
        ),
      AskUserEvent(:final question) => AgentHistoryEntry(
        event: event,
        actor: 'orchestrator',
        title: '사용자에게 질문',
        body: question,
        icon: Icons.help_outline,
        tone: AgentHistoryTone.warning,
        step: step,
      ),
      MessagePostedEvent(:final from, :final to, :final body) =>
        AgentHistoryEntry(
          event: event,
          actor: 'orchestrator',
          title: '메시지 · $from → $to',
          body: body,
          icon: Icons.forward_to_inbox_outlined,
          tone: AgentHistoryTone.secondary,
          sessionId: to,
          sessionName: to,
          step: step,
        ),
      MessageWithdrawnEvent(:final from, :final to, :final body) =>
        AgentHistoryEntry(
          event: event,
          actor: 'orchestrator',
          title: '메시지 회수 · $from → $to',
          body: body,
          icon: Icons.undo,
          tone: AgentHistoryTone.muted,
          sessionId: to,
          sessionName: to,
          step: step,
        ),
      MessageDeliveredEvent(
        :final sessionId,
        :final sessionName,
        :final senders,
      ) =>
        AgentHistoryEntry(
          event: event,
          actor: 'session',
          title: '$sessionName · 메시지 ${senders.length}건 수신',
          body: '발신: ${senders.join(', ')}',
          icon: Icons.mark_email_read_outlined,
          tone: AgentHistoryTone.secondary,
          sessionId: sessionId,
          sessionName: sessionName,
          step: step,
        ),
      HandoffRecordedEvent(:final handoff) => AgentHistoryEntry(
        event: event,
        actor: 'orchestrator',
        title: '인계 기록 · ${handoff.sessionName}',
        body:
            '인계 기록: ${handoff.sessionName} — '
            '${handoff.summary.split('\n').first}',
        icon: Icons.forward_outlined,
        tone: AgentHistoryTone.secondary,
        sessionId: handoff.sessionId,
        sessionName: handoff.sessionName,
        step: step,
      ),
      RolePolicyRejectedEvent(:final sessionName, :final reason) =>
        AgentHistoryEntry(
          event: event,
          actor: 'orchestrator',
          title: '역할 정책 거부 · $sessionName',
          body: reason,
          icon: Icons.block_outlined,
          tone: AgentHistoryTone.warning,
          step: step,
        ),
      LoopErrorEvent(:final message) => AgentHistoryEntry(
        event: event,
        actor: 'orchestrator',
        title: '오류',
        body: message,
        icon: Icons.error_outline,
        tone: AgentHistoryTone.error,
        step: step,
      ),
      LoopRetryEvent(:final attempt, :final delay, :final message) =>
        AgentHistoryEntry(
          event: event,
          actor: 'orchestrator',
          title: 'LLM 재시도 · $attempt회 · ${delay.inSeconds}초 대기',
          body: message,
          icon: Icons.sync_problem_outlined,
          tone: AgentHistoryTone.warning,
          step: step,
        ),
      SessionRetryEvent(
        :final sessionId,
        :final sessionName,
        :final attempt,
        :final reason,
        :final evidence,
      ) =>
        AgentHistoryEntry(
          event: event,
          actor: 'session',
          title: '$sessionName · 작업 속행 재지시 · $attempt회',
          body: evidence.trim().isEmpty ? reason : '$reason\n$evidence',
          icon: Icons.replay_circle_filled_outlined,
          tone: AgentHistoryTone.warning,
          sessionId: sessionId,
          sessionName: sessionName,
          step: step,
        ),
      TerminalRuntimeIssueEvent(
        :final sessionId,
        :final sessionName,
        :final message,
        :final evidence,
      ) =>
        AgentHistoryEntry(
          event: event,
          actor: 'session',
          title: '$sessionName · 복구 필요',
          body: evidence.trim().isEmpty ? message : '$message\n$evidence',
          icon: Icons.build_circle_outlined,
          tone: AgentHistoryTone.error,
          sessionId: sessionId,
          sessionName: sessionName,
          step: step,
        ),
      DeadlineReachedEvent(:final deadline, :final overrun) =>
        AgentHistoryEntry(
          event: event,
          actor: 'system',
          title: '마감 도달',
          body:
              '마감 ${AgentScheduleTrigger.formatDateTime(deadline)} · '
              '${AgentScheduleTrigger.formatDuration(overrun)} 초과',
          icon: Icons.timer_off_outlined,
          tone: AgentHistoryTone.warning,
          step: step,
        ),
      ScheduleTriggeredEvent(:final title, :final triggerLabel) =>
        AgentHistoryEntry(
          event: event,
          actor: 'system',
          title: '예약 실행 · $triggerLabel',
          body: title,
          icon: Icons.schedule_outlined,
          tone: AgentHistoryTone.secondary,
          startsStep: true,
        ),
      ScheduleRequestedEvent(:final title, :final runAt, :final reason) =>
        AgentHistoryEntry(
          event: event,
          actor: 'orchestrator',
          title: '후속 작업 예약 · ${AgentScheduleTrigger.formatDateTime(runAt)}',
          body: reason == null || reason.trim().isEmpty
              ? title
              : '$title\n$reason',
          icon: Icons.more_time,
          tone: AgentHistoryTone.secondary,
          step: step,
        ),
      CollapsedEvent(:final count) => AgentHistoryEntry(
        event: event,
        actor: 'system',
        title: '이전 이벤트 $count개 생략',
        body: '',
        icon: Icons.unfold_less,
        tone: AgentHistoryTone.muted,
      ),
    };
  }

  static String _outcomeLabel(AgentLoopOutcome outcome) => switch (outcome) {
    AgentLoopOutcome.achieved => '달성',
    AgentLoopOutcome.partial => '부분 완료',
    AgentLoopOutcome.blocked => '차단됨',
    AgentLoopOutcome.stopped => '중단됨',
    AgentLoopOutcome.failed => '실패',
  };
}

enum AgentHistoryTone { accent, secondary, success, warning, error, muted }

Color _toneColor(AgentHistoryTone tone) => switch (tone) {
  AgentHistoryTone.accent => VibeColors.accent,
  AgentHistoryTone.secondary => VibeColors.secondary,
  AgentHistoryTone.success => VibeColors.statusConnected,
  AgentHistoryTone.warning => VibeColors.warning,
  AgentHistoryTone.error => VibeColors.statusError,
  AgentHistoryTone.muted => VibeColors.onSurfaceDim,
};

class _Header extends StatelessWidget {
  const _Header({
    required this.loop,
    required this.onCopy,
    required this.onClose,
  });

  final AgentLoopState loop;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.history, size: 20, color: VibeColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '실행 히스토리',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (loop.goal case final goal?)
                  Text(
                    goal,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibeColors.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '보이는 히스토리 복사',
            onPressed: onCopy,
            icon: const Icon(Icons.content_copy_outlined, size: 17),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sessions,
    required this.selected,
    required this.onSelected,
    required this.counts,
  });

  final List<_SessionRef> sessions;
  final String selected;
  final ValueChanged<String> onSelected;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label, {Widget? leading}) {
      final active = selected == value;
      final count = counts[value] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          key: ValueKey('agent-history-filter-$value'),
          selected: active,
          onSelected: (_) => onSelected(value),
          avatar: leading,
          label: Text('$label · $count'),
          labelStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: active ? VibeColors.onAccent : VibeColors.onSurfaceMuted,
          ),
          selectedColor: VibeColors.accent,
          backgroundColor: VibeColors.surfaceHigh,
          side: BorderSide(
            color: active ? VibeColors.accent : VibeColors.borderSoft,
          ),
          visualDensity: VisualDensity.compact,
          showCheckmark: false,
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        children: [
          chip(_filterAll, '전체'),
          chip(
            _filterOrchestrator,
            '오케스트레이터',
            leading: const Icon(
              Icons.hub_outlined,
              size: 14,
              color: VibeColors.onSurfaceMuted,
            ),
          ),
          for (final session in sessions)
            chip(
              session.id,
              _sessionLabel(session),
              leading: _PhaseDot(phase: session.task?.phase),
            ),
        ],
      ),
    );
  }
}

String _sessionLabel(_SessionRef session) {
  final hint = session.task?.agentHint;
  if (hint == null || hint == 'unknown') return session.name;
  return '${session.name} ($hint)';
}

class _PhaseDot extends StatelessWidget {
  const _PhaseDot({required this.phase});
  final SessionTaskPhase? phase;

  @override
  Widget build(BuildContext context) {
    final color = switch (phase) {
      SessionTaskPhase.working => VibeColors.accent,
      SessionTaskPhase.dispatched => VibeColors.secondary,
      SessionTaskPhase.done => VibeColors.statusConnected,
      SessionTaskPhase.error => VibeColors.statusError,
      SessionTaskPhase.waitingInput => VibeColors.warning,
      SessionTaskPhase.idle || null => VibeColors.onSurfaceDim,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 선택한 관점의 요약: 무엇을 얼마나 했고 지금 어떤 상태인지.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.loop,
    required this.task,
    required this.entries,
  });

  final AgentLoopState loop;
  final SessionTaskView? task;
  final List<AgentHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final dispatched = entries.where((e) => e.event is DispatchedEvent).length;
    final retries = entries
        .where((e) => e.event is SessionRetryEvent || e.event is LoopRetryEvent)
        .length;
    final issues = entries
        .where(
          (e) =>
              e.event is TerminalRuntimeIssueEvent || e.event is LoopErrorEvent,
        )
        .length;
    final parts = <String>[
      if (task != null) '상태 ${_phaseLabel(task!.phase)}',
      if (task?.role?.label case final role? when role.trim().isNotEmpty)
        '역할 $role',
      '지시 $dispatched건',
      if (retries > 0) '재시도 $retries회',
      if (issues > 0) '오류 $issues건',
      if (task == null) 'step ${loop.step}/${loop.maxSteps}',
    ];
    final last = task?.lastInstruction;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parts.join(' · '),
            key: const ValueKey('agent-history-summary'),
            style: const TextStyle(
              color: VibeColors.onSurfaceDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (last != null && last.trim().isNotEmpty)
            Text(
              '마지막 지시: $last',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }

  String _phaseLabel(SessionTaskPhase phase) => switch (phase) {
    SessionTaskPhase.idle => '대기',
    SessionTaskPhase.dispatched => '전송됨',
    SessionTaskPhase.working => '작업 중',
    SessionTaskPhase.done => '완료',
    SessionTaskPhase.error => '오류',
    SessionTaskPhase.waitingInput => '승인·입력 필요',
  };
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({
    required this.entry,
    required this.showSession,
    required this.onOpenSession,
  });

  final AgentHistoryEntry entry;
  final bool showSession;
  final ValueChanged<String> onOpenSession;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  static const _previewLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final color = _toneColor(entry.tone);
    final lines = entry.body.split('\n');
    final hasMore = lines.length > _previewLines;
    final body = _expanded || !hasMore
        ? entry.body
        : lines.take(_previewLines).join('\n');
    final monospace = entry.event is ObservedEvent;
    return InkWell(
      onTap: hasMore ? () => setState(() => _expanded = !_expanded) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: entry.startsStep ? VibeColors.surfaceHigh : null,
          borderRadius: BorderRadius.circular(8),
          border: entry.startsStep
              ? Border.all(color: VibeColors.borderSoft)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Text(
                _time(entry.event.at),
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontSize: 10.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Icon(entry.icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (body.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        body,
                        style: TextStyle(
                          color: VibeColors.onSurfaceMuted,
                          fontSize: monospace ? 11 : 12,
                          height: 1.3,
                          fontFamily: monospace ? 'monospace' : null,
                        ),
                      ),
                    ),
                  if (hasMore)
                    Text(
                      _expanded
                          ? '접기'
                          : '${lines.length - _previewLines}줄 더 보기',
                      style: const TextStyle(
                        color: VibeColors.secondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (entry.sessionId case final sessionId?
                when widget.showSession || entry.event is ObservedEvent)
              IconButton(
                tooltip: '${entry.sessionName ?? sessionId} 세션 열기',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 26,
                  height: 26,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => widget.onOpenSession(sessionId),
                icon: const Icon(
                  Icons.open_in_new,
                  size: 13,
                  color: VibeColors.onSurfaceDim,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
