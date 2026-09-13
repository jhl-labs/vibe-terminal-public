import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 연결 진단 이벤트 종류. 정보 탭에 한국어 라벨로 표시된다.
enum SessionEventType {
  pingSent('keepalive 전송'),
  pingFailed('keepalive 실패'),
  dropped('연결 끊김'),
  reconnectScheduled('재연결 예약'),
  reconnectAttempt('재연결 시도'),
  reconnected('재연결 성공'),
  remoteSessionCreated('원격 작업 시작'),
  remoteSessionResumed('원격 작업 복원'),
  reconnectGaveUp('자동 재연결 중단'),
  x11Unavailable('X11 서버 없음');

  const SessionEventType(this.label);
  final String label;
}

/// 세션 연결 진단 이벤트 한 건.
class SessionEvent {
  SessionEvent(this.type, {this.detail}) : at = DateTime.now();
  final SessionEventType type;
  final DateTime at;
  final String? detail;
}

/// 세션별 연결 이벤트 링버퍼(최근 [maxEventsPerSession]건, 메모리만).
///
/// 백그라운드 keepalive가 실제로 동작하는지 기기에서 증명하기 위한
/// 진단 용도다. 파일로 저장하지 않는다(민감정보·복잡도 회피).
class SessionDiagnostics extends Notifier<Map<String, List<SessionEvent>>> {
  static const maxEventsPerSession = 200;

  @override
  Map<String, List<SessionEvent>> build() => const {};

  void record(String sessionId, SessionEventType type, {String? detail}) {
    final current = [...?state[sessionId], SessionEvent(type, detail: detail)];
    if (current.length > maxEventsPerSession) {
      current.removeRange(0, current.length - maxEventsPerSession);
    }
    state = {...state, sessionId: current};
  }

  void remove(String sessionId) {
    if (!state.containsKey(sessionId)) return;
    final next = {...state}..remove(sessionId);
    state = next;
  }
}
