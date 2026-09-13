import 'package:dartssh2/dartssh2.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../session/session.dart';
import '../state/providers.dart';
import 'clipboard_image.dart';

/// 키보드 리치 콘텐츠 삽입에서 허용할 이미지 mime 타입.
const List<String> kImageInsertionMimeTypes = [
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
];

/// 이미지 mime 타입을 파일 확장자(점 제외)로 변환한다. 미지원이면 null.
String? imageExtensionForMime(String mimeType) {
  switch (mimeType) {
    case 'image/png':
      return 'png';
    case 'image/jpeg':
      return 'jpg';
    case 'image/gif':
      return 'gif';
    case 'image/webp':
      return 'webp';
    default:
      return null;
  }
}

/// 키보드가 삽입한 리치 콘텐츠를 ClipboardImage로 변환한다. 지원하지 않는
/// 타입이거나 데이터가 없으면 null.
ClipboardImage? keyboardContentToImage(KeyboardInsertedContent content) {
  final ext = imageExtensionForMime(content.mimeType);
  if (ext == null) return null;
  final data = content.data;
  if (data == null) return null;
  return ClipboardImage(bytes: data, extension: ext);
}

/// 이미지를 세션 종류에 맞는 위치에 저장하고 경로를 반환한다.
/// 로컬 셸은 로컬 임시 파일, SSH 세션은 원격 /tmp에 SFTP 업로드한다.
Future<String> uploadSessionImage(
  WidgetRef ref,
  SessionInfo session,
  ClipboardImage image,
) async {
  final name = clipboardImageFileName(
    image.extension,
    DateTime.now().millisecondsSinceEpoch,
  );
  if (session.host.isLocalShell) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(image.bytes);
    return file.path;
  }
  final client = ref
      .read(sessionManagerProvider.notifier)
      .sshClientFor(session.id);
  if (client == null) {
    throw Exception('SFTP 채널을 열 수 없습니다(연결 상태를 확인하세요)');
  }
  final sftp = await client.sftp();
  try {
    final remotePath = '/tmp/$name';
    final file = await sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.write(Stream.value(image.bytes));
    } finally {
      await file.close();
    }
    return remotePath;
  } finally {
    sftp.close();
  }
}

/// 이미지 업로드 여부를 묻는 확인 다이얼로그. 업로드=true, 취소=false.
Future<bool> confirmImageUpload(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('이미지 붙여넣기'),
      content: const Text('이미지를 업로드해서 경로를 터미널에 입력할까요?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('업로드'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 이미지 감지 후 공통 흐름: 확인 → 업로드 → 경로 입력 → 스낵바.
/// 취소/실패/위젯 해제를 모두 내부에서 처리한다.
Future<void> handleImagePaste({
  required BuildContext context,
  required WidgetRef ref,
  required SessionInfo session,
  required ClipboardImage image,
  required void Function(String text) sendText,
  required void Function(String message) showSnack,
}) async {
  if (!await confirmImageUpload(context)) return;
  if (!context.mounted) return;
  showSnack('이미지 업로드 중…');
  try {
    final path = await uploadSessionImage(ref, session, image);
    if (!context.mounted) return;
    // 경로 뒤 공백으로 다음 인자를 바로 이어 쓸 수 있게 한다.
    sendText('$path ');
    showSnack('이미지 경로 입력됨: $path');
  } catch (e) {
    if (!context.mounted) return;
    showSnack('이미지 업로드 실패: $e');
  }
}
