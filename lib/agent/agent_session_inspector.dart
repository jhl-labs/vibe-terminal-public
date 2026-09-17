/// 터미널 화면에서 CLI agent의 정체와 사용자에게 보여 줄 미리보기를 추출한다.
///
/// 오케스트레이터와 세션 선택 UI가 같은 판별 규칙을 사용하도록 Flutter에 의존하지
/// 않는 순수 도메인 서비스로 둔다.
enum AgentDetectionConfidence { none, possible, confirmed }

class AgentSessionInspection {
  const AgentSessionInspection({
    required this.agentHint,
    required this.confidence,
    required this.preview,
  });

  final String agentHint;
  final AgentDetectionConfidence confidence;
  final String preview;

  bool get isConfirmedAgent => confidence == AgentDetectionConfidence.confirmed;
  bool get isPossibleAgent => confidence != AgentDetectionConfidence.none;
}

class AgentSessionInspector {
  const AgentSessionInspector._();

  static final List<(RegExp, String)> _confirmedPatterns = [
    (
      RegExp(
        r'\bclaude\s+code\b|\banthropic\s+claude\b|'
        // 실행 커맨드와 종료 안내는 배너가 사라진 뒤에도 자주 남는다.
        r'welcome\s+to\s+claude|\bclaude\s+--\w|/help\s+for\s+help',
      ),
      'claude',
    ),
    (
      RegExp(
        r'\bopenai\s+codex\b|\bcodex\s+cli\b|'
        r'welcome\s+to\s+codex|\bcodex\s+resume\b|\bcodex\s+exec\b|'
        r'\bcodex\s+--\w|\bcodex\s+v\d',
      ),
      'codex',
    ),
    (RegExp(r'\bgemini\s+cli\b|\bgoogle\s+gemini\b|\bgemini\s+--\w'), 'gemini'),
    (RegExp(r'\bopencode\b'), 'opencode'),
    (RegExp(r'\baider\s+(chat|v?\d)'), 'aider'),
    (RegExp(r'\bfactory\s+droid\b|\bdroid\s+cli\b'), 'droid'),
    (RegExp(r'\bsourcegraph\s+amp\b|\bamp\s+code\b'), 'amp'),
    (RegExp(r'\bgrok\s+cli\b'), 'grok'),
    (RegExp(r'\bhermes\s+agent\b'), 'hermes'),
    (RegExp(r'\bcursor\s+agent\b'), 'cursor'),
    (RegExp(r'\bantigravity\s+cli\b'), 'antigravity'),
    (RegExp(r'\bkimi\s+(?:code\s+)?cli\b'), 'kimi'),
    (RegExp(r'\bgithub\s+copilot\s+cli\b'), 'copilot'),
    (RegExp(r'\bkiro\s+cli\b'), 'kiro'),
    (RegExp(r'\bqodercli\b|\bqoder\s+cli\b'), 'qoder'),
  ];

  /// 대화가 길어져 시작 배너가 스크롤백 밖으로 밀려난 뒤에도 화면 하단에 계속
  /// 남는 TUI 고정 문구. 다른 CLI에는 없는 문구만 확정 근거로 삼는다.
  static final List<(RegExp, String)> _chromePatterns = [
    (
      RegExp(
        r'shift\+tab to cycle|accept edits on\b|plan mode on\b|'
        r'bypass permissions on\b|auto-accept edits',
      ),
      'claude',
    ),
  ];

  /// 여러 Agent TUI가 공유하는 고정 문구. 어떤 Agent인지는 모르지만 일반 셸
  /// 출력에는 나오지 않으므로 'agent'로 느슨하게 판별한다.
  static final RegExp _genericChromePattern = RegExp(
    r'\? for shortcuts|esc to interrupt|context left\b',
  );

  /// Claude Code가 터미널 제목 앞에 붙이는 글리프. 제목이 대화 요약으로 바뀌면
  /// 'claude'라는 단어가 사라지므로 이 접두어로 알아본다.
  static final RegExp _claudeTitleGlyph = RegExp(r'^[✳✶✻✽✢]\s');

  static final List<(RegExp, String)> _possiblePatterns = [
    (RegExp(r'\bclaude\b'), 'claude'),
    (RegExp(r'\bcodex\b'), 'codex'),
    (RegExp(r'\bgemini\b'), 'gemini'),
    (RegExp(r'\baider\b'), 'aider'),
    (RegExp(r'\bdroid\b'), 'droid'),
    (RegExp(r'\bamp\b'), 'amp'),
    (RegExp(r'\bgrok\b'), 'grok'),
    (RegExp(r'\bhermes\b'), 'hermes'),
    (RegExp(r'\bcursor\b'), 'cursor'),
    (RegExp(r'\bantigravity\b'), 'antigravity'),
    (RegExp(r'\bkimi\b'), 'kimi'),
    (RegExp(r'\bcopilot\b'), 'copilot'),
    (RegExp(r'\bkiro\b'), 'kiro'),
    (RegExp(r'\bqoder\b'), 'qoder'),
  ];

  static AgentSessionInspection inspect(String screen, {int previewLines = 3}) {
    final lines = _normalizedLines(screen);
    final recent = lines.length <= 60
        ? lines
        : lines.sublist(lines.length - 60);
    final searchable = recent.join('\n').toLowerCase();
    // 확정 패턴은 화면 전체에서 찾는다. agent의 시작 배너는 대화가 길어지면
    // 최근 60줄 밖으로 밀려나는데, 그때마다 unknown으로 떨어지면 안 된다.
    // 반면 느슨한 패턴은 최근 화면에서만 본다 — 지나간 출력에 우연히 들어간
    // 단어까지 주워 담으면 엉뚱한 agent로 오인한다.
    final fullText = lines.join('\n').toLowerCase();

    for (final (pattern, hint) in _confirmedPatterns) {
      if (pattern.hasMatch(fullText)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.confirmed,
          preview: _preview(lines, previewLines),
        );
      }
    }
    // 고정 문구는 화면 하단에 있으므로 최근 줄만 본다. 지나간 대화 안의
    // 인용문(예: 문서에 적힌 "esc to interrupt")까지 근거로 삼지 않는다.
    for (final (pattern, hint) in _chromePatterns) {
      if (pattern.hasMatch(searchable)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.confirmed,
          preview: _preview(lines, previewLines),
        );
      }
    }
    for (final (pattern, hint) in _possiblePatterns) {
      if (pattern.hasMatch(searchable)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.possible,
          preview: _preview(lines, previewLines),
        );
      }
    }
    if (_genericChromePattern.hasMatch(searchable)) {
      return AgentSessionInspection(
        agentHint: 'agent',
        confidence: AgentDetectionConfidence.possible,
        preview: _preview(lines, previewLines),
      );
    }
    return AgentSessionInspection(
      agentHint: 'unknown',
      confidence: AgentDetectionConfidence.none,
      preview: _preview(lines, previewLines),
    );
  }

  /// 터미널 제목(OSC 0/2)에서 Agent를 판별한다.
  ///
  /// Claude Code는 "✳ Claude Code" 또는 "✳ <대화 요약>"으로, 다른 CLI는 제품명을
  /// 제목에 쓴다. 화면 문구와 달리 스크롤로 사라지지 않고, 셸이 제목을 되찾으면
  /// Agent가 끝났다는 신호도 된다. 셸 제목에는 작업 디렉터리가 들어가므로
  /// (`user@host: ~/claude-notes`) 느슨한 단어 일치는 쓰지 않는다.
  static AgentSessionInspection inspectTitle(String title) {
    final trimmed = title.trim();
    final lower = trimmed.toLowerCase();
    for (final (pattern, hint) in _confirmedPatterns) {
      if (pattern.hasMatch(lower)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.confirmed,
          preview: trimmed,
        );
      }
    }
    // 제목 전체가 제품명이면(TUI가 직접 설정, tmux 자동 이름) 그 Agent다.
    for (final (pattern, hint) in _possiblePatterns) {
      if (RegExp('^${pattern.pattern}\$').hasMatch(lower)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.confirmed,
          preview: trimmed,
        );
      }
    }
    if (_claudeTitleGlyph.hasMatch(trimmed)) {
      return AgentSessionInspection(
        agentHint: 'claude',
        confidence: AgentDetectionConfidence.possible,
        preview: trimmed,
      );
    }
    return AgentSessionInspection(
      agentHint: 'unknown',
      confidence: AgentDetectionConfidence.none,
      preview: trimmed,
    );
  }

  static List<String> _normalizedLines(String screen) => screen
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);

  static String _preview(List<String> lines, int maxLines) {
    if (lines.isEmpty) return '(화면 내용 없음)';
    final safeMax = maxLines.clamp(1, 6);
    final start = lines.length > safeMax ? lines.length - safeMax : 0;
    return lines.sublist(start).map(_truncateLine).join('\n');
  }

  static String _truncateLine(String line) {
    const maxCharacters = 180;
    if (line.length <= maxCharacters) return line;
    return '${line.substring(0, maxCharacters - 3)}...';
  }
}
