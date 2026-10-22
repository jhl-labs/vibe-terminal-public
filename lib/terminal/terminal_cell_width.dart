import 'package:xterm/xterm.dart';

/// [rune] 하나가 터미널에서 차지하는 셀 수. xterm 버퍼와 같은 wcwidth 표를
/// 쓰므로 한글 음절·호환 자모는 2셀, ASCII는 1셀이다. 제어 문자처럼 wcwidth가
/// 음수인 문자와 결합 문자는 칸을 차지하지 않으므로 0이다.
int terminalRuneCells(int rune) {
  final width = unicodeV11.wcwidth(rune);
  return width > 0 ? width : 0;
}

/// [runes]가 터미널에서 차지하는 셀 수([terminalRuneCells]의 합).
int terminalRunesCells(Iterable<int> runes) {
  var cells = 0;
  for (final rune in runes) {
    cells += terminalRuneCells(rune);
  }
  return cells;
}

/// [text]가 터미널에서 차지하는 셀 수.
int terminalCellWidth(String text) => terminalRunesCells(text.runes);
