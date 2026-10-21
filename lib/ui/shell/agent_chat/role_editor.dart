import 'package:flutter/material.dart';

import '../../../agent/agent_session_role.dart';
import '../../../app/theme.dart';

/// 세션 하나의 역할을 편집한다.
///
/// 역할 종류·모델 라벨·capability·메모를 한 덩어리로 묶어 다이얼로그 폭
/// (540px)에 들어가도록 [Wrap]으로 접는다. 상태는 갖지 않고 변경은 모두
/// [onChanged]로 올려 보낸다.
class AgentRoleEditor extends StatelessWidget {
  const AgentRoleEditor({
    super.key,
    required this.sessionId,
    required this.role,
    required this.onChanged,
    this.detectedModel,
  });

  final String sessionId;
  final AgentSessionRole role;

  /// 화면에서 감지한 모델 라벨. 모델 입력칸의 placeholder로 쓴다.
  final String? detectedModel;

  final ValueChanged<AgentSessionRole> onChanged;

  /// 위젯 key. 테스트에서 `agent-role-kind-<sessionId>` 로 찾는다.
  Key _key(String part) => ValueKey('agent-role-$part-$sessionId');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _kindDropdown(),
            SizedBox(width: 170, child: _modelField()),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            for (final capability in AgentCapability.values)
              _capabilityChip(capability),
          ],
        ),
        const SizedBox(height: 6),
        _noteField(),
      ],
    );
  }

  Widget _kindDropdown() {
    return Tooltip(
      message: AgentSessionRole.kindDescription(role.kind),
      child: DropdownButton<AgentRoleKind>(
        key: _key('kind'),
        value: role.kind,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: VibeColors.surfaceHigh,
        style: const TextStyle(color: VibeColors.onSurface, fontSize: 11.5),
        items: [
          for (final kind in AgentRoleKind.values)
            DropdownMenuItem(
              value: kind,
              child: Text(AgentSessionRole.kindLabel(kind)),
            ),
        ],
        // 종류를 바꾸면 그 종류의 기본 capability로 되돌린다. 직접 고른 조합을
        // 섞어 두면 "설계·검증인데 git도 되는" 정체 불명 역할이 남는다.
        onChanged: (kind) {
          if (kind == null || kind == role.kind) return;
          onChanged(
            role.copyWith(
              kind: kind,
              capabilities: AgentSessionRole.defaultCapabilities(kind),
            ),
          );
        },
      ),
    );
  }

  Widget _modelField() {
    return TextFormField(
      key: _key('model'),
      initialValue: role.declaredModel ?? '',
      style: const TextStyle(color: VibeColors.onSurface, fontSize: 11.5),
      decoration: InputDecoration(
        isDense: true,
        labelText: '모델',
        hintText: detectedModel ?? '예: opus, gpt-5, qwen3-coder',
        labelStyle: const TextStyle(
          color: VibeColors.onSurfaceMuted,
          fontSize: 10.5,
        ),
        hintStyle: const TextStyle(
          color: VibeColors.onSurfaceDim,
          fontSize: 10.5,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        border: _border,
        enabledBorder: _border,
      ),
      onChanged: (value) {
        final trimmed = value.trim();
        onChanged(
          role.copyWith(declaredModel: trimmed.isEmpty ? null : trimmed),
        );
      },
    );
  }

  Widget _capabilityChip(AgentCapability capability) {
    final wire = AgentSessionRole.capabilityLabel(capability);
    final selected = role.capabilities.contains(capability);
    return FilterChip(
      key: ValueKey('agent-role-cap-$sessionId-$wire'),
      label: Text(wire, style: const TextStyle(fontSize: 10.5)),
      selected: selected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (value) {
        final next = {...role.capabilities};
        if (value) {
          next.add(capability);
        } else {
          next.remove(capability);
        }
        onChanged(role.copyWith(capabilities: next));
      },
    );
  }

  Widget _noteField() {
    return TextFormField(
      key: _key('note'),
      initialValue: role.note,
      style: const TextStyle(color: VibeColors.onSurface, fontSize: 11.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: '역할 메모 (예: 테스트 담당)',
        hintStyle: const TextStyle(
          color: VibeColors.onSurfaceDim,
          fontSize: 11,
        ),
        prefixIcon: const Icon(Icons.assignment_ind_outlined, size: 15),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 30,
          minHeight: 30,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        border: _border,
        enabledBorder: _border,
      ),
      onChanged: (value) => onChanged(role.copyWith(note: value)),
    );
  }

  static final OutlineInputBorder _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(5),
    borderSide: const BorderSide(color: VibeColors.border),
  );
}
