import 'dart:async';

import 'package:clock/clock.dart';

import 'agent_schedule.dart';

/// 예약 시각이 되었을 때 실행 측이 내린 결정.
enum AgentScheduleDueOutcome {
  /// loop를 시작했다. 다음 회차를 계산한다.
  started,

  /// 지금은 시작할 수 없어 나중에 다시 묻는다(예: 대기 정책, loop 실행 중).
  deferred,

  /// 이번 회차를 건너뛴다(예: 세션 없음). 다음 회차를 계산한다.
  skipped,
}

class AgentScheduleDueResult {
  const AgentScheduleDueResult._(this.outcome, [this.detail]);

  static const started = AgentScheduleDueResult._(
    AgentScheduleDueOutcome.started,
  );
  static const deferred = AgentScheduleDueResult._(
    AgentScheduleDueOutcome.deferred,
  );

  const AgentScheduleDueResult.skipped(String detail)
    : this._(AgentScheduleDueOutcome.skipped, detail);

  final AgentScheduleDueOutcome outcome;
  final String? detail;
}

typedef AgentScheduleDueHandler =
    Future<AgentScheduleDueResult> Function(AgentScheduledTask task);

typedef AgentTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// 예약 목록을 들고 시각이 되면 [onDue]를 부르는 스케줄러.
///
/// 순수 Dart다. 시각은 `package:clock`으로, 타이머는 [AgentTimerFactory]로
/// 주입받아 테스트에서 시간을 임의로 움직일 수 있다. 실제로 loop를 시작할지,
/// 세션이 살아 있는지 같은 판단은 [onDue]를 구현하는 쪽(Notifier)의 몫이다.
///
/// 타이머는 항상 하나만 두고 가장 이른 예약까지만 잰다. 긴 대기는
/// [maxArmDelay] 단위로 끊어 다시 재서, 절전 후 복귀나 시계 변경에도 크게
/// 어긋나지 않는다.
class AgentScheduler {
  AgentScheduler({
    required this.onDue,
    this.onChanged,
    AgentTimerFactory? timerFactory,
    this.misfireGrace = const Duration(minutes: 10),
    this.maxArmDelay = const Duration(minutes: 30),
    this.deferredRetry = const Duration(minutes: 1),
  }) : _timerFactory = timerFactory ?? _defaultTimer;

  final AgentScheduleDueHandler onDue;

  /// 목록이 바뀔 때마다 전체 목록을 받는다. 저장과 UI 반영용.
  final void Function(List<AgentScheduledTask> tasks)? onChanged;

  /// 이보다 오래 지난 예약은 "놓친 실행"으로 본다. 그 안이면 즉시 실행한다.
  final Duration misfireGrace;
  final Duration maxArmDelay;

  /// 미룬(deferred) 예약을 다시 물어볼 간격.
  final Duration deferredRetry;

  final AgentTimerFactory _timerFactory;
  final List<AgentScheduledTask> _tasks = [];
  final Set<String> _deferred = {};
  final Set<String> _inFlight = {};
  Timer? _timer;
  bool _ticking = false;
  bool _tickRequested = false;
  bool _disposed = false;
  int _idCounter = 0;

  static Timer _defaultTimer(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  /// 다음 실행 시각 순으로 정렬한 사본.
  List<AgentScheduledTask> get tasks {
    final sorted = List<AgentScheduledTask>.from(_tasks)
      ..sort((left, right) {
        final leftAt = left.nextRunAt;
        final rightAt = right.nextRunAt;
        if (leftAt == null && rightAt == null) {
          return right.createdAt.compareTo(left.createdAt);
        }
        if (leftAt == null) return 1;
        if (rightAt == null) return -1;
        return leftAt.compareTo(rightAt);
      });
    return List.unmodifiable(sorted);
  }

  AgentScheduledTask? byId(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  /// 실행 중이거나 미뤄진 채 다시 물어볼 예약이 있는지.
  bool get hasDeferred => _deferred.isNotEmpty;

  /// 저장소에서 읽은 목록으로 교체한다. 놓친 예약을 정리하고 타이머를 잰다.
  void load(List<AgentScheduledTask> tasks) {
    _tasks
      ..clear()
      ..addAll(tasks);
    _deferred.clear();
    _reconcile(clock.now());
    _notify();
    _arm();
  }

  /// 예약을 추가한다. 다음 실행 시각이 없으면 트리거로 계산한다.
  AgentScheduledTask add(AgentScheduledTask task) {
    final now = clock.now();
    final next = task.nextRunAt ?? task.trigger.nextAfter(now, anchor: now);
    final stored = task.copyWith(
      nextRunAt: next,
      enabled: task.enabled && next != null,
    );
    _tasks.add(stored);
    _notify();
    _arm();
    return stored;
  }

  /// 새 예약 id를 만든다.
  String newId() => AgentScheduledTask.newId(clock.now(), _idCounter++);

  bool remove(String id) {
    final before = _tasks.length;
    _tasks.removeWhere((task) => task.id == id);
    _deferred.remove(id);
    if (_tasks.length == before) return false;
    _notify();
    _arm();
    return true;
  }

  bool setEnabled(String id, bool enabled) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return false;
    final task = _tasks[index];
    if (task.enabled == enabled) return true;
    final now = clock.now();
    // 다시 켤 때는 과거 시각을 그대로 두지 않고 다음 회차부터 잡는다.
    final next = enabled
        ? task.trigger.nextAfter(now, anchor: task.lastRunAt ?? now)
        : task.nextRunAt;
    if (enabled && next == null) return false;
    _tasks[index] = task.copyWith(enabled: enabled, nextRunAt: next);
    if (!enabled) _deferred.remove(id);
    _notify();
    _arm();
    return true;
  }

  /// 같은 id의 예약을 새 내용으로 바꾼다. 실행 이력은 유지하고 다음 회차는
  /// 새 트리거로 다시 잡는다. id가 없으면 false.
  bool replace(AgentScheduledTask updated) {
    final index = _tasks.indexWhere((task) => task.id == updated.id);
    if (index < 0) return false;
    final previous = _tasks[index];
    final now = clock.now();
    final next = updated.trigger.nextAfter(now, anchor: now);
    _tasks[index] = updated.copyWith(
      nextRunAt: next,
      enabled: updated.enabled && next != null,
      lastRunAt: previous.lastRunAt,
      lastResult: previous.lastResult,
      runCount: previous.runCount,
    );
    _deferred.remove(updated.id);
    _notify();
    _arm();
    return true;
  }

  /// 예약 시각과 무관하게 지금 한 번 실행을 시도한다.
  ///
  /// 반복 예약의 다음 회차는 건드리지 않는다(수동 실행이 정기 일정을 밀지 않도록).
  /// 1회 예약은 실행되면 끝난다. 결과는 [onDue]의 답에 따라 기록된다.
  Future<AgentScheduleDueResult?> runNow(String id) async {
    final task = byId(id);
    if (task == null || _disposed) return null;
    if (!_inFlight.add(id)) return AgentScheduleDueResult.deferred;
    late AgentScheduleDueResult result;
    try {
      result = await onDue(task);
    } finally {
      _inFlight.remove(id);
    }
    final index = _tasks.indexWhere((candidate) => candidate.id == id);
    if (index < 0) return result;
    final now = clock.now();
    final current = _tasks[index];
    switch (result.outcome) {
      case AgentScheduleDueOutcome.started:
        _tasks[index] = current.copyWith(
          lastRunAt: now,
          runCount: current.runCount + 1,
          nextRunAt: current.trigger.isRecurring ? current.nextRunAt : null,
          enabled: current.enabled && current.trigger.isRecurring,
          lastResult: '${AgentScheduleTrigger.formatDateTime(now)} 수동 실행 시작',
        );
      case AgentScheduleDueOutcome.skipped:
        _tasks[index] = current.copyWith(lastResult: result.detail ?? '건너뜀');
      case AgentScheduleDueOutcome.deferred:
        _tasks[index] = current.copyWith(
          lastResult: '실행 중인 loop가 있어 지금 시작하지 못했습니다',
        );
    }
    _notify();
    _arm();
    return result;
  }

  /// loop 종료 결과처럼 실행 뒤에 알게 된 정보를 남긴다.
  void recordResult(String id, String result) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks[index] = _tasks[index].copyWith(lastResult: result);
    _notify();
  }

  /// 실행 한 회의 결과를 이력에 넣고 마지막 결과 한 줄도 같이 갱신한다.
  void recordRun(String id, AgentScheduleRunRecord record, {String? summary}) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks[index] = _tasks[index]
        .withRunRecord(record)
        .copyWith(lastResult: summary ?? _tasks[index].lastResult);
    _notify();
  }

  /// 지금 시각 기준으로 실행할 때가 된 예약. 정렬은 [tasks]와 같다.
  List<AgentScheduledTask> dueTasks(DateTime now) => [
    for (final task in tasks)
      if (task.enabled &&
          task.nextRunAt != null &&
          !task.nextRunAt!.isAfter(now))
        task,
  ];

  /// 시각이 된 예약을 순서대로 처리한다.
  ///
  /// 처리 중에 또 불리면 끝난 뒤 한 번 더 돈다. [onDue]는 loop 시작처럼 오래
  /// 걸릴 수 있으므로 한 번에 한 건씩만 묻는다.
  Future<void> tick() async {
    if (_disposed) return;
    if (_ticking) {
      _tickRequested = true;
      return;
    }
    _ticking = true;
    try {
      do {
        _tickRequested = false;
        final now = clock.now();
        _reconcile(now);
        for (final task in dueTasks(now)) {
          if (_disposed) return;
          // 처리 도중 제거됐을 수 있다.
          if (byId(task.id) == null || !_inFlight.add(task.id)) continue;
          try {
            final result = await onDue(task);
            _apply(task.id, result, clock.now());
          } finally {
            _inFlight.remove(task.id);
          }
        }
      } while (_tickRequested && !_disposed);
    } finally {
      _ticking = false;
      if (!_disposed) {
        _notify();
        _arm();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _apply(String id, AgentScheduleDueResult result, DateTime now) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    switch (result.outcome) {
      case AgentScheduleDueOutcome.started:
        _deferred.remove(id);
        final next = task.trigger.isRecurring
            ? task.trigger.nextAfter(now, anchor: now)
            : null;
        _tasks[index] = task.copyWith(
          lastRunAt: now,
          runCount: task.runCount + 1,
          nextRunAt: next,
          enabled: task.enabled && next != null,
          lastResult: '${AgentScheduleTrigger.formatDateTime(now)} 실행 시작',
        );
      case AgentScheduleDueOutcome.skipped:
        _deferred.remove(id);
        final next = task.trigger.isRecurring
            ? task.trigger.nextAfter(now, anchor: now)
            : null;
        _tasks[index] = task.copyWith(
          nextRunAt: next,
          enabled: task.enabled && next != null,
          lastResult: result.detail ?? '건너뜀',
        );
      case AgentScheduleDueOutcome.deferred:
        _deferred.add(id);
    }
  }

  /// 놓친 예약을 정리한다.
  ///
  /// 유예 시간 안이면 그대로 두어 이번 tick에서 실행되게 한다. 그보다 오래됐으면
  /// 1회 예약은 끄고, 반복 예약은 다음 회차로 넘긴다. 앱이 꺼져 있던 동안의
  /// 회차를 몰아서 실행하면 사용자가 예상하지 못한 loop가 연달아 돈다.
  void _reconcile(DateTime now) {
    final cutoff = now.subtract(misfireGrace);
    for (var index = 0; index < _tasks.length; index++) {
      final task = _tasks[index];
      if (!task.enabled) continue;
      final next = task.nextRunAt;
      if (next == null) {
        // 저장 당시 다음 회차가 없던 반복 예약은 여기서 다시 잡는다.
        final recomputed = task.trigger.nextAfter(
          now,
          anchor: task.lastRunAt ?? task.createdAt,
        );
        _tasks[index] = task.copyWith(
          nextRunAt: recomputed,
          enabled: recomputed != null,
        );
        continue;
      }
      if (!next.isBefore(cutoff)) continue;
      final missedLabel = AgentScheduleTrigger.formatDateTime(next);
      if (!task.trigger.isRecurring) {
        _tasks[index] = task.copyWith(
          enabled: false,
          nextRunAt: null,
          lastResult: '$missedLabel 예약을 지나 실행하지 못했습니다 (앱이 실행 중이지 않았음)',
        );
        continue;
      }
      _tasks[index] = task.copyWith(
        nextRunAt: task.trigger.nextAfter(now, anchor: now),
        lastResult: '$missedLabel 회차를 건너뛰었습니다 (앱이 실행 중이지 않았음)',
      );
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_disposed) return;
    final now = clock.now();
    Duration? delay;
    if (_deferred.isNotEmpty) {
      delay = deferredRetry;
    } else {
      DateTime? earliest;
      for (final task in _tasks) {
        final next = task.nextRunAt;
        if (!task.enabled || next == null) continue;
        if (earliest == null || next.isBefore(earliest)) earliest = next;
      }
      if (earliest == null) return;
      final until = earliest.difference(now);
      delay = until.isNegative ? Duration.zero : until;
    }
    if (delay > maxArmDelay) delay = maxArmDelay;
    _timer = _timerFactory(delay, () {
      _timer = null;
      unawaited(tick());
    });
  }

  void _notify() {
    onChanged?.call(tasks);
  }
}
