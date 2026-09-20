import 'dart:convert';

/// 모델이 세션 로그를 더 보고 싶을 때 답변에 넣는 요청.
///
/// 4개 provider 모두 function calling 없이 동작하도록, `terminal` 코드블록과
/// 같은 방식의 fenced block 프로토콜을 쓴다:
///
/// ```session-log
/// {"lines": 2000, "grep": "claude"}
/// ```
class SessionLogRequest {
  const SessionLogRequest({this.lines = defaultLines, this.grep});

  static const fenceLanguage = 'session-log';
  static const defaultLines = 2000;
  static const minLines = 100;

  /// 저장소가 평문으로 돌려주는 최대 줄 수(`_maxPlainTextLines`)와 같다.
  static const maxLines = 5000;

  /// grep 매치 앞뒤로 함께 남기는 줄 수.
  static const grepContextLines = 1;

  /// 로그 끝에서 읽을 최대 줄 수.
  final int lines;

  /// 있으면 대소문자 무시 부분 문자열로 줄을 추려 낸다.
  final String? grep;

  static final _fence = RegExp(
    '```$fenceLanguage[ \\t]*\\n([\\s\\S]*?)\\n?```',
    multiLine: true,
  );

  static SessionLogRequest? tryParse(String reply) {
    final match = _fence.firstMatch(reply);
    if (match == null) return null;
    final body = (match.group(1) ?? '').trim();
    var lines = defaultLines;
    String? grep;
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final rawLines = decoded['lines'];
          if (rawLines is num) lines = rawLines.round();
          final rawGrep = decoded['grep'];
          if (rawGrep is String && rawGrep.trim().isNotEmpty) {
            grep = rawGrep.trim();
          }
        }
      } on FormatException {
        // 본문이 JSON이 아니면 기본값으로 로그 tail만 붙인다.
      }
    }
    return SessionLogRequest(
      lines: lines.clamp(minLines, maxLines).toInt(),
      grep: grep,
    );
  }

  /// 읽어 온 로그 tail에 이 요청을 적용한다.
  ///
  /// grep이 없으면 마지막 [lines]줄, 있으면 매치 줄과 앞뒤
  /// [grepContextLines]줄만 남기고 끊긴 구간은 `...`으로 표시한다.
  String filter(String logText) {
    final all = logText.split('\n');
    final tail = all.length > lines ? all.sublist(all.length - lines) : all;
    final needle = grep?.toLowerCase();
    if (needle == null) return tail.join('\n');

    final keep = List<bool>.filled(tail.length, false);
    for (var i = 0; i < tail.length; i += 1) {
      if (!tail[i].toLowerCase().contains(needle)) continue;
      final start = (i - grepContextLines).clamp(0, tail.length - 1);
      final end = (i + grepContextLines).clamp(0, tail.length - 1);
      for (var j = start; j <= end; j += 1) {
        keep[j] = true;
      }
    }
    final out = <String>[];
    var skipping = false;
    for (var i = 0; i < tail.length; i += 1) {
      if (keep[i]) {
        out.add(tail[i]);
        skipping = false;
      } else if (!skipping) {
        out.add('...');
        skipping = true;
      }
    }
    return out.join('\n');
  }

  String get description =>
      grep == null ? '마지막 $lines줄' : '마지막 $lines줄 중 "$grep" 포함 구간';
}
