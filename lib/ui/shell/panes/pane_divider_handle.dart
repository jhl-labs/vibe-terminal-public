import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../session/panes/pane_layout.dart';
import 'pane_geometry.dart';

class PaneDividerHandle extends StatefulWidget {
  const PaneDividerHandle({
    super.key,
    required this.divider,
    required this.onDelta,
    required this.onFinish,
    required this.onCancel,
    required this.onEqualize,
    required this.onUnlink,
  });
  final PaneDivider divider;
  final ValueChanged<double> onDelta;
  final VoidCallback onFinish, onCancel, onEqualize, onUnlink;
  @override
  State<PaneDividerHandle> createState() => _PaneDividerHandleState();
}

class _PaneDividerHandleState extends State<PaneDividerHandle> {
  final _focus = FocusNode(debugLabel: 'pane divider');
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _menu(Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'equal', child: Text('균등 분할')),
        if (widget.divider.split.link != null)
          const PopupMenuItem(value: 'unlink', child: Text('이 열만 조절')),
      ],
    );
    if (!mounted) return;
    if (selected == 'equal') widget.onEqualize();
    if (selected == 'unlink') widget.onUnlink();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.divider.split.axis == PaneAxis.leftRight;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final negative = horizontal
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowUp;
        final positive = horizontal
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowDown;
        if (event.logicalKey != negative && event.logicalKey != positive) {
          return KeyEventResult.ignored;
        }
        widget.onDelta(event.logicalKey == negative ? -10 : 10);
        widget.onFinish();
        return KeyEventResult.handled;
      },
      child: Semantics(
        label: horizontal ? '좌우 칸 크기 조절' : '상하 칸 크기 조절',
        onIncrease: () {
          widget.onDelta(10);
          widget.onFinish();
        },
        onDecrease: () {
          widget.onDelta(-10);
          widget.onFinish();
        },
        child: MouseRegion(
          cursor: horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: Listener(
            onPointerDown: (_) => _focus.requestFocus(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onDoubleTap: widget.onEqualize,
              onSecondaryTapUp: (event) => _menu(event.globalPosition),
              onLongPressStart: (event) => _menu(event.globalPosition),
              onHorizontalDragUpdate: horizontal
                  ? (e) => widget.onDelta(e.delta.dx)
                  : null,
              onVerticalDragUpdate: !horizontal
                  ? (e) => widget.onDelta(e.delta.dy)
                  : null,
              onHorizontalDragEnd: horizontal ? (_) => widget.onFinish() : null,
              onVerticalDragEnd: !horizontal ? (_) => widget.onFinish() : null,
              onHorizontalDragCancel: horizontal ? widget.onCancel : null,
              onVerticalDragCancel: !horizontal ? widget.onCancel : null,
              child: Center(
                child: SizedBox(
                  width: horizontal ? 4 : null,
                  height: horizontal ? null : 4,
                  child: const ColoredBox(color: Color(0xff344458)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
