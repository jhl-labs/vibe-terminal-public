import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../session/session.dart';
import '../session/session_activity.dart';
import '../session/session_attention.dart';
import '../state/providers.dart';
import 'session_port.dart';
import 'session_intervention.dart';

final sessionPortRegistryProvider = Provider<SessionPortRegistry>(
  (ref) => SessionManagerPort(ref),
);

/// [SessionPortRegistry]의 프로덕션 구현. Riverpod [Ref]를 통해 SessionManager와
/// SessionActivityTracker의 라이브 상태를 읽어 오케스트레이터에 노출한다.
class SessionManagerPort implements SessionPortRegistry {
  SessionManagerPort(this._ref);

  final Ref _ref;

  @override
  List<SessionPort> sessions() => [
    for (final info in _ref.read(sessionManagerProvider))
      _LiveSessionPort(_ref, info.id),
  ];

  @override
  SessionPort? byId(String id) {
    final exists = _ref
        .read(sessionManagerProvider)
        .any((session) => session.id == id);
    return exists ? _LiveSessionPort(_ref, id) : null;
  }
}

/// id로 라이브 SessionInfo를 매번 resolve하는 포트. busy/화면/연결상태를
/// 스냅샷이 아닌 현재 값으로 반영한다.
class _LiveSessionPort implements SessionPort, SessionInterventionPort {
  _LiveSessionPort(this._ref, this.id);

  final Ref _ref;

  @override
  final String id;

  SessionInfo? get _info {
    for (final session in _ref.read(sessionManagerProvider)) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  String get displayName => _info?.displayName ?? id;

  @override
  bool get isConnected => _info?.status == SessionStatus.connected;

  @override
  Object get connectionIdentity {
    final info = _info;
    return (info?.engine, info?.connectedAt);
  }

  @override
  bool get isBusy {
    final attention = _ref.read(sessionAttentionProvider)[id];
    // hook의 작업 중 신호는 화면 출력이 잠시 멎어도 유지한다.
    return (attention?.source != SessionAttentionSource.screen &&
            attention?.state == SessionAttentionState.working) ||
        _ref.read(sessionActivityProvider.notifier).isBusy(id);
  }

  @override
  String? get pendingIntervention {
    final attention = _ref.read(sessionAttentionProvider)[id];
    // SCREEN 상태 캐시보다 실제 현재 화면을 다시 검사한다. hook/system은 latch를 존중한다.
    if (attention?.state != SessionAttentionState.blocked ||
        attention?.source == SessionAttentionSource.screen) {
      return null;
    }
    return '${attention!.source.label}: ${attention.message}';
  }

  @override
  String readScreen({int maxLines = 120}) =>
      _info?.engine.recentPlainText(maxLines: maxLines) ?? '';

  @override
  void sendText(String normalizedInput) {
    _info?.engine.terminal.textInput(normalizedInput);
  }

  @override
  void submit() {
    _info?.engine.terminal.keyInput(TerminalKey.enter);
  }
}
