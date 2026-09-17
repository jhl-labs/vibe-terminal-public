import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cli_config_home.dart';

/// WSL 쪽 설정 홈을 찾지 못했을 때의 이유.
class WslCliConfigException implements Exception {
  const WslCliConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Windows에서 기본 WSL 배포판 안의 CLI 설정 홈(`~/.claude` 등)을 찾는다.
///
/// 배포판 안에서 `sh -lc`로 환경변수를 읽어 POSIX 경로를 정한 뒤, Windows가
/// 제공하는 `\\wsl$\<배포판>` UNC 경로로 바꾼다. 그 뒤로는 일반 파일 IO로
/// 읽고 쓸 수 있어 [CliConfigHome]을 그대로 재사용한다.
class WslCliConfigLocator {
  WslCliConfigLocator({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    run,
    bool Function(String path)? directoryExists,
    Map<String, String>? environment,
  }) : _run = run ?? _runProcess,
       _directoryExists =
           directoryExists ?? ((path) => Directory(path).existsSync()),
       _environment = environment ?? Platform.environment;

  final Future<ProcessResult> Function(String, List<String>) _run;
  final bool Function(String) _directoryExists;
  final Map<String, String> _environment;

  /// 첫 실행 시 배포판 부팅까지 포함하므로 넉넉히 잡는다.
  static const _timeout = Duration(seconds: 20);

  /// 배포판 파일시스템을 노출하는 UNC 접두어. `\\wsl$`는 모든 WSL 버전에서
  /// 동작하고, `\\wsl.localhost`는 Windows 11 이후에 추가됐다.
  static const uncPrefixes = [r'\\wsl$', r'\\wsl.localhost'];

  /// 배포판 환경에서 읽어 오는 변수. 로그인 셸(`sh -l`)의 `env` 출력을
  /// 파싱하므로 wsl.exe 인자 인용 문제를 피한다.
  static const _probeVariables = {
    'WSL_DISTRO_NAME',
    'HOME',
    'CLAUDE_CONFIG_DIR',
    'CODEX_HOME',
    'XDG_CONFIG_HOME',
    'OPENCODE_CONFIG_DIR',
  };

  static String wslExecutable([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final systemRoot = env['SystemRoot'] ?? r'C:\Windows';
    return '$systemRoot\\System32\\wsl.exe';
  }

  /// Windows이고 wsl.exe가 있으면 WSL 전환을 제공한다. 배포판 설치 여부는
  /// 실제로 전환할 때 확인한다.
  static bool get isAvailable =>
      Platform.isWindows && File(wslExecutable()).existsSync();

  Future<CliConfigHome> locate(CliConfigApp app) async {
    final env = await _probeEnvironment();
    final distro = env['WSL_DISTRO_NAME'] ?? '';
    if (distro.isEmpty) {
      throw const WslCliConfigException('WSL 배포판 이름을 확인하지 못했습니다.');
    }
    final posixRoot = app.resolveRootPath(environment: env, paths: p.posix);
    if (posixRoot == null || !p.posix.isAbsolute(posixRoot)) {
      throw WslCliConfigException(
        'WSL 안에서 ${app.title} 홈 디렉터리를 찾지 못했습니다. '
        '${app.rootEnvironmentHint} 환경변수를 확인하세요.',
      );
    }
    return CliConfigHome(app: app, rootPath: toUncPath(distro, posixRoot));
  }

  /// 배포판 안의 절대 경로를 Windows에서 접근 가능한 UNC 경로로 바꾼다.
  /// 배포판 루트가 실제로 보이는 접두어를 고르고, 아무것도 안 보이면 첫 번째를 쓴다.
  String toUncPath(String distro, String posixPath) {
    final segments = p.posix
        .split(p.posix.normalize(posixPath))
        .where((s) => s.isNotEmpty && s != '/')
        .toList(growable: false);
    for (final prefix in uncPrefixes) {
      if (_directoryExists('$prefix\\$distro')) {
        return p.windows.joinAll([prefix, distro, ...segments]);
      }
    }
    return p.windows.joinAll([uncPrefixes.first, distro, ...segments]);
  }

  Future<Map<String, String>> _probeEnvironment() async {
    ProcessResult result;
    try {
      result = await _run(wslExecutable(_environment), [
        '--',
        'sh',
        '-lc',
        'env',
      ]).timeout(_timeout);
    } on TimeoutException {
      throw const WslCliConfigException('WSL 응답 시간이 초과되었습니다.');
    } on ProcessException catch (error) {
      throw WslCliConfigException('wsl.exe 를 실행하지 못했습니다: ${error.message}');
    }
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim();
      throw WslCliConfigException(
        detail.isEmpty ? 'WSL이 설치되지 않았거나 기본 배포판이 없습니다.' : 'WSL 실행 실패: $detail',
      );
    }
    return parseEnvironment('${result.stdout}');
  }

  /// `env` 출력에서 필요한 변수만 골라낸다. 값이 비어 있으면 없는 것으로 본다.
  static Map<String, String> parseEnvironment(String output) {
    final env = <String, String>{};
    for (final line in const LineSplitter().convert(output)) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final name = line.substring(0, separator);
      if (!_probeVariables.contains(name) || env.containsKey(name)) continue;
      final value = line.substring(separator + 1).trim();
      if (value.isNotEmpty) env[name] = value;
    }
    return env;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(
    executable,
    arguments,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}
