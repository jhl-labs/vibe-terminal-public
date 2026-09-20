/// 메모 버전 히스토리용 줄 단위 diff. 외부 패키지 없이 LCS로 계산한다.
/// 메모는 수백 줄 수준이라 O(n·m) 메모리로 충분하다.
enum DiffKind { equal, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text);
  final DiffKind kind;
  final String text;
}

/// [oldText]에서 [newText]로의 변경을 줄 단위로 나열한다. 빈 문자열은 줄이
/// 없는 것으로 본다(끝의 개행은 빈 줄로 세지 않는다).
List<DiffLine> diffLines(String oldText, String newText) {
  final a = _split(oldText);
  final b = _split(newText);
  final n = a.length, m = b.length;
  // lcs[i][j] = a[i..]와 b[j..]의 LCS 길이
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffKind.equal, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(DiffLine(DiffKind.removed, a[i++]));
    } else {
      out.add(DiffLine(DiffKind.added, b[j++]));
    }
  }
  while (i < n) {
    out.add(DiffLine(DiffKind.removed, a[i++]));
  }
  while (j < m) {
    out.add(DiffLine(DiffKind.added, b[j++]));
  }
  return out;
}

List<String> _split(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}
