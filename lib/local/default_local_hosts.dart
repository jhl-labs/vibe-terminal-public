import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/atomic_file.dart';
import '../data/models/host.dart';
import '../data/repositories/host_repository.dart';

/// 기본 로컬 호스트를 고를 때의 플랫폼 구분.
enum DefaultLocalHostPlatform { windows, posix, unsupported }

/// 앱이 첫 실행에 대신 만들어 주는 로컬 셸 호스트 후보.
class DefaultLocalHostCandidate {
  const DefaultLocalHostCandidate({
    required this.shell,
    required this.alias,
    required this.workingDirectory,
    required this.username,
  });

  final LocalShellType shell;
  final String alias;
  final String workingDirectory;
  final String username;
}

/// 플랫폼별 기본 로컬 호스트. 처음 쓰는 사람이 PowerShell/WSL/로컬 셸을
/// 매번 직접 등록하지 않아도 되게 한다. 작업 폴더와 사용자명은 호스트 편집
/// 화면의 기본값과 같다.
List<DefaultLocalHostCandidate> defaultLocalHostCandidates({
  required DefaultLocalHostPlatform platform,
  required bool wslAvailable,
  required String? home,
  required String username,
}) {
  final homeDirectory = (home == null || home.trim().isEmpty)
      ? username
      : home.trim();
  return switch (platform) {
    DefaultLocalHostPlatform.windows => [
      DefaultLocalHostCandidate(
        shell: LocalShellType.powershell,
        alias: 'Local (PowerShell)',
        workingDirectory: homeDirectory,
        username: username,
      ),
      if (wslAvailable)
        DefaultLocalHostCandidate(
          shell: LocalShellType.wsl,
          alias: 'WSL',
          workingDirectory: '~',
          username: username,
        ),
    ],
    DefaultLocalHostPlatform.posix => [
      DefaultLocalHostCandidate(
        // 비Windows는 셸 종류가 의미 없고 $SHELL을 쓴다. 저장 필드는 기본값.
        shell: LocalShellType.powershell,
        alias: 'Local Shell',
        workingDirectory: homeDirectory,
        username: username,
      ),
    ],
    DefaultLocalHostPlatform.unsupported => const [],
  };
}

/// 현재 기기 기준 후보. Windows는 `wsl.exe`가 있을 때만 WSL을 포함한다.
List<DefaultLocalHostCandidate> defaultLocalHostCandidatesForThisDevice() {
  final env = Platform.environment;
  final username = env['USERNAME'] ?? env['USER'] ?? 'local';
  final platform = Platform.isWindows
      ? DefaultLocalHostPlatform.windows
      : (Platform.isLinux || Platform.isMacOS)
      ? DefaultLocalHostPlatform.posix
      : DefaultLocalHostPlatform.unsupported;
  var wslAvailable = false;
  if (Platform.isWindows) {
    final systemRoot = env['SystemRoot'] ?? r'C:\Windows';
    wslAvailable = File('$systemRoot\\System32\\wsl.exe').existsSync();
  }
  return defaultLocalHostCandidates(
    platform: platform,
    wslAvailable: wslAvailable,
    home: env['USERPROFILE'] ?? env['HOME'],
    username: username,
  );
}

/// 기본 로컬 호스트를 셸 종류별로 **한 번만** 등록한다.
///
/// 등록한 종류는 앱 지원 디렉터리의 JSON에 기록해, 사용자가 지운 호스트가
/// 다음 실행에 되살아나지 않게 한다. 같은 종류의 로컬 호스트가 이미 있으면
/// 만들지 않고 기록만 남긴다(기존 사용자에게 중복이 생기지 않는다).
class DefaultLocalHostSeeder {
  DefaultLocalHostSeeder(
    this._hosts, {
    required List<DefaultLocalHostCandidate> candidates,
    Future<File> Function()? fileResolver,
    DateTime Function()? now,
  }) : _candidates = List.unmodifiable(candidates),
       _fileResolver = fileResolver ?? _defaultFile,
       _now = now ?? DateTime.now;

  final HostRepository _hosts;
  final List<DefaultLocalHostCandidate> _candidates;
  final Future<File> Function() _fileResolver;
  final DateTime Function() _now;

  static Future<File> _defaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}local_hosts_seed.json');
  }

  /// 호스트를 하나라도 새로 만들었으면 true.
  Future<bool> seed() async {
    if (_candidates.isEmpty) return false;
    final seeded = await _loadSeeded();
    final pending = _candidates
        .where((c) => !seeded.contains(c.shell.name))
        .toList();
    if (pending.isEmpty) return false;

    final existing = await _hosts.getAll();
    var created = false;
    for (final candidate in pending) {
      final alreadyHasKind = existing.any(
        (h) => h.isLocalShell && h.localShellType == candidate.shell,
      );
      if (!alreadyHasKind) {
        final at = _now();
        await _hosts.upsert(
          Host(
            id: 'local-default-${candidate.shell.name}',
            alias: candidate.alias,
            hostname: 'localhost',
            port: 0,
            username: candidate.username,
            connectionType: HostConnectionType.localShell,
            authType: HostAuthType.password,
            localShellType: candidate.shell,
            workingDirectory: candidate.workingDirectory,
            createdAt: at,
            updatedAt: at,
          ),
        );
        created = true;
      }
      seeded.add(candidate.shell.name);
    }
    await _saveSeeded(seeded);
    return created;
  }

  Future<Set<String>> _loadSeeded() async {
    try {
      final file = await _fileResolver();
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return {};
      final list = decoded['seeded'];
      if (list is! List) return {};
      return list.whereType<String>().toSet();
    } catch (_) {
      // 기록을 못 읽으면 한 번 더 시도하는 정도의 손해만 있다(종류별 중복 검사
      // 덕분에 호스트가 두 개 생기지는 않는다).
      return {};
    }
  }

  Future<void> _saveSeeded(Set<String> seeded) async {
    try {
      await writeFileAtomically(
        await _fileResolver(),
        jsonEncode({'seeded': seeded.toList()..sort()}),
      );
    } catch (_) {}
  }
}
