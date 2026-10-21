import 'dart:convert';
import '../../../ai/secret_masker.dart';

import '../../agent_session_inspector.dart';
import '../../quiescence_detector.dart';
import '../../terminal_runtime_issue_detector.dart';
import 'resume_prompts.dart';
import '../autopilot_state.dart';

/// 판정 LLM 호출. 시스템/사용자 프롬프트를 받아 원문 응답을 돌려준다.
typedef ResumeCompletion =
    Future<String> Function({required String system, required String user});

/// "정상 종료 vs 비정상 중단"을 두 단계로 판정한다.
///
/// 1단계는 로컬 정규식(무료): 화면 꼬리에 provider·네트워크 오류 문구가 있으면
/// LLM 없이 곧바로 interrupted다. 2단계는 LLM: 문구 없이 조용히 멈춘 경우만
/// 물어본다. LLM의 evidence는 실제 화면에 존재해야 하고 confidence가 임계값을
/// 넘어야 interrupted로 인정한다 — 정상 완료를 중단으로 오인하면 끝난 작업에
/// 불필요한 지시가 들어가므로 보수적으로 잡는다.
class ResumeJudge {
  const ResumeJudge({
    required this.complete,
    this.issueDetector = const TerminalRuntimeIssueDetector(),
    this.confidenceThreshold = 0.75,
  });

  /// 판정 LLM 호출.
  final ResumeCompletion complete;
  final TerminalRuntimeIssueDetector issueDetector;

  /// LLM interrupted 판정을 받아들일 최소 confidence.
  final double confidenceThreshold;

  Future<ResumeVerdict> judge({
    required String screen,
    required Duration idleFor,
    required int attempt,
    required DateTime now,
    String? lastPrompt,
    bool allowLlm = true,
  }) async {
    final local = judgeLocally(screen, now: now, issueDetector: issueDetector);
    if (local != null) return local;
    if (!allowLlm) {
      return ResumeVerdict(
        status: ResumeStatus.unknown,
        confidence: 0,
        process: detectProcess(screen),
        reason: 'AI 설정이 없어 조용한 멈춤은 판정하지 않음',
        evidence: '',
        source: ResumeVerdictSource.local,
        at: now,
      );
    }
    return _judgeWithLlm(
      screen: screen,
      idleFor: idleFor,
      attempt: attempt,
      now: now,
      lastPrompt: lastPrompt,
    );
  }

  /// 1단계. provider 오류 문구가 화면 꼬리에 있으면 interrupted.
  static ResumeVerdict? judgeLocally(
    String screen, {
    required DateTime now,
    TerminalRuntimeIssueDetector issueDetector =
        const TerminalRuntimeIssueDetector(),
  }) {
    final emptyTurn = openCodeEmptyTurn(screen);
    if (emptyTurn != null) {
      return ResumeVerdict(
        status: ResumeStatus.interrupted,
        confidence: 1.0,
        process: detectProcess(screen),
        reason: 'OpenCode가 응답 없이 턴을 끝냄',
        evidence: emptyTurn,
        source: ResumeVerdictSource.local,
        at: now,
      );
    }
    final issue = issueDetector.detect(screen, now: now);
    if (issue == null || issue.isBlocking) return null;
    return ResumeVerdict(
      status: ResumeStatus.interrupted,
      confidence: 1.0,
      process: detectProcess(screen),
      reason: 'LLM 서버·네트워크 오류 문구',
      evidence: issue.evidence,
      source: ResumeVerdictSource.local,
      at: now,
    );
  }

  /// OpenCode 응답 꼬리표(`▣  Build · 모델`). 응답 내용 아래에 붙는다.
  static final _openCodeTurnFooter = RegExp(r'^\s*▣\s+\S');
  static final _openCodeThought = RegExp(
    r'^\s*\+\s*thought\b',
    caseSensitive: false,
  );

  /// OpenCode가 마지막 사용자 메시지에 아무 내용 없이 턴을 끝냈으면 그 꼬리표 줄을
  /// 돌려준다.
  ///
  /// 화면은 `┃` 테두리의 사용자 메시지 → 들여쓴 응답 내용(생각·도구·글) →
  /// `▣ Build · 모델` 순서다. 사용자 메시지와 마지막 꼬리표 사이에 생각 표시 말고
  /// 아무 줄도 없으면 응답이 비어 있다. 꼬리표 뒤에는 입력창만 와야 한다.
  static String? openCodeEmptyTurn(String screen) {
    final lines = screen
        .replaceAll('\r', '')
        .split('\n')
        .map((line) => line.trimRight())
        .toList(growable: false);
    final footer = lines.lastIndexWhere(_openCodeTurnFooter.hasMatch);
    if (footer < 0) return null;
    // 꼬리표 뒤에 다른 응답 내용이 이어지면 이 꼬리표는 마지막 턴이 아니다.
    final after = lines
        .skip(footer + 1)
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (after.length > 8 || after.any((line) => !_openCodeChrome(line))) {
      return null;
    }
    var sawUserText = false;
    for (var row = footer - 1; row >= 0; row--) {
      final line = lines[row];
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('┃')) {
        if (trimmed.length > 1) sawUserText = true;
        continue;
      }
      if (sawUserText) break; // 사용자 메시지 블록 위쪽에 닿았다.
      if (_openCodeThought.hasMatch(line)) continue;
      return null; // 사용자 메시지와 꼬리표 사이에 응답 내용이 있다.
    }
    return sawUserText ? lines[footer].trim() : null;
  }

  /// 꼬리표 아래에 올 수 있는 OpenCode 입력창·단축키 안내 줄.
  static bool _openCodeChrome(String line) {
    final trimmed = line.trim();
    return trimmed.startsWith('┃') ||
        trimmed.startsWith('╹') ||
        RegExp(
          r'\b(?:tab|ctrl\+\w|esc)\b.{0,40}\b(?:agents?|commands|help|interrupt)\b',
          caseSensitive: false,
        ).hasMatch(trimmed);
  }

  /// Agent 프로세스가 살아 있는지 화면으로 추정한다.
  ///
  /// 마지막 줄이 셸 프롬프트이고 최근 줄에 Agent 흔적이 없으면 exited, Agent
  /// 고정 문구가 보이면 tuiAlive, 그 외는 unknown(LLM 판정에 맡긴다).
  static ResumeProcess detectProcess(String screen) {
    final lines = screen
        .replaceAll('\r', '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return ResumeProcess.unknown;
    final tail = lines
        .skip(lines.length > 16 ? lines.length - 16 : 0)
        .join('\n');
    final inspection = AgentSessionInspector.inspect(tail);
    if (inspection.isPossibleAgent ||
        QuiescenceDetector.hasWorkingIndicator(tail)) {
      return ResumeProcess.tuiAlive;
    }
    if (_shellPromptLine.hasMatch(lines.last.trimRight())) {
      return ResumeProcess.exited;
    }
    return ResumeProcess.unknown;
  }

  /// 셸 프롬프트로 보이는 줄. TUI 입력창(`> `)과 헷갈리지 않게 프롬프트 기호
  /// 앞에 경로·사용자명 같은 내용이 있거나 PowerShell 형태여야 한다.
  static final _shellPromptLine = RegExp(
    r'(?:^|\S)\s*(?:[$#%❯➜]|PS [A-Za-z]:[^>]*>)\s*$',
  );

  /// 화면의 마지막 줄이 셸 프롬프트인지.
  static bool endsWithShellPrompt(String screen) {
    final lines = screen
        .replaceAll('\r', '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty);
    if (lines.isEmpty) return false;
    return _shellPromptLine.hasMatch(lines.last.trimRight());
  }

  Future<ResumeVerdict> _judgeWithLlm({
    required String screen,
    required Duration idleFor,
    required int attempt,
    required DateTime now,
    String? lastPrompt,
  }) async {
    final normalized = _tailForLlm(screen);
    final user = ResumePrompts.judgeUser(
      screen: normalized,
      idleFor: idleFor,
      attempt: attempt,
      lastPrompt: lastPrompt,
    );
    String raw;
    try {
      raw = await complete(system: ResumePrompts.judgeSystem, user: user);
    } catch (error) {
      return _errorVerdict('판정 LLM 호출 실패: $error', now);
    }
    var parsed = parseResponse(raw, screen: screen, now: now);
    if (parsed == null) {
      try {
        raw = await complete(
          system: ResumePrompts.judgeSystem,
          user: '$user\n\n${ResumePrompts.repair(raw)}',
        );
      } catch (error) {
        return _errorVerdict('판정 LLM 재요청 실패: $error', now);
      }
      parsed = parseResponse(raw, screen: screen, now: now);
      if (parsed == null) {
        return _errorVerdict('판정 LLM 응답을 해석하지 못했습니다.', now);
      }
    }
    // 화면 근거로 알 수 있는 프로세스 상태는 LLM 추정보다 우선한다.
    final localProcess = detectProcess(screen);
    if (localProcess != ResumeProcess.unknown) {
      parsed = parsed.copyWith(process: localProcess);
    }
    if (parsed.isInterrupted && parsed.confidence < confidenceThreshold) {
      return ResumeVerdict(
        status: ResumeStatus.unknown,
        confidence: parsed.confidence,
        process: parsed.process,
        reason:
            '중단 의심이지만 확신 부족(${(parsed.confidence * 100).round()}%): '
            '${parsed.reason}',
        evidence: parsed.evidence,
        source: ResumeVerdictSource.llm,
        at: now,
      );
    }
    return parsed;
  }

  /// LLM 응답에서 JSON 객체를 꺼내 검증한다. 실패하면 null.
  ///
  /// evidence가 화면에 없으면 환각으로 보고 interrupted를 unknown으로 낮춘다.
  static ResumeVerdict? parseResponse(
    String raw, {
    required String screen,
    required DateTime now,
  }) {
    final json = _extractJsonObject(raw);
    if (json == null) return null;
    final status = switch ('${json['status'] ?? ''}'.trim().toLowerCase()) {
      'completed' => ResumeStatus.completed,
      'interrupted' => ResumeStatus.interrupted,
      'waiting_user' ||
      'waiting-user' ||
      'waitinguser' => ResumeStatus.waitingUser,
      'working' => ResumeStatus.working,
      'unknown' => ResumeStatus.unknown,
      _ => null,
    };
    if (status == null) return null;
    final confidenceRaw = json['confidence'];
    final confidence = switch (confidenceRaw) {
      num n => n.toDouble().clamp(0.0, 1.0),
      String s => (double.tryParse(s) ?? 0.0).clamp(0.0, 1.0),
      _ => 0.0,
    };
    final process = switch ('${json['process'] ?? ''}'.trim().toLowerCase()) {
      'tui_alive' || 'tui-alive' || 'alive' => ResumeProcess.tuiAlive,
      'exited' => ResumeProcess.exited,
      _ => ResumeProcess.unknown,
    };
    final reason = '${json['reason'] ?? ''}'.trim();
    final evidence = '${json['evidence'] ?? ''}'.trim();
    final evidenceFound =
        evidence.isNotEmpty && _screenContains(screen, evidence);
    if (status == ResumeStatus.interrupted && !evidenceFound) {
      return ResumeVerdict(
        status: ResumeStatus.unknown,
        confidence: confidence,
        process: process,
        reason: '근거 줄이 화면에 없어 중단 판정을 보류: $reason',
        evidence: evidence,
        source: ResumeVerdictSource.llm,
        at: now,
      );
    }
    return ResumeVerdict(
      status: status,
      confidence: confidence,
      process: process,
      reason: reason.isEmpty ? status.name : reason,
      evidence: evidence,
      source: ResumeVerdictSource.llm,
      at: now,
    );
  }

  static bool _screenContains(String screen, String evidence) {
    String squash(String value) =>
        value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final haystack = squash(screen);
    final needle = squash(evidence);
    if (needle.length < 4) return false;
    if (haystack.contains(needle)) return true;
    // 모델이 긴 줄을 앞부분만 인용하는 경우를 허용한다.
    final head = needle.length > 40 ? needle.substring(0, 40) : needle;
    return haystack.contains(head);
  }

  static Map<String, Object?>? _extractJsonObject(String raw) {
    final trimmed = raw.trim();
    final candidates = <String>[trimmed];
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
    if (fenced != null) candidates.add(fenced.group(1)!.trim());
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      candidates.add(trimmed.substring(start, end + 1));
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return decoded.cast<String, Object?>();
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static String _tailForLlm(String screen) {
    final normalized = maskTerminalSecrets(
      QuiescenceDetector.normalize(screen),
    );
    final lines = normalized.split('\n');
    final limit = ResumePrompts.screenLineLimit;
    return lines.length <= limit
        ? normalized
        : lines.sublist(lines.length - limit).join('\n');
  }

  static ResumeVerdict _errorVerdict(String reason, DateTime now) =>
      ResumeVerdict(
        status: ResumeStatus.unknown,
        confidence: 0,
        process: ResumeProcess.unknown,
        reason: reason,
        evidence: '',
        source: ResumeVerdictSource.error,
        at: now,
      );
}
