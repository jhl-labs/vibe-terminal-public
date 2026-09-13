const defaultSessionGroupId = 'default';
const defaultSessionGroupName = '기본';

class SessionGroup {
  const SessionGroup({required this.id, required this.name});

  static const defaultGroup = SessionGroup(
    id: defaultSessionGroupId,
    name: defaultSessionGroupName,
  );

  final String id;
  final String name;

  bool get isDefault => id == defaultSessionGroupId;

  SessionGroup copyWith({String? name}) =>
      SessionGroup(id: id, name: cleanName(name ?? this.name, nameFallback));

  String get nameFallback => isDefault ? defaultSessionGroupName : '그룹';

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static SessionGroup? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawId = value['id'];
    if (rawId is! String) return null;
    final id = rawId.trim();
    if (id.isEmpty) return null;
    if (id == defaultSessionGroupId) return defaultGroup;

    final rawName = value['name'];
    return SessionGroup(
      id: id,
      name: cleanName(rawName is String ? rawName : null, '그룹'),
    );
  }

  static String cleanName(String? value, String fallback) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return fallback;
    return cleaned.length <= 40 ? cleaned : cleaned.substring(0, 40).trim();
  }
}

class SessionGroupState {
  const SessionGroupState({
    this.groups = const [SessionGroup.defaultGroup],
    this.activeGroupId = defaultSessionGroupId,
  });

  static const initial = SessionGroupState();

  final List<SessionGroup> groups;
  final String activeGroupId;

  SessionGroup get activeGroup {
    for (final group in groups) {
      if (group.id == activeGroupId) return group;
    }
    return SessionGroup.defaultGroup;
  }

  bool contains(String id) => groups.any((group) => group.id == id);

  SessionGroupState copyWith({
    List<SessionGroup>? groups,
    String? activeGroupId,
  }) {
    final normalizedGroups = normalizeSessionGroups(groups ?? this.groups);
    final nextActive = activeGroupId ?? this.activeGroupId;
    return SessionGroupState(
      groups: normalizedGroups,
      activeGroupId: normalizedGroups.any((group) => group.id == nextActive)
          ? nextActive
          : defaultSessionGroupId,
    );
  }
}

List<SessionGroup> normalizeSessionGroups(
  Iterable<SessionGroup> groups, {
  Iterable<String> requiredIds = const [],
}) {
  final byId = <String, SessionGroup>{};
  byId[defaultSessionGroupId] = SessionGroup.defaultGroup;

  for (final group in groups) {
    final id = group.id.trim();
    if (id.isEmpty) continue;
    if (id == defaultSessionGroupId) {
      byId[defaultSessionGroupId] = SessionGroup.defaultGroup;
      continue;
    }
    byId[id] = SessionGroup(
      id: id,
      name: SessionGroup.cleanName(group.name, '그룹'),
    );
  }

  var fallbackIndex = byId.length;
  for (final rawId in requiredIds) {
    final id = rawId.trim();
    if (id.isEmpty || byId.containsKey(id)) continue;
    byId[id] = SessionGroup(id: id, name: '그룹 ${fallbackIndex++}');
  }

  return List.unmodifiable(byId.values);
}
