import 'dart:convert';
import 'dart:io';
import 'atomic_file.dart';

/// 손상 원본을 보존하고 마지막 정상 JSON으로 복구한다. 접근 오류는 호출자에게 전달한다.
Future<Object?> readRecoverableJson(
  File file, {
  bool Function(Object?)? validate,
}) async {
  Object? decode(String raw) {
    final value = jsonDecode(raw);
    if (validate != null && !validate(value)) {
      throw const FormatException('저장 파일의 형식 또는 버전을 해석할 수 없습니다.');
    }
    return value;
  }

  final backup = File('${file.path}.last-good');
  if (!await file.exists()) {
    if (!await backup.exists()) return null;
    final raw = await backup.readAsString();
    final decoded = decode(raw);
    await writeFileAtomically(file, raw);
    return decoded;
  }
  try {
    return decode(await file.readAsString());
  } on FormatException {
    await file.copy(
      '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}',
    );
    if (!await backup.exists()) {
      throw const FormatException('JSON 저장 파일이 손상됐고 정상 백업이 없습니다.');
    }
    final raw = await backup.readAsString();
    final decoded = decode(raw);
    await writeFileAtomically(file, raw);
    return decoded;
  }
}

Future<void> writeRecoverableJson(File file, String encoded) async {
  jsonDecode(encoded);
  final backup = File('${file.path}.last-good');
  if (await file.exists()) {
    final previous = await file.readAsString();
    // 손상 파일을 정상본으로 덮어쓰지 않는다. 먼저 읽기 복구가 필요하다.
    jsonDecode(previous);
    await writeFileAtomically(backup, previous);
  } else if (!await backup.exists()) {
    await writeFileAtomically(backup, encoded);
  }
  await writeFileAtomically(file, encoded);
  // 성공 응답 전에 backup도 최신 상태로 맞춘다. 삭제한 예약이 과거 backup에서
  // 되살아나는 일을 막는다. 중간 crash는 이전/최신 정상본 중 하나로 복구된다.
  await writeFileAtomically(backup, encoded);
}
