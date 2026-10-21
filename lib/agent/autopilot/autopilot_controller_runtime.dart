part of 'autopilot_controller.dart';

/// [AutopilotController]의 [AutopilotRuntime] 구현. 같은 라이브러리(part)라
/// 컨트롤러의 비공개 기본 동작(`_set`, `_read`, `_stateAt`, `_mounted`)을 쓰며,
/// 컨트롤러 공개 API를 넓히지 않는다.
///
/// 안전 불변식(세션당 타이머 하나, 작업 토큰, 연결 식별, 주입 표시)과 진단 기록이
/// 여기 한 곳에 있다.
final class _ControllerRuntime implements AutopilotRuntime {
  _ControllerRuntime(this._c);

  final AutopilotController _c;

  final Map<String, Timer> _timers = {};
  final Map<String, List<String>> _log = {};

  /// 우리가 보내는 입력을 사용자 입력으로 오인하지 않게 하는 표시.
  final Set<String> _injecting = {};
  final Map<String, Object> _operations = {};

  static const _logLimit = 80;
  static const _blockSource = 'autopilot';

  void _cancelTimer(String id) => _timers.remove(id)?.cancel();

  void _cancelAllTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  AutopilotTiming get timing => _c.timing;

  @override
  AutopilotState? stateAt(String id) => _c._stateAt(id);

  @override
  AutopilotState stateOf(String id) => _c.stateOf(id);

  @override
  void setState(String id, AutopilotState next) => _c._set(id, next);

  @override
  void schedule(String id, Duration delay, void Function() action) {
    _cancelTimer(id);
    _timers[id] = Timer(delay, () {
      _timers.remove(id);
      action();
    });
  }

  @override
  bool hasTimer(String id) => _timers.containsKey(id);

  @override
  void scheduleSettledCheck(String id, Duration delay) =>
      schedule(id, delay, () => _c._afterApprovalSettle(id));

  @override
  Object beginOperation(String id) {
    final operation = Object();
    _operations[id] = operation;
    return operation;
  }

  @override
  bool isCurrent(String id, Object operation) =>
      _c._mounted &&
      _operations[id] == operation &&
      _c._stateAt(id)?.enabled == true;

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);

  @override
  SessionPort? portOf(String id) => _c._ports.byId(id);

  @override
  bool sameConnection(SessionPort port, Object identity) =>
      port.isConnected &&
      _c._ports.byId(port.id)?.connectionIdentity == identity;

  /// 지금 화면·제목에서 판별한 CLI를 우선한다. 같은 탭에서 opencode를 끝내고
  /// claude를 띄우면 켤 때 기록한 CLI가 아니라 지금 CLI로 읽고 재실행해야 한다.
  @override
  AgentCli? liveCli(String id, AutopilotState current) =>
      _c.cliFor(id) ?? current.cli;

  @override
  void inject(String id, void Function() send) {
    _injecting.add(id);
    try {
      send();
    } finally {
      _injecting.remove(id);
    }
  }

  @override
  bool get aiConfigured => _c.aiConfigured;

  @override
  bool isBusy(String id) =>
      _c._read(sessionActivityProvider.notifier).isBusy(id);

  @override
  void markTaskSubmitted(String id) =>
      _c._read(sessionActivityProvider.notifier).markTaskSubmitted(id);

  @override
  DateTime? idleSince(String id) => _c._idleSince[id];

  @override
  DateTime? lastUserInputAt(String id) => _c._lastUserInputAt[id];

  @override
  bool observedByAgentChat(String id) {
    final loop = _c._read(agentChatProvider);
    return loop.isRunning && loop.allowedSessionIds.contains(id);
  }

  @override
  SessionAttention? attentionOf(String id) =>
      _c._read(sessionAttentionProvider)[id];

  @override
  void raiseBlock(
    String id, {
    required String message,
    required String agentHint,
  }) {
    _c
        ._read(sessionAttentionProvider.notifier)
        .markExternalBlocked(
          id,
          source: _blockSource,
          message: message,
          agentHint: agentHint,
        );
  }

  @override
  void clearBlock(String id) {
    _c
        ._read(sessionAttentionProvider.notifier)
        .clearExternalBlock(id, _blockSource);
  }

  @override
  Future<void> notify(String id, String title, String body) async {
    if (!_c._read(appSettingsProvider).notifications.canShowAgentAttention) {
      return;
    }
    if (_c._read(sessionNotificationMuteProvider).contains(id)) return;
    var name = id;
    for (final session in _c._read(sessionManagerProvider)) {
      if (session.id == id) {
        name = session.displayName;
        break;
      }
    }
    await _c
        ._read(notificationServiceProvider)
        .showAgentAttention(title: '$name · $title', body: body);
  }

  @override
  void record(String id, String message) {
    final entries = _log.putIfAbsent(id, () => []);
    final stamp = clock.now().toIso8601String().substring(11, 19);
    entries.add('$stamp $message');
    if (entries.length > _logLimit) entries.removeAt(0);
  }
}
