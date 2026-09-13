import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';
import 'agent_worktree.dart';

typedef WorktreeApplicationSupportDirectory = Future<Directory> Function();

/// 앱이 만든 Agent worktree의 수명을 세션 스냅샷과 독립적으로 보존한다.
///
/// 세션 탭이 닫히거나 복원 파일이 손상돼도 작업공간을 잃지 않도록 별도 파일을
/// 사용한다. Git 상태 판정과 삭제는 이 저장소가 아닌 SessionManager가 맡는다.
class AgentWorktreeStore {
  AgentWorktreeStore({WorktreeApplicationSupportDirectory? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final WorktreeApplicationSupportDirectory _directory;
  Future<void> _pendingWrite = Future<void>.value();

  Future<List<AgentWorktreeRecord>> all() async {
    try {
      await _pendingWrite;
      return await _readWithoutWaiting();
    } catch (_) {
      return const [];
    }
  }

  Future<AgentWorktreeRecord?> find(String id) async {
    for (final entry in await all()) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> upsert(AgentWorktreeRecord record) => _mutate((entries) {
    entries.removeWhere((entry) => entry.id == record.id);
    entries.add(record);
  });

  Future<void> remove(String id) =>
      _mutate((entries) => entries.removeWhere((entry) => entry.id == id));

  /// 이전 앱 실행에서 active/provisioning으로 남은 항목은 현재 프로세스에서
  /// 실행 중임을 보장할 수 없으므로 일단 stranded로 내린다.
  Future<void> markPreviousRunStranded() async {
    try {
      await _mutate((entries) {
        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          if (entry.lifecycle == AgentWorktreeLifecycle.active ||
              entry.lifecycle == AgentWorktreeLifecycle.provisioning) {
            entries[index] = entry.copyWith(
              lifecycle: AgentWorktreeLifecycle.stranded,
              sessionId: null,
            );
          }
        }
      });
    } catch (_) {
      // Registry 복구 실패가 터미널 세션 시작을 막아서는 안 된다.
    }
  }

  Future<void> _mutate(
    void Function(List<AgentWorktreeRecord> entries) change,
  ) {
    _pendingWrite = _pendingWrite.then(
      (_) async {
        final entries = await _readWithoutWaiting();
        change(entries);
        entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _write(entries);
      },
      onError: (_) async {
        final entries = await _readWithoutWaiting();
        change(entries);
        entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _write(entries);
      },
    );
    return _pendingWrite;
  }

  Future<List<AgentWorktreeRecord>> _readWithoutWaiting() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) return [];
      return (decoded['entries'] as List)
          .map(AgentWorktreeRecord.fromJson)
          .whereType<AgentWorktreeRecord>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<AgentWorktreeRecord> entries) async {
    final file = await _file();
    if (entries.isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    await writeFileAtomically(
      file,
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'entries': [for (final entry in entries) entry.toJson()],
      }),
    );
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File(
      '${directory.path}${Platform.pathSeparator}agent_worktrees.json',
    );
  }
}
