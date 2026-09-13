import 'dart:io';

/// [target]의 내용을 [contents]로 원자적으로 바꾼다.
///
/// 같은 디렉터리에 임시 파일을 쓰고 flush 한 뒤 rename 한다. rename은 같은
/// 파일시스템 안에서 원자적이므로, 어느 시점에 프로세스가 죽어도 [target]은
/// 항상 예전 내용이거나 새 내용이지 잘린 내용이 되지 않는다.
///
/// 곧바로 `writeAsString`을 쓰면 파일을 먼저 비우고 쓰기 때문에, 그 사이에
/// 앱이 종료되면(안드로이드에서는 흔한 일이다) 설정 파일이 빈 채로 남아
/// 다음 실행에서 전부 기본값으로 되돌아간다.
Future<void> writeFileAtomically(File target, String contents) async {
  await target.parent.create(recursive: true);
  final temporary = File(
    '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  } finally {
    // rename에 성공했으면 임시 파일은 이미 없다. 실패했을 때만 치운다.
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } catch (_) {
        // 임시 파일이 남아도 다음 쓰기는 새 이름을 쓴다.
      }
    }
  }
}

/// [writeFileAtomically]의 동기 버전. 작은 로컬 설정 파일을 UI 스레드에서
/// 바로 저장할 때 쓴다(예: `~/.claude` 편집기).
void writeFileAtomicallySync(File target, String contents) {
  target.parent.createSync(recursive: true);
  final temporary = File(
    '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    temporary.writeAsStringSync(contents, flush: true);
    temporary.renameSync(target.path);
  } finally {
    if (temporary.existsSync()) {
      try {
        temporary.deleteSync();
      } catch (_) {
        // 임시 파일이 남아도 다음 쓰기는 새 이름을 쓴다.
      }
    }
  }
}
