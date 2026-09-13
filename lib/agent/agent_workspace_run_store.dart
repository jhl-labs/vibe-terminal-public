import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';
import 'agent_workspace_run.dart';

typedef WorkspaceRunApplicationSupportDirectory = Future<Directory> Function();

abstract interface class AgentWorkspaceRunStore {
  Future<AgentWorkspaceRunRecord?> latest(String workspaceId);
  Future<void> save(AgentWorkspaceRunRecord record);
  Future<void> remove(String workspaceId);
}

class FileAgentWorkspaceRunStore implements AgentWorkspaceRunStore {
  FileAgentWorkspaceRunStore({
    WorkspaceRunApplicationSupportDirectory? directory,
  }) : _directory = directory ?? getApplicationSupportDirectory;

  final WorkspaceRunApplicationSupportDirectory _directory;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<AgentWorkspaceRunRecord?> latest(String workspaceId) async {
    try {
      await _pendingWrite;
      return (await _read())[workspaceId];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(AgentWorkspaceRunRecord record) => _mutate((entries) {
    entries[record.workspaceId] = record;
  });

  @override
  Future<void> remove(String workspaceId) => _mutate((entries) {
    entries.remove(workspaceId);
  });

  Future<void> _mutate(
    void Function(Map<String, AgentWorkspaceRunRecord> entries) change,
  ) {
    Future<void> operation() async {
      final entries = await _read();
      change(entries);
      final file = await _file();
      if (entries.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await writeFileAtomically(
        file,
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'entries': [for (final record in entries.values) record.toJson()],
        }),
      );
    }

    _pendingWrite = _pendingWrite.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    return _pendingWrite;
  }

  Future<Map<String, AgentWorkspaceRunRecord>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) return {};
      final records = <String, AgentWorkspaceRunRecord>{};
      for (final value in decoded['entries'] as List) {
        final record = AgentWorkspaceRunRecord.fromJson(value);
        if (record != null) records[record.workspaceId] = record;
      }
      return records;
    } catch (_) {
      return {};
    }
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File(
      '${directory.path}${Platform.pathSeparator}agent_workspace_runs.json',
    );
  }
}

final agentWorkspaceRunStoreProvider = Provider<AgentWorkspaceRunStore>(
  (ref) => FileAgentWorkspaceRunStore(),
);
