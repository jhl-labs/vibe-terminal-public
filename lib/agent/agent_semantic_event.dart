import 'dart:convert';

/// CLI hook, shim, App Server가 공통으로 보고하는 Agent 실행 단계.
enum AgentSemanticPhase {
  sessionStarted,
  working,
  waitingApproval,
  waitingInput,
  completed,
  failed,
  stopped,
}

/// 화면 문구와 독립적으로 Agent 상태를 전달하는 정규화 이벤트.
///
/// 이 신호는 상태 표시와 알림 품질을 높이기 위한 것이며 권한 승인이나 명령 실행의
/// 보안 경계가 아니다. 터미널 안의 프로세스는 sideband 출력을 만들 수 있다.
class AgentSemanticEvent {
  const AgentSemanticEvent({
    required this.provider,
    required this.phase,
    required this.name,
    this.providerSessionId,
    this.turnId,
    this.message,
  });

  static const sidebandChannel = 'vibe-agent-event';
  static const supportedProviders = {'claude', 'codex', 'opencode'};

  final String provider;
  final AgentSemanticPhase phase;
  final String name;
  final String? providerSessionId;
  final String? turnId;
  final String? message;

  bool get blocksUser =>
      phase == AgentSemanticPhase.waitingApproval ||
      phase == AgentSemanticPhase.waitingInput ||
      phase == AgentSemanticPhase.failed;

  /// base64url(JSON)으로 감싼 sideband payload를 해석한다.
  static AgentSemanticEvent? tryParseSideband(String encoded) {
    if (encoded.isEmpty || encoded.length > 16 * 1024) return null;
    try {
      final normalized = base64Url.normalize(encoded);
      final bytes = base64Url.decode(normalized);
      if (bytes.length > 12 * 1024) return null;
      return tryParseJson(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return null;
    }
  }

  /// 정규화 envelope와 Claude/Codex 호환 hook payload 이름을 함께 받는다.
  static AgentSemanticEvent? tryParseJson(Object? value) {
    if (value is! Map) return null;
    final provider = _string(value['provider'], 20)?.toLowerCase();
    if (provider == null || !supportedProviders.contains(provider)) return null;

    final rawName =
        _string(value['event'], 80) ??
        _string(value['hook_event_name'], 80) ??
        _string(value['type'], 80) ??
        _string(value['method'], 80);
    if (rawName == null) return null;
    final phase = _phaseFor(rawName, value);
    if (phase == null) return null;

    return AgentSemanticEvent(
      provider: provider,
      phase: phase,
      name: rawName,
      providerSessionId:
          _string(value['session_id'], 160) ??
          _string(value['sessionId'], 160) ??
          _nestedString(value, 'thread', 'id', 160),
      turnId:
          _string(value['turn_id'], 160) ??
          _string(value['turnId'], 160) ??
          _nestedString(value, 'turn', 'id', 160),
      message:
          _string(value['message'], 500) ??
          _string(value['reason'], 500) ??
          _nestedString(value, 'error', 'message', 500) ??
          _nestedString(value, 'tool_input', 'description', 500),
    );
  }

  /// hook/shim 구현 및 테스트에서 사용할 OSC 777 wire 형식.
  String toSidebandSequence() {
    final bytes = utf8.encode(
      jsonEncode({
        'v': 1,
        'provider': provider,
        'event': name,
        if (providerSessionId != null) 'session_id': providerSessionId,
        if (turnId != null) 'turn_id': turnId,
        if (message != null) 'message': message,
      }),
    );
    return '\x1b]777;$sidebandChannel;${base64Url.encode(bytes)}\x07';
  }

  static AgentSemanticPhase? _phaseFor(String name, Map value) {
    final normalized = name
        .trim()
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]}_${match[2]}',
        )
        .replaceAll(RegExp(r'[./-]+'), '_')
        .toLowerCase();
    return switch (normalized) {
      'sessionstart' || 'session_start' => AgentSemanticPhase.sessionStarted,
      'userpromptsubmit' ||
      'user_prompt_submit' ||
      'pretooluse' ||
      'pre_tool_use' ||
      'posttooluse' ||
      'post_tool_use' ||
      'turn_started' ||
      'item_started' => AgentSemanticPhase.working,
      'permissionrequest' ||
      'permission_request' ||
      'approval_required' => AgentSemanticPhase.waitingApproval,
      'waiting_input' || 'input_required' => AgentSemanticPhase.waitingInput,
      'stop' || 'turn_completed' =>
        _turnFailed(value)
            ? AgentSemanticPhase.failed
            : AgentSemanticPhase.completed,
      'turn_failed' || 'error' => AgentSemanticPhase.failed,
      'sessionend' || 'session_end' => AgentSemanticPhase.stopped,
      _ => null,
    };
  }

  static bool _turnFailed(Map value) {
    final turn = value['turn'];
    final status = turn is Map ? turn['status'] : value['status'];
    return status == 'failed';
  }

  static String? _nestedString(
    Map value,
    String objectKey,
    String fieldKey,
    int maximumLength,
  ) {
    final nested = value[objectKey];
    return nested is Map ? _string(nested[fieldKey], maximumLength) : null;
  }

  static String? _string(Object? value, int maximumLength) {
    if (value is! String) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty || cleaned.length > maximumLength) return null;
    return cleaned.replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '');
  }
}
