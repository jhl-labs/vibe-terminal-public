import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 선택 영역 위(또는 아래)에 복사·전체선택 버튼을 표시하는 플로팅 툴바.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.anchor,
    required this.onCopy,
    required this.onSelectAll,
    this.belowAnchorGap = 56,
    this.aboveAnchorGap = 32,
  });

  /// 선택 상단 중앙(로컬 px).
  final Offset anchor;
  final VoidCallback onCopy;
  final VoidCallback onSelectAll;

  static const double _height = 40;
  final double belowAnchorGap;
  final double aboveAnchorGap;

  @override
  Widget build(BuildContext context) {
    // 선택 상단 위로 띄우되, 화면 최상단이면 아래로 내린다.
    final showBelow = anchor.dy < _height + aboveAnchorGap;
    final top = showBelow
        ? anchor.dy + belowAnchorGap
        : anchor.dy - _height - aboveAnchorGap;
    return Positioned(
      key: const ValueKey('sel-toolbar'),
      left: (anchor.dx - 90).clamp(8.0, double.infinity),
      top: top.clamp(0.0, double.infinity),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: VibeColors.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const ValueKey('sel-copy'),
              onPressed: onCopy,
              child: const Text('복사'),
            ),
            TextButton(
              key: const ValueKey('sel-select-all'),
              onPressed: onSelectAll,
              child: const Text('전체 선택'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 선택 양끝의 픽셀 좌표(로컬). null이면 선택 없음.
class SelectionGeometry {
  const SelectionGeometry({
    required this.begin,
    required this.end,
    required this.cellSize,
  });

  final Offset begin;
  final Offset end;
  final Size cellSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionGeometry &&
          begin == other.begin &&
          end == other.end &&
          cellSize == other.cellSize;

  @override
  int get hashCode => Object.hash(begin, end, cellSize);
}

/// xterm TerminalView 위에 올려 Termius식 드래그 핸들과 툴바를 그린다.
class TerminalSelectionOverlay extends StatelessWidget {
  const TerminalSelectionOverlay({
    super.key,
    required this.geometry,
    required this.onHandleDragBegin,
    required this.onHandleDragEnd,
    required this.toolbar,
    this.onHandleDragStart,
    this.onHandleDragStop,
    this.onPointerSignal,
    this.showHandles = true,
  });

  final SelectionGeometry? geometry;
  final ValueChanged<Offset> onHandleDragBegin;
  final ValueChanged<Offset> onHandleDragEnd;
  final Widget toolbar;

  /// 핸들 드래그 제스처 시작/종료. 부모가 고정 anchor를 한 번만 잡고
  /// 드래그 종료 시 해제하도록 신호를 준다(양끝이 같이 끌려가는 버그 방지).
  /// 시작 신호는 어느 핸들([begin])을 어디서 잡았는지 알려, 부모가 손가락과
  /// 선택 끝 글자 사이의 거리를 보정할 수 있게 한다.
  final void Function(bool begin, DragStartDetails details)? onHandleDragStart;
  final VoidCallback? onHandleDragStop;

  /// 핸들 위에서 발생한 휠/트랙패드 스크롤을 넘겨받는다. 마우스로 드래그
  /// 선택하면 끝 핸들이 포인터 바로 아래를 따라다니므로, 핸들이 휠을 삼키면
  /// 드래그하면서 스크롤할 수 없다. 부모가 아래 터미널로 전달해야 한다.
  final ValueChanged<PointerSignalEvent>? onPointerSignal;

  /// 드래그 핸들을 그릴지. 마우스로 만든 선택은 다시 끌어 고치면 되므로
  /// 핸들을 숨긴다. 핸들은 글자 위에 겹쳐 있어 세 번째 클릭이나 이어지는
  /// 드래그를 가로챈다.
  final bool showHandles;

  static const double _handleRadius = 8;
  static const double _touchExtent = 48;

  @override
  Widget build(BuildContext context) {
    final geo = geometry;
    if (geo == null) return const SizedBox.shrink();

    // Selection.end is exclusive: its offset is already the right boundary.
    final beginAnchor = geo.begin + Offset(0, geo.cellSize.height);
    final endAnchor = geo.end + Offset(0, geo.cellSize.height);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return const SizedBox.shrink();
        // Keep full finger targets in ordinary panes; in a tiny pane choose the
        // largest targets for which two can still fit on at least one axis.
        final extent = math.min(
          _touchExtent,
          math.max(size.width, size.height) / 2,
        );
        final hitSize = Size(
          math.min(extent, size.width),
          math.min(extent, size.height),
        );
        Offset bounded(Offset point) => Offset(
          point.dx.clamp(hitSize.width / 2, size.width - hitSize.width / 2),
          point.dy.clamp(hitSize.height / 2, size.height - hitSize.height / 2),
        );
        bool visible(Offset anchor) =>
            anchor.dy >= 0 && anchor.dy <= size.height;
        var begin = visible(beginAnchor)
            ? bounded(beginAnchor - const Offset(_handleRadius, 0))
            : beginAnchor;
        var end = visible(endAnchor)
            ? bounded(endAnchor + const Offset(_handleRadius, 0))
            : endAnchor;
        if (showHandles &&
            visible(beginAnchor) &&
            visible(endAnchor) &&
            (begin.dx - end.dx).abs() < hitSize.width &&
            (begin.dy - end.dy).abs() < hitSize.height) {
          if (size.width >= hitSize.width * 2) {
            final middle = ((begin.dx + end.dx) / 2).clamp(
              hitSize.width,
              size.width - hitSize.width,
            );
            begin = Offset(middle - hitSize.width / 2, begin.dy);
            end = Offset(middle + hitSize.width / 2, end.dy);
          } else {
            final middle = ((begin.dy + end.dy) / 2).clamp(
              hitSize.height,
              size.height - hitSize.height,
            );
            begin = Offset(begin.dx, middle - hitSize.height / 2);
            end = Offset(end.dx, middle + hitSize.height / 2);
          }
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (showHandles) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SelectionHandleLinks(
                      beginAnchor,
                      begin,
                      endAnchor,
                      end,
                    ),
                  ),
                ),
              ),
              _handle(
                const ValueKey('sel-handle-begin'),
                begin,
                hitSize,
                begin: true,
                onDrag: onHandleDragBegin,
              ),
              _handle(
                const ValueKey('sel-handle-end'),
                end,
                hitSize,
                begin: false,
                onDrag: onHandleDragEnd,
              ),
            ],
            toolbar,
          ],
        );
      },
    );
  }

  Widget _handle(
    Key key,
    Offset anchor,
    Size hitSize, {
    required bool begin,
    required ValueChanged<Offset> onDrag,
  }) {
    return Positioned(
      left: anchor.dx - hitSize.width / 2,
      top: anchor.dy - hitSize.height / 2,
      child: Listener(
        onPointerSignal: onPointerSignal,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onHandleDragStart?.call(begin, d),
          onPanUpdate: (d) => onDrag(d.globalPosition),
          onPanEnd: (_) => onHandleDragStop?.call(),
          onPanCancel: () => onHandleDragStop?.call(),
          child: SizedBox.fromSize(
            size: hitSize,
            child: Center(
              child: Container(
                width: math.min(_handleRadius * 2, hitSize.width),
                height: math.min(_handleRadius * 2, hitSize.height),
                decoration: const BoxDecoration(
                  color: VibeColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionHandleLinks extends CustomPainter {
  const _SelectionHandleLinks(
    this.beginAnchor,
    this.begin,
    this.endAnchor,
    this.end,
  );
  final Offset beginAnchor;
  final Offset begin;
  final Offset endAnchor;
  final Offset end;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VibeColors.accent
      ..strokeWidth = 1.5;
    canvas.drawLine(beginAnchor, begin, paint);
    canvas.drawLine(endAnchor, end, paint);
  }

  @override
  bool shouldRepaint(_SelectionHandleLinks oldDelegate) =>
      beginAnchor != oldDelegate.beginAnchor ||
      begin != oldDelegate.begin ||
      endAnchor != oldDelegate.endAnchor ||
      end != oldDelegate.end;
}
