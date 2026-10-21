import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';
import 'agent_mailbox.dart';
import 'agent_models.dart';
import 'agent_session_role.dart';

class AgentRunSnapshot {
  const AgentRunSnapshot({
    required this.runId,
    required this.savedAt,
    required this.state,
  });

  final String runId;
  final DateTime savedAt;
  final AgentLoopState state;

  Map<String, Object?> toJson() => {
    'version': 1,
    'runId': runId,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'state': AgentRunCodec.stateToJson(state),
  };

  static AgentRunSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final runId = value['runId'];
    final savedAt = DateTime.tryParse(value['savedAt']?.toString() ?? '');
    final state = AgentRunCodec.stateFromJson(value['state']);
    if (runId is! String || runId.isEmpty || savedAt == null || state == null) {
      return null;
    }
    return AgentRunSnapshot(runId: runId, savedAt: savedAt, state: state);
  }
}

abstract interface class AgentRunStore {
  Future<AgentRunSnapshot?> loadCurrent();

  Future<void> saveCurrent(AgentRunSnapshot snapshot);

  Future<void> appendEvent(String runId, AgentEvent event);

  Future<List<AgentEvent>> loadEvents(String runId);

  Future<void> clearCurrent();

  /// [runId]의 이력과, 같은 실행을 가리키는 현재 스냅샷만 지운다.
  /// 삭제 실패는 호출자에게 전달한다. 다른 실행은 보존한다.
  Future<void> clearRun(String runId);
}

class FileAgentRunStore implements AgentRunStore {
  FileAgentRunStore({this.maxHistoryRuns = 20, Directory? baseDirectory})
    : _baseDirectoryOverride = baseDirectory;

  final int maxHistoryRuns;
  final Directory? _baseDirectoryOverride;
  Future<void> _pendingWrite = Future<void>.value();

  Future<Directory> _baseDirectory() async {
    final override = _baseDirectoryOverride;
    if (override != null) return override;
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}agent_chat');
  }

  Future<File> _currentFile() async {
    final base = await _baseDirectory();
    return File('${base.path}${Platform.pathSeparator}current.json');
  }

  Future<Directory> _historyDirectory() async {
    final base = await _baseDirectory();
    return Directory('${base.path}${Platform.pathSeparator}history');
  }

  Future<File> _historyFile(String runId) async {
    final history = await _historyDirectory();
    final safeRunId = runId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${history.path}${Platform.pathSeparator}$safeRunId.jsonl');
  }

  @override
  Future<AgentRunSnapshot?> loadCurrent() async {
    try {
      await _settlePendingWrite();
      final file = await _currentFile();
      if (!file.existsSync()) return null;
      return AgentRunSnapshot.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveCurrent(AgentRunSnapshot snapshot) {
    final encoded = const JsonEncoder.withIndent(
      ' ',
    ).convert(snapshot.toJson());
    return _enqueue(() async {
      final file = await _currentFile();
      await file.parent.create(recursive: true);
      await _replaceAtomically(file, encoded);
    });
  }

  @override
  Future<void> appendEvent(String runId, AgentEvent event) {
    final encoded = '${jsonEncode(AgentRunCodec.eventToJson(event))}\n';
    return _enqueue(() async {
      final file = await _historyFile(runId);
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, mode: FileMode.append, flush: true);
      if (event is LoopStartedEvent) await _pruneHistory(file.parent);
    });
  }

  @override
  Future<List<AgentEvent>> loadEvents(String runId) async {
    try {
      await _settlePendingWrite();
      final file = await _historyFile(runId);
      if (!file.existsSync()) return const [];
      final events = <AgentEvent>[];
      for (final line in await file.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final event = AgentRunCodec.eventFromJson(jsonDecode(line));
          if (event != null) events.add(event);
        } catch (_) {
          // 손상된 한 행은 건너뛰고 나머지 감사 기록은 계속 읽는다.
        }
      }
      return events;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> clearCurrent() {
    return _enqueue(() async {
      final file = await _currentFile();
      await _deleteIfPresent(file);
    }, propagateErrors: true);
  }

  @override
  Future<void> clearRun(String runId) {
    return _enqueue(() async {
      final current = await _currentFile();
      var matchesCurrent = false;
      try {
        final snapshot = AgentRunSnapshot.fromJson(
          jsonDecode(await current.readAsString()),
        );
        if (snapshot == null) {
          throw const FormatException('실행 스냅샷을 확인할 수 없습니다.');
        }
        matchesCurrent = snapshot.runId == runId;
      } on FileSystemException catch (error) {
        if (!_isMissingFile(error)) rethrow;
      }
      final history = await _historyFile(runId);
      // 이력 삭제가 실패하면 복원용 current는 남겨 재시도할 수 있게 한다.
      await _deleteIfPresent(history);
      if (matchesCurrent) await _deleteIfPresent(current);
    }, propagateErrors: true);
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      if (!_isMissingFile(error)) rethrow;
    }
  }

  bool _isMissingFile(FileSystemException error) =>
      error.osError?.errorCode == 2 ||
      (Platform.isWindows && error.osError?.errorCode == 3);

  Future<void> _pruneHistory(Directory directory) async {
    if (maxHistoryRuns <= 0 || !directory.existsSync()) return;
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.jsonl'))
            .toList()
          ..sort(
            (left, right) =>
                right.lastModifiedSync().compareTo(left.lastModifiedSync()),
          );
    for (final file in files.skip(maxHistoryRuns)) {
      await file.delete();
    }
  }

  Future<void> _replaceAtomically(File target, String contents) =>
      writeFileAtomically(target, contents);

  Future<void> _settlePendingWrite() async {
    try {
      await _pendingWrite;
    } catch (_) {
      // 이어지는 읽기/쓰기가 이전 실패와 무관하게 진행되도록 한다.
    }
  }

  Future<void> _enqueue(
    Future<void> Function() operation, {
    bool propagateErrors = false,
  }) {
    final result = _pendingWrite.then((_) => operation());
    // 실패해도 큐는 계속 진행한다. 삭제 호출자에게는 실제 결과를 돌려준다.
    _pendingWrite = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return propagateErrors ? result : _pendingWrite;
  }
}

final agentRunStoreProvider = Provider<AgentRunStore>(
  (ref) => FileAgentRunStore(),
);

abstract final class AgentRunCodec {
  static Map<String, Object?> stateToJson(AgentLoopState state) => {
    'status': state.status.name,
    'goal': state.goal,
    if (state.goalSpec != null) 'goalSpec': _goalSpecToJson(state.goalSpec!),
    'step': state.step,
    'maxSteps': state.maxSteps,
    'startedAt': state.startedAt?.toUtc().toIso8601String(),
    'allowedSessionIds': state.allowedSessionIds,
    'sessionRoles': sessionRolesToJson(state.sessionRoles),
    'sessionTasks': {
      for (final entry in state.sessionTasks.entries)
        entry.key: _sessionTaskToJson(entry.value),
    },
    'events': [for (final event in state.events) eventToJson(event)],
    if (state.pendingApproval != null)
      'pendingApproval': _approvalToJson(state.pendingApproval!),
    'pendingQuestion': state.pendingQuestion,
    'pauseReason': state.pauseReason?.name,
    'pauseMessage': state.pauseMessage,
    'outcome': state.outcome?.name,
    'undeliveredMessages': [
      for (final message in state.undeliveredMessages) _messageToJson(message),
    ],
    'handoffs': [for (final handoff in state.handoffs) handoff.toJson()],
  };

  static AgentLoopState? stateFromJson(Object? value) {
    if (value is! Map) return null;
    final status = _enumByName(AgentLoopStatus.values, value['status']);
    if (status == null) return null;
    final rawTasks = value['sessionTasks'];
    final rawEvents = value['events'];
    return AgentLoopState(
      status: status,
      goal: _string(value['goal']),
      goalSpec: _goalSpecFromJson(value['goalSpec']),
      step: _integer(value['step']) ?? 0,
      maxSteps: _integer(value['maxSteps']) ?? AgentLoopState.defaultMaxSteps,
      startedAt: _dateTime(value['startedAt']),
      allowedSessionIds: _stringList(value['allowedSessionIds']),
      sessionRoles: sessionRolesFromJson(value['sessionRoles']),
      sessionTasks: rawTasks is Map
          ? {
              for (final entry in rawTasks.entries)
                if (entry.key is String)
                  if (_sessionTaskFromJson(entry.value)
                      case final SessionTaskView task)
                    entry.key as String: task,
            }
          : const {},
      events: rawEvents is List
          ? rawEvents.map(eventFromJson).whereType<AgentEvent>().toList()
          : const [],
      pendingApproval: _approvalFromJson(value['pendingApproval']),
      pendingQuestion: _string(value['pendingQuestion']),
      pauseReason: _enumByName(AgentPauseReason.values, value['pauseReason']),
      pauseMessage: _string(value['pauseMessage']),
      outcome: _enumByName(AgentLoopOutcome.values, value['outcome']),
      undeliveredMessages: value['undeliveredMessages'] is List
          ? [
              for (final item in value['undeliveredMessages'] as List)
                ?_messageFromJson(item),
            ]
          : const [],
      handoffs: value['handoffs'] is List
          ? [
              for (final item in value['handoffs'] as List)
                ?AgentHandoff.fromJson(item),
            ]
          : const [],
    );
  }

  static Map<String, Object?> _messageToJson(AgentMessage message) => {
    'id': message.id,
    'from': message.from,
    'to': message.to,
    'body': message.body,
    'at': message.at.toUtc().toIso8601String(),
  };

  static AgentMessage? _messageFromJson(Object? value) {
    if (value is! Map || !_hasStrings(value, ['from', 'to', 'body'])) {
      return null;
    }
    final at = _dateTime(value['at']);
    if (at == null) return null;
    return AgentMessage(
      id: _integer(value['id']) ?? 0,
      from: value['from'] as String,
      to: value['to'] as String,
      body: value['body'] as String,
      at: at,
    );
  }

  static Map<String, Object?> eventToJson(AgentEvent event) {
    final base = <String, Object?>{'at': event.at.toUtc().toIso8601String()};
    return switch (event) {
      LoopStartedEvent(:final goal, :final scope, :final goalSpec) => {
        ...base,
        'type': 'loopStarted',
        'goal': goal,
        'scope': scope,
        if (goalSpec != null) 'goalSpec': _goalSpecToJson(goalSpec),
      },
      LoopFinishedEvent(
        :final outcome,
        :final summary,
        :final steps,
        :final elapsed,
      ) =>
        {
          ...base,
          'type': 'loopFinished',
          'outcome': outcome.name,
          'summary': summary,
          'steps': steps,
          'elapsedMs': elapsed.inMilliseconds,
        },
      ThoughtEvent(:final step, :final text) => {
        ...base,
        'type': 'thought',
        'step': step,
        'text': text,
      },
      DispatchedEvent(
        :final sessionId,
        :final sessionName,
        :final kind,
        :final payload,
        :final reason,
        :final capability,
      ) =>
        {
          ...base,
          'type': 'dispatched',
          'sessionId': sessionId,
          'sessionName': sessionName,
          'kind': kind,
          'payload': payload,
          'reason': reason,
          if (capability != null)
            'capability': AgentSessionRole.capabilityLabel(capability),
        },
      ObservedEvent(
        :final sessionId,
        :final sessionName,
        :final delta,
        :final quiescent,
        :final isSnapshot,
      ) =>
        {
          ...base,
          'type': 'observed',
          'sessionId': sessionId,
          'sessionName': sessionName,
          'delta': delta,
          'quiescent': quiescent,
          'isSnapshot': isSnapshot,
        },
      VerifiedEvent(:final verdict, :final summary) => {
        ...base,
        'type': 'verified',
        'verdict': verdict,
        'summary': summary,
      },
      ReportEvent(:final markdown) => {
        ...base,
        'type': 'report',
        'markdown': markdown,
      },
      UserFeedbackEvent(:final text) => {
        ...base,
        'type': 'userFeedback',
        'text': text,
      },
      ApprovalRequestedEvent(:final approval) => {
        ...base,
        'type': 'approvalRequested',
        'approval': _approvalToJson(approval),
      },
      ApprovalResolvedEvent(:final approved, :final description) => {
        ...base,
        'type': 'approvalResolved',
        'approved': approved,
        'description': description,
      },
      RolePolicyRejectedEvent(
        :final sessionId,
        :final sessionName,
        :final roleKind,
        :final capability,
        :final reason,
      ) =>
        {
          ...base,
          'type': 'rolePolicyRejected',
          'sessionId': sessionId,
          'sessionName': sessionName,
          'roleKind': roleKind.name,
          'capability': AgentSessionRole.capabilityLabel(capability),
          'reason': reason,
        },
      HandoffRecordedEvent(:final handoff) => {
        ...base,
        'type': 'handoffRecorded',
        'handoff': handoff.toJson(),
      },
      AskUserEvent(:final question) => {
        ...base,
        'type': 'askUser',
        'question': question,
      },
      MessagePostedEvent(:final from, :final to, :final body) => {
        ...base,
        'type': 'messagePosted',
        'from': from,
        'to': to,
        'body': body,
      },
      MessageWithdrawnEvent(:final from, :final to, :final body) => {
        ...base,
        'type': 'messageWithdrawn',
        'from': from,
        'to': to,
        'body': body,
      },
      MessageDeliveredEvent(
        :final sessionId,
        :final sessionName,
        :final senders,
      ) =>
        {
          ...base,
          'type': 'messageDelivered',
          'sessionId': sessionId,
          'sessionName': sessionName,
          'senders': senders,
        },
      LoopErrorEvent(:final message) => {
        ...base,
        'type': 'loopError',
        'message': message,
      },
      LoopRetryEvent(:final attempt, :final delay, :final message) => {
        ...base,
        'type': 'loopRetry',
        'attempt': attempt,
        'delayMs': delay.inMilliseconds,
        'message': message,
      },
      SessionRetryEvent(
        :final sessionId,
        :final sessionName,
        :final attempt,
        :final reason,
        :final evidence,
      ) =>
        {
          ...base,
          'type': 'sessionRetry',
          'sessionId': sessionId,
          'sessionName': sessionName,
          'attempt': attempt,
          'reason': reason,
          'evidence': evidence,
        },
      TerminalRuntimeIssueEvent(
        :final code,
        :final sessionId,
        :final sessionName,
        :final message,
        :final evidence,
      ) =>
        {
          ...base,
          'type': 'terminalRuntimeIssue',
          'code': code,
          'sessionId': sessionId,
          'sessionName': sessionName,
          'message': message,
          'evidence': evidence,
        },
      DeadlineReachedEvent(:final deadline, :final overrun) => {
        ...base,
        'type': 'deadlineReached',
        'deadline': deadline.toUtc().toIso8601String(),
        'overrunMs': overrun.inMilliseconds,
      },
      ScheduleTriggeredEvent(
        :final taskId,
        :final title,
        :final triggerLabel,
        :final interruptedGoal,
      ) =>
        {
          ...base,
          'type': 'scheduleTriggered',
          'taskId': taskId,
          'title': title,
          'triggerLabel': triggerLabel,
          'interruptedGoal': interruptedGoal,
        },
      ScheduleRequestedEvent(
        :final taskId,
        :final title,
        :final runAt,
        :final reason,
      ) =>
        {
          ...base,
          'type': 'scheduleRequested',
          'taskId': taskId,
          'title': title,
          'runAt': runAt.toUtc().toIso8601String(),
          'reason': reason,
        },
      CollapsedEvent(:final count) => {
        ...base,
        'type': 'collapsed',
        'count': count,
      },
    };
  }

  static AgentEvent? eventFromJson(Object? value) {
    if (value is! Map) return null;
    final at = _dateTime(value['at']);
    final type = value['type'];
    if (at == null || type is! String) return null;
    return switch (type) {
      'loopStarted' when _hasStrings(value, ['goal', 'scope']) =>
        LoopStartedEvent(
          at,
          goal: value['goal'] as String,
          scope: value['scope'] as String,
          goalSpec: _goalSpecFromJson(value['goalSpec']),
        ),
      'loopFinished'
          when _enumByName(AgentLoopOutcome.values, value['outcome']) != null &&
              _string(value['summary']) != null =>
        LoopFinishedEvent(
          at,
          outcome: _enumByName(AgentLoopOutcome.values, value['outcome'])!,
          summary: value['summary'] as String,
          steps: _integer(value['steps']) ?? 0,
          elapsed: Duration(milliseconds: _integer(value['elapsedMs']) ?? 0),
        ),
      'thought' when _string(value['text']) != null => ThoughtEvent(
        at,
        step: _integer(value['step']) ?? 0,
        text: value['text'] as String,
      ),
      'dispatched'
          when _hasStrings(value, [
            'sessionId',
            'sessionName',
            'kind',
            'payload',
          ]) =>
        DispatchedEvent(
          at,
          sessionId: value['sessionId'] as String,
          sessionName: value['sessionName'] as String,
          kind: value['kind'] as String,
          payload: value['payload'] as String,
          reason: _string(value['reason']),
          capability: AgentSessionRole.capabilityFromWire(
            _string(value['capability']) ?? '',
          ),
        ),
      'observed'
          when _hasStrings(value, ['sessionId', 'sessionName', 'delta']) =>
        ObservedEvent(
          at,
          sessionId: value['sessionId'] as String,
          sessionName: value['sessionName'] as String,
          delta: value['delta'] as String,
          quiescent: value['quiescent'] == true,
          isSnapshot: value['isSnapshot'] == true,
        ),
      'verified' when _hasStrings(value, ['verdict', 'summary']) =>
        VerifiedEvent(
          at,
          verdict: value['verdict'] as String,
          summary: value['summary'] as String,
        ),
      'report' when _string(value['markdown']) != null => ReportEvent(
        at,
        markdown: value['markdown'] as String,
      ),
      'userFeedback' when _string(value['text']) != null => UserFeedbackEvent(
        at,
        text: value['text'] as String,
      ),
      'approvalRequested' when _approvalFromJson(value['approval']) != null =>
        ApprovalRequestedEvent(
          at,
          approval: _approvalFromJson(value['approval'])!,
        ),
      'approvalResolved' when _string(value['description']) != null =>
        ApprovalResolvedEvent(
          at,
          approved: value['approved'] == true,
          description: value['description'] as String,
        ),
      'rolePolicyRejected'
          when _hasStrings(value, ['sessionId', 'sessionName', 'reason']) &&
              AgentSessionRole.capabilityFromWire(
                    _string(value['capability']) ?? '',
                  ) !=
                  null =>
        RolePolicyRejectedEvent(
          at,
          sessionId: value['sessionId'] as String,
          sessionName: value['sessionName'] as String,
          roleKind: _roleKindFromName(value['roleKind']),
          capability: AgentSessionRole.capabilityFromWire(
            _string(value['capability'])!,
          )!,
          reason: value['reason'] as String,
        ),
      'handoffRecorded' when AgentHandoff.fromJson(value['handoff']) != null =>
        HandoffRecordedEvent(
          at,
          handoff: AgentHandoff.fromJson(value['handoff'])!,
        ),
      'askUser' when _string(value['question']) != null => AskUserEvent(
        at,
        question: value['question'] as String,
      ),
      'messagePosted' when _hasStrings(value, ['from', 'to', 'body']) =>
        MessagePostedEvent(
          at,
          from: value['from'] as String,
          to: value['to'] as String,
          body: value['body'] as String,
        ),
      'messageWithdrawn' when _hasStrings(value, ['from', 'to', 'body']) =>
        MessageWithdrawnEvent(
          at,
          from: value['from'] as String,
          to: value['to'] as String,
          body: value['body'] as String,
        ),
      'messageDelivered'
          when _hasStrings(value, ['sessionId', 'sessionName']) =>
        MessageDeliveredEvent(
          at,
          sessionId: value['sessionId'] as String,
          sessionName: value['sessionName'] as String,
          senders: [
            for (final sender in value['senders'] as List? ?? const [])
              if (sender is String) sender,
          ],
        ),
      'loopError' when _string(value['message']) != null => LoopErrorEvent(
        at,
        message: value['message'] as String,
      ),
      'loopRetry' when _string(value['message']) != null => LoopRetryEvent(
        at,
        attempt: _integer(value['attempt']) ?? 1,
        delay: Duration(milliseconds: _integer(value['delayMs']) ?? 0),
        message: value['message'] as String,
      ),
      'sessionRetry'
          when _hasStrings(value, ['sessionId', 'sessionName', 'reason']) =>
        SessionRetryEvent(
          at,
          sessionId: value['sessionId'] as String,
          sessionName: value['sessionName'] as String,
          attempt: _integer(value['attempt']) ?? 1,
          reason: value['reason'] as String,
          evidence: _string(value['evidence']) ?? '',
        ),
      'terminalRuntimeIssue'
          when _hasStrings(value, [
            'code',
            'sessionId',
            'sessionName',
            'message',
            'evidence',
          ]) =>
        TerminalRuntimeIssueEvent(
          at,
          code: value['code'] as String,
          sessionId: value['sessionId'] as String,
          sessionName: value['sessionName'] as String,
          message: value['message'] as String,
          evidence: value['evidence'] as String,
        ),
      'deadlineReached' when _dateTime(value['deadline']) != null =>
        DeadlineReachedEvent(
          at,
          deadline: _dateTime(value['deadline'])!,
          overrun: Duration(milliseconds: _integer(value['overrunMs']) ?? 0),
        ),
      'scheduleTriggered'
          when _hasStrings(value, ['taskId', 'title', 'triggerLabel']) =>
        ScheduleTriggeredEvent(
          at,
          taskId: value['taskId'] as String,
          title: value['title'] as String,
          triggerLabel: value['triggerLabel'] as String,
          interruptedGoal: _string(value['interruptedGoal']),
        ),
      'scheduleRequested'
          when _hasStrings(value, ['taskId', 'title']) &&
              _dateTime(value['runAt']) != null =>
        ScheduleRequestedEvent(
          at,
          taskId: value['taskId'] as String,
          title: value['title'] as String,
          runAt: _dateTime(value['runAt'])!,
          reason: _string(value['reason']),
        ),
      'collapsed' => CollapsedEvent(at, count: _integer(value['count']) ?? 0),
      _ => null,
    };
  }

  static Map<String, Object?> _goalSpecToJson(AgentGoalSpec goal) => {
    'objective': goal.objective,
    'successCriteria': goal.successCriteria,
    'verificationSteps': goal.verificationSteps,
    'constraints': goal.constraints,
    'continuationContext': goal.continuationContext,
    'deadline': goal.deadline?.toUtc().toIso8601String(),
  };

  static AgentGoalSpec? _goalSpecFromJson(Object? value) {
    if (value is! Map || _string(value['objective']) == null) return null;
    return AgentGoalSpec(
      objective: value['objective'] as String,
      successCriteria: _stringList(value['successCriteria']),
      verificationSteps: _stringList(value['verificationSteps']),
      constraints: _stringList(value['constraints']),
      continuationContext: _string(value['continuationContext']),
      deadline: _dateTime(value['deadline']),
    ).normalized();
  }

  static Map<String, Object?> _approvalToJson(PendingApproval approval) => {
    'sessionId': approval.sessionId,
    'sessionName': approval.sessionName,
    'description': approval.description,
    'reason': approval.reason,
    'screenContext': approval.screenContext,
    if (approval.kind != PendingApprovalKind.destructive)
      'kind': approval.kind.name,
    if (approval.capability != null)
      'capability': AgentSessionRole.capabilityLabel(approval.capability!),
  };

  static AgentRoleKind _roleKindFromName(Object? raw) {
    for (final kind in AgentRoleKind.values) {
      if (kind.name == raw) return kind;
    }
    return AgentRoleKind.custom;
  }

  static PendingApprovalKind _approvalKindFromName(Object? raw) {
    for (final kind in PendingApprovalKind.values) {
      if (kind.name == raw) return kind;
    }
    return PendingApprovalKind.destructive;
  }

  static PendingApproval? _approvalFromJson(Object? value) {
    if (value is! Map ||
        !_hasStrings(value, [
          'sessionId',
          'sessionName',
          'description',
          'reason',
        ])) {
      return null;
    }
    return PendingApproval(
      sessionId: value['sessionId'] as String,
      sessionName: value['sessionName'] as String,
      description: value['description'] as String,
      reason: value['reason'] as String,
      screenContext: _string(value['screenContext']) ?? '',
      kind: _approvalKindFromName(value['kind']),
      capability: AgentSessionRole.capabilityFromWire(
        _string(value['capability']) ?? '',
      ),
    );
  }

  static Map<String, Object?> _sessionTaskToJson(SessionTaskView task) => {
    'sessionId': task.sessionId,
    'displayName': task.displayName,
    'agentHint': task.agentHint,
    'phase': task.phase.name,
    'role': task.role?.toJson(),
    'lastInstruction': task.lastInstruction,
    'unreadMessages': task.unreadMessages,
    'backgroundRunning': task.backgroundRunning,
  };

  static SessionTaskView? _sessionTaskFromJson(Object? value) {
    if (value is! Map ||
        !_hasStrings(value, ['sessionId', 'displayName', 'agentHint'])) {
      return null;
    }
    final phase = _enumByName(SessionTaskPhase.values, value['phase']);
    if (phase == null) return null;
    return SessionTaskView(
      sessionId: value['sessionId'] as String,
      displayName: value['displayName'] as String,
      agentHint: value['agentHint'] as String,
      phase: phase,
      role: AgentSessionRole.fromJson(value['role']),
      lastInstruction: _string(value['lastInstruction']),
      unreadMessages: _integer(value['unreadMessages']) ?? 0,
      backgroundRunning: value['backgroundRunning'] == true,
    );
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static DateTime? _dateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal();

  static int? _integer(Object? value) => switch (value) {
    int() => value,
    num() => value.round(),
    String() => int.tryParse(value),
    _ => null,
  };

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static List<String> _stringList(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is String) item,
        ]
      : const [];

  static bool _hasStrings(Map<dynamic, dynamic> value, List<String> keys) =>
      keys.every((key) => value[key] is String);
}
