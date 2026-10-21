import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'session.dart';
import 'session_restore_store.dart';
import 'session_tab_group.dart';
import 'session_tab_layout.dart';

/// 작업공간 안 탭 그룹의 표시 속성과 세션 소속 변경을 맡는다.
///
/// - 그룹 속성(이름·색·접힘)은 이 컨트롤러 상태가 갖는다.
/// - 세션 소속과 순서는 [SessionInfo.tabGroupId]와 세션 목록 순서가 갖는다.
///   소속을 바꾸는 동작은 배치([SessionPlacement])를 계산해
///   [SessionManager.arrangeSessionsInGroup] 한 번으로 반영한다.
/// - 멤버가 없어진 탭 그룹(세션 닫기·다른 작업공간 이동·그룹에서 제거)은
///   [removeEmptyGroups]로 지운다. 세션 목록을 그리는 위젯이
///   [listenSessionTabGroupCleanup]으로 세션 목록 변경마다 부른다.
///
/// 이 컨트롤러는 build에서 [sessionManagerProvider]를 구독하지 않는다.
/// [SessionManager]가 복원 스냅샷을 저장할 때 이 provider를 읽기 때문에,
/// 구독하면 순환 의존이 된다.
class SessionTabGroupController extends Notifier<SessionTabGroupState> {
  int _counter = 1;

  @override
  SessionTabGroupState build() => SessionTabGroupState.empty;

  List<SessionInfo> get _sessions => ref.read(sessionManagerProvider);

  // ── 그룹 속성 ─────────────────────────────────────────────────────────

  /// [workspaceGroupId] 작업공간에 빈 탭 그룹을 만든다. 멤버를 넣지 않으면
  /// 다음 세션 목록 변경 때 자동으로 지워지므로, 보통은 [addToNewGroup]을 쓴다.
  String create(
    String workspaceGroupId, {
    String? name,
    SessionTabGroupColor? color,
  }) {
    final existing = groupsWithMembers(workspaceGroupId);
    final id = _nextId();
    final group = SessionTabGroup(
      id: id,
      workspaceGroupId: workspaceGroupId,
      name: SessionTabGroup.cleanName(
        name,
        '$sessionTabGroupDefaultName ${existing.length + 1}',
      ),
      color: color ?? _nextColor(existing),
    );
    state = SessionTabGroupState(groups: [...state.groups, group]);
    return id;
  }

  void rename(String id, String name) =>
      _update(id, (group) => group.copyWith(name: name));

  void setColor(String id, SessionTabGroupColor color) =>
      _update(id, (group) => group.copyWith(color: color));

  void setCollapsed(String id, bool collapsed) =>
      _update(id, (group) => group.copyWith(collapsed: collapsed));

  void toggleCollapsed(String id) {
    final group = state.byId(id);
    if (group != null) setCollapsed(id, !group.collapsed);
  }

  // ── 세션 소속 ─────────────────────────────────────────────────────────

  /// 세션을 새 탭 그룹에 넣는다. 새 그룹 id를 돌려주고, 세션이 없으면 null.
  String? addToNewGroup(String sessionId, {String? name}) {
    final session = _sessionById(sessionId);
    if (session == null) return null;
    final id = create(session.groupId, name: name);
    _place(session, SessionDropTarget(anchorId: sessionId, tabGroupId: id));
    return id;
  }

  /// 세션을 같은 작업공간의 [tabGroupId] 그룹 끝으로 옮긴다.
  void moveToGroup(String sessionId, String tabGroupId) {
    final session = _sessionById(sessionId);
    final group = state.byId(tabGroupId);
    if (session == null ||
        group == null ||
        group.workspaceGroupId != session.groupId ||
        session.tabGroupId == tabGroupId) {
      return;
    }
    final lastMember = _memberIds(group).lastOrNull;
    _place(
      session,
      SessionDropTarget(
        anchorId: lastMember,
        after: lastMember != null,
        tabGroupId: tabGroupId,
      ),
    );
  }

  /// 세션을 탭 그룹에서 빼서 그룹 바로 뒤에 둔다.
  void removeFromGroup(String sessionId) {
    final session = _sessionById(sessionId);
    final group = state.byId(session?.tabGroupId);
    if (session == null || group == null) return;
    _place(
      session,
      SessionDropTarget(anchorId: _memberIds(group).last, after: true),
    );
  }

  /// 탭 그룹을 해제한다. 세션은 그 자리에 그대로 남는다.
  void ungroup(String tabGroupId) {
    final group = state.byId(tabGroupId);
    if (group == null) return;
    ref
        .read(sessionManagerProvider.notifier)
        .arrangeSessionsInGroup(group.workspaceGroupId, [
          for (final placement in _placements(group.workspaceGroupId))
            placement.tabGroupId == tabGroupId
                ? SessionPlacement(placement.id, null)
                : placement,
        ]);
    _remove(tabGroupId);
    ref.read(sessionManagerProvider.notifier).persistLayoutSoon();
  }

  /// 드래그한 세션을 [target] 위치·소속으로 옮긴다.
  void dropSession(String sessionId, SessionDropTarget target) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    final targetGroup = state.byId(target.tabGroupId);
    if (target.tabGroupId != null &&
        targetGroup?.workspaceGroupId != session.groupId) {
      return;
    }
    _place(session, target);
  }

  /// [workspaceGroupId]에서 멤버가 있는 탭 그룹. 아직 정리되지 않은 빈 그룹은
  /// 빼고 돌려준다.
  List<SessionTabGroup> groupsWithMembers(String workspaceGroupId) => [
    for (final group in state.inWorkspace(workspaceGroupId))
      if (_memberIds(group).isNotEmpty) group,
  ];

  /// [tabGroupId] 그룹 멤버 세션 id(목록 순서).
  List<String> memberIds(String tabGroupId) {
    final group = state.byId(tabGroupId);
    return group == null ? const [] : _memberIds(group);
  }

  // ── 복원 ──────────────────────────────────────────────────────────────

  void restoreFromSnapshot(SessionRestoreSnapshot snapshot) {
    for (final group in snapshot.tabGroups) {
      _reserveCounterFor(group.id);
    }
    state = SessionTabGroupState(
      groups: normalizeSessionTabGroups(snapshot.tabGroups),
    );
  }

  // ── 내부 ──────────────────────────────────────────────────────────────

  SessionInfo? _sessionById(String id) =>
      _sessions.where((session) => session.id == id).firstOrNull;

  List<String> _memberIds(SessionTabGroup group) => [
    for (final session in _sessions)
      if (session.groupId == group.workspaceGroupId &&
          session.tabGroupId == group.id)
        session.id,
  ];

  /// 작업공간 세션의 현재 배치. 이 작업공간 그룹이 아닌 tabGroupId는
  /// 그룹 없음으로 정리한다.
  List<SessionPlacement> _placements(String workspaceGroupId) {
    final groups = state.mapForWorkspace(workspaceGroupId);
    return [
      for (final session in _sessions)
        if (session.groupId == workspaceGroupId)
          SessionPlacement(
            session.id,
            groups.containsKey(session.tabGroupId) ? session.tabGroupId : null,
          ),
    ];
  }

  void _place(SessionInfo session, SessionDropTarget target) {
    final current = _placements(session.groupId);
    ref
        .read(sessionManagerProvider.notifier)
        .arrangeSessionsInGroup(
          session.groupId,
          placeSession(current, session.id, target),
        );
  }

  void _update(String id, SessionTabGroup Function(SessionTabGroup) change) {
    final index = state.groups.indexWhere((group) => group.id == id);
    if (index < 0) return;
    final next = change(state.groups[index]);
    if (next == state.groups[index]) return;
    state = SessionTabGroupState(groups: [...state.groups]..[index] = next);
    ref.read(sessionManagerProvider.notifier).persistLayoutSoon();
  }

  void _remove(String id) {
    if (state.byId(id) == null) return;
    state = SessionTabGroupState(
      groups: [
        for (final group in state.groups)
          if (group.id != id) group,
      ],
    );
  }

  /// [sessions]에 멤버가 하나도 없는 탭 그룹을 지운다.
  void removeEmptyGroups(List<SessionInfo> sessions) {
    final used = <String>{
      for (final session in sessions)
        if (session.tabGroupId case final id?) '${session.groupId}/$id',
    };
    final kept = [
      for (final group in state.groups)
        if (used.contains('${group.workspaceGroupId}/${group.id}')) group,
    ];
    if (kept.length == state.groups.length) return;
    state = SessionTabGroupState(groups: kept);
  }

  /// 같은 작업공간에서 아직 쓰지 않은 색을 팔레트 순서대로 고른다.
  SessionTabGroupColor _nextColor(List<SessionTabGroup> existing) {
    final used = existing.map((group) => group.color).toSet();
    for (final color in SessionTabGroupColor.values) {
      if (color != SessionTabGroupColor.grey && !used.contains(color)) {
        return color;
      }
    }
    return SessionTabGroupColor.values[(existing.length + 1) %
        SessionTabGroupColor.values.length];
  }

  String _nextId() {
    while (state.byId('t$_counter') != null) {
      _counter++;
    }
    return 't${_counter++}';
  }

  static final _generatedIdPattern = RegExp(r'^t(\d+)$');

  void _reserveCounterFor(String id) {
    final match = _generatedIdPattern.firstMatch(id);
    final index = match == null ? null : int.tryParse(match.group(1)!);
    if (index != null && _counter <= index) _counter = index + 1;
  }
}

final sessionTabGroupProvider =
    NotifierProvider<SessionTabGroupController, SessionTabGroupState>(
      SessionTabGroupController.new,
    );

/// 세션 목록이 바뀔 때마다 멤버 없는 탭 그룹을 지우도록 구독한다. 세션 목록을
/// 그리는 위젯([SessionRail], 접힌 좌측 패널)의 build에서 부른다.
void listenSessionTabGroupCleanup(WidgetRef ref) {
  ref.listen<List<SessionInfo>>(
    sessionManagerProvider,
    (_, sessions) =>
        ref.read(sessionTabGroupProvider.notifier).removeEmptyGroups(sessions),
  );
}
