import 'dart:math';

import 'remote_session_device.dart';

/// 접속별 UUID로 저장 키를 구분하고 실제 client의 PID·생성 시각을 대조한다.
class TmuxRemoteClientMetadata {
  const TmuxRemoteClientMetadata._();

  static String newConnectionId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String registrationCommand({
    required String serverName,
    required String connectionId,
    required RemoteSessionDevice device,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(connectionId)) {
      throw ArgumentError.value(connectionId, 'connectionId');
    }
    return "tmux -L $serverName set-option -g "
        "@vibe_terminal_connection_$connectionId "
        "'#{client_pid} #{client_created} ${device.encode()}' >/dev/null 2>&1 || :";
  }

  /// 기록을 먼저 읽고 실제 연결을 읽는다. 키를 재사용하지 않으므로 이후
  /// 접속의 기록은 이 정리 대상에 들어올 수 없다.
  static String cleanupCommand(String serverName) =>
      '''
vibe_records=\$(
${_recordsCommand(serverName)}
)
vibe_live=\$(tmux -L $serverName list-clients -F '#{client_pid}_#{client_created}' 2>/dev/null) || exit 0
vibe_live=" \$(printf '%s\\n' "\$vibe_live" | tr '\\n' ' ') "
printf '%s\\n' "\$vibe_records" | while read -r vibe_key vibe_pid vibe_created vibe_device; do
  [ -n "\$vibe_key" ] || continue
  case "\$vibe_live" in *" \${vibe_pid}_\$vibe_created "*) ;; *) tmux -L $serverName set-option -gu "\$vibe_key" >/dev/null 2>&1 ;; esac
done
''';

  static String listCommand(String serverName) =>
      '''
${_recordsCommand(serverName).trimRight()} | while read -r vibe_key vibe_pid vibe_created vibe_device; do
  printf 'VIBE_DEVICE\\t%s\\t%s\\t%s\\t%s\\n' "\$vibe_key" "\$vibe_pid" "\$vibe_created" "\$vibe_device"
done
tmux -L $serverName list-clients -F 'VIBE_CLIENT_V2\t#{@vibe_terminal_session_id}\t#{client_pid}\t#{client_created}' 2>/dev/null
''';

  static String _recordsCommand(String serverName) =>
      '''
tmux -L $serverName show-options -g 2>/dev/null | while read -r vibe_key vibe_value; do
  case "\$vibe_key" in @vibe_terminal_connection_*) ;; *) continue ;; esac
  vibe_token=\${vibe_key#@vibe_terminal_connection_}
  [ "\${#vibe_token}" -eq 32 ] || continue
  case "\$vibe_token" in *[!0-9a-f]*) continue ;; esac
  vibe_record=\$(tmux -L $serverName show-options -gv "\$vibe_key" 2>/dev/null) || continue
  printf '%s %s\\n' "\$vibe_key" "\$vibe_record"
done
''';
}
