import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/recoverable_json_file.dart';
import 'agent_schedule.dart';
import 'agent_schedule_claim_store.dart';

/// 예약 목록 저장소. 앱을 재시작해도 예약이 유지되도록 한다.
abstract interface class AgentScheduleStore {
  Future<List<AgentScheduledTask>> load();

  Future<void> save(List<AgentScheduledTask> tasks);
}

/// `agent_chat/schedule.json` 한 파일에 전체 목록을 원자적으로 쓴다.
///
/// 실행 기록(AgentRunStore)과 같은 디렉터리를 쓰되 파일은 분리한다. 예약은
/// 실행과 수명이 달라서(실행이 끝나도 반복 예약은 남는다) 같은 스냅샷에 섞으면
/// `clearCurrent`가 예약까지 지운다.
class FileAgentScheduleStore
    implements AgentScheduleStore, AgentScheduleClaimStore {
  FileAgentScheduleStore({Directory? baseDirectory})
    : _baseDirectoryOverride = baseDirectory;

  late final FileAgentScheduleClaims _claims = FileAgentScheduleClaims(
    () async => (await _file()).parent,
  );
  @override
  Future<bool> claimOccurrence(String key) => _claims.claimOccurrence(key);

  final Directory? _baseDirectoryOverride;
  Future<void> _pendingWrite = Future<void>.value();

  Future<File> _file() async {
    final base =
        _baseDirectoryOverride ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}agent_chat',
        );
    return File('${base.path}${Platform.pathSeparator}schedule.json');
  }

  @override
  Future<List<AgentScheduledTask>> load() async {
    await _settlePendingWrite();
    final file = await _file();
    final decoded = await readRecoverableJson(
      file,
      validate: (value) {
        if (value is! Map || value['version'] != 1 || value['tasks'] is! List) {
          return false;
        }
        return (value['tasks'] as List).every(
          (row) => AgentScheduledTask.fromJson(row) != null,
        );
      },
    );
    return AgentScheduleCodec.tasksFromJson(decoded);
  }

  @override
  Future<void> save(List<AgentScheduledTask> tasks) {
    final encoded = const JsonEncoder.withIndent(
      ' ',
    ).convert(AgentScheduleCodec.tasksToJson(tasks));
    return _enqueue(() async {
      final file = await _file();
      await writeRecoverableJson(file, encoded);
    });
  }

  Future<void> _settlePendingWrite() async {
    try {
      await _pendingWrite;
    } catch (_) {
      // 이전 쓰기 실패가 읽기를 막지 않게 한다.
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _pendingWrite = _pendingWrite.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    return _pendingWrite;
  }
}

abstract final class AgentScheduleCodec {
  static Map<String, Object?> tasksToJson(List<AgentScheduledTask> tasks) => {
    'version': 1,
    'tasks': [for (final task in tasks) task.toJson()],
  };

  static List<AgentScheduledTask> tasksFromJson(Object? value) {
    if (value is! Map) return const [];
    final raw = value['tasks'];
    if (raw is! List) return const [];
    return [for (final item in raw) ?AgentScheduledTask.fromJson(item)];
  }
}

final agentScheduleStoreProvider = Provider<AgentScheduleStore>(
  (ref) => FileAgentScheduleStore(),
);
