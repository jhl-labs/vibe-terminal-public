import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 선택 영역 위(또는 아래)에 복사·전체선택 버튼을 표시하는 플로팅 툴바.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.anchor,
    required this.onCopy,
    required this.onSelectAll,
  });

  /// 선택 상단 중앙(로컬 px).
  final Offset anchor;
  final VoidCallback onCopy;
  final VoidCallback onSelectAll;

  static const double _height = 40;
  static const double _belowAnchorGap = 24;

  @override
  Widget build(BuildContext context) {
    // 선택 상단 위로 띄우되, 화면 최상단이면 아래로 내린다.
    final showBelow = anchor.dy < _height + 8;
    final top = showBelow
        ? anchor.dy + _belowAnchorGap
        : anchor.dy - _height - 8;
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
  });

  final SelectionGeometry? geometry;
  final ValueChanged<Offset> onHandleDragBegin;
  final ValueChanged<Offset> onHandleDragEnd;
  final Widget toolbar;

  /// 핸들 드래그 제스처 시작/종료. 부모가 고정 anchor를 한 번만 잡고
  /// 드래그 종료 시 해제하도록 신호를 준다(양끝이 같이 끌려가는 버그 방지).
  final VoidCallback? onHandleDragStart;
  final VoidCallback? onHandleDragStop;

  static const double _handleRadius = 8;
  static const double _touchPadding = 14;

  @override
  Widget build(BuildContext context) {
    final geo = geometry;
    if (geo == null) return const SizedBox.shrink();

    // 시작 핸들: 시작 셀 좌하단. 끝 핸들: 끝 셀 우하단.
    final beginAnchor = Offset(
      geo.begin.dx,
      geo.begin.dy + geo.cellSize.height,
    );
    final endAnchor = Offset(
      geo.end.dx + geo.cellSize.width,
      geo.end.dy + geo.cellSize.height,
    );

    return Stack(
      children: [
        _handle(
          const ValueKey('sel-handle-begin'),
          beginAnchor,
          onHandleDragBegin,
        ),
        _handle(const ValueKey('sel-handle-end'), endAnchor, onHandleDragEnd),
        toolbar,
      ],
    );
  }

  Widget _handle(Key key, Offset anchor, ValueChanged<Offset> onDrag) {
    return Positioned(
      left: anchor.dx - _handleRadius - _touchPadding,
      top: anchor.dy - _handleRadius - _touchPadding,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onHandleDragStart?.call(),
        onPanUpdate: (d) => onDrag(d.globalPosition),
        onPanEnd: (_) => onHandleDragStop?.call(),
        onPanCancel: () => onHandleDragStop?.call(),
        child: Padding(
          padding: const EdgeInsets.all(_touchPadding),
          child: Container(
            width: _handleRadius * 2,
            height: _handleRadius * 2,
            decoration: const BoxDecoration(
              color: VibeColors.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
