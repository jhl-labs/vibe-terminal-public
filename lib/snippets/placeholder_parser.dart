/// 스니펫 본문의 `{{name}}` 플레이스홀더를 추출·치환한다.
class PlaceholderParser {
  PlaceholderParser._();

  static final RegExp _pattern = RegExp(r'\{\{(\w+)\}\}');

  /// `{{name}}` 안의 이름을 등장 순서대로, 중복 제거하여 반환.
  static List<String> extract(String body) {
    final seen = <String>{};
    final result = <String>[];
    for (final m in _pattern.allMatches(body)) {
      final name = m.group(1)!;
      if (seen.add(name)) result.add(name);
    }
    return result;
  }

  /// `{{name}}`를 values[name]로 치환. 값이 없으면 빈 문자열.
  static String substitute(String body, Map<String, String> values) {
    return body.replaceAllMapped(_pattern, (m) => values[m.group(1)!] ?? '');
  }
}
