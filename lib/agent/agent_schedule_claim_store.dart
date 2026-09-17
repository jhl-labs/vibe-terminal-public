import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// 외부 효과를 시작하기 전에 회차를 기록한다. 완료 여부를 알 수 없는 crash 후에는
/// 자동 재실행하지 않는다. exactly-once 외부 효과를 보장하는 것으로 취급하지 않는다.
abstract interface class AgentScheduleClaimStore {
  Future<bool> claimOccurrence(String key);
}

/// 회차별 exclusive-create marker를 사용한다. 이전 JSON 백업으로 돌아가 최근의
/// 실행 기록이 사라지는 일이 없으며, 여러 앱 프로세스도 같은 회차를 획득할 수 없다.
/// 빈 marker도 시작 여부 불명으로 취급한다. 자동 삭제/만료시키지 않는다.
class FileAgentScheduleClaims implements AgentScheduleClaimStore {
  FileAgentScheduleClaims(this.directory);
  final Future<Directory> Function() directory;

  @override
  Future<bool> claimOccurrence(String key) async {
    final dir = Directory('${(await directory()).path}/schedule-claims');
    await dir.create(recursive: true);
    final name = sha256.convert(utf8.encode(key)).toString();
    final file = File('${dir.path}/$name.json');
    try {
      await file.create(exclusive: true);
    } on FileSystemException {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return false;
      }
      rethrow;
    }
    // 쓰기 실패 시 marker를 남긴다. 시작할 수 있는지 불명확한 회차를 재실행하지 않는다.
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'key': key,
        'claimedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    return true;
  }
}
