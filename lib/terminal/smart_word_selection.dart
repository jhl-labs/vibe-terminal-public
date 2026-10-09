import 'dart:math' show min;

import 'package:xterm/xterm.dart';

/// 더블클릭·롱프레스로 선택할 단위를 고른다. URL·파일 경로는 `.` `/` `:`
/// 같은 구분자에서 끊지 않고 통째로, 그 밖은 셸 인자 정도의 단어로 고른다.
///
/// 텍스트 규칙([SmartWordFinder])과 버퍼 좌표 변환([selectSmartWord])을 나눠
/// 규칙만 따로 검증할 수 있게 한다.
class SmartWordFinder {
  const SmartWordFinder._();

  // 우선순위 순서. 클릭 위치를 덮는 첫 패턴을 쓴다.
  static final List<RegExp> _patterns = [
    // URL. 괄호는 위키 주소처럼 URL 안에 올 수 있어 일단 포함하고 뒤에서
    // 짝이 맞지 않는 닫는 괄호만 덜어 낸다.
    RegExp(
      r'''(?:(?:https?|ftp|file|wss?|ssh|sftp|git)://|www\.)[^\s"'`<>]+''',
      caseSensitive: false,
    ),
    // Windows 경로: C:\..., \\server\share\...
    RegExp(r'''(?:[A-Za-z]:|\\\\[\w.$-]+)\\[^\s"'`<>|*?]*(?::\d+){0,2}'''),
    // Unix 경로: /abs, ~/x, ./x, ../x, src/x (뒤의 :줄:열 포함)
    RegExp(
      r'''(?:~|[\p{L}\p{N}_@.+-]+)?/[^\s"'`<>|;:$(){}\[\],]*(?::\d+){0,2}''',
      unicode: true,
    ),
    // scp 형식 원격 경로: git@github.com:org/repo.git
    RegExp(r'''[\w.-]+@[\w.-]+:[\w./~-]+'''),
    // 확장자가 있는 파일 이름·도메인·버전: main.dart:12, example.com, 1.2.3
    RegExp(
      r'''[\p{L}\p{N}_@+-][\p{L}\p{N}_@.+-]*\.[\p{L}\p{N}_-]+(?::\d+){0,2}''',
      unicode: true,
    ),
    // 일반 단어: 셸 인자(--force, -rf, ~user, #123)까지 한 단위로 본다.
    RegExp(r'''[\p{L}\p{N}_.+~#%@-]+''', unicode: true),
  ];

  static const _trailingPunctuation = '.,;:!?';
  static const _closingToOpening = {')': '(', ']': '[', '}': '{'};

  /// [text]에서 [index] 위치 글자를 덮는 선택 범위 `[start, end)`.
  /// 덮는 단위가 없으면 null.
  static (int, int)? find(String text, int index) {
    if (index < 0 || index >= text.length) return null;
    for (final pattern in _patterns) {
      for (final match in pattern.allMatches(text)) {
        if (match.start > index) break;
        if (match.end <= index) continue;
        final end = _trimEnd(text, match.start, match.end);
        if (index < end) return (match.start, end);
        // 클릭한 곳이 덜어 낸 문장 부호면 다음 패턴으로 넘어간다.
        break;
      }
    }
    return null;
  }

  /// 문장 끝 부호와 짝 없는 닫는 괄호를 뒤에서 덜어 낸다.
  static int _trimEnd(String text, int start, int end) {
    while (end > start) {
      final last = text[end - 1];
      if (_trailingPunctuation.contains(last)) {
        end--;
        continue;
      }
      final opening = _closingToOpening[last];
      if (opening != null) {
        final token = text.substring(start, end);
        final opens = opening.allMatches(token).length;
        final closes = last.allMatches(token).length;
        if (closes > opens) {
          end--;
          continue;
        }
      }
      break;
    }
    return end;
  }
}

/// 한 논리 줄(소프트 랩으로 이어진 행 전체)을 이 이상 위아래로 읽지 않는다.
/// 수천 행짜리 한 줄(압축된 JSON 등)에서도 더블클릭이 바로 반응하게 한다.
const _maxWrappedRows = 64;

/// [cell]에서 더블클릭·롱프레스로 고를 범위. 소프트 랩으로 여러 행에 걸친
/// URL도 한 범위로 돌려준다. 고를 것이 없으면 null(기본 단어 경계로 처리).
BufferRangeLine? selectSmartWord(Buffer buffer, CellOffset cell) {
  final lines = buffer.lines;
  if (cell.y < 0 || cell.y >= lines.length) return null;

  var first = cell.y;
  while (first > 0 &&
      cell.y - first < _maxWrappedRows &&
      lines[first].isWrapped) {
    first--;
  }
  var last = cell.y;
  while (last + 1 < lines.length &&
      last - cell.y < _maxWrappedRows &&
      lines[last + 1].isWrapped) {
    last++;
  }

  final text = StringBuffer();
  // 문자열의 UTF-16 코드 단위마다 그 글자가 놓인 셀.
  final cells = <CellOffset>[];
  int? clickIndex;
  for (var y = first; y <= last; y++) {
    final line = lines[y];
    final width = min(line.length, buffer.viewWidth);
    for (var x = 0; x < width; x++) {
      final codePoint = line.getCodePoint(x);
      // 넓은 글자(한글 등)의 둘째 셀은 내용 없이 앞 셀에 딸려 있다.
      if (codePoint == 0 && x > 0 && line.getWidth(x - 1) == 2) {
        if (y == cell.y && x == cell.x) clickIndex = cells.length - 1;
        continue;
      }
      final char = codePoint == 0 ? ' ' : String.fromCharCode(codePoint);
      if (y == cell.y && x == cell.x) clickIndex = cells.length;
      text.write(char);
      for (var i = 0; i < char.length; i++) {
        cells.add(CellOffset(x, y));
      }
    }
  }
  final index = clickIndex;
  if (index == null || index < 0) return null;

  final range = SmartWordFinder.find(text.toString(), index);
  if (range == null) return null;
  final (start, end) = range;
  final lastCell = cells[end - 1];
  final lastWidth = lines[lastCell.y].getWidth(lastCell.x);
  return BufferRangeLine(
    cells[start],
    CellOffset(lastCell.x + (lastWidth > 1 ? lastWidth : 1), lastCell.y),
  );
}
