import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_schedule.dart';
import '../../agent/cron_expression.dart';
import '../../agent/agent_schedule_notifier.dart';
import '../../app/theme.dart';

/// Loop 실행 설정에서 고른 "언제 실행할지".
///
/// [trigger]가 null이면 지금 시작하고, 있으면 예약으로 등록한다. [deadline]은
/// 지금 시작할 때의 절대 마감, [timeBudget]은 예약 실행 때 마감으로 환산할
/// 상대 시간이다.
class AgentTimingSelection {
  const AgentTimingSelection({
    this.trigger,
    this.valid = true,
    this.conflictPolicy = AgentScheduleConflictPolicy.wait,
    this.deadline,
    this.timeBudget,
  });

  static const now = AgentTimingSelection();

  final AgentScheduleTrigger? trigger;
  final bool valid;
  final AgentScheduleConflictPolicy conflictPolicy;
  final DateTime? deadline;
  final Duration? timeBudget;

  bool get isScheduled => trigger != null;
}

enum _TimingMode { now, once, daily, interval, cron }

/// 마감·시간 예산 프리셋. null은 "없음".
const _budgetPresets = <Duration?>[
  null,
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
];

const _intervalPresets = <Duration>[
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 6),
  Duration(hours: 12),
  Duration(hours: 24),
];

/// 현재 실행 시점 선택을 한 줄로 요약한다. 버튼 라벨과 스낵바에 쓴다.
String describeAgentTiming(AgentTimingSelection value) {
  if (!value.valid) return '실행 시점 오류 · 예약을 수정하세요';
  final trigger = value.trigger;
  if (trigger == null) {
    final deadline = value.deadline;
    if (deadline == null) return '지금 실행';
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative
        ? '지금 실행 · 마감 지남'
        : '지금 실행 · ${AgentScheduleTrigger.formatDuration(remaining)} 안에';
  }
  return '예약 · ${trigger.label}';
}

/// Loop 실행 설정 다이얼로그에 놓이는 "실행 시점" 버튼.
///
/// 누르면 [AgentTimingDialog]가 열린다. 섹션을 인라인으로 펼치지 않는 이유는
/// 세션 목록 높이를 잡아먹어 세션이 화면 밖으로 밀리기 때문이다.
class AgentTimingButton extends StatelessWidget {
  const AgentTimingButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNow = true,
  });

  final AgentTimingSelection value;
  final ValueChanged<AgentTimingSelection> onChanged;

  /// false면 "지금 실행"을 고를 수 없다(예약 편집 화면).
  final bool allowNow;

  @override
  Widget build(BuildContext context) {
    final scheduled = value.isScheduled;
    return TextButton.icon(
      key: const ValueKey('agent-timing-button'),
      onPressed: () async {
        final next = await showDialog<AgentTimingSelection>(
          context: context,
          builder: (_) => AgentTimingDialog(initial: value, allowNow: allowNow),
        );
        if (next != null) onChanged(next);
      },
      // 정보 행 높이를 키우지 않도록 기본 40px 최소 높이를 없앤다. 커지면 그만큼
      // 세션 목록이 줄어 아래쪽 세션이 화면 밖으로 밀린다.
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        foregroundColor: scheduled ? VibeColors.secondary : VibeColors.accent,
        textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      icon: Icon(
        scheduled ? Icons.schedule_outlined : Icons.play_circle_outline,
        size: 14,
      ),
      label: Text(
        describeAgentTiming(value),
        key: const ValueKey('agent-timing-summary'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 실행 시점을 고르는 다이얼로그. 선택을 돌려주고 취소하면 null.
class AgentTimingDialog extends StatefulWidget {
  const AgentTimingDialog({
    super.key,
    required this.initial,
    this.allowNow = true,
  });

  final AgentTimingSelection initial;
  final bool allowNow;

  @override
  State<AgentTimingDialog> createState() => _AgentTimingDialogState();
}

class _AgentTimingDialogState extends State<AgentTimingDialog> {
  late AgentTimingSelection _value = widget.initial;

  bool get _valid {
    if (!_value.valid) return false;
    final trigger = _value.trigger;
    if (trigger == null || trigger.kind != AgentScheduleKind.once) return true;
    return trigger.at?.isAfter(DateTime.now()) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.schedule_outlined, size: 19, color: VibeColors.secondary),
          SizedBox(width: 8),
          Text('실행 시점'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: AgentTimingSection(
          value: _value,
          allowNow: widget.allowNow,
          onChanged: (value) => setState(() => _value = value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('agent-timing-apply'),
          onPressed: _valid ? () => Navigator.of(context).pop(_value) : null,
          child: const Text('적용'),
        ),
      ],
    );
  }
}

/// "실행 시점" 편집 UI.
///
/// 지금 실행(마감 선택)과 예약(1회·매일·간격, 충돌 정책, 시간 예산)을 한
/// 곳에서 고른다. 값은 [onChanged]로 부모에게 넘기고 자체 상태는 편집 중인
/// 위젯 상태만 가진다.
class AgentTimingSection extends StatefulWidget {
  const AgentTimingSection({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNow = true,
  });

  final AgentTimingSelection value;
  final ValueChanged<AgentTimingSelection> onChanged;

  /// false면 "지금" 모드를 숨기고 예약 모드만 고른다.
  final bool allowNow;

  @override
  State<AgentTimingSection> createState() => _AgentTimingSectionState();
}

class _AgentTimingSectionState extends State<AgentTimingSection> {
  late _TimingMode _mode;
  late DateTime _onceAt;
  late TimeOfDay _dailyAt;
  late Duration _interval;
  late AgentScheduleConflictPolicy _policy;
  Duration? _budget;
  late final TextEditingController _cronController;

  static const _defaultCron = '0 9 * * 1-5';

  /// 입력 중인 cron 표현식. 틀리면 null이고 [_cronError]에 이유가 남는다.
  CronExpression? get _cron => CronExpression.tryParse(_cronController.text);

  String? get _cronError {
    try {
      CronExpression.parse(_cronController.text);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  @override
  void dispose() {
    _cronController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final trigger = widget.value.trigger;
    final now = DateTime.now();
    _mode = switch (trigger?.kind) {
      null => widget.allowNow ? _TimingMode.now : _TimingMode.once,
      AgentScheduleKind.once => _TimingMode.once,
      AgentScheduleKind.daily => _TimingMode.daily,
      AgentScheduleKind.interval => _TimingMode.interval,
      AgentScheduleKind.cron => _TimingMode.cron,
    };
    _cronController = TextEditingController(
      text: trigger?.cron?.source ?? _defaultCron,
    );
    _onceAt = trigger?.at ?? _roundedNextHour(now);
    _dailyAt = trigger?.hour == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: trigger!.hour!, minute: trigger.minute ?? 0);
    _interval = trigger?.every ?? const Duration(hours: 1);
    _policy = widget.value.conflictPolicy;
    _budget = widget.value.trigger == null
        ? _budgetFromDeadline(widget.value.deadline, now)
        : widget.value.timeBudget;
  }

  static DateTime _roundedNextHour(DateTime now) =>
      DateTime(now.year, now.month, now.day, now.hour + 1);

  static Duration? _budgetFromDeadline(DateTime? deadline, DateTime now) {
    if (deadline == null) return null;
    final remaining = deadline.difference(now);
    for (final preset in _budgetPresets) {
      if (preset != null &&
          (preset - remaining).abs() < const Duration(minutes: 1)) {
        return preset;
      }
    }
    return remaining.isNegative ? null : remaining;
  }

  void _publish() {
    final now = DateTime.now();
    final selection = switch (_mode) {
      _TimingMode.now => AgentTimingSelection(
        deadline: _budget == null ? null : now.add(_budget!),
      ),
      _TimingMode.once => AgentTimingSelection(
        trigger: AgentScheduleTrigger.once(_onceAt),
        conflictPolicy: _policy,
        timeBudget: _budget,
      ),
      _TimingMode.daily => AgentTimingSelection(
        trigger: AgentScheduleTrigger.daily(
          hour: _dailyAt.hour,
          minute: _dailyAt.minute,
        ),
        conflictPolicy: _policy,
        timeBudget: _budget,
      ),
      _TimingMode.interval => AgentTimingSelection(
        trigger: AgentScheduleTrigger.interval(_interval),
        conflictPolicy: _policy,
        timeBudget: _budget,
      ),
      // 표현식이 틀리면 트리거 없이 알려 등록 버튼이 잠기게 한다.
      _TimingMode.cron => switch (_cron) {
        final cron? => AgentTimingSelection(
          trigger: AgentScheduleTrigger.cron(cron),
          conflictPolicy: _policy,
          timeBudget: _budget,
        ),
        null => const AgentTimingSelection(valid: false),
      },
    };
    widget.onChanged(selection);
  }

  Future<void> _pickOnceAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _onceAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_onceAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _onceAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
    _publish();
  }

  Future<void> _pickDailyAt() async {
    final time = await showTimePicker(context: context, initialTime: _dailyAt);
    if (time == null || !mounted) return;
    setState(() => _dailyAt = time);
    _publish();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _summary(),
          key: const ValueKey('agent-timing-section-summary'),
          style: const TextStyle(
            color: VibeColors.onSurfaceMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<_TimingMode>(
          key: const ValueKey('agent-timing-mode'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
          ),
          segments: [
            if (widget.allowNow)
              const ButtonSegment(value: _TimingMode.now, label: Text('지금')),
            const ButtonSegment(value: _TimingMode.once, label: Text('특정 시각')),
            const ButtonSegment(value: _TimingMode.daily, label: Text('매일')),
            const ButtonSegment(value: _TimingMode.interval, label: Text('간격')),
            const ButtonSegment(value: _TimingMode.cron, label: Text('cron')),
          ],
          selected: {_mode},
          onSelectionChanged: (values) {
            setState(() => _mode = values.first);
            _publish();
          },
        ),
        const SizedBox(height: 10),
        ..._modeControls(),
        const SizedBox(height: 10),
        _budgetControl(),
        if (_mode != _TimingMode.now) ...[
          const SizedBox(height: 10),
          _policyControl(),
        ],
      ],
    );
  }

  String _summary() => switch (_mode) {
    _TimingMode.now =>
      _budget == null
          ? '지금 실행 · 마감 없음'
          : '지금 실행 · ${AgentScheduleTrigger.formatDuration(_budget!)} 안에',
    _TimingMode.once => '${AgentScheduleTrigger.formatDateTime(_onceAt)} 1회 예약',
    _TimingMode.daily =>
      '매일 ${_dailyAt.hour.toString().padLeft(2, '0')}:'
          '${_dailyAt.minute.toString().padLeft(2, '0')} 예약',
    _TimingMode.interval =>
      '${AgentScheduleTrigger.formatDuration(_interval)}마다 예약',
    _TimingMode.cron => switch (_cron) {
      final cron? => '${cron.label} 예약',
      null => 'cron 표현식을 확인하세요',
    },
  };

  List<Widget> _modeControls() => switch (_mode) {
    _TimingMode.now => const [
      Text(
        '목표 계약과 세션 범위로 바로 시작합니다.',
        style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 10.5),
      ),
    ],
    _TimingMode.once => [
      _pickerRow(
        key: const ValueKey('agent-timing-once-at'),
        icon: Icons.event_outlined,
        label: AgentScheduleTrigger.formatDateTime(_onceAt),
        onTap: _pickOnceAt,
        warning: _onceAt.isBefore(DateTime.now()) ? '이미 지난 시각입니다.' : null,
      ),
    ],
    _TimingMode.daily => [
      _pickerRow(
        key: const ValueKey('agent-timing-daily-at'),
        icon: Icons.access_time,
        label:
            '매일 ${_dailyAt.hour.toString().padLeft(2, '0')}:'
            '${_dailyAt.minute.toString().padLeft(2, '0')}',
        onTap: _pickDailyAt,
      ),
    ],
    _TimingMode.interval => [
      _dropdown<Duration>(
        key: const ValueKey('agent-timing-interval'),
        label: '반복 간격',
        value: _interval,
        items: [
          for (final preset in _intervalPresets)
            DropdownMenuItem(
              value: preset,
              child: Text('${AgentScheduleTrigger.formatDuration(preset)}마다'),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => _interval = value);
          _publish();
        },
      ),
    ],
    _TimingMode.cron => [
      TextField(
        key: const ValueKey('agent-timing-cron'),
        controller: _cronController,
        style: const TextStyle(
          color: VibeColors.onSurface,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          isDense: true,
          labelText: 'cron 표현식 (분 시 일 월 요일)',
          labelStyle: const TextStyle(
            color: VibeColors.onSurfaceMuted,
            fontSize: 10.5,
          ),
          hintText: '예: 0 9 * * 1-5 · */30 * * * * · @daily',
          helperText: switch (_cron) {
            final cron? => '다음 실행 ${_nextCronLabel(cron)}',
            null => null,
          },
          helperStyle: const TextStyle(
            color: VibeColors.onSurfaceDim,
            fontSize: 10.5,
          ),
          errorText: _cronError,
          errorMaxLines: 2,
          filled: true,
          fillColor: VibeColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: VibeColors.border),
          ),
        ),
        onChanged: (_) {
          setState(() {});
          _publish();
        },
      ),
    ],
  };

  static String _nextCronLabel(CronExpression cron) {
    final next = cron.nextAfter(DateTime.now());
    return next == null ? '없음' : AgentScheduleTrigger.formatDateTime(next);
  }

  Widget _budgetControl() => _dropdown<Duration?>(
    key: const ValueKey('agent-timing-budget'),
    label: _mode == _TimingMode.now ? '마감' : '실행당 시간 예산',
    value: _budgetPresets.contains(_budget) ? _budget : null,
    items: [
      for (final preset in _budgetPresets)
        DropdownMenuItem(
          value: preset,
          child: Text(
            preset == null
                ? '없음'
                : '${AgentScheduleTrigger.formatDuration(preset)} 안에 마무리',
          ),
        ),
    ],
    onChanged: (value) {
      setState(() => _budget = value);
      _publish();
    },
  );

  Widget _policyControl() => _dropdown<AgentScheduleConflictPolicy>(
    key: const ValueKey('agent-timing-policy'),
    label: '실행 중인 loop가 있으면',
    value: _policy,
    items: const [
      DropdownMenuItem(
        value: AgentScheduleConflictPolicy.wait,
        child: Text('끝난 뒤 시작 (대기)'),
      ),
      DropdownMenuItem(
        value: AgentScheduleConflictPolicy.interrupt,
        child: Text('중단하고 전환'),
      ),
    ],
    onChanged: (value) {
      if (value == null) return;
      setState(() => _policy = value);
      _publish();
    },
  );

  Widget _pickerRow({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? warning,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          key: key,
          onPressed: onTap,
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 11.5)),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: VibeColors.onSurface,
            side: const BorderSide(color: VibeColors.border),
          ),
        ),
        if (warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              warning,
              style: const TextStyle(color: VibeColors.warning, fontSize: 10.5),
            ),
          ),
      ],
    );
  }

  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isDense: true,
      style: const TextStyle(color: VibeColors.onSurface, fontSize: 11.5),
      dropdownColor: VibeColors.surfaceHigh,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(
          color: VibeColors.onSurfaceMuted,
          fontSize: 10.5,
        ),
        filled: true,
        fillColor: VibeColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: VibeColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: VibeColors.border),
        ),
      ),
    );
  }
}

/// 등록된 예약 목록. 켜고 끄기와 삭제만 한다. 편집은 삭제 후 다시 등록한다.
class AgentScheduleListDialog extends ConsumerWidget {
  const AgentScheduleListDialog({
    super.key,
    this.onAdd,
    this.onEdit,
    this.onRunNow,
    this.sessionNames = const {},
  });

  /// 새 예약 등록 진입점. 목록을 닫은 뒤 불린다. null이면 버튼을 숨긴다.
  final VoidCallback? onAdd;

  /// 세션 id → 표시 이름. 메시지 예약의 수신 세션을 이름으로 보여준다.
  final Map<String, String> sessionNames;

  /// 예약 편집 진입점. 목록을 닫은 뒤 불린다.
  final ValueChanged<AgentScheduledTask>? onEdit;

  /// 예약 시각을 기다리지 않고 지금 실행한다.
  final ValueChanged<AgentScheduledTask>? onRunNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(agentScheduleProvider);
    final storageError = ref.watch(agentScheduleStorageStatusProvider);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.schedule_outlined,
            size: 19,
            color: VibeColors.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('예약된 실행'),
                if (storageError != null)
                  Text(
                    storageError,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                if (storageError != null)
                  TextButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(agentScheduleProvider.notifier)
                            .retrySave();
                      } catch (_) {
                        /* 오류 배너 유지 */
                      }
                    },
                    child: const Text('저장 다시 시도'),
                  ),
              ],
            ),
          ),
          if (onAdd != null)
            FilledButton.tonalIcon(
              key: const ValueKey('agent-schedule-add'),
              onPressed: () {
                Navigator.of(context).pop();
                onAdd!();
              },
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11.5),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('새 예약'),
            ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: tasks.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '예약이 없습니다. "새 예약"으로 목표·세션·실행 시점을 등록하거나, '
                  '목표 입력 뒤 실행 설정의 "실행 시점"을 예약으로 바꾸거나, loop 안에서 '
                  '플래너가 후속 작업을 예약하면 여기에 나타납니다.',
                  style: TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontSize: 12,
                  ),
                ),
              )
            : SizedBox(
                width: 520,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ScheduleTile(
                    task: tasks[index],
                    sessionNames: sessionNames,
                    onToggle: (enabled) => ref
                        .read(agentScheduleProvider.notifier)
                        .setEnabled(tasks[index].id, enabled),
                    onDelete: () => ref
                        .read(agentScheduleProvider.notifier)
                        .remove(tasks[index].id),
                    onEdit: onEdit == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onEdit!(tasks[index]);
                          },
                    onRunNow: onRunNow == null
                        ? null
                        : () => onRunNow!(tasks[index]),
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.task,
    required this.onToggle,
    required this.onDelete,
    this.onEdit,
    this.onRunNow,
    this.sessionNames = const {},
  });

  final AgentScheduledTask task;
  final Map<String, String> sessionNames;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onRunNow;

  @override
  Widget build(BuildContext context) {
    final next = task.nextRunAt;
    final target = task.messageSessionId;
    final routineTarget = task.aiChatSessionId;
    final lines = [
      if (task.isMessage)
        '메시지 → ${sessionNames[target] ?? target ?? '(세션 없음)'}',
      if (task.isAiChat) ...[
        'AI Chat 루틴 → ${sessionNames[routineTarget] ?? routineTarget ?? '(세션 없음)'}',
        if (task.terminalToolCall) '터미널 입력 허용',
      ],
      task.trigger.label,
      if (next != null && task.enabled)
        '다음 ${AgentScheduleTrigger.formatDateTime(next)}',
      if (!task.isMessage && !task.isAiChat) ...[
        if (task.timeBudget case final budget?)
          '예산 ${AgentScheduleTrigger.formatDuration(budget)}',
        task.conflictPolicy == AgentScheduleConflictPolicy.interrupt
            ? '실행 중이면 전환'
            : '실행 중이면 대기',
        if (task.origin == AgentScheduleOrigin.orchestrator) '플래너 예약',
        '${task.allowedSessionIds.length}개 세션',
      ],
      if (task.runCount > 0) '${task.runCount}회 실행',
    ];
    return Container(
      key: ValueKey('agent-schedule-${task.id}'),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        border: Border.all(color: VibeColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: task.enabled
                        ? VibeColors.onSurface
                        : VibeColors.onSurfaceDim,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lines.join(' · '),
                  style: const TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontSize: 10.5,
                  ),
                ),
                if (task.lastResult case final result? when result.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      result,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                if (task.reason case final reason?
                    when reason.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '이유: $reason',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                if (task.history.isNotEmpty)
                  _RunHistory(taskId: task.id, records: task.history),
              ],
            ),
          ),
          Switch(
            key: ValueKey('agent-schedule-toggle-${task.id}'),
            value: task.enabled,
            onChanged: task.nextRunAt == null && !task.enabled
                ? null
                : onToggle,
          ),
          if (onRunNow != null)
            IconButton(
              key: ValueKey('agent-schedule-run-${task.id}'),
              tooltip: '지금 실행',
              icon: const Icon(Icons.play_circle_outline, size: 18),
              color: VibeColors.accent,
              onPressed: onRunNow,
            ),
          if (onEdit != null)
            IconButton(
              key: ValueKey('agent-schedule-edit-${task.id}'),
              tooltip: '예약 편집',
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: VibeColors.onSurfaceDim,
              onPressed: onEdit,
            ),
          IconButton(
            key: ValueKey('agent-schedule-delete-${task.id}'),
            tooltip: '예약 삭제',
            icon: const Icon(Icons.delete_outline, size: 18),
            color: VibeColors.onSurfaceDim,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 예약 항목 아래 접혀 있는 최근 실행 이력. 눌러서 펼친다.
class _RunHistory extends StatefulWidget {
  const _RunHistory({required this.taskId, required this.records});

  final String taskId;
  final List<AgentScheduleRunRecord> records;

  @override
  State<_RunHistory> createState() => _RunHistoryState();
}

class _RunHistoryState extends State<_RunHistory> {
  bool _expanded = false;

  static String _outcomeLabel(String outcome) => switch (outcome) {
    'achieved' => '달성',
    'partial' => '부분 완료',
    'blocked' => '차단',
    'stopped' => '중단됨',
    'failed' => '실패',
    'delivered' => '전달됨',
    _ => outcome,
  };

  static Color _outcomeColor(String outcome) => switch (outcome) {
    'achieved' || 'delivered' => VibeColors.statusConnected,
    'failed' => VibeColors.statusError,
    'stopped' => VibeColors.onSurfaceDim,
    _ => VibeColors.warning,
  };

  @override
  Widget build(BuildContext context) {
    final records = widget.records;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: ValueKey('agent-schedule-history-${widget.taskId}'),
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: VibeColors.onSurfaceDim,
                ),
                const SizedBox(width: 2),
                Text(
                  '실행 이력 ${records.length}회',
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _outcomeColor(
                        record.outcome,
                      ).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _outcomeLabel(record.outcome),
                      style: TextStyle(
                        color: _outcomeColor(record.outcome),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        AgentScheduleTrigger.formatDateTime(record.finishedAt),
                        if (record.outcome != 'delivered')
                          '${record.steps} step · '
                              '${AgentScheduleTrigger.formatDuration(record.elapsed)}',
                        if (record.summary.trim().isNotEmpty) record.summary,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurfaceMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// 세션 우편함에 넣을 메시지를 받는 작은 다이얼로그. 본문을 돌려준다.
class AgentInboxComposeDialog extends StatefulWidget {
  const AgentInboxComposeDialog({super.key, required this.sessionName});

  final String sessionName;

  @override
  State<AgentInboxComposeDialog> createState() =>
      _AgentInboxComposeDialogState();
}

class _AgentInboxComposeDialogState extends State<AgentInboxComposeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.sessionName} 우편함에 메시지 넣기'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '세션 안의 에이전트에게 전할 말입니다. 오케스트레이터가 이 세션에 다음 '
              '지시를 보낼 때 [INBOX] 블록으로 함께 전달됩니다.',
              style: TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('agent-inbox-compose-field'),
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontSize: 12.5,
              ),
              decoration: const InputDecoration(
                hintText: '예: 테스트는 통합 테스트까지 돌려줘',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          key: const ValueKey('agent-inbox-compose-submit'),
          onPressed: _submit,
          icon: const Icon(Icons.forward_to_inbox_outlined, size: 16),
          label: const Text('우편함에 넣기'),
        ),
      ],
    );
  }
}
