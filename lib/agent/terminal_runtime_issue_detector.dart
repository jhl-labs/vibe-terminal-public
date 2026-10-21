enum TerminalRuntimeIssueKind {
  usageLimit,
  incompatibleModel,
  sandboxFailure,
  shellLaunchFailure,

  /// CLI 에이전트가 자기 LLM provider와의 통신 실패(연결 끊김, 5xx, 타임아웃,
  /// 과부하)로 턴을 중단했다. 사용자가 고칠 문제가 아니라 시간이 지나면 풀리는
  /// 문제라, 오케스트레이터가 사람 대신 "이어서 계속"을 다시 지시한다.
  providerFailure,
}

class TerminalRuntimeIssue {
  const TerminalRuntimeIssue({
    required this.kind,
    required this.message,
    required this.evidence,
    this.retryAt,
  });

  final TerminalRuntimeIssueKind kind;
  final String message;
  final String evidence;
  final DateTime? retryAt;

  String get code => switch (kind) {
    TerminalRuntimeIssueKind.usageLimit => 'codex_usage_limit',
    TerminalRuntimeIssueKind.incompatibleModel => 'codex_model_incompatible',
    TerminalRuntimeIssueKind.sandboxFailure => 'codex_sandbox_failure',
    TerminalRuntimeIssueKind.shellLaunchFailure => 'shell_launch_failure',
    TerminalRuntimeIssueKind.providerFailure => 'llm_provider_failure',
  };

  int get priority => switch (kind) {
    TerminalRuntimeIssueKind.shellLaunchFailure => 4,
    TerminalRuntimeIssueKind.sandboxFailure => 3,
    TerminalRuntimeIssueKind.incompatibleModel => 2,
    TerminalRuntimeIssueKind.usageLimit => 1,
    TerminalRuntimeIssueKind.providerFailure => 0,
  };

  /// 사용자가 터미널에서 손을 써야만 풀리는 문제인지. false면 오케스트레이터가
  /// 자동 재지시로 넘긴다.
  bool get isBlocking => kind != TerminalRuntimeIssueKind.providerFailure;
}

class TerminalRuntimeIssueDetector {
  const TerminalRuntimeIssueDetector();

  static final _usageLimitPatterns = <RegExp>[
    RegExp(r"you(?:'|’)ve hit your usage limit", caseSensitive: false),
    RegExp(
      r'usage limit (?:has been )?(?:reached|exceeded)',
      caseSensitive: false,
    ),
    RegExp(r'credits? or try again at', caseSensitive: false),
  ];
  static final _modelPatterns = <RegExp>[
    RegExp(
      r'model.{0,120}requires? .{0,40}newer .{0,20}(?:codex|cli)',
      caseSensitive: false,
    ),
    RegExp(
      r'model.{0,120}(?:is not|isn.t) supported.{0,80}(?:codex|version)',
      caseSensitive: false,
    ),
    RegExp(r'unsupported model.{0,120}(?:codex|version)', caseSensitive: false),
  ];
  static final _sandboxPatterns = <RegExp>[
    RegExp(
      r'createprocessasuserw failed(?::| with error)?\s*1312',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:windows |restricted-token )?sandbox.{0,100}(?:failed|unavailable)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:failed|unable) to (?:start|create).{0,60}sandbox',
      caseSensitive: false,
    ),
  ];
  static final _shellPatterns = <RegExp>[
    RegExp(
      r'''argument ['"]?pwsh\.exe['"]?.{0,120}(?:script file|recognized)''',
      caseSensitive: false,
    ),
    RegExp(r'failed to create pty', caseSensitive: false),
    RegExp(r'로컬 셸을 시작하지 못했습니다'),
  ];

  /// CLI 에이전트가 provider·네트워크 오류로 턴을 끝냈을 때 마지막 줄들에 남는
  /// 문구. opencode(Vercel AI SDK), claude, codex, 그리고 흔한 Node/Go 소켓 오류.
  static final _providerFailurePatterns = <RegExp>[
    RegExp(r'\bAI_(?:APICallError|RetryError|NoOutputGeneratedError)\b'),
    RegExp(r'\bfetch failed\b', caseSensitive: false),
    RegExp(r'\bsocket hang up\b', caseSensitive: false),
    RegExp(r'\bother side closed\b', caseSensitive: false),
    RegExp(r'\bUND_ERR_[A-Z_]+\b'),
    RegExp(
      r'\b(?:ECONNRESET|ECONNREFUSED|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|EPIPE)\b',
    ),
    RegExp(r'\bheaders? timeout error\b', caseSensitive: false),
    RegExp(r'\bconnection reset by peer\b', caseSensitive: false),
    RegExp(r'\bcontext deadline exceeded\b', caseSensitive: false),
    RegExp(r'\btls handshake timeout\b', caseSensitive: false),
    RegExp(
      r'\bAPI error(?:\s*\(|:|\s)\s*(?:5\d\d|429|529)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:502|503|504|529)\b.{0,40}\b(?:bad gateway|service unavailable|'
      r'gateway time-?out|overloaded|error)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:bad gateway|service unavailable|gateway time-?out)\b.{0,20}'
      r'\b(?:502|503|504)\b',
      caseSensitive: false,
    ),
    RegExp(r'\boverloaded_error\b|\bapi is overloaded\b', caseSensitive: false),
    RegExp(r'\btoo many requests\b', caseSensitive: false),
    RegExp(r'\brate.?limit(?:ed|\s+exceeded)?\b', caseSensitive: false),
    RegExp(
      r'\b(?:request|connection|response)\s+timed?\s*out\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:connection|network|stream)\s+(?:error|failed|closed|'
      r'disconnected|reset)\b',
      caseSensitive: false,
    ),
    RegExp(r'\berror sending request\b', caseSensitive: false),
    RegExp(r'\bfailed to connect\b', caseSensitive: false),
    RegExp(r'\bunexpected end of (?:stream|json|file)\b', caseSensitive: false),
    RegExp(r'\bfailed after \d+ attempts?\b', caseSensitive: false),
    // Codex·OpenAI 계열의 일시적 모델 과부하. `Please try a different model`이
    // 붙지만 시간이 지나면 같은 모델로 다시 된다.
    RegExp(
      r'\b(?:selected )?model is (?:currently )?(?:at capacity|overloaded)\b',
      caseSensitive: false,
    ),
    // OpenCode는 Bun 런타임이라 소켓 오류가 Bun 고유 문구로 나온다.
    RegExp(
      r'\bunable to connect\. is the computer able to access the url\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bsocket connection was closed unexpectedly\b',
      caseSensitive: false,
    ),
    RegExp(r'\bConnection(?:Refused|Closed)\b'),
    RegExp(
      r'\bterminated\b.{0,40}\b(?:fetch|request|stream)\b',
      caseSensitive: false,
    ),
  ];

  static final _retryTimePattern = RegExp(
    r'try again at\s+(\d{1,2}):(\d{2})\s*(am|pm)',
    caseSensitive: false,
  );

  TerminalRuntimeIssue? detect(String screen, {required DateTime now}) {
    final normalized = screen
        .replaceAll('\r', '')
        .split('\n')
        .reversed
        .take(16)
        .toList(growable: false)
        .reversed
        .join('\n');
    if (_matchesAny(normalized, _usageLimitPatterns)) {
      final retryAt = _parseRetryAt(normalized, now);
      final retryText = retryAt == null
          ? '사용량이 다시 제공되거나 크레딧을 추가한 뒤'
          : '${_formatLocalTime(retryAt)} 이후 또는 크레딧을 추가한 뒤';
      return TerminalRuntimeIssue(
        kind: TerminalRuntimeIssueKind.usageLimit,
        message:
            'Codex 사용량 한도에 도달했습니다. $retryText 재개하세요. '
            '현재 목표와 loop 상태는 유지됩니다.',
        evidence: _evidence(normalized, _usageLimitPatterns),
        retryAt: retryAt,
      );
    }
    if (_matchesAny(normalized, _modelPatterns)) {
      return TerminalRuntimeIssue(
        kind: TerminalRuntimeIssueKind.incompatibleModel,
        message:
            'Codex CLI와 선택한 모델이 호환되지 않습니다. 터미널에서 '
            '`codex update`를 실행하거나 지원 모델로 변경한 뒤 재개하세요.',
        evidence: _evidence(normalized, _modelPatterns),
      );
    }
    if (_matchesAny(normalized, _sandboxPatterns)) {
      return TerminalRuntimeIssue(
        kind: TerminalRuntimeIssueKind.sandboxFailure,
        message:
            'Codex Windows sandbox를 시작하지 못했습니다. `codex update` 후에도 '
            '반복되면 `~/.codex/config.toml`에 `[windows] sandbox = "unelevated"`를 '
            '설정하세요. workspace-write가 분리 쓰기 루트를 거부하면 '
            '`[sandbox_workspace_write]`의 `exclude_slash_tmp`와 '
            '`exclude_tmpdir_env_var`도 `true`로 설정한 뒤 세션을 다시 여세요. '
            '`danger-full-access`로는 자동 전환하지 않습니다.',
        evidence: _evidence(normalized, _sandboxPatterns),
      );
    }
    if (_matchesAny(normalized, _shellPatterns)) {
      return TerminalRuntimeIssue(
        kind: TerminalRuntimeIssueKind.shellLaunchFailure,
        message:
            '로컬 셸이 정상적으로 시작되지 않았습니다. 셸 프로필을 다시 연 뒤 '
            '재개하세요. 문제가 반복되면 PowerShell 설치 경로를 확인하세요.',
        evidence: _evidence(normalized, _shellPatterns),
      );
    }
    if (_matchesAny(normalized, _providerFailurePatterns)) {
      return TerminalRuntimeIssue(
        kind: TerminalRuntimeIssueKind.providerFailure,
        message:
            'CLI 에이전트가 LLM 서버·네트워크 오류로 작업을 중단했습니다. '
            '같은 작업을 이어가도록 자동으로 다시 지시합니다.',
        evidence: _evidence(normalized, _providerFailurePatterns),
      );
    }
    return null;
  }

  /// 사용자가 손을 써야 하는 문제만 돌려준다. provider 오류는 자동 속행 대상이라
  /// 여기서는 무시한다.
  TerminalRuntimeIssue? detectBlocking(String screen, {required DateTime now}) {
    final issue = detect(screen, now: now);
    return issue != null && issue.isBlocking ? issue : null;
  }

  bool _matchesAny(String text, List<RegExp> patterns) =>
      patterns.any((pattern) => pattern.hasMatch(text));

  DateTime? _parseRetryAt(String text, DateTime now) {
    final match = _retryTimePattern.firstMatch(text);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3)!.toLowerCase();
    if (hour == 12) hour = 0;
    if (meridiem == 'pm') hour += 12;
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  String _evidence(String text, List<RegExp> patterns) {
    final lines = text.split('\n');
    for (var index = 0; index < lines.length; index++) {
      if (!patterns.any((pattern) => pattern.hasMatch(lines[index]))) continue;
      final excerpt = lines
          .skip(index)
          .take(2)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join(' ');
      return _truncate(excerpt);
    }
    return _truncate(text.trim());
  }

  String _truncate(String value) {
    const limit = 360;
    return value.length <= limit ? value : '${value.substring(0, limit)}...';
  }

  String _formatLocalTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }
}
