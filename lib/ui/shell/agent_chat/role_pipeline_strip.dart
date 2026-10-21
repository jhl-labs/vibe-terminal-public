import 'package:flutter/material.dart';

import '../../../agent/agent_models.dart';
import '../../../agent/agent_session_role.dart';
import '../../../app/theme.dart';
import 'role_badges.dart';

/// 파이프라인 한 단계의 상태.
enum StageStatus {
  /// 이 역할을 맡은 세션이 없다.
  none,

  /// 세션은 있지만 아직 아무 지시도 돌지 않는다.
  idle,

  /// 전송됐거나 작업 중인 세션이 있다.
  working,

  /// 이 단계의 세션이 모두 끝났다.
  done,

  /// 오류나 승인·입력 대기가 있다. 사람 손이 필요하다.
  error,
}

/// 역할 기반 작업 흐름을 한 줄로 보여 준다.
///
/// 설계·검증 → 구현 → 리뷰 → 단순 작업 순으로, 각 단계에 배정된 세션들의
/// 상태를 합쳐 보여 준다. 세션 보드는 세션 단위라 "지금 어느 공정에서
/// 막혀 있는지"가 보이지 않는다.
class RolePipelineStrip extends StatelessWidget {
  const RolePipelineStrip({super.key, required this.tasks});

  final Map<String, SessionTaskView> tasks;

  /// 화면에 그리는 단계 순서. lead는 리뷰 공정으로 둔다.
  static const List<AgentRoleKind> stageOrder = [
    AgentRoleKind.architect,
    AgentRoleKind.implementer,
    AgentRoleKind.lead,
    AgentRoleKind.operator,
  ];

  static String stageLabel(AgentRoleKind kind) => switch (kind) {
    AgentRoleKind.architect => '설계·검증',
    AgentRoleKind.implementer => '구현',
    AgentRoleKind.lead => '리뷰',
    AgentRoleKind.operator => '단순 작업',
    AgentRoleKind.custom => '사용자 정의',
  };

  /// 역할이 배정된 세션이 하나라도 있는지. 없으면 띠를 숨긴다.
  ///
  /// capability를 고른 사용자 정의 역할도 공정에 올라가므로(→ [stageOf]) 띠를
  /// 띄운다. 종류도 capability도 없는 메모뿐인 역할만 숨김 대상이다.
  static bool hasRoles(Map<String, SessionTaskView> tasks) =>
      tasks.values.any((task) => stageOf(task.role) != null);

  /// 이 역할이 올라갈 공정. 올릴 곳이 없으면 null.
  ///
  /// 프리셋 종류는 그대로 쓰고, 사용자 정의는 고른 capability 중 대표 하나로
  /// 공정을 고른다. 설계·검증 → 구현 → 리뷰 → 단순 작업 순으로 본다.
  static AgentRoleKind? stageOf(AgentSessionRole? role) {
    if (role == null) return null;
    if (role.kind != AgentRoleKind.custom) return role.kind;
    final capabilities = role.capabilities;
    if (capabilities.contains(AgentCapability.design)) {
      return AgentRoleKind.architect;
    }
    if (capabilities.contains(AgentCapability.implement) ||
        capabilities.contains(AgentCapability.runTests)) {
      return AgentRoleKind.implementer;
    }
    if (capabilities.contains(AgentCapability.review)) {
      return AgentRoleKind.lead;
    }
    if (capabilities.contains(AgentCapability.git) ||
        capabilities.contains(AgentCapability.shell)) {
      return AgentRoleKind.operator;
    }
    return null;
  }

  /// 단계별 상태를 계산한다. 위젯 없이 검증할 수 있게 분리했다.
  static Map<AgentRoleKind, StageStatus> aggregate(
    Map<String, SessionTaskView> tasks,
  ) {
    final result = <AgentRoleKind, StageStatus>{};
    for (final kind in stageOrder) {
      final staged = tasks.values
          .where((task) => stageOf(task.role) == kind)
          .toList(growable: false);
      if (staged.isEmpty) {
        result[kind] = StageStatus.none;
        continue;
      }
      if (staged.any(
        (task) =>
            task.phase == SessionTaskPhase.error ||
            task.phase == SessionTaskPhase.waitingInput,
      )) {
        result[kind] = StageStatus.error;
        continue;
      }
      if (staged.any(
        (task) =>
            task.phase == SessionTaskPhase.dispatched ||
            task.phase == SessionTaskPhase.working,
      )) {
        result[kind] = StageStatus.working;
        continue;
      }
      result[kind] = staged.every((task) => task.phase == SessionTaskPhase.done)
          ? StageStatus.done
          : StageStatus.idle;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final statuses = aggregate(tasks);
    return Container(
      key: const ValueKey('agent-role-pipeline'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: VibeColors.borderSoft)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < stageOrder.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    '→',
                    style: TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              _stage(stageOrder[i], statuses[stageOrder[i]]!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stage(AgentRoleKind kind, StageStatus status) {
    final color = _color(status);
    return Tooltip(
      key: ValueKey('agent-role-stage-${kind.name}'),
      message: '${stageLabel(kind)} · ${_statusLabel(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: status == StageStatus.none ? 0.0 : 0.14,
          ),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AgentRoleKindIcon.iconFor(kind), size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              stageLabel(kind),
              style: TextStyle(
                color: color,
                fontSize: 10,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _color(StageStatus status) => switch (status) {
    StageStatus.none => VibeColors.onSurfaceDim,
    StageStatus.idle => VibeColors.onSurfaceMuted,
    StageStatus.working => VibeColors.accent,
    StageStatus.done => VibeColors.statusConnected,
    StageStatus.error => VibeColors.warning,
  };

  static String _statusLabel(StageStatus status) => switch (status) {
    StageStatus.none => '담당 세션 없음',
    StageStatus.idle => '대기',
    StageStatus.working => '작업 중',
    StageStatus.done => '완료',
    StageStatus.error => '오류·입력 필요',
  };
}
