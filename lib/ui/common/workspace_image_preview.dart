import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Decode only a viewport-sized preview; never alter the uploaded original.
class WorkspaceImagePreview extends StatefulWidget {
  const WorkspaceImagePreview({super.key, required this.imageBase64});

  final String imageBase64;

  @override
  State<WorkspaceImagePreview> createState() => _WorkspaceImagePreviewState();
}

class _WorkspaceImagePreviewState extends State<WorkspaceImagePreview> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(WorkspaceImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBase64 != widget.imageBase64) _decode();
  }

  void _decode() {
    try {
      _bytes = base64Decode(widget.imageBase64);
    } on FormatException {
      _bytes = null;
    }
  }

  int _pixelBound(double logicalSize, double pixelRatio) =>
      (logicalSize * pixelRatio).ceil().clamp(1, 1600).toInt();

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const Text('이미지를 해석하지 못했습니다.');
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final width = _pixelBound(
          math.min(constraints.maxWidth, screen.width),
          ratio,
        );
        final height = _pixelBound(
          math.min(constraints.maxHeight, screen.height),
          ratio,
        );
        return InteractiveViewer(
          child: Image(
            image: ResizeImage(
              MemoryImage(bytes),
              width: width,
              height: height,
              policy: ResizeImagePolicy.fit,
            ),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text('이미지를 해석하지 못했습니다.'),
          ),
        );
      },
    );
  }
}
