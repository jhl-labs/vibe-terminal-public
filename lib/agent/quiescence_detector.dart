/// CLI 에이전트 세션의 "턴 종료(작업 완료로 조용해짐)"를 화면 스냅샷 안정화로
/// 감지한다.
///
/// claude/codex 등은 작업 중 스피너와 경과 시간을 계속 다시 그리므로, 단순
/// "출력 없음" 기준으로는 완료를 판정할 수 없다. 스피너/진행률 줄을 정규화로
/// 제거한 뒤 화면 텍스트가 [stabilityWindow] 동안 변하지 않으면 quiescent로
/// 본다. 단, 작업 중 신호가 있으면 안정화나 프롬프트보다 우선해 완료를 막는다.
///
/// 순수 Dart. 시간은 호출자가 [pushSnapshot]을 부르는 주기로 표현한다
/// (테스트에서 fake 시계로 제어).
class QuiescenceDetector {
  QuiescenceDetector({
    this.pollInterval = const Duration(milliseconds: 750),
    this.stabilityWindow = const Duration(milliseconds: 2500),
  });

  /// pushSnapshot 호출 사이의 간격(안정 시간 누적에 사용).
  final Duration pollInterval;

  /// 이만큼 화면이 안정되면 quiescent.
  final Duration stabilityWindow;

  String? _lastHash;
  Duration _stableFor = Duration.zero;
  bool _promptSeen = false;
  bool _working = false;

  /// 마지막으로 안정된 시간(디버깅/표시용).
  Duration get stableFor => _stableFor;

  /// 새 화면 스냅샷을 밀어 넣는다. [busy]는 SessionActivityTracker 등의 보조
  /// 신호다. 작업 중이면 안정 시간을 누적하지 않는다.
  void pushSnapshot(String screen, {bool busy = true}) {
    _working = busy || hasWorkingIndicator(screen);
    if (_working) {
      _lastHash = null;
      _stableFor = Duration.zero;
      _promptSeen = false;
      return;
    }
    final normalized = normalize(screen);
    _promptSeen = _endsWithPrompt(normalized);
    final hash = normalized.hashCode;
    if (_lastHash == null) {
      _lastHash = hash.toString();
      _stableFor = Duration.zero;
      return;
    }
    if (hash.toString() == _lastHash) {
      _stableFor += pollInterval;
    } else {
      _lastHash = hash.toString();
      _stableFor = Duration.zero;
    }
  }

  /// 현재 quiescent인지. 프롬프트가 보이면 즉시 true.
  bool get isQuiescent =>
      !_working && (_promptSeen || _stableFor >= stabilityWindow);

  void reset() {
    _lastHash = null;
    _stableFor = Duration.zero;
    _promptSeen = false;
    _working = false;
  }

  /// 정규화 전에 최근 상태 줄의 중단 안내를 확인한다. OpenCode의 입력창은
  /// 작업 중에도 표시되므로 입력창 존재만으로 완료를 판정해서는 안 된다.
  static bool hasWorkingIndicator(String screen) {
    final lines = screen
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final tail = lines.skip(lines.length > 8 ? lines.length - 8 : 0).join('\n');
    return RegExp(
      r'\besc(?:ape)?\s+(?:(?:to|again to)\s+)?(?:interrupt|cancel|stop)\b',
      caseSensitive: false,
    ).hasMatch(tail);
  }

  // --- 정규화 ---

  static final _spinnerGlyphs = RegExp(r'[⠀-⣿⣾⣽⣻⢿⡿⣟⣯⣷]');
  static final _asciiSpinner = RegExp(r'^[\s]*[-\\|/][\s]*$');
  static final _elapsed = RegExp(
    r'\(?\b\d+(\.\d+)?\s*(s|sec|secs|seconds|m|min|ms)\b\)?',
    caseSensitive: false,
  );
  static final _elapsedWord = RegExp(
    r'\belapsed\b|\btokens?\b|\besc to interrupt\b',
    caseSensitive: false,
  );
  static final _percent = RegExp(r'\b\d{1,3}\s*%');
  static final _trailingWs = RegExp(r'[ \t]+$', multiLine: true);

  /// 스피너/경과시간/진행률 등 "작업 중에도 계속 바뀌는" 요소를 제거해,
  /// 실질 텍스트 변화만 남긴다.
  static String normalize(String screen) {
    final lines = screen.split('\n');
    final kept = <String>[];
    for (final line in lines) {
      var l = line.replaceAll(_trailingWs, '');
      if (_asciiSpinner.hasMatch(l)) continue;
      final hasSpinner = _spinnerGlyphs.hasMatch(l);
      final hasElapsed = _elapsed.hasMatch(l) || _elapsedWord.hasMatch(l);
      final hasPercent = _percent.hasMatch(l);
      if (hasSpinner || hasElapsed || hasPercent) {
        // 변동 요소가 있는 줄은 그 요소만 지우고 나머지 텍스트는 유지한다.
        l = l
            .replaceAll(_spinnerGlyphs, '')
            .replaceAll(_elapsed, '')
            .replaceAll(_percent, '')
            .replaceAll(_trailingWs, '')
            .trimRight();
        if (l.trim().isEmpty) continue;
      }
      kept.add(l);
    }
    return kept.join('\n').trimRight();
  }

  static final _promptPatterns = [
    RegExp(r'[❯➜\$#>]\s*$'),
    RegExp(r'\(y/n\)\s*$', caseSensitive: false),
    RegExp(r'\(Y/n\)\s*$'),
    RegExp(r'\[y/N\]\s*$', caseSensitive: false),
    RegExp(r'\? for shortcuts\s*$', caseSensitive: false),
    RegExp(r'press enter\b', caseSensitive: false),
  ];

  static bool _endsWithPrompt(String normalized) {
    if (normalized.isEmpty) return false;
    final lines = normalized.split('\n');
    // 마지막 비어있지 않은 줄을 검사.
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trimRight();
      if (line.isEmpty) continue;
      for (final pattern in _promptPatterns) {
        if (pattern.hasMatch(line)) return true;
      }
      return false;
    }
    return false;
  }
}
