import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/result.dart';
import 'remote_session_identity.dart';
import 'remote_session_device.dart';
import 'remote_client_metadata.dart';

class RemoteTerminalLaunch {
  const RemoteTerminalLaunch({
    required this.session,
    this.persistentSessionName,
    this.resumedPersistentSession = false,
    this.recreatedPersistentSession = false,
  });

  final SSHSession session;
  final String? persistentSessionName;
  final bool resumedPersistentSession;

  /// 있어야 할 작업(재접속·복원)이 서버에 없어 같은 이름으로 새로 만들었다.
  final bool recreatedPersistentSession;

  bool get isPersistent => persistentSessionName != null;
}

/// SSH 인증이 끝난 뒤 어떤 원격 터미널 프로세스를 열지 결정하는 전략.
abstract interface class RemoteTerminalLauncher {
  /// [expectExisting]은 [remoteSessionId]의 작업이 서버에 이미 있어야 한다는
  /// 뜻이다(재접속·복원). 없으면 만들되 재생성으로 표시한다.
  Future<Result<RemoteTerminalLaunch>> launch({
    required SSHClient client,
    required SSHPtyConfig pty,
    SSHX11Config? x11,
    String? remoteSessionId,
    bool expectExisting = false,
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
    bool expectExisting = false,
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
  const TmuxRemoteTerminalLauncher({this.device});

  final RemoteSessionDevice? device;

  static const toolName = 'tmux';
  static const serverName = 'vibe-terminal';
  static const sessionNotFoundExitCode = 44;
  static const notManagedExitCode = 45;
  static const identityMismatchExitCode = 46;

  /// 다른 기기(다른 tmux client)가 아직 이 작업에 붙어 있어 끝내지 않았다.
  static const attachedElsewhereExitCode = 47;
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

  /// 앱이 관리하는 tmux 작업을 끝내는 명령.
  ///
  /// 다른 기기가 같은 작업을 보고 있으면(붙은 client가 있으면) 끝내지 않고
  /// [attachedElsewhereExitCode]로 끝난다. 한 기기의 "작업 종료"가 다른 기기의
  /// 화면까지 닫지 않게 하기 위해서다. 이 기기가 방금 자기 client를 떼었다면
  /// tmux가 그 client를 정리할 때까지 [detachGrace]만큼 기다린 뒤 센다.
  static String killCommandFor(
    String persistentSessionName, {
    Duration detachGrace = Duration.zero,
  }) {
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
    // if-shell -F는 셸 작업 없이 같은 tmux 명령 큐에서 검사와 종료를 실행한다.
    // 앞선 대기 루프가 끝난 직후 새 client가 붙어도 마지막 검사에서 보호한다.
    final target = '=$persistentSessionName';
    String guard(String condition, String command, int failure) =>
        'if-shell -F -t ${_quote(target)} ${_quote(condition)} '
        '${_quote(command)} ${_quote("run-shell 'exit $failure'")}';
    var finish = guard(
      '#{==:#{session_attached},0}',
      'kill-session -t ${_quote(target)}',
      attachedElsewhereExitCode,
    );
    for (final check in [
      ('@vibe_terminal_protocol', '1', identityMismatchExitCode),
      ('@vibe_terminal_owner', expectedOwnerId, identityMismatchExitCode),
      ('@vibe_terminal_session_id', remoteSessionId, identityMismatchExitCode),
      ('@vibe_terminal_managed', '1', notManagedExitCode),
    ]) {
      finish = guard('#{==:#{${check.$1}},${check.$2}}', finish, check.$3);
    }
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
vibe_wait=${detachGrace.inMilliseconds ~/ 100}
while :; do
  vibe_attached=\$(tmux -L $serverName display-message -p -t "\$vibe_target" '#{session_attached}' 2>/dev/null)
  [ "\$vibe_attached" -gt 0 ] 2>/dev/null || break
  [ "\$vibe_wait" -gt 0 ] || exit $attachedElsewhereExitCode
  vibe_wait=\$((vibe_wait - 1))
  sleep 0.1 2>/dev/null || sleep 1
done
tmux -L $serverName $finish
''';
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  @override
  Future<Result<RemoteTerminalLaunch>> launch({
    required SSHClient client,
    required SSHPtyConfig pty,
    SSHX11Config? x11,
    String? remoteSessionId,
    bool expectExisting = false,
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
      final device = this.device ?? RemoteSessionDevice.current();
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
          .runWithResult(
            _setupCommand(
              quotedName,
              remoteSessionId,
              expectExisting: expectExisting,
              device: device,
            ),
          )
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

      final sessionTarget = markerMatch.group(2)!;
      final session = await client.execute(
        attachCommandFor(sessionTarget, device: device),
        pty: pty,
        x11: x11,
      );
      final resumed = markerMatch.group(1) == 'RESUMED';
      return Ok(
        RemoteTerminalLaunch(
          session: session,
          persistentSessionName: sessionName,
          resumedPersistentSession: resumed,
          recreatedPersistentSession: !resumed && expectExisting,
        ),
      );
    } catch (error) {
      return Err(RemoteSessionFailure('서버에서 작업 유지 세션을 준비하지 못했습니다: $error'));
    }
  }

  @visibleForTesting
  static String setupCommandForTest(
    String remoteSessionId, {
    bool expectExisting = false,
    RemoteSessionDevice? device,
  }) {
    final sessionName = sessionNameFor(remoteSessionId);
    return _setupCommand(
      _quote(sessionName),
      remoteSessionId,
      expectExisting: expectExisting,
      device: device,
    );
  }

  static String _setupCommand(
    String quotedName,
    String remoteSessionId, {
    required bool expectExisting,
    RemoteSessionDevice? device,
  }) {
    final ownerId =
        RemoteSessionIdentity.ownerIdOf(remoteSessionId) ?? 'legacy';
    final quotedOwnerId = _quote(ownerId);
    final quotedRemoteSessionId = _quote(remoteSessionId);
    final creatorMark = device == null
        ? ':'
        : 'tmux -L $serverName set-option -t "\$vibe_target" '
              '@vibe_terminal_creator ${_quote(device.encode())} >/dev/null 2>&1 || :';
    // 있어야 할 작업이 없어 복원·재접속 중 새로 만들면 표시한다.
    final recreatedMark = expectExisting
        ? 'tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_recreated 1 >/dev/null 2>&1 || :'
        : ':';
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
  $recreatedMark
  $creatorMark
fi
# 설정 없이(-f /dev/null) 띄운 tmux는 default-terminal이 'screen'이라 내부
# 프로그램이 8색 터미널로 인식해 ANSI 256색·truecolor가 사라진다. 바깥은
# xterm-256color PTY이므로 256색 terminfo(가능하면 tmux-256color, 없으면
# screen-256color)와 RGB 통과(Tc/RGB)를 켠다. COLORTERM은 SSH env로 전달되지
# 않으므로(AcceptEnv) tmux 전역 환경에 넣어 내부 셸이 truecolor를 알게 한다.
vibe_term=screen-256color
if infocmp tmux-256color >/dev/null 2>&1; then vibe_term=tmux-256color; fi
tmux -L $serverName set-option -g default-terminal "\$vibe_term" >/dev/null 2>&1 || :
tmux -L $serverName set-option -ga terminal-overrides ',xterm-256color:Tc' >/dev/null 2>&1 || :
tmux -L $serverName set-option -as terminal-features ',xterm-256color:RGB' >/dev/null 2>&1 || :
tmux -L $serverName set-environment -g COLORTERM truecolor >/dev/null 2>&1 || :
if [ "\$vibe_tmux_state" = CREATED ]; then
  # 방금 만든 첫 셸은 옛 TERM=screen으로 이미 시작됐다. 사용자 작업이 없는
  # 시점이므로 새 TERM/COLORTERM으로 다시 띄운다. 재개(RESUMED)한 세션은
  # 실행 중인 작업을 죽이지 않도록 건드리지 않는다.
  tmux -L $serverName respawn-window -k -t "\$vibe_target" >/dev/null 2>&1 || :
fi
tmux -L $serverName set-option -t "\$vibe_target" status off >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" prefix None >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" prefix2 None >/dev/null 2>&1 || :
# tmux client가 사용하는 alternate screen에는 바깥 터미널의 스크롤백이
# 없다. mouse를 켜고 WheelUpPane을 직접 바인딩해, Codex처럼 main buffer에서
# 마우스를 요청하는 인라인 TUI에서도 휠을 tmux history 탐색에 일관되게
# 사용한다. 단 Claude Code처럼 alternate screen에서 마우스를 요청하는 앱은
# 자체 화면을 스크롤해야 하므로 휠을 앱으로 넘긴다(send-keys -M). 무조건
# copy-mode로 들어가면 alt screen에는 history가 없어 휠이 먹통으로 보인다.
tmux -L $serverName set-option -t "\$vibe_target" mouse on >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" history-limit 10000 >/dev/null 2>&1 || :
tmux -L $serverName bind-key -T root WheelUpPane "if -Ft= '#{&&:#{alternate_on},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -e; send-keys -X -N 5 scroll-up'" >/dev/null 2>&1 || :
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_managed 1 >/dev/null 2>&1 || exit 1
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_owner $quotedOwnerId >/dev/null 2>&1 || exit 1
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_session_id $quotedRemoteSessionId >/dev/null 2>&1 || exit 1
tmux -L $serverName set-option -t "\$vibe_target" @vibe_terminal_protocol 1 >/dev/null 2>&1 || exit 1
printf 'VIBE_TMUX_%s:%s\n' "\$vibe_tmux_state" "\$vibe_target"
''';
  }

  /// attach가 성공한 뒤 해당 client의 PID·생성 시각과 기기 정보를 등록한다.
  /// 등록 실패는 터미널 접속을 막지 않는다.
  @visibleForTesting
  static String attachCommandFor(
    String target, {
    required RemoteSessionDevice device,
    String? connectionId,
  }) {
    if (!RegExp(r'^\$[0-9]+$').hasMatch(target)) {
      throw ArgumentError.value(target, 'target', '안전한 tmux 대상이 아닙니다.');
    }
    final cleanup = TmuxRemoteClientMetadata.cleanupCommand(
      serverName,
    ).replaceAll('#', '##');
    final cleanupHook = _quote('run-shell ${_quote(cleanup)}');
    final registration = _quote(
      TmuxRemoteClientMetadata.registrationCommand(
        serverName: serverName,
        connectionId:
            connectionId ?? TmuxRemoteClientMetadata.newConnectionId(),
        device: device,
      ),
    );
    return '''
tmux -L $serverName set-hook -g 'client-detached[9720]' $cleanupHook >/dev/null 2>&1 || :
exec tmux -L $serverName attach-session -t ${_quote(target)} \\; run-shell $registration 2>&1
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
