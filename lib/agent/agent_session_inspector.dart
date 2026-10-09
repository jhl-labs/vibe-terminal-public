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
    this.modelHint,
    this.modelConfidence = AgentDetectionConfidence.none,
  });

  final String agentHint;
  final AgentDetectionConfidence confidence;
  final String preview;

  /// 화면에서 감지한 모델 라벨(소문자 정규화). CLI 종류와 무관하게 일반 규칙으로 찾는다.
  final String? modelHint;
  final AgentDetectionConfidence modelConfidence;

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
        r'welcome\s+to\s+claude|\bclaude\s+--\w',
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
    // 제품명 단독(`opencode`)은 확정 근거로 쓰지 않는다. 다른 Agent 안에서
    // OpenCode 설정 파일·경로를 다루기만 해도 화면에 흔히 나오기 때문이다.
    (
      RegExp(
        r'welcome\s+to\s+opencode|\bopencode\s+v?\d|\bopencode\s+--\w|'
        r'\bopencode\s+(?:run|serve|auth|models)\b',
      ),
      'opencode',
    ),
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
    (
      RegExp(r'vim\s+-\s+vi\s+improved|--\s*insert\s*--|--\s*visual\s*--'),
      'vim',
    ),
    (
      RegExp(
        r'\bsepilot(?:\s+cli)?(?:\s*[·|]\s*|\s+)v\d|welcome\s+to\s+sepilot|\bsepilotd\b',
      ),
      'sepilot',
    ),
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
    (RegExp(r'\bopencode\b'), 'opencode'),
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
    (RegExp(r'\bvim\b'), 'vim'),
    (RegExp(r'\bsepilot\b'), 'sepilot'),
  ];

  // 모델 라벨 감지: 특정 벤더에 종속되지 않은 일반 표기 규칙.
  //
  // usesCapture가 true면 group(1)(명시적 대입/플래그 형태)을, false면 전체
  // 일치(known id shape)를 라벨로 쓴다. 순서를 바꿔도 안전하도록 위치(i==0/1/2)
  // 대신 각 패턴에 직접 표시해 둔다.
  static final List<(RegExp pattern, bool usesCapture)>
  _confirmedModelPatterns = [
    // {1,}: "o3"처럼 두 글자짜리 알려진 id도 model: 뒤에서 잡아낸다({2,}이면
    // 최소 3글자가 필요해 o1~o9 같은 짧은 id를 놓친다).
    (RegExp(r'\bmodel[:=\s]+([\w][\w.\-/:]{1,})', caseSensitive: false), true),
    (RegExp(r'/model\s+(\S+)', caseSensitive: false), true),
    (RegExp(r'--model[= ]([\w.\-/:]+)', caseSensitive: false), true),
    (RegExp(r'\bclaude-[\w.-]+', caseSensitive: false), false),
    (RegExp(r'\bgpt-[\w.-]+', caseSensitive: false), false),
    (RegExp(r'\bgemini-[\w.-]+', caseSensitive: false), false),
    (RegExp(r'\bcodex-[\w.-]+', caseSensitive: false), false),
    // llama/qwen/deepseek은 패밀리 단어만으로는 "llamas", "qwentin" 같은
    // 평문과 구분이 안 된다. 숫자(버전)가 뒤따를 때만 confirmed로 인정하고,
    // 숫자 없는 단독 등장은 _possibleModelPatterns로 possible 처리한다.
    (
      RegExp(
        r'\b(?:llama|qwen|deepseek)(?:[\w.-]*\d[\w.-]*)\b',
        caseSensitive: false,
      ),
      false,
    ),
    (
      RegExp(
        r'\b(?:Opus|Sonnet|Haiku|Fable)\s*\d(?:\.\d)?\b',
        caseSensitive: false,
      ),
      false,
    ),
  ];

  static const List<String> _modelFamilyWords = [
    'opus',
    'sonnet',
    'haiku',
    'fable',
    'gpt',
    'gemini',
    'qwen',
    'deepseek',
    'llama',
    'mistral',
    'grok',
  ];

  static final List<RegExp> _possibleModelPatterns = [
    for (final word in _modelFamilyWords) _familyWordPattern(word),
  ];

  static RegExp _familyWordPattern(String word) =>
      RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false);

  /// 선언된 모델에서 뽑은 패밀리 단어가 버전 숫자를 달고 나타나는 형태.
  /// 내장 llama/qwen/deepseek 규칙과 같은 근거로 confirmed로 인정한다.
  static RegExp _familyWithVersionPattern(String word) => RegExp(
    '\\b${RegExp.escape(word)}(?:[\\w.-]*\\d[\\w.-]*)\\b',
    caseSensitive: false,
  );

  /// 선언된 모델 라벨에서 패밀리 후보 단어를 뽑는다.
  ///
  /// `openai/gpt-5`, `claude-opus-4-1`처럼 구분자가 섞인 식별자를 `/`, `-`,
  /// `:`로 쪼개고, 너무 짧아 평문과 구분이 안 되는 토큰(2자 이하)과 순수
  /// 숫자는 버린다.
  static Set<String> familyWordsFrom(Iterable<String> declaredModels) {
    final words = <String>{};
    for (final model in declaredModels) {
      for (final token in model.toLowerCase().split(RegExp(r'[/:\-]'))) {
        final trimmed = token.trim();
        if (trimmed.length < 3) continue;
        if (RegExp(r'^\d+$').hasMatch(trimmed)) continue;
        words.add(trimmed);
      }
    }
    return words;
  }

  /// 화면 텍스트에서 모델 라벨을 감지한다. CLI 종류와 무관한 일반 규칙만 사용한다.
  ///
  /// confirmed는 명시적 모델 표기(`model: xxx`, `/model xxx`, `--model xxx`,
  /// 또는 알려진 모델 id 형태)에서 나오며, 같은 확신도 안에서는 화면 아래쪽(마지막
  /// 발견 위치)의 값을 우선한다 — 상태 표시줄은 보통 하단에 있기 때문이다.
  /// possible은 패밀리 단어 단독 등장이며 인벤토리에는 노출하지 않고 UI 힌트로만 쓴다.
  /// [extraFamilies]는 사용자가 역할에 선언한 모델에서 뽑은 패밀리 단어다.
  /// 내장 목록에 없는 사내·자체 호스팅 모델 이름도 같은 규칙으로 잡아내려고
  /// 받는다. 단독 등장은 possible, 버전 숫자가 붙으면 confirmed다.
  static (String?, AgentDetectionConfidence) detectModel(
    String screen, {
    Iterable<String> extraFamilies = const [],
  }) {
    final lines = _normalizedLines(screen);
    final fullText = lines.join('\n');
    final extras = <String>{
      for (final word in extraFamilies)
        if (word.trim().length >= 3 &&
            !_modelFamilyWords.contains(word.trim().toLowerCase()))
          word.trim().toLowerCase(),
    };

    String? bestLabel;
    int bestStart = -1;
    for (final word in extras) {
      for (final match in _familyWithVersionPattern(
        word,
      ).allMatches(fullText)) {
        if (match.start > bestStart) {
          bestStart = match.start;
          bestLabel = match.group(0)!;
        }
      }
    }
    for (final (pattern, usesCapture) in _confirmedModelPatterns) {
      for (final match in pattern.allMatches(fullText)) {
        String label;
        if (usesCapture) {
          final captured = match.group(1);
          if (captured == null) continue;
          if (!_looksLikeModelToken(captured)) {
            // 오탐 방지: 숫자/대시가 없고 알려진 패밀리 단어도 아니면 건너뛴다.
            continue;
          }
          label = captured;
        } else {
          label = match.group(0)!;
        }
        if (match.start > bestStart) {
          bestStart = match.start;
          bestLabel = label;
        }
      }
    }
    if (bestLabel != null) {
      return (
        _normalizeModelLabel(bestLabel),
        AgentDetectionConfidence.confirmed,
      );
    }

    for (final pattern in [
      ..._possibleModelPatterns,
      for (final word in extras) _familyWordPattern(word),
    ]) {
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        return (
          _normalizeModelLabel(match.group(0)!),
          AgentDetectionConfidence.possible,
        );
      }
    }
    return (null, AgentDetectionConfidence.none);
  }

  static bool _looksLikeModelToken(String token) {
    if (RegExp(r'\d').hasMatch(token)) return true;
    if (token.contains('-')) return true;
    final lower = token.toLowerCase();
    return _modelFamilyWords.contains(lower) ||
        lower == 'claude' ||
        lower == 'codex';
  }

  static String _normalizeModelLabel(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// 선언된 모델 라벨과 감지된 모델 라벨이 대소문자 무시 부분 일치하는지 본다.
  /// 예: 선언 "opus" ⊂ 감지 "claude-opus-4-1".
  static bool modelMatches(String declared, String detected) {
    final declaredLower = declared.trim().toLowerCase();
    final detectedLower = detected.trim().toLowerCase();
    if (declaredLower.isEmpty || detectedLower.isEmpty) return false;
    return detectedLower.contains(declaredLower) ||
        declaredLower.contains(detectedLower);
  }

  /// 화면 텍스트로 Agent를 판별한다. [title]을 주면 터미널 제목(OSC 0/2)
  /// 판별도 합친다: 화면의 확정 근거가 있으면 그것을, 없으면 제목을, 제목도
  /// 없으면 화면의 느슨한 근거를 쓴다 — 제목은 지금 떠 있는 TUI가 직접 쓴
  /// 값이라 스크롤을 지나간 단어보다 믿을 만하다. 미리보기·모델은 늘 화면에서
  /// 가져온다. SessionAttentionNotifier의 규칙과 같다.
  static AgentSessionInspection inspect(
    String screen, {
    int previewLines = 3,
    Iterable<String> extraFamilies = const [],
    String? title,
    bool liveSession = false,
  }) {
    final fromScreen = _inspectScreen(
      screen,
      previewLines: previewLines,
      extraFamilies: extraFamilies,
      liveSession: liveSession,
    );
    if (title == null ||
        (!liveSession && fromScreen.isConfirmedAgent) ||
        (liveSession && hasShellPrompt(screen))) {
      return fromScreen;
    }
    final fromTitle = inspectTitle(title);
    if (!fromTitle.isPossibleAgent) return fromScreen;
    return AgentSessionInspection(
      agentHint: fromTitle.agentHint,
      confidence: fromTitle.confidence,
      preview: fromScreen.preview,
      modelHint: fromScreen.modelHint,
      modelConfidence: fromScreen.modelConfidence,
    );
  }

  static AgentSessionInspection _inspectScreen(
    String screen, {
    required int previewLines,
    required Iterable<String> extraFamilies,
    required bool liveSession,
  }) {
    final (modelHint, modelConfidence) = detectModel(
      screen,
      extraFamilies: extraFamilies,
    );
    final lines = _normalizedLines(screen);
    final recent = lines.length <= 60
        ? lines
        : lines.sublist(lines.length - 60);
    final searchable = recent.join('\n').toLowerCase();
    if (liveSession) {
      final hint = _liveHint(lines);
      return AgentSessionInspection(
        agentHint: hint ?? 'unknown',
        confidence: hint == null
            ? AgentDetectionConfidence.none
            : hint == 'agent'
            ? AgentDetectionConfidence.possible
            : AgentDetectionConfidence.confirmed,
        preview: _preview(lines, previewLines),
        modelHint: modelHint,
        modelConfidence: modelConfidence,
      );
    }

    // 확정 패턴은 화면 전체에서 찾는다. agent의 시작 배너는 대화가 길어지면
    // 최근 60줄 밖으로 밀려나는데, 그때마다 unknown으로 떨어지면 안 된다.
    // 반면 느슨한 패턴은 최근 화면에서만 본다 — 지나간 출력에 우연히 들어간
    // 단어까지 주워 담으면 엉뚱한 agent로 오인한다.
    final fullText = lines.join('\n').toLowerCase();

    // 고정 문구(입력창 하단 chrome)는 "지금 떠 있는" TUI의 증거라 스크롤백의
    // 배너·명령보다 앞선다. 화면 하단에 있으므로 최근 줄만 본다 — 지나간
    // 대화 안의 인용문(예: 문서에 적힌 "esc to interrupt")까지 근거로 삼지 않는다.
    for (final (pattern, hint) in _chromePatterns) {
      if (pattern.hasMatch(searchable)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.confirmed,
          preview: _preview(lines, previewLines),
          modelHint: modelHint,
          modelConfidence: modelConfidence,
        );
      }
    }
    for (final (pattern, hint) in _confirmedPatterns) {
      if (pattern.hasMatch(fullText)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.confirmed,
          preview: _preview(lines, previewLines),
          modelHint: modelHint,
          modelConfidence: modelConfidence,
        );
      }
    }
    for (final (pattern, hint) in _possiblePatterns) {
      if (pattern.hasMatch(searchable)) {
        return AgentSessionInspection(
          agentHint: hint,
          confidence: AgentDetectionConfidence.possible,
          preview: _preview(lines, previewLines),
          modelHint: modelHint,
          modelConfidence: modelConfidence,
        );
      }
    }
    if (_genericChromePattern.hasMatch(searchable)) {
      return AgentSessionInspection(
        agentHint: 'agent',
        confidence: AgentDetectionConfidence.possible,
        preview: _preview(lines, previewLines),
        modelHint: modelHint,
        modelConfidence: modelConfidence,
      );
    }
    return AgentSessionInspection(
      agentHint: 'unknown',
      confidence: AgentDetectionConfidence.none,
      preview: _preview(lines, previewLines),
      modelHint: modelHint,
      modelConfidence: modelConfidence,
    );
  }

  /// 세션 배지는 실행 중인 UI만 식별한다. 문서/파일명 속 제품명은 근거가 아니다.
  /// 마지막 셸 프롬프트보다 앞의 배너와 문구는 이미 종료된 작업일 수 있다.
  static bool hasShellPrompt(String screen) {
    final lines = _normalizedLines(screen);
    return lines.isNotEmpty && _shellPrompt.hasMatch(lines.last.trim());
  }

  static final _shellPrompt = RegExp(
    r'^(?:[$#%]|(?:\([^\n]*\)\s*)?[^\s@]+@[^\s]+[^\n]*[$#%]|'
    r'PS\s+[^\n]+>|[A-Za-z]:\\[^\n]*>|[~/.]\S*[$#%])(?:\s.*)?$',
    caseSensitive: false,
  );

  static bool isShellTitle(String title) => RegExp(
    r'^(?:(?:ba|z|fi)?sh|pwsh|powershell|cmd)(?:\.exe)?$|'
    r'^[^\s@]+@[^\s:]+[: ]|^(?:[A-Za-z]:[\\/]|[~/])',
    caseSensitive: false,
  ).hasMatch(title.trim());

  static final _liveBrandedBanner = RegExp(
    r'^(?:welcome\s+to\s+)?(openai\s+codex(?:\s+cli)?|codex(?:\s+cli)?|'
    r'claude(?:\s+code)?|anthropic\s+claude|google\s+gemini|'
    r'gemini(?:\s+cli)?|sepilot(?:\s+cli)?)'
    r'(?:\s*(?:[!│|·(]|v?\d).*)?$',
  );
  static const _primaryAgents = {'claude', 'codex', 'gemini', 'sepilot'};

  /// 배너가 스크롤로 사라진 뒤에도 화면 하단에 남는 제품 고유 UI.
  ///
  /// tmux 안에서는 제목(OSC 0/2)과 hook이 바깥으로 전달되지 않아 화면이 유일한
  /// 근거가 된다. 문서·명령 출력 속 같은 문구를 오인하지 않도록 [_liveUiRows]
  /// 안의 줄 시작에서만 찾는다.
  static final List<(RegExp, String)> _liveUiPatterns = [
    // Codex 입력창 placeholder. 입력 중에는 사라진다.
    (RegExp(r'^›\s+ask codex to do anything\b'), 'codex'),
    // Codex 상태 줄: `gpt-6.1-sol high · ~/repo · ...`. 입력 중에도 남는다.
    (
      RegExp(
        r'^(?:gpt-|codex-|o\d)[\w.-]*(?:\s+(?:minimal|low|medium|high|xhigh))?'
        r'\s+·\s+(?:[~/]|\d+% context left)',
      ),
      'codex',
    ),
    (
      RegExp(
        r'^•\s+working\s+\((?:\d+h\s+)?(?:\d+m\s+)?\d+s\s+•\s+esc to interrupt',
      ),
      'codex',
    ),
    // Codex 승인 대화상자의 마지막 선택지.
    (RegExp(r'^3\.\s+no, and tell codex what to do differently'), 'codex'),
    // OpenCode 응답 꼬리표(`▣  Build · GLM-5.2`)와 권한 요청 선택지.
    (RegExp(r'^▣\s+\S+\s+·\s+\S'), 'opencode'),
    (RegExp(r'^(?:┃\s*)?allow once\s+allow always\s+reject\b'), 'opencode'),
    // Claude Code 승인 대화상자 하단 안내.
    (RegExp(r'^esc to cancel · tab to amend\b'), 'claude'),
    // Claude 선택지 커서(`❯ 2. Yes, …`). Codex는 `›`를 쓴다.
    (RegExp(r'^❯\s+\d\.\s+(?:yes|no)\b'), 'claude'),
    // Claude Code 스피너·완료 줄: `✶ Photosynthesizing… (4m 48s`, `✻ Worked for 3m`.
    (RegExp(r'^[✻✶✳✽✢]\s+(?:\S+…\s*\(|\S+ for \d+[hms])'), 'claude'),
  ];
  static const _liveUiRows = 8;

  static String? _liveHint(List<String> lines) {
    final boundary = lines.lastIndexWhere(
      (line) => _shellPrompt.hasMatch(line.trim()),
    );
    final active = lines.sublist(boundary + 1);
    // A banner lower on screen supersedes an older agent's banner/footer.
    for (var row = active.length - 1; row >= 0; row--) {
      final raw = active[row];
      final line = raw
          .trim()
          .replaceFirst(RegExp(r'^[│┃║╭╰┌└─━\s✳✶✻✽✢]+'), '')
          .toLowerCase();
      for (final (pattern, hint) in _chromePatterns) {
        if (pattern.hasMatch(line) &&
            !line.startsWith('>') &&
            !line.startsWith('›')) {
          return hint;
        }
      }
      if (row >= active.length - _liveUiRows) {
        final liveLine = raw.trim().toLowerCase();
        for (final (pattern, hint) in _liveUiPatterns) {
          if (pattern.hasMatch(liveLine)) return hint;
        }
      }
      final banner = _liveBrandedBanner.firstMatch(line);
      if (banner != null) {
        final brand = banner[1]!;
        for (final hint in _primaryAgents) {
          if (brand.contains(hint)) return hint;
        }
      }
      for (final (pattern, hint) in _confirmedPatterns) {
        if (_primaryAgents.contains(hint)) continue;
        final match = pattern.firstMatch(line);
        if (match?.start == 0) return hint;
      }
      // Gemini's ASCII logo may not contain a searchable product name. Require
      // both its input placeholder and model/sandbox footer, never a model alone.
      final footer = active
          .sublist(row > 5 ? row - 5 : 0, row + 1)
          .join('\n')
          .toLowerCase();
      if (row >= active.length - 3 &&
          footer.contains('type your message or @path/to/file') &&
          footer.contains('sandbox') &&
          RegExp(r'\bgemini-\d[\w.-]*').hasMatch(footer)) {
        return 'gemini';
      }
    }
    final footer = active
        .skip(active.length > 6 ? active.length - 6 : 0)
        .join('\n')
        .toLowerCase();
    return _genericChromePattern.hasMatch(footer) ? 'agent' : null;
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
    if (isShellTitle(trimmed)) {
      return AgentSessionInspection(
        agentHint: 'unknown',
        confidence: AgentDetectionConfidence.none,
        preview: trimmed,
      );
    }
    final branded = RegExp(
      r'^(?:[✳✶✻✽✢]\s*)?(claude(?: code)?|codex|gemini(?: cli)?|sepilot)(?:$|\s*(?:[|:·—–-]|\(?v?\d)\s*)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (branded != null) {
      return AgentSessionInspection(
        agentHint: branded[1]!.toLowerCase().split(' ').first,
        confidence: AgentDetectionConfidence.confirmed,
        preview: trimmed,
      );
    }
    for (final (pattern, hint) in _confirmedPatterns) {
      if (pattern.firstMatch(lower)?.start == 0) {
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
