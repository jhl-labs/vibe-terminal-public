import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/result.dart';
import 'remote_session_identity.dart';
import 'remote_terminal_launcher.dart';

class RemotePersistentSession {
  const RemotePersistentSession({
    required this.name,
    required this.remoteSessionId,
    required this.ownerId,
    required this.createdAt,
    required this.lastActivityAt,
    required this.attachedClients,
  });

  final String name;
  final String remoteSessionId;
  final String ownerId;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;
  final int attachedClients;

  bool get isAttached => attachedClients > 0;
}

enum RemoteSessionTerminationOutcome {
  terminated,
  alreadyAbsent,
  notManaged,
  identityMismatch,
  failed,
}

abstract interface class RemoteSessionCatalog {
  Future<Result<List<RemotePersistentSession>>> list(SSHClient client);

  Future<RemoteSessionTerminationOutcome> terminate(
    SSHClient client, {
    required String persistentSessionName,
  });
}

/// 앱 전용 tmux 서버에서 Vibe Terminal 소유권 표식이 있는 세션만 다룬다.
class TmuxRemoteSessionCatalog implements RemoteSessionCatalog {
  const TmuxRemoteSessionCatalog();

  static const _fieldSeparator = '\t';
  static const _listCommand =
      "tmux -L ${TmuxRemoteTerminalLauncher.serverName} list-sessions "
      "-F '#{session_name}\t#{session_created}\t#{session_activity}\t"
      "#{session_attached}\t#{@vibe_terminal_managed}\t"
      "#{@vibe_terminal_owner}\t#{@vibe_terminal_session_id}\t"
      "#{@vibe_terminal_protocol}' 2>/dev/null";

  @override
  Future<Result<List<RemotePersistentSession>>> list(SSHClient client) async {
    try {
      final result = await client
          .runWithResult(_listCommand)
          .timeout(const Duration(seconds: 5));
      final stdout = utf8.decode(result.stdout, allowMalformed: true);
      if ((result.exitCode ?? 0) != 0 && stdout.trim().isEmpty) {
        // 아직 앱 전용 tmux 서버가 없거나 세션이 하나도 없는 상태다.
        return const Ok([]);
      }

      return Ok(parseListOutput(stdout));
    } catch (error) {
      return Err(RemoteSessionFailure('서버 작업 목록을 읽지 못했습니다: $error'));
    }
  }

  @visibleForTesting
  static List<RemotePersistentSession> parseListOutput(String stdout) {
    final sessions = <RemotePersistentSession>[];
    for (final line in const LineSplitter().convert(stdout)) {
      final fields = line.split(_fieldSeparator);
      if (fields.length < 8 || fields[4] != '1' || fields[7] != '1') continue;
      final name = fields[0];
      final remoteSessionId = fields[6];
      String expectedName;
      try {
        expectedName = TmuxRemoteTerminalLauncher.sessionNameFor(
          remoteSessionId,
        );
      } on ArgumentError {
        continue;
      }
      if (name != expectedName) continue;
      final expectedOwnerId =
          RemoteSessionIdentity.ownerIdOf(remoteSessionId) ?? 'legacy';
      if (fields[5] != expectedOwnerId) continue;

      sessions.add(
        RemotePersistentSession(
          name: name,
          remoteSessionId: remoteSessionId,
          ownerId: fields[5],
          createdAt: _dateTimeFromEpoch(fields[1]),
          lastActivityAt: _dateTimeFromEpoch(fields[2]),
          attachedClients: int.tryParse(fields[3]) ?? 0,
        ),
      );
    }
    sessions.sort((a, b) {
      final aTime = a.lastActivityAt ?? a.createdAt;
      final bTime = b.lastActivityAt ?? b.createdAt;
      if (aTime == null && bTime == null) return a.name.compareTo(b.name);
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return sessions;
  }

  @override
  Future<RemoteSessionTerminationOutcome> terminate(
    SSHClient client, {
    required String persistentSessionName,
  }) async {
    try {
      final result = await client
          .runWithResult(
            TmuxRemoteTerminalLauncher.killCommandFor(persistentSessionName),
          )
          .timeout(const Duration(seconds: 5));
      return switch (result.exitCode ?? -1) {
        0 => RemoteSessionTerminationOutcome.terminated,
        TmuxRemoteTerminalLauncher.sessionNotFoundExitCode =>
          RemoteSessionTerminationOutcome.alreadyAbsent,
        TmuxRemoteTerminalLauncher.notManagedExitCode =>
          RemoteSessionTerminationOutcome.notManaged,
        TmuxRemoteTerminalLauncher.identityMismatchExitCode =>
          RemoteSessionTerminationOutcome.identityMismatch,
        _ => RemoteSessionTerminationOutcome.failed,
      };
    } catch (_) {
      return RemoteSessionTerminationOutcome.failed;
    }
  }

  static DateTime? _dateTimeFromEpoch(String value) {
    final seconds = int.tryParse(value);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toLocal();
  }
}
