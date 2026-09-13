import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';

typedef CleanupApplicationSupportDirectory = Future<Directory> Function();

class PendingRemoteSessionTermination {
  const PendingRemoteSessionTermination({
    required this.hostId,
    required this.remoteSessionId,
    required this.queuedAt,
  });

  final String hostId;
  final String remoteSessionId;
  final DateTime queuedAt;

  String get key => '$hostId\u0000$remoteSessionId';

  Map<String, Object?> toJson() => {
    'hostId': hostId,
    'remoteSessionId': remoteSessionId,
    'queuedAt': queuedAt.toUtc().toIso8601String(),
  };

  static PendingRemoteSessionTermination? fromJson(Object? value) {
    if (value is! Map) return null;
    final hostId = value['hostId'];
    final remoteSessionId = value['remoteSessionId'];
    final queuedAt = value['queuedAt'];
    if (hostId is! String ||
        hostId.isEmpty ||
        remoteSessionId is! String ||
        remoteSessionId.isEmpty ||
        queuedAt is! String) {
      return null;
    }
    final parsedQueuedAt = DateTime.tryParse(queuedAt);
    if (parsedQueuedAt == null) return null;
    return PendingRemoteSessionTermination(
      hostId: hostId,
      remoteSessionId: remoteSessionId,
      queuedAt: parsedQueuedAt,
    );
  }
}

/// 오프라인에서 닫은 원격 작업을 잊지 않고 다음 연결 때 종료하기 위한 저장소.
class RemoteSessionCleanupStore {
  RemoteSessionCleanupStore({CleanupApplicationSupportDirectory? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final CleanupApplicationSupportDirectory _directory;
  Future<void> _pendingWrite = Future<void>.value();

  Future<List<PendingRemoteSessionTermination>> all() async {
    try {
      await _pendingWrite;
      final file = await _file();
      if (!file.existsSync()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) return const [];
      return (decoded['entries'] as List)
          .map(PendingRemoteSessionTermination.fromJson)
          .whereType<PendingRemoteSessionTermination>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<PendingRemoteSessionTermination>> forHost(String hostId) async =>
      [
        for (final entry in await all())
          if (entry.hostId == hostId) entry,
      ];

  Future<void> enqueue(PendingRemoteSessionTermination entry) =>
      _mutate((entries) {
        entries.removeWhere((item) => item.key == entry.key);
        entries.add(entry);
      });

  Future<void> remove({
    required String hostId,
    required String remoteSessionId,
  }) => _mutate(
    (entries) => entries.removeWhere(
      (entry) =>
          entry.hostId == hostId && entry.remoteSessionId == remoteSessionId,
    ),
  );

  Future<void> _mutate(
    void Function(List<PendingRemoteSessionTermination> entries) change,
  ) {
    _pendingWrite = _pendingWrite.then(
      (_) async {
        final entries = await _readWithoutWaiting();
        change(entries);
        await _write(entries);
      },
      onError: (_) async {
        final entries = await _readWithoutWaiting();
        change(entries);
        await _write(entries);
      },
    );
    return _pendingWrite;
  }

  Future<List<PendingRemoteSessionTermination>> _readWithoutWaiting() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['entries'] is! List) return [];
      return (decoded['entries'] as List)
          .map(PendingRemoteSessionTermination.fromJson)
          .whereType<PendingRemoteSessionTermination>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<PendingRemoteSessionTermination> entries) async {
    final file = await _file();
    if (entries.isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    await writeFileAtomically(
      file,
      const JsonEncoder.withIndent(' ').convert({
        'version': 1,
        'entries': [for (final entry in entries) entry.toJson()],
      }),
    );
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File(
      '${directory.path}${Platform.pathSeparator}remote_session_cleanup.json',
    );
  }
}
