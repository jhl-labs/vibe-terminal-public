import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';
import 'agent_workspace_test.dart';

typedef WorkspaceTestApplicationSupportDirectory = Future<Directory> Function();

abstract interface class AgentWorkspaceTestStore {
  Future<AgentWorkspaceTestResult?> latest(String workspaceId);
  Future<void> save(AgentWorkspaceTestResult result);
  Future<void> remove(String workspaceId);
}

class FileAgentWorkspaceTestStore implements AgentWorkspaceTestStore {
  FileAgentWorkspaceTestStore({
    WorkspaceTestApplicationSupportDirectory? directory,
  }) : _directory = directory ?? getApplicationSupportDirectory;

  final WorkspaceTestApplicationSupportDirectory _directory;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<AgentWorkspaceTestResult?> latest(String workspaceId) async {
    try {
      await _pendingWrite;
      return (await _read())[workspaceId];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(AgentWorkspaceTestResult result) => _mutate((entries) {
    entries[result.workspaceId] = result;
  });

  @override
  Future<void> remove(String workspaceId) => _mutate((entries) {
    entries.remove(workspaceId);
  });

  Future<void> _mutate(
    void Function(Map<String, AgentWorkspaceTestResult> entries) change,
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
          'entries': [for (final result in entries.values) result.toJson()],
        }),
      );
    }

    _pendingWrite = _pendingWrite.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    return _pendingWrite;
  }

  Future<Map<String, AgentWorkspaceTestResult>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) return {};
      final results = <String, AgentWorkspaceTestResult>{};
      for (final value in decoded['entries'] as List) {
        final result = AgentWorkspaceTestResult.fromJson(value);
        if (result != null) results[result.workspaceId] = result;
      }
      return results;
    } catch (_) {
      return {};
    }
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File(
      '${directory.path}${Platform.pathSeparator}agent_workspace_tests.json',
    );
  }
}

final agentWorkspaceTestStoreProvider = Provider<AgentWorkspaceTestStore>(
  (ref) => FileAgentWorkspaceTestStore(),
);
