import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'session_attention.dart';

/// 세션별 busy/idle 상태를 터미널 출력 활동으로 추적한다.
///
/// 서버 출력이 도착하면 busy로 전환하고, [idleDelay] 동안 추가 출력이 없으면
/// idle로 돌린다(= 작업 단락 완료로 간주). busy가 [minBusyForNotify] 이상
/// 지속됐고, 그 세션을 사용자가 보고 있지 않으면 작업당 한 번 완료 알림을 보낸다.
class SessionActivityTracker extends Notifier<Map<String, bool>> {
  /// 출력이 멈춘 뒤 idle로 판정하기까지의 대기 시간.
  static const idleDelay = Duration(milliseconds: 1500);

  /// 완료 알림을 보낼 최소 busy 지속 시간(짧은 프롬프트 출력 등은 제외).
  static const minBusyForNotify = Duration(seconds: 3);

  final Map<String, Timer> _timers = {};
  final Map<String, DateTime> _busySince = {};
  final Map<String, String> _latestScreens = {};
  final Set<String> _notifiedTaskIds = {};

  @override
  Map<String, bool> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  bool isBusy(String id) => state[id] ?? false;

  /// Enter로 새 명령이나 Agent 요청이 제출되면 다음 완료를 새 작업으로 취급한다.
  ///
  /// 출력 사이의 짧은 정지는 같은 작업 안에서도 여러 번 생기므로 알림 latch를
  /// 출력 재개만으로 풀지 않는다. 사용자의 명시적인 제출이 새 작업의 경계다.
  void markTaskSubmitted(String id) {
    _notifiedTaskIds.remove(id);
  }

  /// 세션 [id]에 출력 활동이 있었음을 알린다(매 출력마다 호출돼도 가볍다).
  void markActivity(String id, {String screen = ''}) {
    if (screen.isNotEmpty) _latestScreens[id] = screen;
    if (!(state[id] ?? false)) {
      _busySince[id] = _now();
      state = {...state, id: true};
    }
    ref
        .read(sessionAttentionProvider.notifier)
        .markWorking(id, _latestScreens[id] ?? screen);
    _timers[id]?.cancel();
    _timers[id] = Timer(idleDelay, () => _toIdle(id));
  }

  void _toIdle(String id) {
    _timers.remove(id);
    if (!(state[id] ?? false)) return;
    final since = _busySince.remove(id);
    state = {...state, id: false};
    final busyFor = since == null ? Duration.zero : _now().difference(since);
    final completedLongTask = busyFor >= minBusyForNotify;
    final userIsWatching = _userIsWatching(id);
    final attention = ref
        .read(sessionAttentionProvider.notifier)
        .settle(
          id,
          _latestScreens[id] ?? '',
          completedLongTask: completedLongTask,
          userIsWatching: userIsWatching,
        );
    final shouldNotify = attention == null
        ? completedLongTask
        : attention.needsAttention;
    if (shouldNotify) {
      _maybeNotify(id);
    }
  }

  /// 사용자가 보고 있지 않은 세션이면(다른 세션이 활성이거나 앱이 백그라운드)
  /// 완료 알림을 보낸다.
  void _maybeNotify(String id) {
    if (_notifiedTaskIds.contains(id)) return;
    if (!ref.read(appSettingsProvider).notifications.canShowTaskComplete) {
      return;
    }
    if (_userIsWatching(id)) return;

    // 비동기 알림 표시가 끝나기 전에 같은 idle 판정이 다시 들어와도 한 번만
    // 전송되도록 호출 전에 latch를 닫는다.
    _notifiedTaskIds.add(id);

    final sessions = ref.read(sessionManagerProvider);
    var name = id;
    for (final s in sessions) {
      if (s.id == id) {
        name = s.displayName;
        break;
      }
    }
    unawaited(ref.read(notificationServiceProvider).showTaskComplete(name));
  }

  /// 세션이 닫히면 상태와 타이머를 정리한다.
  void remove(String id) {
    _timers.remove(id)?.cancel();
    _busySince.remove(id);
    _latestScreens.remove(id);
    _notifiedTaskIds.remove(id);
    ref.read(sessionAttentionProvider.notifier).remove(id);
    if (state.containsKey(id)) {
      state = {...state}..remove(id);
    }
  }

  bool _userIsWatching(String id) =>
      ref.read(appForegroundProvider) &&
      ref.read(activeSessionIdProvider) == id;

  DateTime _now() => clock.now();
}

final sessionActivityProvider =
    NotifierProvider<SessionActivityTracker, Map<String, bool>>(
      SessionActivityTracker.new,
    );
