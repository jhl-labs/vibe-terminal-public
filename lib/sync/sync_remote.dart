/// 원격에 저장된 동기화 파일. [sha]는 다음 업로드의 낙관적 잠금 값이다.
class SyncRemoteFile {
  const SyncRemoteFile({required this.sha, required this.content});

  final String sha;
  final String content;
}

/// 내려받은 뒤 다른 기기가 먼저 올렸다.
class SyncRemoteConflictException implements Exception {
  const SyncRemoteConflictException();

  @override
  String toString() => '다른 기기가 먼저 동기화했습니다.';
}

/// 암호화된 동기화 파일 하나를 보관하는 원격 저장소.
abstract interface class SyncRemote {
  /// 파일이 아직 없으면 null.
  Future<SyncRemoteFile?> download();

  /// [content]를 올리고 새 sha를 돌려준다. [sha]가 원격과 다르면
  /// [SyncRemoteConflictException]을 던진다.
  Future<String> upload(String content, {String? sha});
}
