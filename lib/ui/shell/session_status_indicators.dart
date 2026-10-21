import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../session/session.dart';
import '../../session/session_attention.dart';
import '../common/activity_clock.dart';

/// 세션 연결 상태 색. 세션 레일·접힌 패널·정보 툴팁이 같은 색을 쓴다.
Color sessionStatusColor(SessionStatus status) => switch (status) {
  SessionStatus.connecting => VibeColors.statusConnecting,
  SessionStatus.connected => VibeColors.statusConnected,
  SessionStatus.disconnected => VibeColors.statusDisconnected,
  SessionStatus.error => VibeColors.statusError,
};

String sessionStatusLabel(SessionStatus status) => switch (status) {
  SessionStatus.connecting => '연결 중',
  SessionStatus.connected => '연결됨',
  SessionStatus.disconnected => '연결 끊김',
  SessionStatus.error => '오류',
};

extension SessionAttentionStateStyle on SessionAttentionState {
  String get label => switch (this) {
    SessionAttentionState.idle => '대기',
    SessionAttentionState.working => '작업 중',
    SessionAttentionState.done => '완료 · 미확인',
    SessionAttentionState.blocked => '입력 필요',
  };

  IconData get icon => switch (this) {
    SessionAttentionState.idle => Icons.circle,
    SessionAttentionState.working => Icons.sync,
    SessionAttentionState.done => Icons.check_circle_outline,
    SessionAttentionState.blocked => Icons.error_outline,
  };

  Color get color => switch (this) {
    SessionAttentionState.idle => VibeColors.statusConnected,
    SessionAttentionState.working => VibeColors.accent,
    SessionAttentionState.done => VibeColors.accent,
    SessionAttentionState.blocked => VibeColors.statusError,
  };
}

/// 세션이 작업 중(busy)일 때 보여주는 작은 회전 인디케이터.
class SessionBusyIndicator extends StatelessWidget {
  const SessionBusyIndicator({super.key, this.size = 13, this.padding = 4});

  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Tooltip(
        message: '작업 중',
        child: SizedBox(
          width: size,
          height: size,
          child: const ActivitySpinner(color: VibeColors.accent),
        ),
      ),
    );
  }
}

/// Agent 세션의 상태 표시: 대기(초록 점)·작업 중(스피너)·완료·입력 필요.
class AgentAttentionIndicator extends StatelessWidget {
  const AgentAttentionIndicator({
    super.key,
    required this.state,
    this.agentHint,
    this.size = 15,
    this.padding = 4,
  });

  final SessionAttentionState state;
  final String? agentHint;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    if (state == SessionAttentionState.working) {
      return SessionBusyIndicator(size: size - 2, padding: padding);
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Tooltip(
        message: '${agentHint ?? 'SESSION'} · ${state.label}',
        child: Icon(state.icon, size: size, color: state.color),
      ),
    );
  }
}
