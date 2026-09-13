import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_attention.dart';
import '../agent/agent_semantic_event.dart';
import '../state/providers.dart';

enum SessionAttentionState { idle, working, done, blocked }

enum SessionAttentionSource { screen, hook, external }

extension SessionAttentionSourceLabel on SessionAttentionSource {
  String get label => switch (this) {
    SessionAttentionSource.screen => 'SCREEN',
    SessionAttentionSource.hook => 'HOOK',
    SessionAttentionSource.external => 'SYSTEM',
  };
}

class SessionAttention {
  const SessionAttention({
    required this.sessionId,
    required this.state,
    required this.agentHint,
    required this.message,
    required this.updatedAt,
    this.source = SessionAttentionSource.screen,
  });

  final String sessionId;
  final SessionAttentionState state;
  final String agentHint;
  final String message;
  final DateTime updatedAt;
  final SessionAttentionSource source;

  bool get needsAttention =>
      state == SessionAttentionState.blocked ||
      state == SessionAttentionState.done;

  SessionAttention copyWith({
    SessionAttentionState? state,
    String? agentHint,
    String? message,
    DateTime? updatedAt,
    SessionAttentionSource? source,
  }) => SessionAttention(
    sessionId: sessionId,
    state: state ?? this.state,
    agentHint: agentHint ?? this.agentHint,
    message: message ?? this.message,
    updatedAt: updatedAt ?? this.updatedAt,
    source: source ?? this.source,
  );
}

/// 세션의 Agent 상태를 사용자가 처리해야 할 순서로 유지한다.
///
/// 터미널 활동 추적은 실행 여부만 담당하고, 이 컨트롤러는 Agent 식별·입력 대기·
/// 완료 후 미확인 상태를 담당해 일반 SSH 세션과 Agent UX를 분리한다.
class SessionAttentionTracker extends Notifier<Map<String, SessionAttention>> {
  SessionAttentionTracker({AgentAttentionClassifier? classifier})
    : _classifier = classifier ?? const AgentAttentionClassifier();

  final AgentAttentionClassifier _classifier;
  final Map<String, Map<String, String>> _externalBlocks = {};
  final Map<String, AgentSemanticEvent> _semanticSignals = {};

  @override
  Map<String, SessionAttention> build() {
    ref.listen<String?>(activeSessionIdProvider, (_, next) {
      if (next != null && ref.read(appForegroundProvider)) markSeen(next);
    });
    ref.listen<bool>(appForegroundProvider, (_, foreground) {
      if (!foreground) return;
      final activeId = ref.read(activeSessionIdProvider);
      if (activeId != null) markSeen(activeId);
    });
    return const {};
  }

  void markWorking(String sessionId, String screen) {
    final assessment = _classifier.inspect(screen);
    final previous = state[sessionId];
    if (!assessment.isAgent && previous == null) return;
    final externalMessage = _externalBlockMessage(sessionId);
    final semantic = _semanticSignals[sessionId];
    if (externalMessage == null && semantic != null) {
      _set(_attentionFromSemantic(sessionId, semantic, previous: previous));
      return;
    }
    _set(
      SessionAttention(
        sessionId: sessionId,
        state: externalMessage == null
            ? SessionAttentionState.working
            : SessionAttentionState.blocked,
        agentHint: assessment.isAgent
            ? assessment.agentHint
            : previous!.agentHint,
        message: externalMessage ?? assessment.preview,
        updatedAt: clock.now(),
        source: externalMessage == null
            ? SessionAttentionSource.screen
            : SessionAttentionSource.external,
      ),
    );
  }

  SessionAttention? settle(
    String sessionId,
    String screen, {
    required bool completedLongTask,
    required bool userIsWatching,
  }) {
    final assessment = _classifier.inspect(screen);
    final previous = state[sessionId];
    if (!assessment.isAgent && previous == null) return null;

    final externalMessage = _externalBlockMessage(sessionId);
    final semantic = _semanticSignals[sessionId];
    if (externalMessage == null && semantic != null) {
      final next = _attentionFromSemantic(
        sessionId,
        semantic,
        previous: previous,
        completedLongTask: completedLongTask,
        userIsWatching: userIsWatching,
      );
      _set(next);
      return next;
    }

    final nextState = externalMessage != null || assessment.needsInput
        ? SessionAttentionState.blocked
        : completedLongTask && !userIsWatching
        ? SessionAttentionState.done
        : SessionAttentionState.idle;
    final next = SessionAttention(
      sessionId: sessionId,
      state: nextState,
      agentHint: assessment.isAgent
          ? assessment.agentHint
          : previous!.agentHint,
      message:
          externalMessage ??
          assessment.evidence ??
          (assessment.preview == '(화면 내용 없음)'
              ? previous?.message ?? assessment.preview
              : assessment.preview),
      updatedAt: clock.now(),
      source: externalMessage == null
          ? SessionAttentionSource.screen
          : SessionAttentionSource.external,
    );
    _set(next);
    return next;
  }

  void markSeen(String sessionId) {
    final current = state[sessionId];
    if (current == null || current.state != SessionAttentionState.done) return;
    _set(
      current.copyWith(
        state: SessionAttentionState.idle,
        updatedAt: clock.now(),
      ),
    );
  }

  /// CLI hook/shim의 구조화 이벤트를 화면 휴리스틱과 합친다.
  ///
  /// 이벤트는 UX 상태만 바꾸며 승인 결정을 대신하지 않는다. 같은 세션의 이후
  /// 구조화 working 이벤트가 이전 approval/completed latch를 명시적으로 푼다.
  void applySemanticEvent(
    String sessionId,
    AgentSemanticEvent event, {
    required bool userIsWatching,
  }) {
    _semanticSignals[sessionId] = event;
    final externalMessage = _externalBlockMessage(sessionId);
    if (externalMessage != null) {
      final current = state[sessionId];
      _set(
        SessionAttention(
          sessionId: sessionId,
          state: SessionAttentionState.blocked,
          agentHint: current?.agentHint ?? event.provider,
          message: externalMessage,
          updatedAt: clock.now(),
          source: SessionAttentionSource.external,
        ),
      );
      return;
    }
    _set(
      _attentionFromSemantic(
        sessionId,
        event,
        previous: state[sessionId],
        userIsWatching: userIsWatching,
      ),
    );
  }

  void markExternalBlocked(
    String sessionId, {
    required String source,
    required String message,
    required String agentHint,
  }) {
    final blocks = {...?_externalBlocks[sessionId], source: message};
    _externalBlocks[sessionId] = blocks;
    final previous = state[sessionId];
    _set(
      SessionAttention(
        sessionId: sessionId,
        state: SessionAttentionState.blocked,
        agentHint: previous?.agentHint ?? agentHint,
        message: _externalBlockMessage(sessionId)!,
        updatedAt: clock.now(),
        source: SessionAttentionSource.external,
      ),
    );
  }

  void clearExternalBlock(String sessionId, String source) {
    final blocks = _externalBlocks[sessionId];
    if (blocks == null || !blocks.containsKey(source)) return;
    blocks.remove(source);
    if (blocks.isEmpty) {
      _externalBlocks.remove(sessionId);
      final current = state[sessionId];
      if (current?.state == SessionAttentionState.blocked) {
        final semantic = _semanticSignals[sessionId];
        if (semantic != null) {
          _set(_attentionFromSemantic(sessionId, semantic, previous: current));
          return;
        }
        _set(
          current!.copyWith(
            state: SessionAttentionState.idle,
            message: '충돌이 해결되었습니다. 변경을 다시 검증하세요.',
            updatedAt: clock.now(),
            source: SessionAttentionSource.external,
          ),
        );
      }
      return;
    }
    final current = state[sessionId];
    if (current != null) {
      _set(
        current.copyWith(
          state: SessionAttentionState.blocked,
          message: _externalBlockMessage(sessionId),
          updatedAt: clock.now(),
          source: SessionAttentionSource.external,
        ),
      );
    }
  }

  void remove(String sessionId) {
    _externalBlocks.remove(sessionId);
    _semanticSignals.remove(sessionId);
    if (!state.containsKey(sessionId)) return;
    state = {...state}..remove(sessionId);
  }

  String? _externalBlockMessage(String sessionId) {
    final blocks = _externalBlocks[sessionId];
    if (blocks == null || blocks.isEmpty) return null;
    return blocks.values.join(' · ');
  }

  SessionAttention _attentionFromSemantic(
    String sessionId,
    AgentSemanticEvent event, {
    SessionAttention? previous,
    bool completedLongTask = true,
    bool userIsWatching = false,
  }) {
    final state = switch (event.phase) {
      AgentSemanticPhase.sessionStarted ||
      AgentSemanticPhase.working => SessionAttentionState.working,
      AgentSemanticPhase.waitingApproval ||
      AgentSemanticPhase.waitingInput ||
      AgentSemanticPhase.failed => SessionAttentionState.blocked,
      AgentSemanticPhase.completed =>
        previous?.source == SessionAttentionSource.hook &&
                (previous?.state == SessionAttentionState.idle ||
                    previous?.state == SessionAttentionState.done)
            ? previous!.state
            : completedLongTask && !userIsWatching
            ? SessionAttentionState.done
            : SessionAttentionState.idle,
      AgentSemanticPhase.stopped => SessionAttentionState.idle,
    };
    return SessionAttention(
      sessionId: sessionId,
      state: state,
      agentHint: event.provider,
      message: event.message ?? _semanticMessage(event.phase),
      updatedAt: clock.now(),
      source: SessionAttentionSource.hook,
    );
  }

  static String _semanticMessage(AgentSemanticPhase phase) => switch (phase) {
    AgentSemanticPhase.sessionStarted => 'Agent 세션이 시작되었습니다.',
    AgentSemanticPhase.working => 'Agent가 작업 중입니다.',
    AgentSemanticPhase.waitingApproval => 'Agent가 권한 승인을 기다립니다.',
    AgentSemanticPhase.waitingInput => 'Agent가 사용자 입력을 기다립니다.',
    AgentSemanticPhase.completed => 'Agent 작업이 완료되었습니다.',
    AgentSemanticPhase.failed => 'Agent 작업이 실패해 확인이 필요합니다.',
    AgentSemanticPhase.stopped => 'Agent 세션이 종료되었습니다.',
  };

  void _set(SessionAttention attention) {
    state = {...state, attention.sessionId: attention};
  }
}

final sessionAttentionProvider =
    NotifierProvider<SessionAttentionTracker, Map<String, SessionAttention>>(
      SessionAttentionTracker.new,
    );
