import 'dart:async';
import 'dart:collection';

/// 세션별 연속 keepalive 무응답 횟수를 센다.
///
/// 부하가 높은 서버는 keepalive에 수 초씩 늦게 답하기도 한다. 한 번의 무응답을
/// 끊김으로 보면 살아 있는 연결을 끊고 재연결 폭주를 만들므로, [threshold]번
/// 연속일 때만 끊김으로 판정한다.
class KeepaliveMissTracker {
  KeepaliveMissTracker({this.threshold = 2}) : assert(threshold > 0);

  final int threshold;
  final Map<String, int> _misses = {};

  int missesFor(String id) => _misses[id] ?? 0;

  /// 무응답을 기록하고, 끊김으로 판정해야 하면 true를 반환한다.
  bool recordMiss(String id) {
    final misses = missesFor(id) + 1;
    if (misses >= threshold) {
      _misses.remove(id);
      return true;
    }
    _misses[id] = misses;
    return false;
  }

  void recordSuccess(String id) => _misses.remove(id);

  void forget(String id) => _misses.remove(id);
}

/// 동시에 진행할 수 있는 작업 수를 제한하는 비동기 세마포어.
class ConnectGate {
  ConnectGate(this.capacity) : assert(capacity > 0);

  final int capacity;
  int _active = 0;
  final _waiters = Queue<Completer<void>>();

  int get active => _active;
  int get waiting => _waiters.length;

  Future<void> acquire() {
    if (_active < capacity) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  /// 대기자가 있으면 슬롯을 바로 넘기고, 없으면 반납한다.
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else if (_active > 0) {
      _active--;
    }
  }
}
