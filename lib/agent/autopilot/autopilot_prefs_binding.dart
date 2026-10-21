import 'autopilot_prefs_store.dart';
import 'autopilot_prefs_sync.dart';
import 'autopilot_state.dart';

/// 컨트롤러 상태와 [AutopilotPrefsSync]를 잇는다: 시작 때 저장 토글 로드,
/// 복원된 세션에 되살리기, 상태가 바뀔 때 저장.
///
/// Riverpod을 직접 읽지 않고, 세션 목록·포트·상태 조회와 복원 동작을 생성자
/// 함수로 받는다.
class AutopilotPrefsBinding {
  AutopilotPrefsBinding(
    this._sync, {
    required this._states,
    required this._sessionHosts,
    required this._wasRestored,
    required this._hasPort,
    required this._restore,
    required this._record,
    required this._mounted,
  });

  final AutopilotPrefsSync _sync;
  final Map<String, AutopilotState> Function() _states;
  final Map<String, String> Function() _sessionHosts;
  final bool Function(String id) _wasRestored;
  final bool Function(String id) _hasPort;
  final void Function(String id, AutopilotPrefs prefs) _restore;
  final void Function(String id, String message) _record;
  final bool Function() _mounted;

  bool isPending(String id) => _sync.isPending(id);

  Future<void> load() async {
    // 로드 전에 이미 켠 세션은 현재 상태가 우선한다.
    final loaded = await _sync.read();
    if (!_mounted()) return;
    _sync.accept(loaded, alreadySet: _states().keys);
    reconcile();
    persist(); // 로드 전에 바꾼 토글과 버린 항목을 반영한다.
  }

  /// 저장된 토글을 복원된 같은 세션에 되살리고, 되살릴 수 없는 항목은 버린다
  /// ([AutopilotPrefsSync.reconcile]).
  void reconcile() {
    if (!_sync.hasPending) return;
    final pass = _sync.reconcile(
      sessionHosts: _sessionHosts(),
      wasRestored: _wasRestored,
      hasPort: _hasPort,
    );
    for (final id in pass.dropped) {
      _record(id, '저장된 자율사용 설정 폐기: 복원된 같은 세션이 아님');
    }
    for (final MapEntry(key: id, value: prefs) in pass.apply.entries) {
      _restore(id, prefs);
      _record(id, '이전 실행의 자율사용 설정 복원');
    }
    if (pass.dropped.isNotEmpty) persist();
  }

  /// 켜진 세션을 저장한다. 호스트를 모르는 항목은 복원할 수 없으므로 뺀다.
  void persist() {
    final hosts = _sessionHosts();
    _sync.save({
      for (final e in _states().entries)
        if (e.value.enabled)
          if (hosts[e.key] case final hostId?)
            e.key: AutopilotPrefs(
              enabled: true,
              notifyOnly: e.value.notifyOnly,
              hostId: hostId,
            ),
    });
  }

  /// 세션이 닫혔다. 대기 항목을 버리고, 상태나 대기 항목이 바뀌었으면 저장한다.
  /// [stateRemoved]는 호출자가 이미 상태에서 이 세션을 뺐는지다.
  void forget(String id, {required bool stateRemoved}) {
    final hadPending = _sync.drop(id);
    if (stateRemoved || hadPending) persist();
  }
}
