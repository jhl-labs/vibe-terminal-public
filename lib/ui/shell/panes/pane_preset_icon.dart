import 'package:flutter/material.dart';
import '../../../session/panes/pane_layout.dart';
import 'pane_geometry.dart';

String panePresetLabel(PanePreset preset) => switch (preset) {
  PanePreset.single => '단일',
  PanePreset.columns => '좌우 2분할',
  PanePreset.rows => '상하 2분할',
  PanePreset.leftLarge => '왼쪽 크게',
  PanePreset.rightLarge => '오른쪽 크게',
  PanePreset.topLarge => '위쪽 크게',
  PanePreset.bottomLarge => '아래쪽 크게',
  PanePreset.grid => '4격자',
};

class PanePresetIcon extends StatelessWidget {
  const PanePresetIcon(this.preset, {super.key});
  final PanePreset preset;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    height: 26,
    child: CustomPaint(
      painter: _PresetPainter(preset, Theme.of(context).colorScheme.primary),
    ),
  );
}

class _PresetPainter extends CustomPainter {
  const _PresetPainter(this.preset, this.color);
  final PanePreset preset;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final layout = const SessionPaneLayout().preset(preset, []);
    final geometry = const PaneGeometryResolver(
      minimum: Size.zero,
      gap: 3,
    ).resolve(layout, size);
    for (final rect in geometry.panes.values) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(.5), const Radius.circular(2)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_PresetPainter old) =>
      old.preset != preset || old.color != color;
}

/// Shared by pane headers and the session rail; never drags terminal text.
class PaneSessionDrag {
  const PaneSessionDrag(this.sessionId, this.groupId);
  final String sessionId;
  final String groupId;
}
