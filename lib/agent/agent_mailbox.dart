/// 세션 간 메시지 전달을 담당하는 우편함.
///
/// 세션 안에서 도는 CLI 에이전트(claude/codex/gemini)는 화면과 키 입력이라는
/// 공통 최소 인터페이스밖에 없어서, 스스로 남의 우편함을 조회하거나 서로에게
/// 직접 메시지를 보낼 수 없다. 그래서 우편함은 **오케스트레이터가 소유**하고,
/// 배달은 수신 세션에게 나가는 다음 `send_prompt` 앞머리에 `[INBOX]` 블록으로
/// 주입하는 방식으로 이뤄진다.
///
/// 이렇게 두면 오케스트레이터 LLM이 매번 화면을 눈으로 베껴 옮기는 방식과 달리
/// 전달이 보장된다. 메시지는 배달될 때까지 큐에 남고, 배달 시점이 이벤트로
/// 기록되며, 계획 단계에서 미배달 건수가 인벤토리에 노출된다.
///
/// 순수 Dart(Flutter 무관)라 테스트 가능하다.
library;

/// 세션 간 메시지 한 통.
class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.body,
    required this.at,
    this.delivered = false,
  });

  /// 오케스트레이터가 자기 이름으로 보낼 때 쓰는 발신자 id.
  static const orchestrator = 'orchestrator';

  /// 사용자가 패널에서 직접 넣은 메시지의 발신자 id.
  static const user = 'user';

  final int id;

  /// 발신 세션 id 또는 [orchestrator].
  final String from;

  /// 수신 세션 id.
  final String to;
  final String body;
  final DateTime at;

  /// 수신 세션에게 실제로 주입되었는지.
  final bool delivered;

  AgentMessage asDelivered() => AgentMessage(
    id: id,
    from: from,
    to: to,
    body: body,
    at: at,
    delivered: true,
  );
}

/// 세션별 우편함. 오케스트레이터 loop 하나가 소유한다.
class AgentMailbox {
  final Map<String, List<AgentMessage>> _boxes = {};
  int _nextId = 1;

  /// 메시지 한 통을 [to]의 우편함에 넣는다. 아직 배달되지는 않는다.
  AgentMessage post({
    required String from,
    required String to,
    required String body,
    required DateTime at,
  }) {
    final message = AgentMessage(
      id: _nextId++,
      from: from,
      to: to,
      body: body,
      at: at,
    );
    _boxes.putIfAbsent(to, () => []).add(message);
    return message;
  }

  /// 이전 실행에서 배달되지 못한 메시지를 되살린다.
  ///
  /// 앱 재시작이나 "같은 목표 이어가기" 뒤에 부른다. 새 id를 부여하되 발신자·
  /// 수신자·본문·시각은 그대로 둔다. 이미 배달된 메시지는 무시한다.
  void seed(Iterable<AgentMessage> messages) {
    for (final message in messages) {
      if (message.delivered) continue;
      post(
        from: message.from,
        to: message.to,
        body: message.body,
        at: message.at,
      );
    }
  }

  /// 아직 배달되지 않은 메시지를 큐에서 뺀다. 배달됐거나 없으면 null.
  ///
  /// 사용자가 잘못 넣은 메시지나 이미 상황이 바뀐 세션 간 전달을 배달 전에
  /// 거둬들이는 용도다. 배달 이력은 손대지 않는다.
  AgentMessage? withdraw(int id) {
    for (final box in _boxes.values) {
      final index = box.indexWhere(
        (message) => message.id == id && !message.delivered,
      );
      if (index >= 0) return box.removeAt(index);
    }
    return null;
  }

  /// 모든 세션의 미배달 메시지를 넣은 순서대로 모은다. 스냅샷 저장용.
  List<AgentMessage> allPending() {
    final pending = <AgentMessage>[
      for (final box in _boxes.values)
        for (final message in box)
          if (!message.delivered) message,
    ]..sort((left, right) => left.id.compareTo(right.id));
    return pending;
  }

  /// 같은 본문을 여러 세션에 넣는다. 발신자 자신은 제외한다.
  List<AgentMessage> broadcast({
    required String from,
    required Iterable<String> to,
    required String body,
    required DateTime at,
  }) => [
    for (final recipient in to)
      if (recipient != from)
        post(from: from, to: recipient, body: body, at: at),
  ];

  /// 아직 배달되지 않은 메시지. 조회만 하고 상태를 바꾸지 않는다.
  List<AgentMessage> pendingFor(String sessionId) => [
    for (final message in _boxes[sessionId] ?? const <AgentMessage>[])
      if (!message.delivered) message,
  ];

  int unreadCount(String sessionId) => pendingFor(sessionId).length;

  /// 미배달이 있는 세션만 담은 맵. 인벤토리 표기에 쓴다.
  Map<String, int> unreadCounts() {
    final counts = <String, int>{};
    for (final entry in _boxes.entries) {
      final count = unreadCount(entry.key);
      if (count > 0) counts[entry.key] = count;
    }
    return counts;
  }

  /// 미배달 메시지를 꺼내면서 배달됨으로 표시한다.
  ///
  /// 실제로 세션에 주입이 확정된 뒤에만 불러야 한다. 승인 거부처럼 전송이
  /// 무산되는 경로에서 먼저 부르면 메시지가 배달된 적 없이 사라진다.
  List<AgentMessage> takePendingFor(String sessionId) {
    return markInjected(sessionId, pendingFor(sessionId).map((m) => m.id));
  }

  /// 전송에 포함된 id만 주입 완료로 확정한다. 대기 중 새로 온 메시지는 보존한다.
  /// 이는 입력 주입 확인이며, 수신 에이전트가 읽거나 처리했다는 확인이 아니다.
  List<AgentMessage> markInjected(String sessionId, Iterable<int> messageIds) {
    final ids = messageIds.toSet();
    final box = _boxes[sessionId];
    if (box == null) return const [];
    final taken = <AgentMessage>[];
    for (var index = 0; index < box.length; index++) {
      final message = box[index];
      if (message.delivered || !ids.contains(message.id)) continue;
      taken.add(message);
      box[index] = message.asDelivered();
    }
    return taken;
  }

  /// 배달 여부와 무관한 전체 이력.
  List<AgentMessage> historyFor(String sessionId) =>
      List.unmodifiable(_boxes[sessionId] ?? const <AgentMessage>[]);

  /// 수신 세션 프롬프트 앞에 붙일 `[INBOX]` 블록. 비어 있으면 빈 문자열.
  static String formatBlock(List<AgentMessage> messages) {
    if (messages.isEmpty) return '';
    final lines = messages.map(
      (message) => '- ${message.from}: ${message.body}',
    );
    return '[INBOX] 다른 세션이 너에게 남긴 메시지\n'
        '${lines.join('\n')}\n'
        '[/INBOX]\n\n';
  }
}
