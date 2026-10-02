import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 세션별 알림 음소거.
///
/// 음소거한 세션에서 나오는 시스템 알림(작업 완료, 자동 재개, 능동 감시,
/// AI Chat 예약)을 보내지 않는다. 전역 알림 설정과 별개로 "이 세션만 조용히"를
/// 위한 것이라 앱 실행 동안만 유지하고, 닫힌 세션은 [retainOnly]로 정리한다.
class SessionNotificationMute extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isMuted(String sessionId) => state.contains(sessionId);

  void toggle(String sessionId) {
    state = state.contains(sessionId)
        ? ({...state}..remove(sessionId))
        : {...state, sessionId};
  }

  /// 열린 세션만 남긴다. 닫힌 세션의 id가 재사용돼도 음소거가 따라가지 않게 한다.
  void retainOnly(Iterable<String> openSessionIds) {
    final open = openSessionIds.toSet();
    if (state.every(open.contains)) return;
    state = state.where(open.contains).toSet();
  }
}

final sessionNotificationMuteProvider =
    NotifierProvider<SessionNotificationMute, Set<String>>(
      SessionNotificationMute.new,
    );
