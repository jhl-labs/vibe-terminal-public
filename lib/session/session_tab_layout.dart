import 'session_attention.dart';
import 'session_tab_group.dart';

/// 세션 하나의 작업공간 내 위치와 탭 그룹 소속. 작업공간 세션 목록의 순서를
/// 바꾸거나 탭 그룹 소속을 바꿀 때 주고받는 최소 단위다.
class SessionPlacement {
  const SessionPlacement(this.id, this.tabGroupId);

  final String id;
  final String? tabGroupId;

  @override
  bool operator ==(Object other) =>
      other is SessionPlacement &&
      other.id == id &&
      other.tabGroupId == tabGroupId;

  @override
  int get hashCode => Object.hash(id, tabGroupId);

  @override
  String toString() => 'SessionPlacement($id, $tabGroupId)';
}

/// 세로 탭 목록의 한 덩어리: 그룹 없는 세션 하나 또는 탭 그룹 하나.
sealed class SessionTabBlock<T> {
  const SessionTabBlock();
}

class SessionTabSingle<T> extends SessionTabBlock<T> {
  const SessionTabSingle(this.item);

  final T item;
}

class SessionTabGroupBlock<T> extends SessionTabBlock<T> {
  const SessionTabGroupBlock(this.group, this.members);

  final SessionTabGroup group;
  final List<T> members;

  /// 목록에 그릴 멤버. 펼친 그룹은 모든 멤버, 접힌 그룹은 활성 멤버만이다.
  /// 활성 세션은 그룹이 접혀 있어도 항상 보인다(Ctrl+Tab·칸 포커스 등으로 접힌
  /// 그룹 안 세션이 활성이 될 때). 레일과 접힌 좌측 패널이 이 규칙을 함께 쓴다.
  List<T> visibleMembers({required bool Function(T member) isActive}) =>
      group.collapsed ? [...members.where(isActive)] : members;
}

/// 작업공간 세션 목록을 표시 덩어리로 묶는다. 탭 그룹은 첫 멤버가 나온
/// 자리에 한 번만 나오고, 멤버는 원래 순서를 유지한다. [groups]에 없는
/// tabGroupId(다른 작업공간 소속, 삭제됨 등)는 그룹 없음으로 취급한다.
List<SessionTabBlock<T>> buildSessionTabBlocks<T>(
  List<T> items, {
  required String? Function(T item) tabGroupOf,
  required Map<String, SessionTabGroup> groups,
}) {
  final members = <String, List<T>>{};
  for (final item in items) {
    final group = groups[tabGroupOf(item)];
    if (group != null) (members[group.id] ??= []).add(item);
  }
  final emitted = <String>{};
  final blocks = <SessionTabBlock<T>>[];
  for (final item in items) {
    final group = groups[tabGroupOf(item)];
    if (group == null) {
      blocks.add(SessionTabSingle(item));
    } else if (emitted.add(group.id)) {
      blocks.add(
        SessionTabGroupBlock(group, List.unmodifiable(members[group.id]!)),
      );
    }
  }
  return blocks;
}

/// 같은 탭 그룹의 세션이 이어져 있도록 첫 멤버 자리에 모은다.
/// 그룹 없는 세션의 상대 순서는 그대로다.
List<SessionPlacement> normalizeSessionPlacements(
  List<SessionPlacement> placements,
) {
  final members = <String, List<SessionPlacement>>{};
  for (final placement in placements) {
    final groupId = placement.tabGroupId;
    if (groupId != null) (members[groupId] ??= []).add(placement);
  }
  final emitted = <String>{};
  final result = <SessionPlacement>[];
  for (final placement in placements) {
    final groupId = placement.tabGroupId;
    if (groupId == null) {
      result.add(placement);
    } else if (emitted.add(groupId)) {
      result.addAll(members[groupId]!);
    }
  }
  return result;
}

/// 드롭 위치. [anchorId] 세션의 앞([after]=false) 또는 뒤에 놓고 소속을
/// [tabGroupId]로 바꾼다. [anchorId]가 null이면 맨 끝에 놓는다.
class SessionDropTarget {
  const SessionDropTarget({this.anchorId, this.after = false, this.tabGroupId});

  /// 목록 맨 끝, 그룹 밖.
  static const end = SessionDropTarget();

  final String? anchorId;
  final bool after;
  final String? tabGroupId;

  @override
  bool operator ==(Object other) =>
      other is SessionDropTarget &&
      other.anchorId == anchorId &&
      other.after == after &&
      other.tabGroupId == tabGroupId;

  @override
  int get hashCode => Object.hash(anchorId, after, tabGroupId);

  @override
  String toString() =>
      'SessionDropTarget($anchorId, after: $after, $tabGroupId)';
}

/// [sessionId]를 [target] 위치로 옮긴 새 배치. 세션이 없으면 원래 목록을
/// 그대로 돌려준다. 결과는 [normalizeSessionPlacements]로 정리돼 있다.
List<SessionPlacement> placeSession(
  List<SessionPlacement> placements,
  String sessionId,
  SessionDropTarget target,
) {
  final moving = placements.where((p) => p.id == sessionId).firstOrNull;
  if (moving == null) return placements;
  final rest = [
    for (final placement in placements)
      if (placement.id != sessionId) placement,
  ];
  var index = rest.length;
  if (target.anchorId case final anchorId? when anchorId != sessionId) {
    final anchorIndex = rest.indexWhere((p) => p.id == anchorId);
    if (anchorIndex >= 0) index = target.after ? anchorIndex + 1 : anchorIndex;
  } else if (target.anchorId == sessionId) {
    // 자기 자신 앞/뒤: 순서는 그대로 두고 소속만 바꾼다.
    index = placements.indexWhere((p) => p.id == sessionId);
  }
  rest.insert(index, SessionPlacement(sessionId, target.tabGroupId));
  return normalizeSessionPlacements(rest);
}

/// 접힌 탭 그룹 헤더에 보일 대표 상태. 확인이 필요한 상태를 우선한다
/// (입력 필요 > 완료·미확인 > 작업 중 > 대기). 상태가 하나도 없으면 null.
SessionAttentionState? strongestAttentionState(
  Iterable<SessionAttentionState?> states,
) {
  const priority = [
    SessionAttentionState.blocked,
    SessionAttentionState.done,
    SessionAttentionState.working,
    SessionAttentionState.idle,
  ];
  final present = states.whereType<SessionAttentionState>().toSet();
  for (final state in priority) {
    if (present.contains(state)) return state;
  }
  return null;
}
