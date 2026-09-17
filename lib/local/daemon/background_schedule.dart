import 'dart:convert';
import 'dart:io';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../../core/recoverable_json_file.dart';
import '../../agent/agent_schedule_claim_store.dart';
import 'protocol.dart';

typedef BackgroundTaskLauncher =
    Future<String> Function(Map<String, dynamic> launch);

/// 데몬이 소유하는 명령 예약. UI 연결이나 Flutter provider 수명과 무관하다.
class BackgroundScheduleService {
  BackgroundScheduleService(
    this.directory,
    this.launch, {
    DateTime Function()? now,
    this.isRunning,
  }) : now = now ?? DateTime.now {
    tzdata.initializeTimeZones();
  }
  final Directory directory;
  final BackgroundTaskLauncher launch;
  final bool Function(String sessionId)? isRunning;
  final Map<String, int> _earlyExits = {};
  final DateTime Function() now;
  final Map<String, Map<String, dynamic>> _tasks = {};
  bool _ticking = false;
  bool _mutating = false;
  Future<T> _mutate<T>(Future<T> Function() action) async {
    if (_ticking || _mutating) {
      throw StateError('예약 실행 또는 저장 중입니다. 잠시 후 다시 저장하세요.');
    }
    _mutating = true;
    try {
      return await action();
    } finally {
      _mutating = false;
    }
  }

  Future<void> _writes = Future.value();
  File get _file => File('${directory.path}/background-schedules.json');
  List<Map<String, dynamic>> get tasks => [
    for (final task in _tasks.values) Map<String, dynamic>.from(task),
  ];
  Future<void> load() async {
    if (_ticking || _mutating) throw StateError('Schedule storage is busy');
    final value = await readRecoverableJson(
      _file,
      validate: (v) => v is Map && v['version'] == 1 && v['tasks'] is List,
    );
    if (value == null) return;
    final loaded = <String, Map<String, dynamic>>{};
    for (final row in (value as Map)['tasks'] as List) {
      final task = Map<String, dynamic>.from(row as Map);
      _validate(task);
      loaded[task['id'] as String] = task;
    }
    _tasks
      ..clear()
      ..addAll(loaded);
  }

  void _validate(Map<String, dynamic> task) {
    if (task['id'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(task['id'] as String)) {
      throw ArgumentError('Invalid schedule ID');
    }
    if (task['title'] is! String || (task['title'] as String).length > 200) {
      throw ArgumentError('Invalid title');
    }
    if (task['launch'] is! Map) throw ArgumentError('Invalid launch');
    final spec = task['launch'] as Map;
    if (spec['executable'] is! String ||
        spec['arguments'] is! List ||
        (spec['arguments'] as List).any(
          (v) => v is! String || (v).contains('\x00'),
        )) {
      throw ArgumentError('Invalid command');
    }
    if (!['once', 'interval', 'daily'].contains(task['kind'])) {
      throw ArgumentError('Unknown trigger');
    }
    if (task['kind'] == 'interval' &&
        (task['minutes'] is! int ||
            (task['minutes'] as int) < 1 ||
            (task['minutes'] as int) > 525600)) {
      throw ArgumentError('반복 간격은 1분~1년이어야 합니다.');
    }
    if (task['kind'] == 'daily') {
      tz.getLocation(task['timezone'] as String);
      if (task['hour'] is! int ||
          task['minute'] is! int ||
          !(task['hour'] as int).isBetween(0, 23) ||
          !(task['minute'] as int).isBetween(0, 59)) {
        throw ArgumentError('Invalid daily time');
      }
    }
    if (task['nextRunAt'] != null &&
        DateTime.tryParse(task['nextRunAt'] as String) == null) {
      throw ArgumentError('Invalid next run time');
    }
  }

  Future<Map<String, dynamic>> set(Map<String, dynamic> supplied) =>
      _mutate(() => _set(supplied));
  Future<Map<String, dynamic>> _set(Map<String, dynamic> supplied) async {
    final task = Map<String, dynamic>.from(supplied);
    task['id'] ??= 'schedule-${daemonToken().replaceAll('=', '')}';
    task['enabled'] ??= true;
    _validate(task);
    final current = now().toUtc();
    task['nextRunAt'] ??= nextBackgroundOccurrence(
      task,
      current,
    )?.toIso8601String();
    if (task['enabled'] == true && task['nextRunAt'] == null) {
      throw ArgumentError('실행 시각을 지정하세요.');
    }
    final previous = _tasks[task['id']];
    _tasks[task['id']] = task;
    try {
      await _save();
    } catch (_) {
      if (previous == null) {
        _tasks.remove(task['id']);
      } else {
        _tasks[task['id']] = previous;
      }
      rethrow;
    }
    return task;
  }

  Future<void> remove(String id) => _mutate(() => _remove(id));
  Future<void> _remove(String id) async {
    final previous = _tasks.remove(id);
    try {
      await _save();
    } catch (_) {
      if (previous != null) _tasks[id] = previous;
      rethrow;
    }
  }

  Future<void> _save() {
    final encoded = jsonEncode({'version': 1, 'tasks': tasks});
    _writes = _writes.then(
      (_) => writeRecoverableJson(_file, encoded),
      onError: (_) => writeRecoverableJson(_file, encoded),
    );
    return _writes;
  }

  Future<void> tick() async {
    if (_ticking || _mutating) return;
    _ticking = true;
    try {
      for (final task in _tasks.values.toList()) {
        if (task['enabled'] != true || !identical(_tasks[task['id']], task)) {
          continue;
        }
        final due = DateTime.tryParse('${task['nextRunAt']}');
        final current = now().toUtc();
        if (due == null || due.isAfter(current)) continue;
        final previousSession = task['lastSessionId'];
        if (previousSession is String &&
            isRunning?.call(previousSession) == true) {
          task['lastResult'] = '이전 실행이 진행 중이어서 이번 회차를 건너뛰었습니다';
        } else if (current.difference(due) > const Duration(minutes: 10)) {
          task['lastResult'] = '놓친 회차를 건너뛰었습니다';
        } else {
          final claimed = await FileAgentScheduleClaims(() async => directory)
              .claimOccurrence(
                'background:${task['id']}:${due.toUtc().toIso8601String()}',
              );
          if (!identical(_tasks[task['id']], task)) continue;
          if (claimed) {
            try {
              final sessionId = await launch(
                Map<String, dynamic>.from(task['launch'] as Map),
              );
              task['lastSessionId'] = sessionId;
              task['lastResult'] = '실행 시작';
              task['lastStartedAt'] = current.toIso8601String();
              final earlyExit = _earlyExits.remove(sessionId);
              if (earlyExit != null) {
                task['lastExitCode'] = earlyExit;
                task['lastResult'] = '종료 코드 $earlyExit';
                task['lastFinishedAt'] = now().toUtc().toIso8601String();
              }
            } catch (error) {
              task['lastResult'] = '시작 실패: $error';
            }
          } else {
            task['lastResult'] = '시작 기록이 있는 회차입니다. 자동 중복 실행하지 않았습니다.';
          }
        }
        final next = nextBackgroundOccurrence(task, current, afterRun: true);
        task['nextRunAt'] = next?.toIso8601String();
        task['enabled'] = next != null;
        await _save();
      }
    } finally {
      _ticking = false;
    }
  }

  Future<void> recordExit(String sessionId, int code) async {
    var matched = false;
    for (final task in _tasks.values.toList()) {
      if (task['lastSessionId'] == sessionId) {
        matched = true;
        task['lastExitCode'] = code;
        task['lastResult'] = '종료 코드 $code';
        task['lastFinishedAt'] = now().toUtc().toIso8601String();
        await _save();
      }
    }
    if (!matched && _ticking) _earlyExits[sessionId] = code;
  }
}

DateTime? nextBackgroundOccurrence(
  Map task,
  DateTime after, {
  bool afterRun = false,
}) {
  switch (task['kind']) {
    case 'once':
      return afterRun
          ? null
          : DateTime.tryParse('${task['nextRunAt']}')?.toUtc();
    case 'interval':
      return after.toUtc().add(Duration(minutes: task['minutes'] as int));
    case 'daily':
      final location = tz.getLocation(task['timezone'] as String);
      final local = tz.TZDateTime.from(after, location);
      for (var day = afterRun ? 1 : 0; day < 4; day++) {
        final candidate = tz.TZDateTime(
          location,
          local.year,
          local.month,
          local.day + day,
          task['hour'] as int,
          task['minute'] as int,
        );
        // DST로 존재하지 않는 시각은 건너뛰고, 반복되는 시각은 하루 한 번만 실행한다.
        if (candidate.hour == task['hour'] &&
            candidate.minute == task['minute'] &&
            candidate.isAfter(after)) {
          return candidate.toUtc();
        }
      }
  }
  return null;
}

extension on int {
  bool isBetween(int min, int max) => this >= min && this <= max;
}
