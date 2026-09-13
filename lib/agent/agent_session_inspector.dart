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
    for (final (pattern, hint) in _possiblePatterns) {
      if (pattern.hasMatch(searchable)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.possible,
          preview: _preview(lines, previewLines),
        );
      }
    }
    return AgentSessionInspection(
      agentHint: 'unknown',
      confidence: AgentDetectionConfidence.none,
      preview: _preview(lines, previewLines),
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
