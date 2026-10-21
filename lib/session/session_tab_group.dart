import 'session_group.dart';

/// 탭 그룹 색상. 브라우저 세로 탭 그룹처럼 작은 고정 팔레트만 둔다.
/// 실제 색 값은 UI 계층(`session_tab_group_style.dart`)이 정한다.
enum SessionTabGroupColor {
  grey,
  blue,
  red,
  yellow,
  green,
  pink,
  purple,
  cyan,
  orange;

  static SessionTabGroupColor? fromName(Object? value) {
    if (value is! String) return null;
    for (final color in values) {
      if (color.name == value) return color;
    }
    return null;
  }
}

const sessionTabGroupNameMaxLength = 40;
const sessionTabGroupDefaultName = '탭 그룹';

/// 작업공간([SessionGroup]) 안에서 세션 탭을 묶는 하위 그룹.
///
/// 한 탭 그룹은 정확히 하나의 작업공간([workspaceGroupId])에 속한다. 세션의
/// 소속은 [SessionInfo.tabGroupId]가 갖고, 이 객체는 표시 속성(이름·색·접힘)만
/// 갖는다.
class SessionTabGroup {
  const SessionTabGroup({
    required this.id,
    required this.workspaceGroupId,
    required this.name,
    this.color = SessionTabGroupColor.grey,
    this.collapsed = false,
  });

  final String id;
  final String workspaceGroupId;
  final String name;
  final SessionTabGroupColor color;
  final bool collapsed;

  SessionTabGroup copyWith({
    String? name,
    SessionTabGroupColor? color,
    bool? collapsed,
  }) => SessionTabGroup(
    id: id,
    workspaceGroupId: workspaceGroupId,
    name: name == null ? this.name : cleanName(name, this.name),
    color: color ?? this.color,
    collapsed: collapsed ?? this.collapsed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'workspaceGroupId': workspaceGroupId,
    'name': name,
    'color': color.name,
    if (collapsed) 'collapsed': true,
  };

  static SessionTabGroup? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawId = value['id'];
    if (rawId is! String || rawId.trim().isEmpty) return null;
    final rawWorkspace = value['workspaceGroupId'];
    final rawName = value['name'];
    return SessionTabGroup(
      id: rawId.trim(),
      workspaceGroupId: rawWorkspace is String && rawWorkspace.trim().isNotEmpty
          ? rawWorkspace.trim()
          : defaultSessionGroupId,
      name: cleanName(
        rawName is String ? rawName : null,
        sessionTabGroupDefaultName,
      ),
      color:
          SessionTabGroupColor.fromName(value['color']) ??
          SessionTabGroupColor.grey,
      collapsed: value['collapsed'] == true,
    );
  }

  static String cleanName(String? value, String fallback) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return fallback;
    return cleaned.length <= sessionTabGroupNameMaxLength
        ? cleaned
        : cleaned.substring(0, sessionTabGroupNameMaxLength).trim();
  }

  @override
  bool operator ==(Object other) =>
      other is SessionTabGroup &&
      other.id == id &&
      other.workspaceGroupId == workspaceGroupId &&
      other.name == name &&
      other.color == color &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(id, workspaceGroupId, name, color, collapsed);
}

/// 모든 작업공간의 탭 그룹 목록. 순서는 의미가 없고(표시 순서는 세션 순서가
/// 정한다) id로 찾는다.
class SessionTabGroupState {
  const SessionTabGroupState({this.groups = const []});

  static const empty = SessionTabGroupState();

  final List<SessionTabGroup> groups;

  SessionTabGroup? byId(String? id) {
    if (id == null) return null;
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  List<SessionTabGroup> inWorkspace(String workspaceGroupId) => [
    for (final group in groups)
      if (group.workspaceGroupId == workspaceGroupId) group,
  ];

  /// [workspaceGroupId]의 탭 그룹을 id로 찾는 맵. 다른 작업공간의 그룹은
  /// 들어 있지 않으므로 이 맵에 없는 tabGroupId는 "그룹 없음"으로 취급한다.
  Map<String, SessionTabGroup> mapForWorkspace(String workspaceGroupId) => {
    for (final group in groups)
      if (group.workspaceGroupId == workspaceGroupId) group.id: group,
  };
}

/// 저장된 탭 그룹 목록을 정리한다. 빈 id·중복 id를 버린다.
List<SessionTabGroup> normalizeSessionTabGroups(
  Iterable<SessionTabGroup> groups,
) {
  final byId = <String, SessionTabGroup>{};
  for (final group in groups) {
    if (group.id.isEmpty || byId.containsKey(group.id)) continue;
    byId[group.id] = group;
  }
  return List.unmodifiable(byId.values);
}
