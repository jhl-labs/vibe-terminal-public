import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../../../session/panes/pane_layout.dart';

class PaneDivider {
  const PaneDivider(
    this.split,
    this.parent,
    this.rect,
    this.minRatio,
    this.maxRatio,
  );
  final PaneSplit split;
  final Rect parent;
  final Rect rect;
  final double minRatio;
  final double maxRatio;
}

class PaneGeometry {
  const PaneGeometry(this.panes, this.dividers, this.fits);
  final Map<String, Rect> panes;
  final List<PaneDivider> dividers;
  final bool fits;
}

class PaneGeometryResolver {
  const PaneGeometryResolver({
    this.minimum = const Size(320, 200),
    this.gap = 8,
  });
  final Size minimum;
  final double gap;
  Size minimumFor(PaneNode node) {
    if (node is! PaneSplit) return minimum;
    final a = minimumFor(node.first), b = minimumFor(node.second);
    return node.axis == PaneAxis.leftRight
        ? Size(a.width + b.width + gap, math.max(a.height, b.height))
        : Size(math.max(a.width, b.width), a.height + b.height + gap);
  }

  PaneGeometry resolve(SessionPaneLayout layout, Size size) {
    final required = minimumFor(layout.root);
    final fits = size.width >= required.width && size.height >= required.height;
    if (!fits && layout.count > 1) {
      return PaneGeometry(
        {layout.focused.id: Offset.zero & size},
        const [],
        false,
      );
    }
    final panes = <String, Rect>{};
    final dividers = <PaneDivider>[];
    void walk(PaneNode node, Rect rect) {
      if (node is PaneLeaf) {
        panes[node.id] = rect;
        return;
      }
      final split = node as PaneSplit;
      final horizontal = split.axis == PaneAxis.leftRight;
      final total = (horizontal ? rect.width : rect.height) - gap;
      final a = minimumFor(split.first), b = minimumFor(split.second);
      final low = (horizontal ? a.width : a.height) / total;
      final high = 1 - (horizontal ? b.width : b.height) / total;
      final ratio = split.ratio.clamp(low, math.max(low, high));
      final first = total * ratio;
      final r1 = horizontal
          ? Rect.fromLTWH(rect.left, rect.top, first, rect.height)
          : Rect.fromLTWH(rect.left, rect.top, rect.width, first);
      final r2 = horizontal
          ? Rect.fromLTWH(
              rect.left + first + gap,
              rect.top,
              total - first,
              rect.height,
            )
          : Rect.fromLTWH(
              rect.left,
              rect.top + first + gap,
              rect.width,
              total - first,
            );
      final divider = horizontal
          ? Rect.fromLTWH(rect.left + first, rect.top, gap, rect.height)
          : Rect.fromLTWH(rect.left, rect.top + first, rect.width, gap);
      dividers.add(PaneDivider(split, rect, divider, low, high));
      walk(split.first, r1);
      walk(split.second, r2);
    }

    walk(layout.root, Offset.zero & size);
    return PaneGeometry(panes, dividers, fits);
  }
}
