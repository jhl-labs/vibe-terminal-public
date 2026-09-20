import 'dart:io';

import 'package:path/path.dart' as p;

class SshKeyCandidate {
  const SshKeyCandidate({
    required this.path,
    required this.fileName,
    required this.encrypted,
  });

  final String path;
  final String fileName;

  /// 헤더만으로 판단한 암호화 여부. OpenSSH 포맷은 본문을 파싱해야 알 수
  /// 있으므로 false로 두고, 가져올 때 실패하면 패스프레이즈를 묻는다.
  final bool encrypted;

  Future<String> read() => File(path).readAsString();
}

/// `~/.ssh` 같은 디렉터리에서 개인키로 보이는 파일을 찾는다.
class SshKeyScanner {
  static const _maxBytes = 256 * 1024;

  static Directory? defaultDirectory() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return null;
    final dir = Directory(p.join(home, '.ssh'));
    return dir.existsSync() ? dir : null;
  }

  static Future<List<SshKeyCandidate>> scan(Directory dir) async {
    if (!await dir.exists()) return const [];
    final found = <SshKeyCandidate>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.pub') || name == 'known_hosts' || name == 'config') {
        continue;
      }
      if (await entity.length() > _maxBytes) continue;
      final String head;
      try {
        head = await entity.readAsString();
      } catch (_) {
        continue; // 바이너리나 읽기 불가 파일은 건너뛴다.
      }
      if (!head.contains('-----BEGIN') || !head.contains('PRIVATE KEY-----')) {
        continue;
      }
      found.add(
        SshKeyCandidate(
          path: entity.path,
          fileName: name,
          encrypted: head.contains('ENCRYPTED'),
        ),
      );
    }
    found.sort((a, b) => a.fileName.compareTo(b.fileName));
    return found;
  }
}
