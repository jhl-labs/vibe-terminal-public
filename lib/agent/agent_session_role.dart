/// Agent Chat 세션 역할 프로필.
///
/// 역할은 CLI·모델에 비특화다. 모델 라벨은 사용자가 적는 자유 문자열이고,
/// 기본 capability·타임아웃 같은 규칙은 모델이 아니라 "역할 종류"에 붙는다.
library;

/// 역할 종류. 팀 프리셋 4종과 사용자 정의.
enum AgentRoleKind {
  /// 설계·검증 담당.
  architect,

  /// 설계·구현·리뷰를 모두 보는 리드.
  lead,

  /// 설계를 받아 구현만 담당.
  implementer,

  /// git add/commit 등 단순 작업 담당.
  operator,

  /// 프리셋에 맞지 않는 자유 역할(기존 자유 텍스트 메모 호환).
  custom,
}

/// 세션이 맡을 수 있는 작업 종류.
enum AgentCapability { design, review, implement, runTests, git, shell }

/// 세션 하나에 배정된 역할.
///
/// 불변 값이며 변경은 [copyWith]로 새 인스턴스를 만든다.
class AgentSessionRole {
  const AgentSessionRole({
    required this.kind,
    this.declaredModel,
    required this.capabilities,
    this.note = '',
    this.timeoutSeconds,
  });

  /// 역할 종류.
  final AgentRoleKind kind;

  /// 사용자가 선언한 모델 라벨. 자유 문자열이며 CLI와 무관하다.
  final String? declaredModel;

  /// 이 세션이 맡을 수 있는 작업들.
  final Set<AgentCapability> capabilities;

  /// 자유 텍스트 역할 메모. 예전 문자열 역할이 여기로 들어온다.
  final String note;

  /// 이 역할의 관찰 타임아웃(초). null이면 종류 기본값을 쓴다.
  final int? timeoutSeconds;

  /// 아무 정보도 없는 역할. 저장·전달에서 걸러낸다.
  bool get isEmpty =>
      kind == AgentRoleKind.custom &&
      (declaredModel == null || declaredModel!.trim().isEmpty) &&
      capabilities.isEmpty &&
      note.trim().isEmpty;

  /// 실제 적용할 타임아웃(초).
  int get effectiveTimeoutSeconds => timeoutSeconds ?? defaultTimeoutFor(kind);

  /// 인벤토리·UI 표기. 없는 요소는 생략한다.
  ///
  /// 예) `설계·검증 [opus] · can: design,review · 메모`
  /// 사용자 정의 + 메모만 있으면 메모 그대로라, 예전 자유 텍스트와 같아 보인다.
  String get label {
    final model = declaredModel?.trim() ?? '';
    final trimmedNote = note.trim();
    final parts = <String>[];
    if (kind != AgentRoleKind.custom) {
      parts.add(
        model.isEmpty ? kindLabel(kind) : '${kindLabel(kind)} [$model]',
      );
    } else if (model.isNotEmpty) {
      parts.add('[$model]');
    }
    if (capabilities.isNotEmpty) {
      parts.add('can: ${_sortedCapabilityNames().join(',')}');
    }
    if (trimmedNote.isNotEmpty) parts.add(trimmedNote);
    if (parts.isEmpty) return kindLabel(kind);
    return parts.join(' · ');
  }

  List<String> _sortedCapabilityNames() {
    final names = capabilities.map(capabilityLabel).toList()..sort();
    return names;
  }

  AgentSessionRole copyWith({
    AgentRoleKind? kind,
    Object? declaredModel = _unchanged,
    Set<AgentCapability>? capabilities,
    String? note,
    Object? timeoutSeconds = _unchanged,
  }) => AgentSessionRole(
    kind: kind ?? this.kind,
    declaredModel: identical(declaredModel, _unchanged)
        ? this.declaredModel
        : declaredModel as String?,
    capabilities: capabilities ?? this.capabilities,
    note: note ?? this.note,
    timeoutSeconds: identical(timeoutSeconds, _unchanged)
        ? this.timeoutSeconds
        : timeoutSeconds as int?,
  );

  Map<String, Object?> toJson() {
    final model = declaredModel?.trim() ?? '';
    final trimmedNote = note.trim();
    return {
      'kind': kind.name,
      if (model.isNotEmpty) 'model': model,
      'capabilities': _sortedCapabilityNames(),
      if (trimmedNote.isNotEmpty) 'note': trimmedNote,
      if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
    };
  }

  /// JSON에서 역할을 읽는다.
  ///
  /// 문자열이면 예전 자유 텍스트 역할이므로 `custom(note)`로 강등한다.
  /// 손상된 값은 기본값으로 메우고 경고하지 않는다(설계 §8).
  static AgentSessionRole? fromJson(Object? value) {
    if (value is String) {
      final note = value.trim();
      if (note.isEmpty) return null;
      return AgentSessionRole(
        kind: AgentRoleKind.custom,
        capabilities: const {},
        note: note,
      );
    }
    if (value is! Map) return null;
    final kind = _kindByName(value['kind']) ?? AgentRoleKind.custom;
    final rawCaps = value['capabilities'];
    final caps = <AgentCapability>{};
    if (rawCaps is List) {
      for (final item in rawCaps) {
        final cap = capabilityFromWire(item?.toString() ?? '');
        if (cap != null) caps.add(cap);
      }
    }
    final model = value['model']?.toString().trim() ?? '';
    final note = value['note']?.toString().trim() ?? '';
    final timeout = value['timeoutSeconds'];
    final role = AgentSessionRole(
      kind: kind,
      declaredModel: model.isEmpty ? null : model,
      capabilities: caps,
      note: note,
      timeoutSeconds: timeout is int
          ? timeout
          : int.tryParse(timeout?.toString() ?? ''),
    );
    return role.isEmpty ? null : role;
  }

  /// 역할 종류 프리셋. capabilities는 종류 기본값으로 채운다.
  static AgentSessionRole preset(
    AgentRoleKind kind, {
    String? declaredModel,
    String note = '',
  }) => AgentSessionRole(
    kind: kind,
    declaredModel: declaredModel,
    capabilities: defaultCapabilities(kind),
    note: note,
  );

  /// "4단 팀" 프리셋에서 선택 세션 순서대로 배정할 역할 종류.
  static const List<AgentRoleKind> teamPresetOrder = [
    AgentRoleKind.architect,
    AgentRoleKind.lead,
    AgentRoleKind.implementer,
    AgentRoleKind.operator,
  ];

  static String kindLabel(AgentRoleKind kind) => switch (kind) {
    AgentRoleKind.architect => '설계·검증',
    AgentRoleKind.lead => '설계·구현·리뷰',
    AgentRoleKind.implementer => '구현',
    AgentRoleKind.operator => '단순 작업',
    AgentRoleKind.custom => '사용자 정의',
  };

  static String kindDescription(AgentRoleKind kind) => switch (kind) {
    AgentRoleKind.architect => '아주 어려운 검증·설계를 맡는다.',
    AgentRoleKind.lead => '설계·복잡한 구현·코드 리뷰를 모두 본다.',
    AgentRoleKind.implementer => '설계를 받아 구현과 테스트를 맡는다.',
    AgentRoleKind.operator => 'git add/commit 등 단순 작업을 맡는다.',
    AgentRoleKind.custom => '자유롭게 정의하는 역할.',
  };

  static Set<AgentCapability> defaultCapabilities(AgentRoleKind kind) =>
      switch (kind) {
        AgentRoleKind.architect => const {
          AgentCapability.design,
          AgentCapability.review,
        },
        AgentRoleKind.lead => const {
          AgentCapability.design,
          AgentCapability.implement,
          AgentCapability.review,
          AgentCapability.runTests,
        },
        AgentRoleKind.implementer => const {
          AgentCapability.implement,
          AgentCapability.runTests,
        },
        AgentRoleKind.operator => const {
          AgentCapability.git,
          AgentCapability.shell,
        },
        AgentRoleKind.custom => const {},
      };

  /// 역할 종류별 기본 관찰 타임아웃(초). 모델과 무관하다.
  static int defaultTimeoutFor(AgentRoleKind kind) => switch (kind) {
    AgentRoleKind.architect => 600,
    AgentRoleKind.lead => 600,
    AgentRoleKind.implementer => 300,
    AgentRoleKind.operator => 120,
    AgentRoleKind.custom => 180,
  };

  /// 프롬프트·JSON에 쓰는 capability 이름.
  static String capabilityLabel(AgentCapability capability) =>
      switch (capability) {
        AgentCapability.design => 'design',
        AgentCapability.review => 'review',
        AgentCapability.implement => 'implement',
        AgentCapability.runTests => 'run_tests',
        AgentCapability.git => 'git',
        AgentCapability.shell => 'shell',
      };

  static AgentCapability? capabilityFromWire(String raw) {
    final name = raw.trim().toLowerCase();
    for (final capability in AgentCapability.values) {
      if (capabilityLabel(capability) == name ||
          capability.name.toLowerCase() == name) {
        return capability;
      }
    }
    return null;
  }

  static AgentRoleKind? _kindByName(Object? raw) {
    if (raw is! String) return null;
    for (final kind in AgentRoleKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AgentSessionRole &&
      other.kind == kind &&
      other.declaredModel == declaredModel &&
      other.note == note &&
      other.timeoutSeconds == timeoutSeconds &&
      other.capabilities.length == capabilities.length &&
      other.capabilities.containsAll(capabilities);

  @override
  int get hashCode => Object.hash(
    kind,
    declaredModel,
    note,
    timeoutSeconds,
    Object.hashAllUnordered(capabilities),
  );

  @override
  String toString() => 'AgentSessionRole(${toJson()})';
}

const Object _unchanged = Object();

/// 세션 id → 역할 맵을 JSON에서 읽는다. 예전 문자열 맵도 그대로 받는다.
Map<String, AgentSessionRole> sessionRolesFromJson(Object? value) {
  if (value is! Map) return const {};
  final result = <String, AgentSessionRole>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final role = AgentSessionRole.fromJson(entry.value);
    if (role != null && !role.isEmpty) result[key] = role;
  }
  return result;
}

/// 세션 id → 역할 맵을 JSON으로 적는다. 빈 역할은 건너뛴다.
Map<String, Object?> sessionRolesToJson(Map<String, AgentSessionRole> roles) =>
    {
      for (final entry in roles.entries)
        if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
    };
