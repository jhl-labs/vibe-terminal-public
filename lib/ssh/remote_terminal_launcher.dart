import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/result.dart';
import 'remote_session_identity.dart';

class RemoteTerminalLaunch {
  const RemoteTerminalLaunch({
    required this.session,
    this.persistentSessionName,
    this.resumedPersistentSession = false,
  });

  final SSHSession session;
  final String? persistentSessionName;
  final bool resumedPersistentSession;

  bool get isPersistent => persistentSessionName != null;
}

/// SSH 인증이 끝난 뒤 어떤 원격 터미널 프로세스를 열지 결정하는 전략.
abstract interface class RemoteTerminalLauncher {
  Future<Result<RemoteTerminalLaunch>> launch({
    required SSHClient client,
    required SSHPtyConfig pty,
    SSHX11Config? x11,
    String? remoteSessionId,
  });
}

/// 작업 유지 터미널을 열지 못했을 때 일반 SSH로 전환해도 안전한지 판단한다.
class RemoteTerminalFallbackPolicy {
  const RemoteTerminalFallbackPolicy();

  bool shouldUseDirectSsh(Failure failure) =>
      failure is RemoteSessionToolMissingFailure &&
      failure.tool == TmuxRemoteTerminalLauncher.toolName;
}

class DirectRemoteTerminalLauncher implements RemoteTerminalLauncher {
  const DirectRemoteTerminalLauncher();

  @override
  Future<Result<RemoteTerminalLaunch>> launch({
    required SSHClient client,
    required SSHPtyConfig pty,
    SSHX11Config? x11,
    String? remoteSessionId,
  }) async {
    final session = await client.shell(pty: pty, x11: x11);
    return Ok(RemoteTerminalLaunch(session: session));
  }
}

/// 앱 전용 tmux 서버에 세션을 만들거나 기존 세션을 다시 붙이는 전략.
///
/// 사용자의 기본 tmux 서버/설정과 섞이지 않도록 별도 socket label을 쓰고,
/// 상태줄과 prefix 키를 꺼서 일반 SSH 셸과 같은 화면/키 입력 경험을 유지한다.
class TmuxRemoteTerminalLauncher implements RemoteTerminalLauncher {
  const TmuxRemoteTerminalLauncher();

  static const toolName = 'tmux';
  static const serverName = 'vibe-terminal';
  static const sessionNotFoundExitCode = 44;
  static const notManagedExitCode = 45;
  static const identityMismatchExitCode = 46;
  static const _probeTimeout = Duration(seconds: 5);
  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{8,80}$');

  static String sessionNameFor(String remoteSessionId) {
    if (!_safeId.hasMatch(remoteSessionId)) {
      throw ArgumentError.value(
        remoteSessionId,
        'remoteSessionId',
        '안전한 원격 세션 식별자가 아닙니다.',
      );
    }
    return 'vibe_$remoteSessionId';
  }

  static String killCommandFor(String persistentSessionName) {
    if (!persistentSessionName.startsWith('vibe_') ||
        !_safeId.hasMatch(persistentSessionName.substring(5))) {
      throw ArgumentError.value(
        persistentSessionName,
        'persistentSessionName',
        '안전한 tmux 세션 이름이 아닙니다.',
      );
    }
    final remoteSessionId = persistentSessionName.substring(5);
    final expectedOwnerId =
        RemoteSessionIdentity.ownerIdOf(remoteSessionId) ?? 'legacy';
    final quotedName = _quote(persistentSessionName);
    final quotedId = _quote(remoteSessionId);
    final quotedOwnerId = _quote(expectedOwnerId);
    return '''
${_findSessionTarget(quotedName)}
[ -n "\$vibe_target" ] || exit $sessionNotFoundExitCode
vibe_managed=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_managed 2>/dev/null)
[ "\$vibe_managed" = "1" ] || exit $notManagedExitCode
vibe_session_id=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_session_id 2>/dev/null)
[ "\$vibe_session_id" = $quotedId ] || exit $identityMismatchExitCode
vibe_owner=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_owner 2>/dev/null)
[ "\$vibe_owner" = $quotedOwnerId ] || exit $identityMismatchExitCode
vibe_protocol=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_protocol 2>/dev/null)
[ "\$vibe_protocol" = "1" ] || exit $identityMismatchExitCode
tmux -L $serverName kill-session -t "\$vibe_target"
''';
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  @override
  Future<Result<RemoteTerminalLaunch>> launch({
    required SSHClient client,
    required SSHPtyConfig pty,
    SSHX11Config? x11,
    String? remoteSessionId,
  }) async {
    if (remoteSessionId == null) {
      return const Err(RemoteSessionFailure('작업을 이어갈 원격 세션 식별자가 없습니다.'));
    }

    final String sessionName;
    try {
      sessionName = sessionNameFor(remoteSessionId);
    } on ArgumentError {
      return const Err(RemoteSessionFailure('저장된 원격 작업 식별자가 올바르지 않습니다.'));
    }

    try {
      final available = await client
          .runWithResult('command -v tmux')
          .timeout(_probeTimeout);
      final executable = utf8
          .decode(available.stdout, allowMalformed: true)
          .trim();
      if ((available.exitCode ?? 0) != 0 || executable.isEmpty) {
        return const Err(
          RemoteSessionToolMissingFailure(
            tool: toolName,
            message:
                '이 서버에 tmux가 없습니다. tmux를 설치하거나 호스트 설정에서 '
                '작업 이어가기를 꺼 주세요.',
          ),
        );
      }

      final quotedName = _quote(sessionName);
      final setup = await client
          .runWithResult(_setupCommand(quotedName, remoteSessionId))
          .timeout(_probeTimeout);
      final marker = utf8.decode(setup.stdout, allowMalformed: true).trim();
      final markerMatch = RegExp(
        r'VIBE_TMUX_(CREATED|RESUMED):(\$[0-9]+)',
      ).firstMatch(marker);
      if ((setup.exitCode ?? 0) != 0 || markerMatch == null) {
        final detail = utf8.decode(setup.stderr, allowMalformed: true).trim();
        return Err(
          RemoteSessionFailure(
            detail.isEmpty
                ? '서버에서 작업 유지 세션을 준비하지 못했습니다.'
                : '서버에서 작업 유지 세션을 준비하지 못했습니다: $detail',
          ),
        );
      }

      final sessionTarget = _quote(markerMatch.group(2)!);
      final session = await client.execute(
        'exec tmux -L $serverName attach-session -t $sessionTarget 2>&1',
        pty: pty,
        x11: x11,
      );
      return Ok(
        RemoteTerminalLaunch(
          session: session,
          persistentSessionName: sessionName,
          resumedPersistentSession: markerMatch.group(1) == 'RESUMED',
        ),
      );
    } catch (error) {
      return Err(RemoteSessionFailure('서버에서 작업 유지 세션을 준비하지 못했습니다: $error'));
    }
  }

  @visibleForTesting
  static String setupCommandForTest(String remoteSessionId) {
    final sessionName = sessionNameFor(remoteSessionId);
    return _setupCommand(_quote(sessionName), remoteSessionId);
  }

  static String _setupCommand(String quotedName, String remoteSessionId) {
    final ownerId =
        RemoteSessionIdentity.ownerIdOf(remoteSessionId) ?? 'legacy';
    final quotedOwnerId = _quote(ownerId);
    final quotedRemoteSessionId = _quote(remoteSessionId);
    return '''
${_findSessionTarget(quotedName)}
if [ -n "\$vibe_target" ]; then
  vibe_managed=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_managed 2>/dev/null)
  [ "\$vibe_managed" = "1" ] || exit $notManagedExitCode
  vibe_session_id=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_session_id 2>/dev/null)
  [ "\$vibe_session_id" = $quotedRemoteSessionId ] || exit $identityMismatchExitCode
  vibe_owner=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_owner 2>/dev/null)
  [ "\$vibe_owner" = $quotedOwnerId ] || exit $identityMismatchExitCode
  vibe_protocol=\$(tmux -L $serverName show-options -v -t "\$vibe_target" @vibe_terminal_protocol 2>/dev/null)
  [ "\$vibe_protocol" = "1" ] || exit $identityMismatchExitCode
  vibe_tmux_state=RESUMED
else
  vibe_tmux_state=CREATED
  vibe_target=\$(tmux -L $serverName -f /dev/null new-session -d -P -F '#{session_id}' -s $quotedName) || exit 1
  [ -n "\$vibe_target" ] || exit 1
fi
tmux -L $serverName set-option -t "\$vibe_target" status off >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" prefix None >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" prefix2 None >/dev/null 2>&1 || :
# tmux client가 사용하는 alternate screen에는 바깥 터미널의 스크롤백이
# 없다. mouse를 켜고 WheelUpPane을 직접 바인딩해, Codex처럼 마우스를
# 요청하는 내부 앱에서도 휠을 tmux history 탐색에 일관되게 사용한다.
tmux -L $serverName set-option -t "\$vibe_target" mouse on >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" history-limit 10000 >/dev/null 2>&1 || :
tmux -L $serverName bind-key -T root WheelUpPane 'copy-mode -e; send-keys -X -N 5 scroll-up' >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_managed 1 >/dev/null 2>&1 || exit 1
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_owner $quotedOwnerId >/dev/null 2>&1 || exit 1
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_session_id $quotedRemoteSessionId >/dev/null 2>&1 || exit 1
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_protocol 1 >/dev/null 2>&1 || exit 1
printf 'VIBE_TMUX_%s:%s\n' "\$vibe_tmux_state" "\$vibe_target"
''';
  }

  /// 이름을 tmux 자체 target parser에 넘기지 않고 정확히 일치하는 세션 ID를
  /// 찾는다. 세션 ID(`$0` 등)를 이후 명령에 사용해 접두어 매칭과 TOCTOU 오작동을
  /// 피하고, `=name` exact-target 문법이 없는 구버전 tmux도 지원한다.
  static String _findSessionTarget(String quotedName) =>
      '''
vibe_target=\$(tmux -L $serverName list-sessions -F '#{session_id} #{session_name}' 2>/dev/null | while read -r vibe_id vibe_name; do
  if [ "\$vibe_name" = $quotedName ]; then
    printf '%s' "\$vibe_id"
    break
  fi
done)
''';
}
