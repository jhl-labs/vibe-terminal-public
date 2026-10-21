/// 두 터미널 화면 사이에서 새로 추가되거나 변경된 줄을 추출한다.
///
/// 터미널 스크롤백은 최대 줄 수에 도달하면 앞부분이 사라지므로 단순 접두 비교로는
/// 화면 전체가 새 출력처럼 보인다. 먼저 이전 화면의 suffix와 현재 화면의 prefix가
/// 겹치는지 찾고, 겹치지 않으면 line 기반 LCS로 현재 화면의 추가/변경 줄만 남긴다.
class TerminalScreenDelta {
  const TerminalScreenDelta._();

  static String compute(String before, String after) {
    final previous = _lines(before);
    final current = _lines(after);

    if (_same(previous, current)) return '(변화 없음)';
    if (current.isEmpty) return '(화면이 비워짐)';
    if (previous.isEmpty) return current.join('\n').trim();

    final overlap = _suffixPrefixOverlap(previous, current);
    if (overlap > 0) {
      final appended = current.sublist(overlap);
      if (appended.isNotEmpty) return appended.join('\n').trim();
    }

    final added = _addedLinesFromLcs(previous, current);
    if (added.isEmpty) return '(화면이 갱신됨)';
    return added.join('\n').trim();
  }

  static List<String> _lines(String value) {
    final lines = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .toList();
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  static bool _same(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  static int _suffixPrefixOverlap(List<String> previous, List<String> current) {
    final max = previous.length < current.length
        ? previous.length
        : current.length;
    for (var length = max; length > 0; length--) {
      var matches = true;
      final previousStart = previous.length - length;
      for (var i = 0; i < length; i++) {
        if (previous[previousStart + i] != current[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return length;
    }
    return 0;
  }

  static List<String> _addedLinesFromLcs(
    List<String> previous,
    List<String> current,
  ) {
    final lengths = List.generate(
      previous.length + 1,
      (_) => List<int>.filled(current.length + 1, 0),
    );
    for (var i = previous.length - 1; i >= 0; i--) {
      for (var j = current.length - 1; j >= 0; j--) {
        lengths[i][j] = previous[i] == current[j]
            ? lengths[i + 1][j + 1] + 1
            : _max(lengths[i + 1][j], lengths[i][j + 1]);
      }
    }

    final added = <String>[];
    var previousIndex = 0;
    var currentIndex = 0;
    while (previousIndex < previous.length && currentIndex < current.length) {
      if (previous[previousIndex] == current[currentIndex]) {
        previousIndex++;
        currentIndex++;
      } else if (lengths[previousIndex + 1][currentIndex] >=
          lengths[previousIndex][currentIndex + 1]) {
        previousIndex++;
      } else {
        added.add(current[currentIndex]);
        currentIndex++;
      }
    }
    added.addAll(current.skip(currentIndex));
    return added;
  }

  static int _max(int first, int second) => first > second ? first : second;
}
