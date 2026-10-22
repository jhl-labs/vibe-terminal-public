import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const daemonProtocolVersion = 1;

/// 앱↔daemon loopback 소켓에서 Nagle 지연을 끈다. 키 입력·에코처럼 작은
/// 프레임이 직전 프레임의 ACK를 기다리며 묶이지 않게 한다(SSH 소켓과 같은 정책).
/// 일부 플랫폼·소켓 종류가 옵션을 거부해도 연결은 그대로 쓴다.
void enableDaemonSocketNoDelay(Socket socket) {
  try {
    socket.setOption(SocketOption.tcpNoDelay, true);
  } on SocketException {
    // 옵션 미지원: 지연만 남고 동작은 같다.
  } on OSError {
    // 위와 같다.
  }
}

String daemonToken() =>
    base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256)));

Stream<Map<String, dynamic>> daemonMessages(Stream<List<int>> input) async* {
  var pending = <int>[];
  await for (final bytes in input) {
    for (final byte in bytes) {
      if (byte == 10) {
        if (pending.isEmpty) continue;
        final value = jsonDecode(utf8.decode(pending));
        pending = [];
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid frame');
        }
        yield value;
      } else {
        pending.add(byte);
        if (pending.length > 1024 * 1024) {
          throw const FormatException('Frame exceeds limit');
        }
      }
    }
  }
  if (pending.isNotEmpty) throw const FormatException('Incomplete frame');
}

String daemonFrame(Map<String, Object?> value) => '${jsonEncode(value)}\n';
Future<void> secureDaemonDirectory(Directory directory) async {
  await directory.create(recursive: true);
  if (Platform.isWindows) {
    final identity = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '[Security.Principal.WindowsIdentity]::GetCurrent().User.Value',
    ]);
    final sid = '${identity.stdout}'.trim();
    if (identity.exitCode != 0 || !RegExp(r'^S-1-[0-9-]+$').hasMatch(sid)) {
      throw StateError('Cannot resolve owner SID');
    }
    final encodedPath = base64Encode(utf8.encode(directory.absolute.path));
    // SetOwner + Set-Acl 조합은 비관리자 세션에서 SeRestorePrivilege 를
    // 요구해 "unauthorized operation" 으로 실패한다. 디렉터리는 현재 사용자가
    // 만들었으므로 소유자 변경 없이 DACL 만 상속 차단 + 본인 FullControl 로
    // 교체한다 (chmod 700 과 동등).
    final acl = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '\$ErrorActionPreference="Stop"; '
          '\$vibePath=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$encodedPath")); '
          '\$vibeSid=New-Object Security.Principal.SecurityIdentifier("$sid"); '
          '\$vibeDir=Get-Item -LiteralPath \$vibePath -Force; '
          '\$vibeAcl=\$vibeDir.GetAccessControl([Security.AccessControl.AccessControlSections]::Access); '
          '\$vibeAcl.SetAccessRuleProtection(\$true,\$false); '
          'foreach (\$vibeOld in @(\$vibeAcl.Access)) { [void]\$vibeAcl.RemoveAccessRuleAll(\$vibeOld) }; '
          '\$vibeRule=New-Object Security.AccessControl.FileSystemAccessRule(\$vibeSid,"FullControl","ContainerInherit,ObjectInherit","None","Allow"); '
          '\$vibeAcl.AddAccessRule(\$vibeRule); \$vibeDir.SetAccessControl(\$vibeAcl)',
    ]);
    if (acl.exitCode != 0) {
      final detail = '${acl.stderr}'.trim();
      throw StateError(
        'Cannot protect daemon directory'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  } else {
    final result = await Process.run('chmod', ['700', directory.path]);
    if (result.exitCode != 0) {
      throw StateError('Cannot protect daemon directory');
    }
  }
}
