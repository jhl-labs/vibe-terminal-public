import 'package:flutter/widgets.dart';

import '../../terminal/terminal_cell_width.dart';

/// IME 오버레이 한 조각(조합 중 꼬리, 에코 대기 텍스트)을 터미널 셀 격자에
/// 맞춰 그린다.
///
/// - 폭은 글꼴 측정값이 아니라 `셀 수 × xterm 셀 폭`이다. 한글처럼 2셀인
///   글자가 실제 에코와 같은 칸을 덮는다.
/// - 배경은 불투명한 터미널 배경색이다. 아래에 이미 그려진(또는 늦게 도착한)
///   글자와 섞여 겹쳐 보이지 않는다.
class TerminalImeCells extends StatelessWidget {
  const TerminalImeCells({
    super.key,
    required this.text,
    required this.cellSize,
    required this.style,
    required this.background,
    this.underline,
  });

  final String text;
  final Size cellSize;
  final TextStyle style;
  final Color background;
  final BorderSide? underline;

  @override
  Widget build(BuildContext context) {
    final cells = terminalCellWidth(text).clamp(1, 1 << 16);
    return SizedBox(
      width: cells * cellSize.width,
      height: cellSize.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background.withAlpha(0xFF),
          border: underline == null ? null : Border(bottom: underline!),
        ),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Text(text, maxLines: 1, softWrap: false, style: style),
          ),
        ),
      ),
    );
  }
}
