import 'agent_session_inspector.dart';

/// CLI Agent 화면을 사용자의 개입이 필요한 상태인지 판별한 결과.
class AgentAttentionAssessment {
  const AgentAttentionAssessment({
    required this.agentHint,
    required this.confidence,
    required this.preview,
    required this.needsInput,
    this.evidence,
  });

  final String agentHint;
  final AgentDetectionConfidence confidence;
  final String preview;
  final bool needsInput;
  final String? evidence;

  bool get isAgent => confidence != AgentDetectionConfidence.none;
}

/// Claude/Codex/OpenCode 등 실제 TUI의 최근 화면에서 승인·입력 대기를 찾는다.
///
/// 화면 휴리스틱은 보조 신호일 뿐 보안 경계가 아니다. Agent로 판별된 화면의
/// 최근 줄에만 적용해 일반 셸 출력과 오래된 대화 내용을 오인하는 범위를 줄인다.
class AgentAttentionClassifier {
  const AgentAttentionClassifier();

  static final _inputPatterns = <RegExp>[
    RegExp(
      r'(?:do you want to|would you like to).{0,120}\?\s*$',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:allow|approve|confirm)(?: this| the)? .{0,100}\?\s*$',
      caseSensitive: false,
    ),
    RegExp(
      r'press (?:enter|return) to (?:continue|confirm|approve|submit)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:waiting for|needs?|requires?) (?:your )?'
      r'(?:input|approval|confirmation|permission)',
      caseSensitive: false,
    ),
    RegExp(r'(?:\[[yn]/[yn]\]|\([yn]/[yn]\))\s*$', caseSensitive: false),
    RegExp(r'yes,? and don.t ask again', caseSensitive: false),
    RegExp(
      r'(?:usage limit|rate limit).{0,80}(?:reached|exceeded|reset|try again)',
      caseSensitive: false,
    ),
  ];

  AgentAttentionAssessment inspect(String screen) {
    final inspection = AgentSessionInspector.inspect(screen, previewLines: 3);
    if (!inspection.isPossibleAgent) {
      return AgentAttentionAssessment(
        agentHint: inspection.agentHint,
        confidence: inspection.confidence,
        preview: inspection.preview,
        needsInput: false,
      );
    }

    final recentLines = screen
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final start = recentLines.length > 16 ? recentLines.length - 16 : 0;
    for (final line in recentLines.sublist(start).reversed) {
      if (_inputPatterns.any((pattern) => pattern.hasMatch(line))) {
        return AgentAttentionAssessment(
          agentHint: inspection.agentHint,
          confidence: inspection.confidence,
          preview: inspection.preview,
          needsInput: true,
          evidence: _truncate(line.trim()),
        );
      }
    }

    return AgentAttentionAssessment(
      agentHint: inspection.agentHint,
      confidence: inspection.confidence,
      preview: inspection.preview,
      needsInput: false,
    );
  }

  static String _truncate(String value) {
    const limit = 160;
    return value.length <= limit ? value : '${value.substring(0, limit)}…';
  }
}
