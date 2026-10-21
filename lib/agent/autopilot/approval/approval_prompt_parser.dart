import '../../agent_launcher.dart';
import 'approval_prompt.dart';

/// CLI Agent 화면에서 권한 요청을 해석한다. 순수 함수, 보안 경계 아님.
///
/// 형식은 `test/agent/autopilot/fixtures/README.md`의 실제 캡처(claude 2.1.291,
/// codex 0.160.1, opencode 1.18.32)에 맞췄다. 확실히 인식하지 못하면 null —
/// 자율사용은 null을 "사람이 볼 일"로 처리한다. 화면 끝의 빈 줄을 버린 뒤
/// 마지막 [_window]줄만 본다(오래된 대화 내용 오인 방지).
class ApprovalPromptParser {
  const ApprovalPromptParser();

  static const _window = 40;

  ApprovalPrompt? parse(AgentCli cli, String screen) {
    final lines = _tailLines(screen);
    return switch (cli) {
      AgentCli.claude => _parseClaude(lines),
      AgentCli.codex => _parseCodex(lines),
      // fixture README: opencode는 선택 항목을 색상으로만 표시해 일반 텍스트로는
      // `Allow once`가 선택됐는지 알 수 없다(`opencode_bash_cursor_moved`가
      // `opencode_bash`와 글자 그대로 같다). Enter가 "항상 허용"을 고를 수 있으므로
      // 자동 승인을 지원하지 않는다(fail closed).
      AgentCli.opencode => null,
    };
  }

  // ---------------------------------------------------------------- claude

  static final _claudeQuestion = RegExp(r'^Do you want to .+\?$');
  static final _claudeFooter = RegExp(r'^Esc to cancel');
  static final _dashedRule = RegExp(r'^╌{3,}$');
  static final _claudeReadCall = RegExp(r'^\w+\((.+)\)$');
  static const _claudeHeaderMaxLines = 4;
  static const _claudeTitles = <String, ApprovalKind>{
    'bash command': ApprovalKind.command,
    'edit file': ApprovalKind.fileEdit,
    'create file': ApprovalKind.fileEdit,
    'read file': ApprovalKind.fileRead,
  };

  /// 구조(위에서 아래로): 빈 줄(가로선) · 제목 · [Tip/설명/경로] · `╌` 구분선 ·
  /// 본문 · `╌` 구분선 · 질문 · 선택지 · `Esc to cancel`.
  ApprovalPrompt? _parseClaude(List<String> lines) {
    final q = _lastIndexWhere(lines, _claudeQuestion.hasMatch);
    if (q < 0) return null;
    final options = _readOptions(lines, q + 1, _claudeFooter);
    if (options == null || !_hasYesOnceAndNo(options, RegExp(r'^Yes$'))) {
      return null;
    }

    // `╌` 구분선은 화면 전체에서 정확히 두 줄(여는 줄·닫는 줄)이어야 한다. 본문(명령
    // heredoc 등)에 `╌`만 있는 줄이 끼면 어디가 본문 시작인지 확신할 수 없어 앞쪽
    // 명령 줄을 빠뜨릴 수 있으므로 해석하지 않는다.
    final rules = [
      for (var i = 0; i < q; i++)
        if (_dashedRule.hasMatch(lines[i])) i,
    ];
    if (rules.length != 2 || rules.last != _previousNonEmpty(lines, q)) {
      return null;
    }
    final open = rules.first;
    final close = rules.last;
    final body = lines.sublist(open + 1, close).where((l) => l.isNotEmpty);

    // 제목: 여는 구분선 위쪽, 빈 줄(가로선) 바로 아래 줄.
    var title = open - 1;
    while (title > 0 &&
        lines[title - 1].isNotEmpty &&
        open - title < _claudeHeaderMaxLines) {
      title--;
    }
    if (title < 0 || (title > 0 && lines[title - 1].isNotEmpty)) return null;
    final kind = _claudeTitles[lines[title].toLowerCase()];
    if (kind == null) return null;
    final header = lines
        .sublist(title + 1, open)
        .where((l) => !l.startsWith('Tip:'))
        .toList();

    final String? subject = switch (kind) {
      ApprovalKind.command => body.join(' '),
      ApprovalKind.fileRead =>
        _claudeReadCall.firstMatch(body.join(''))?.group(1),
      _ => _claudeEditTarget(header, lines[q]),
    };
    if (subject == null) return null;
    return _prompt(kind, lines[q], subject, '1');
  }

  static final _claudeEditQuestion = RegExp(
    r'^Do you want to (?:make this edit to|create) (.+)\?$',
  );

  /// 편집 대상 경로: 제목 아래(Tip 제외)가 정확히 한 줄이고, 질문의 파일 이름과
  /// 같거나 `/<이름>`으로 끝나야 한다. 설명 줄이 끼거나 접힌 경로는 확신할 수
  /// 없으므로 null.
  static String? _claudeEditTarget(List<String> header, String question) {
    final name = _claudeEditQuestion.firstMatch(question)?.group(1);
    if (name == null || header.length != 1) return null;
    final path = header.single;
    return path == name || path.endsWith('/$name') ? path : null;
  }

  // ----------------------------------------------------------------- codex

  static final _codexQuestion = RegExp(
    r'^Would you like to (run the following command|make the following edits)\?$',
  );
  static final _codexFooter = RegExp(r'^Press enter to confirm');
  static final _codexDestinationLine = RegExp(r'^Destination:\s*(.*)$');

  /// 구조: 질문 · Environment/Reason/Description · `$ 명령` 또는
  /// `Destination:` + 경로 · 선택지 · `Press enter to confirm ...`.
  ApprovalPrompt? _parseCodex(List<String> lines) {
    final q = _lastIndexWhere(lines, _codexQuestion.hasMatch);
    if (q < 0) return null;
    final first = lines.indexWhere(_optionLine.hasMatch, q + 1);
    if (first < 0) return null;
    final options = _readOptions(lines, first, _codexFooter);
    if (options == null ||
        !_hasYesOnceAndNo(options, RegExp(r'^Yes, proceed \(y\)$'))) {
      return null;
    }

    final body = _trimTrailingEmpty(lines.sublist(q + 1, first));
    final isCommand = lines[q].contains('command');
    final subject = isCommand ? _codexCommand(body) : _codexDestination(body);
    if (subject == null) return null;
    final kind = isCommand ? ApprovalKind.command : ApprovalKind.fileEdit;
    return _prompt(kind, lines[q], subject, 'y');
  }

  /// `$ ` 줄부터 선택지 직전까지 전부(빈 줄 제외)를 공백 하나로 잇는다. 명령 안의
  /// 빈 줄(heredoc 등) 뒤 내용도 빠뜨리지 않는다.
  static String? _codexCommand(List<String> body) {
    final start = body.indexWhere((l) => l.startsWith(r'$ '));
    if (start < 0) return null;
    return [
      body[start].substring(2),
      ...body.sublist(start + 1).where((l) => l.isNotEmpty),
    ].join(' ');
  }

  /// `Destination:` 뒤 경로. 경로는 화면 폭에서 글자 중간이 접히므로
  /// (`.../a` + `.txt`) 공백 없이 잇는다. 여러 파일로 보이는 화면(대상이 둘 이상,
  /// 빈 줄로 나뉜 블록, `/`·`~`로 시작하는 이어진 줄)은 null.
  static String? _codexDestination(List<String> body) {
    final starts = [
      for (var i = 0; i < body.length; i++)
        if (_codexDestinationLine.hasMatch(body[i])) i,
    ];
    if (starts.length != 1) return null;
    final head = _codexDestinationLine
        .firstMatch(body[starts.single])!
        .group(1)!;
    final rest = body.sublist(starts.single + 1);
    if (rest.any((l) => l.isEmpty)) return null;
    final parts = [if (head.isNotEmpty) head, ...rest];
    if (parts.skip(1).any((l) => l.startsWith('/') || l.startsWith('~'))) {
      return null;
    }
    return parts.join('');
  }

  // ----------------------------------------------------------------- 공통

  /// 번호 선택지 줄. 선택 표시(`❯`·`›`·`>`)는 있어도 없어도 된다.
  static final _optionLine = RegExp(r'^(?:[❯›>]\s*)?(\d+)\.\s+(.+)$');

  static ApprovalPrompt? _prompt(
    ApprovalKind kind,
    String question,
    String subject,
    String key,
  ) {
    final normalized = subject.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    return ApprovalPrompt(
      kind: kind,
      subject: normalized,
      answer: ApprovalAnswer.text(key),
      fingerprint: '$question|$normalized',
    );
  }

  /// [from]부터 선택지 본문을 1번부터 순서대로 읽는다. 선택지 사이의 번호 없는 줄은
  /// 앞 선택지가 접힌 것이다. 선택지 뒤에는 빈 줄과 [footer]만 올 수 있다 — 그 밖의
  /// 출력이 있으면 이미 지나간 프롬프트이므로 null.
  static List<String>? _readOptions(
    List<String> lines,
    int from,
    RegExp footer,
  ) {
    final options = <String>[];
    var ended = false;
    for (var i = from; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) {
        if (options.isNotEmpty) ended = true;
        continue;
      }
      if (footer.hasMatch(line)) {
        ended = true;
        continue;
      }
      if (ended) return null;
      final m = _optionLine.firstMatch(line);
      if (m != null) {
        if (int.parse(m.group(1)!) != options.length + 1) return null;
        options.add(m.group(2)!);
      } else if (options.isEmpty) {
        return null;
      }
    }
    return options.isEmpty ? null : options;
  }

  /// 1번이 정확히 "이번만 Yes"이고 마지막이 No인지. 둘 다 보여야 잘리지 않은 화면이다.
  static bool _hasYesOnceAndNo(List<String> options, RegExp yesOnce) =>
      options.length >= 2 &&
      yesOnce.hasMatch(options.first) &&
      RegExp(r'^No\b').hasMatch(options.last);

  static List<String> _trimTrailingEmpty(List<String> lines) {
    var end = lines.length;
    while (end > 0 && lines[end - 1].isEmpty) {
      end--;
    }
    return lines.sublist(0, end);
  }

  static final _borderLead = RegExp(r'^[\s│┃║╭╰╮╯─━]+');
  static final _borderTrail = RegExp(r'[\s│┃║╭╰╮╯─━]+$');

  /// 화면 꼬리를 줄 단위로, 박스 테두리(│ ╭ ╰ ┃ ─)와 양끝 공백을 벗겨 돌려준다.
  /// 가로선만 있는 줄은 빈 줄이 된다.
  static List<String> _tailLines(String screen) {
    final all = screen.replaceAll('\r', '').trimRight().split('\n');
    final start = all.length > _window ? all.length - _window : 0;
    return [
      for (final line in all.sublist(start))
        line.replaceAll(_borderLead, '').replaceAll(_borderTrail, ''),
    ];
  }

  static int _previousNonEmpty(List<String> lines, int before) {
    for (var i = before - 1; i >= 0; i--) {
      if (lines[i].isNotEmpty) return i;
    }
    return -1;
  }

  static int _lastIndexWhere(List<String> lines, bool Function(String) test) {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (test(lines[i])) return i;
    }
    return -1;
  }
}
