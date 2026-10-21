import 'package:flutter/material.dart';

import '../../../agent/agent_session_role.dart';
import '../../../app/theme.dart';

/// 역할 종류를 한눈에 보여 주는 작은 아이콘.
class AgentRoleKindIcon extends StatelessWidget {
  const AgentRoleKindIcon({super.key, required this.kind, this.size = 12});

  final AgentRoleKind kind;
  final double size;

  /// 역할 종류별 아이콘. 라벨 없이도 보드에서 구분되게 한다.
  static IconData iconFor(AgentRoleKind kind) => switch (kind) {
    AgentRoleKind.architect => Icons.architecture,
    AgentRoleKind.lead => Icons.engineering,
    AgentRoleKind.implementer => Icons.build_outlined,
    AgentRoleKind.operator => Icons.terminal,
    AgentRoleKind.custom => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          '${AgentSessionRole.kindLabel(kind)} · '
          '${AgentSessionRole.kindDescription(kind)}',
      child: Icon(iconFor(kind), size: size, color: VibeColors.secondary),
    );
  }
}

/// 세션의 모델 배지.
///
/// 선언 모델이 있으면 그것을, 없으면 화면에서 감지한 모델을 보여 준다.
/// 둘이 다르면 경고색 테두리로 표시한다. 사용자가 "opus를 시켰는데 화면은
/// 다른 모델"인 상황을 보드에서 바로 알아채게 하려는 것이다.
class AgentModelBadge extends StatelessWidget {
  const AgentModelBadge({
    super.key,
    required this.sessionId,
    required this.declared,
    required this.detected,
    required this.mismatch,
  });

  final String sessionId;
  final String? declared;
  final String? detected;
  final bool mismatch;

  @override
  Widget build(BuildContext context) {
    final declaredLabel = declared?.trim() ?? '';
    final detectedLabel = detected?.trim() ?? '';
    final label = declaredLabel.isNotEmpty ? declaredLabel : detectedLabel;
    if (label.isEmpty) return const SizedBox.shrink();
    final color = mismatch ? VibeColors.warning : VibeColors.onSurfaceMuted;
    final tooltip = mismatch
        ? '선언 $declaredLabel · 화면 $detectedLabel'
        : (declaredLabel.isNotEmpty
              ? '선언 모델 $declaredLabel'
              : '화면 감지 모델 $detectedLabel');
    return Tooltip(
      key: ValueKey('agent-model-badge-$sessionId'),
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: color.withValues(alpha: mismatch ? 0.9 : 0.35),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 9,
            height: 1.15,
            fontWeight: FontWeight.w700,
            fontFamily: kMonoFontFamily,
            fontFamilyFallback: kMonoFontFallback,
          ),
        ),
      ),
    );
  }
}

/// capability 목록을 아주 작은 칩으로 나열한다.
class AgentCapabilityChips extends StatelessWidget {
  const AgentCapabilityChips({
    super.key,
    required this.capabilities,
    this.max = 3,
  });

  final Set<AgentCapability> capabilities;

  /// 보드 한 줄에 다 넣을 수 없으니 이 개수까지만 칩으로 보여 준다.
  final int max;

  @override
  Widget build(BuildContext context) {
    if (capabilities.isEmpty) return const SizedBox.shrink();
    final wires = capabilities.map(AgentSessionRole.capabilityLabel).toList()
      ..sort();
    final shown = wires.take(max).toList();
    final rest = wires.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final wire in shown) ...[
          // 좁은 보드에서는 칩 이름을 줄여서라도 넘치지 않게 한다.
          Flexible(child: _chip(wire)),
          const SizedBox(width: 3),
        ],
        if (rest > 0) _chip('+$rest'),
      ],
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    decoration: BoxDecoration(
      color: VibeColors.secondary.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: VibeColors.secondary,
        fontSize: 8.5,
        height: 1.15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
