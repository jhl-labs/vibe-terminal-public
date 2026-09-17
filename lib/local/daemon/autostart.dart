import 'dart:io';
import 'protocol.dart';

/// 로그인 시 시작하는 현재 사용자 전용 등록. 설치 당시 실행 중인 daemon은 유지한다.
class DaemonAutostart {
  const DaemonAutostart({required this.executable, required this.directory});
  final String executable, directory;
  static const name = 'com.vibeterminal.background.v1';
  String get _home =>
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
      (throw StateError('사용자 홈 경로를 찾을 수 없습니다.'));
  File get _file => File(
    Platform.isMacOS
        ? '$_home/Library/LaunchAgents/$name.plist'
        : '$_home/.config/systemd/user/$name.service',
  );
  Future<bool> enabled() async {
    if (Platform.isWindows) {
      return (await Process.run('schtasks.exe', [
            '/Query',
            '/TN',
            name,
          ])).exitCode ==
          0;
    }
    return _file.exists();
  }

  Future<void> setEnabled(bool enabled) async {
    if (Platform.isWindows) {
      final result = await Process.run(
        'schtasks.exe',
        enabled
            ? [
                '/Create',
                '/TN',
                name,
                '/SC',
                'ONLOGON',
                '/TR',
                '"$executable" "$directory"',
                '/F',
              ]
            : ['/Delete', '/TN', name, '/F'],
      );
      if (result.exitCode != 0) {
        throw StateError('로그인 작업 등록 실패: ${result.stderr} ${result.stdout}');
      }
      return;
    }
    final file = _file;
    if (!enabled) {
      if (Platform.isLinux) {
        await Process.run('systemctl', ['--user', 'disable', '$name.service']);
      }
      if (await file.exists()) await file.delete();
      return;
    }
    await secureDaemonDirectory(Directory(directory));
    await file.parent.create(recursive: true);
    if (Platform.isMacOS) {
      await file.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>$name</string><key>ProgramArguments</key><array><string>${_xml(executable)}</string><string>${_xml(directory)}</string></array><key>WorkingDirectory</key><string>${_xml(directory)}</string><key>RunAtLoad</key><true/><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict><key>ThrottleInterval</key><integer>30</integer></dict></plist>
''', flush: true);
    } else if (Platform.isLinux) {
      await file.writeAsString(
        '[Unit]\nDescription=Vibe Terminal background daemon\n[Service]\nExecStart=${_systemd(executable)} ${_systemd(directory)}\nRestart=on-failure\n[Install]\nWantedBy=default.target\n',
        flush: true,
      );
      final reload = await Process.run('systemctl', [
        '--user',
        'daemon-reload',
      ]);
      final enable = await Process.run('systemctl', [
        '--user',
        'enable',
        '$name.service',
      ]);
      if (reload.exitCode != 0 || enable.exitCode != 0) {
        throw StateError('systemd 사용자 서비스 등록 실패: ${enable.stderr}');
      }
    } else {
      throw UnsupportedError('데스크톱에서만 로그인 예약을 지원합니다.');
    }
  }
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
String _systemd(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('%', '%%').replaceAll('\n', '\\n')}"';
