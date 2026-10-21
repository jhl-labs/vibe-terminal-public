import 'dart:async';

import 'autopilot_prefs_store.dart';

/// [AutopilotPrefsSync.reconcile] 결과: 지금 켤 세션과 버린 저장 항목.
class AutopilotRestorePass {
  const AutopilotRestorePass({required this.apply, required this.dropped});

  final Map<String, AutopilotPrefs> apply;
  final List<String> dropped;

  static const empty = AutopilotRestorePass(apply: {}, dropped: []);
}

/// 자율사용 토글의 저장과 재시작 뒤 복원 대기 목록을 맡는다.
///
/// 세션 id(`sN`)는 순번이라, 지난 실행에서 복원되지 않은 세션(오류 상태로
/// 스냅샷에서 빠졌거나 호스트가 지워진 경우)의 id를 나중에 연 새 세션이 다시
/// 받을 수 있다. 사용자가 켠 적 없는 세션에 자율사용이 켜지면 안 되므로, 저장
/// 항목은 "앱 시작 복원으로 만든 같은 id·같은 호스트의 세션"에만 되살리고 그 밖의
/// 항목은 버린다.
class AutopilotPrefsSync {
  AutopilotPrefsSync(this._store);

  final AutopilotPrefsStore _store;

  /// 디스크에서 읽었지만 아직 되살리지 못한 토글(복원된 세션의 포트가 아직 없음).
  Map<String, AutopilotPrefs> _pending = {};

  /// 로드 전에 저장하면 디스크의 다른 세션 설정을 지우므로 로드 뒤에만 쓴다.
  bool _loaded = false;

  bool get hasPending => _pending.isNotEmpty;

  bool isPending(String id) => _pending.containsKey(id);

  /// 디스크의 저장 토글을 읽는다. 결과는 [accept]로 넘긴다(호출자가 비동기
  /// 공백 뒤 아직 살아 있는지 확인한 다음).
  Future<Map<String, AutopilotPrefs>> read() => _store.load();

  /// 읽은 토글을 대기 목록으로 삼는다. [alreadySet]은 로드 전에 사용자가 이미
  /// 바꾼 세션이라 현재 상태가 우선한다.
  void accept(
    Map<String, AutopilotPrefs> loaded, {
    required Iterable<String> alreadySet,
  }) {
    _loaded = true;
    final skip = alreadySet.toSet();
    _pending = {
      for (final e in loaded.entries)
        if (e.value.enabled && !skip.contains(e.key)) e.key: e.value,
    };
  }

  /// 현재 세션 목록과 대조한다.
  ///
  /// - [sessionHosts]가 비어 있으면 아직 복원 전이라 아무것도 하지 않는다.
  ///   (복원은 세션 목록이 비어 있을 때만 한 번에 채운다. 목록이 비어 있지 않으면
  ///   복원이 끝났거나 앞으로도 일어나지 않는다.)
  /// - 목록에 없거나, 복원된 세션이 아니거나, 호스트가 다르거나, 호스트 정보가
  ///   없는 항목은 버린다(fail closed).
  /// - 조건이 맞아도 [hasPort]가 false면(연결 전) 다음 대조까지 기다린다.
  AutopilotRestorePass reconcile({
    required Map<String, String> sessionHosts,
    required bool Function(String id) wasRestored,
    required bool Function(String id) hasPort,
  }) {
    if (!_loaded || _pending.isEmpty || sessionHosts.isEmpty) {
      return AutopilotRestorePass.empty;
    }
    final apply = <String, AutopilotPrefs>{};
    final dropped = <String>[];
    for (final entry in _pending.entries.toList()) {
      final id = entry.key;
      final hostId = entry.value.hostId;
      final valid =
          hostId != null && sessionHosts[id] == hostId && wasRestored(id);
      if (!valid) {
        _pending.remove(id);
        dropped.add(id);
      } else if (hasPort(id)) {
        _pending.remove(id);
        apply[id] = entry.value;
      }
    }
    return AutopilotRestorePass(apply: apply, dropped: dropped);
  }

  /// 세션이 닫혀 대기 항목을 버린다. 버렸으면 true.
  bool drop(String id) => _pending.remove(id) != null;

  /// 켜진 세션 [enabled]와 아직 되살리지 못한 대기 항목을 함께 저장한다.
  void save(Map<String, AutopilotPrefs> enabled) {
    if (!_loaded) return;
    unawaited(_store.save({...enabled, ..._pending}));
  }
}
