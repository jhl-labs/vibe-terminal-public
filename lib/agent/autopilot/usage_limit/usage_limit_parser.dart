/// 사용량 한도 감지 결과. [resetAt]은 로컬 시각, 못 읽으면 null.
class UsageLimitHit {
  const UsageLimitHit({required this.evidence, required this.resetAt});

  final String evidence;
  final DateTime? resetAt;
}

/// claude·codex·opencode의 사용량 한도 문구와 리셋 시각을 해석한다. 순수 함수.
///
/// 자율사용이 보낸 마지막 재개 문구 이후만 본다. 재개가 성공해 짧은 응답만
/// 나오면 이전 한도 문구가 화면 꼬리에 남는데, 이를 새 한도로 오인하지 않기 위해서다.
/// 같은 이유로 공지 뒤에 새 Agent 출력 줄(●·⏺·• 글머리)이 있으면 지난 공지로 본다
/// (사용자가 직접 이어간 경우). 공지 뒤에는 입력창·상태 표시줄만 올 수 있다.
class UsageLimitParser {
  const UsageLimitParser();

  static const resumeMarker = '계속 진행해';
  static const _window = 16;

  /// 줄 앞의 TUI 장식(●, ⎿, │, ┃, >, ❯, ›, ■, ⚠ 등)과 공백. 이 뒤에서 공지가 시작해야 한다.
  static final _leadingGlyphs = RegExp(r'^[\s●⎿│┃>❯›■✗✘✖⚠•!⏺⎯]+');

  /// 장식 뒤에 붙는 선택적 `Error:` 접두.
  static final _errorPrefix = RegExp(r'^error:\s*', caseSensitive: false);

  /// 인용부호·diff 표지(+/-)로 시작하는 줄은 코드·테스트·diff 인용이다.
  static final _quotedOrDiff = RegExp(r'''^[+\-'"`]''');

  static final _resetCue = RegExp(
    r'resets?\b|reset at|try again',
    caseSensitive: false,
  );

  /// 줄 맨 앞에서 시작해야 하는 공지.
  static final _anchoredPatterns = <RegExp>[
    RegExp(
      r'^(?:claude )?usage limit (?:has been )?(?:reached|exceeded)',
      caseSensitive: false,
    ),
    RegExp(r"^you(?:'|’)ve hit your usage limit", caseSensitive: false),
  ];

  /// 리셋/재시도 단서가 같은 줄에 있어야 하는 일반 `limit reached` 공지.
  static final _genericLimit = RegExp(
    r'^(?:\d+-hour |weekly |opus |session |usage |claude usage )?limit reached',
    caseSensitive: false,
  );

  /// 공지가 줄바꿈돼 다음 줄 맨 앞에서 시작하는 뒷부분. 산문 속 문구(`the API
  /// limit will reset ...`)를 공지로 오인하지 않도록 줄 맨 앞만 본다.
  static final _continuationPatterns = <RegExp>[
    RegExp(r'^(?:your )?(?:usage )?limit will reset\b', caseSensitive: false),
    RegExp(
      r'^(?:(?:purchase|buy|add) (?:more )?)?credits? or try again at',
      caseSensitive: false,
    ),
  ];

  /// 새 Agent 응답의 글머리(claude ●·⏺, codex •). 공지 뒤에 있으면 지난 공지다.
  static final _agentOutputLine = RegExp(r'^\s*[●⏺•]\s*\S');

  static final _clock = RegExp(
    r'(?:resets?(?:\s+at)?|try again at)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b'
    r'(?:\s*\(([^)]+)\))?',
    caseSensitive: false,
  );
  static final _duration = RegExp(
    r'try again in\s+(?:(\d+)\s*h(?:ours?)?\b)?\s*(?:(\d+)\s*m(?:in(?:ute)?s?)?\b)?',
    caseSensitive: false,
  );

  /// 리셋 시각을 찾는 범위: 한도 줄 + 다음 2줄.
  static const _resetSearchLines = 3;

  /// [screen]에서 [evidence]와 같은 공지 줄이 몇 번 보이는지. 사용자가 직접
  /// 이어간 시점의 공지를 기억해 두고, 같은 공지가 새로 더 뜬 경우만 새 한도로 본다.
  static int occurrences(String screen, String evidence) => screen
      .replaceAll('\r', '')
      .split('\n')
      .where((line) => line.trim() == evidence)
      .length;

  static bool isUsageLimitLine(String line) {
    final text = line
        .replaceFirst(_leadingGlyphs, '')
        .replaceFirst(_errorPrefix, '');
    if (text.isEmpty || _quotedOrDiff.hasMatch(text)) return false;
    if (_anchoredPatterns.any((p) => p.hasMatch(text))) return true;
    if (_genericLimit.hasMatch(text) && _resetCue.hasMatch(text)) return true;
    return _continuationPatterns.any((p) => p.hasMatch(text));
  }

  UsageLimitHit? detect(String screen, {required DateTime now}) {
    var lines = screen.replaceAll('\r', '').split('\n');
    final marker = lines.lastIndexWhere((l) => l.contains(resumeMarker));
    if (marker >= 0) lines = lines.sublist(marker + 1);
    if (lines.length > _window) lines = lines.sublist(lines.length - _window);
    final index = lines.lastIndexWhere(isUsageLimitLine);
    if (index < 0) return null;
    if (lines.skip(index + 1).any(_agentOutputLine.hasMatch)) return null;
    final end = (index + _resetSearchLines).clamp(0, lines.length);
    final text = lines.sublist(index, end).join(' ');
    return UsageLimitHit(
      evidence: lines[index].trim(),
      resetAt: _clockReset(text, now) ?? _durationReset(text, now),
    );
  }

  static DateTime? _clockReset(String text, DateTime now) {
    final m = _clock.firstMatch(text);
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.tryParse(m.group(2) ?? '') ?? 0;
    if (hour < 1 || hour > 12 || minute > 59) return null;
    final pm = m.group(3)!.toLowerCase() == 'pm';
    hour = hour % 12 + (pm ? 12 : 0); // 12am → 0, 12pm → 12
    final zone = m.group(4)?.trim().toUpperCase();
    DateTime candidate;
    if (zone == 'UTC' || zone == 'GMT') {
      final utcNow = now.toUtc();
      candidate = DateTime.utc(
        utcNow.year,
        utcNow.month,
        utcNow.day,
        hour,
        minute,
      ).toLocal();
    } else {
      // 지역 타임존 이름(Asia/Seoul 등)은 tz DB 없이 변환할 수 없으므로 로컬로 본다.
      candidate = DateTime(now.year, now.month, now.day, hour, minute);
    }
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  static DateTime? _durationReset(String text, DateTime now) {
    final m = _duration.firstMatch(text);
    if (m == null) return null;
    final hours = int.tryParse(m.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(m.group(2) ?? '') ?? 0;
    if (hours == 0 && minutes == 0) return null;
    return now.add(Duration(hours: hours, minutes: minutes));
  }
}
