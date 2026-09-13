import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

/// 클립보드에서 읽어온 이미지(바이트 + 확장자).
class ClipboardImage {
  const ClipboardImage({required this.bytes, required this.extension});

  final Uint8List bytes;

  /// 파일 확장자(점 제외). 예: 'png', 'jpg'.
  final String extension;
}

/// 업로드/저장에 쓸 이미지 파일명을 만든다. 충돌을 피하려 타임스탬프를 쓴다.
String clipboardImageFileName(String extension, int timestampMs) =>
    'vibe-terminal-$timestampMs.$extension';

/// 우선순위 순서대로 시도할 이미지 포맷과 확장자.
const List<(FileFormat, String)> _imageCandidates = [
  (Formats.png, 'png'),
  (Formats.jpeg, 'jpg'),
  (Formats.gif, 'gif'),
  (Formats.webp, 'webp'),
];

/// 시스템 클립보드에서 이미지를 읽는다. 이미지가 없거나 플랫폼이 클립보드를
/// 지원하지 않으면 null을 반환한다.
Future<ClipboardImage?> readClipboardImage() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();

  for (final (format, ext) in _imageCandidates) {
    if (!reader.canProvide(format)) continue;
    final completer = Completer<ClipboardImage?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          final data = await file.readAll();
          if (!completer.isCompleted) {
            completer.complete(ClipboardImage(bytes: data, extension: ext));
          }
        } catch (_) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    // getFile이 즉시 null을 반환하면 해당 포맷은 실제로 제공 불가하므로 다음 후보로.
    if (progress == null) continue;
    return completer.future;
  }
  return null;
}
