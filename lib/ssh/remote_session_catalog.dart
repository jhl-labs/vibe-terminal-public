import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/result.dart';
import 'remote_session_identity.dart';
import 'remote_session_device.dart';
import 'remote_client_metadata.dart';
import 'remote_terminal_launcher.dart';

class RemotePersistentSession {
  const RemotePersistentSession({
    required this.name,
    required this.remoteSessionId,
    required this.ownerId,
    required this.createdAt,
    required this.lastActivityAt,
    required this.attachedClients,
    this.recreated = false,
    this.title,
    this.workingDirectory,
    this.creatorDevice,
    this.clients = const [],
  });

  final String name;
  final String remoteSessionId;
  final String ownerId;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;
  final int attachedClients;
  final String? title;
  final String? workingDirectory;
  final RemoteSessionDevice? creatorDevice;
  final List<RemoteSessionClient> clients;

  String get displayName => title ?? workingDirectory ?? '이름 없는 작업';

  /// 복원·재접속이 "있어야 할 작업"을 찾지 못해 같은 이름으로 새로 만든 세션.
  /// 원래 작업이 종료된 뒤 새로 만들어진 세션을 구분한다.
  final bool recreated;

  bool get isAttached => attachedClients > 0;
}

enum RemoteSessionTerminationOutcome {
  terminated,
  alreadyAbsent,
  notManaged,
  identityMismatch,

  /// 다른 기기가 아직 이 작업을 보고 있어 끝내지 않았다.
  attachedElsewhere,
  failed,
}

/// 종료 명령의 종료 코드를 결과로 바꾼다.
RemoteSessionTerminationOutcome remoteSessionTerminationOutcomeOf(
  int? exitCode,
) => switch (exitCode ?? -1) {
  0 => RemoteSessionTerminationOutcome.terminated,
  TmuxRemoteTerminalLauncher.sessionNotFoundExitCode =>
    RemoteSessionTerminationOutcome.alreadyAbsent,
  TmuxRemoteTerminalLauncher.notManagedExitCode =>
    RemoteSessionTerminationOutcome.notManaged,
  TmuxRemoteTerminalLauncher.identityMismatchExitCode =>
    RemoteSessionTerminationOutcome.identityMismatch,
  TmuxRemoteTerminalLauncher.attachedElsewhereExitCode =>
    RemoteSessionTerminationOutcome.attachedElsewhere,
  _ => RemoteSessionTerminationOutcome.failed,
};

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
  static const _sessionListCommand =
      "tmux -L ${TmuxRemoteTerminalLauncher.serverName} list-sessions "
      "-F '#{session_name}\t#{session_created}\t#{session_activity}\t"
      "#{session_attached}\t#{@vibe_terminal_managed}\t"
      "#{@vibe_terminal_owner}\t#{@vibe_terminal_session_id}\t"
      "#{@vibe_terminal_protocol}\t#{@vibe_terminal_recreated}\t"
      "#{@vibe_terminal_title}\t#{pane_current_path}\t"
      "#{@vibe_terminal_creator}' 2>/dev/null";

  // 서버가 아는 실제 연결 목록에만 기기 정보를 붙인다. 끊긴 PC의 기록이
  // 남아 있더라도 사용 중인 PC로 표시하지 않는다. 이름이 공백을 포함할 수
  // 있으므로 세션 이름 대신 공백 없는 앱의 원격 작업 ID를 출력한다.
  @visibleForTesting
  static final clientsCommand = TmuxRemoteClientMetadata.listCommand(
    TmuxRemoteTerminalLauncher.serverName,
  );

  @visibleForTesting
  static final listCommand = '$_sessionListCommand\n$clientsCommand';

  @override
  Future<Result<List<RemotePersistentSession>>> list(SSHClient client) async {
    try {
      final result = await client
          .runWithResult(listCommand)
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
    final lines = const LineSplitter().convert(stdout);
    final devices = <(String, String), RemoteSessionDevice?>{};
    for (final line in lines) {
      final fields = line.split(_fieldSeparator);
      if (fields.length != 5 || fields[0] != 'VIBE_DEVICE') continue;
      if (!RegExp(
        r'^@vibe_terminal_connection_[a-f0-9]{32}$',
      ).hasMatch(fields[1])) {
        continue;
      }
      final key = (fields[2], fields[3]);
      // 같은 PID·시각에 서로 다른 기록이 남았으면 추측하지 않는다.
      devices[key] = devices.containsKey(key)
          ? null
          : RemoteSessionDevice.decode(fields[4]);
    }
    final clients = <String, List<RemoteSessionClient>>{};
    for (final line in lines) {
      final fields = line.split(_fieldSeparator);
      if (fields.length != 4 || fields[0] != 'VIBE_CLIENT_V2') continue;
      (clients[fields[1]] ??= []).add(
        RemoteSessionClient(
          device: devices[(fields[2], fields[3])],
          connectedAt: _dateTimeFromEpoch(fields[3]),
        ),
      );
    }
    for (final line in lines) {
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
          attachedClients: _clientCount(fields[3]),
          // 옛 버전이 만든 세션은 열(field)이 없다. 없으면 재생성 아님.
          recreated: fields.length > 8 && fields[8] == '1',
          title: fields.length > 9 && fields[9].trim().isNotEmpty
              ? fields[9].trim()
              : null,
          workingDirectory: fields.length > 10 && fields[10].trim().isNotEmpty
              ? fields[10].trim()
              : null,
          creatorDevice: fields.length > 11
              ? RemoteSessionDevice.decode(fields[11])
              : null,
          clients: List.unmodifiable(
            (clients[remoteSessionId] ?? const <RemoteSessionClient>[]).take(
              _clientCount(fields[3]),
            ),
          ),
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
      return remoteSessionTerminationOutcomeOf(result.exitCode);
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

  static int _clientCount(String value) {
    final count = int.tryParse(value) ?? 0;
    return count > 0 ? count : 0;
  }
}
