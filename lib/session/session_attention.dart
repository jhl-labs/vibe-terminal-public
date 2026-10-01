import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_attention.dart';
import '../agent/agent_semantic_event.dart';
import '../agent/agent_session_inspector.dart';
import '../state/providers.dart';

const Object _unchanged = Object();

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
  final String? agentHint;
  final String message;
  final DateTime updatedAt;
  final SessionAttentionSource source;

  /// [updatedAt]을 제외한 모든 필드가 같은지.
  bool sameAs(SessionAttention other) =>
      sessionId == other.sessionId &&
      state == other.state &&
      agentHint == other.agentHint &&
      message == other.message &&
      source == other.source;

  bool get needsAttention =>
      state == SessionAttentionState.blocked ||
      state == SessionAttentionState.done;

  SessionAttention copyWith({
    SessionAttentionState? state,
    Object? agentHint = _unchanged,
    String? message,
    DateTime? updatedAt,
    SessionAttentionSource? source,
  }) => SessionAttention(
    sessionId: sessionId,
    state: state ?? this.state,
    agentHint: identical(agentHint, _unchanged)
        ? this.agentHint
        : agentHint as String?,
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

  /// 터미널 제목으로 알아낸 Agent. 화면 문구는 스크롤·재그리기로 사라지지만
  /// 제목은 Agent가 살아 있는 동안 유지되므로 화면 판별을 보완한다.
  final Map<String, AgentSessionInspection> _titleHints = {};

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

  /// 터미널 제목(OSC 0/2)이 바뀌었다.
  ///
  /// Agent 제목이면 이후 화면 판별에서 Agent로 취급한다. Agent 제목이었다가
  /// 셸 제목(`user@host: ~`)으로 돌아오면 Agent가 종료된 것으로 보고 식별
  /// 상태를 정리한다. 외부 차단 알림이 있더라도 Agent 레이블 근거만 지운다.
  void markTitle(String sessionId, String title) {
    final inspection = AgentSessionInspector.inspectTitle(title);
    if (inspection.isPossibleAgent) {
      _titleHints[sessionId] = inspection;
      final current = state[sessionId];
      if (current == null) {
        _set(
          SessionAttention(
            sessionId: sessionId,
            state: SessionAttentionState.idle,
            agentHint: inspection.agentHint,
            message: inspection.preview,
            updatedAt: clock.now(),
          ),
        );
      } else if ((current.source == SessionAttentionSource.screen ||
              current.agentHint == null) &&
          current.agentHint != inspection.agentHint &&
          _outranksScreenHint(current, inspection)) {
        _set(current.copyWith(agentHint: inspection.agentHint));
      }
      return;
    }
    if (_titleHints.remove(sessionId) == null) return;
    final current = state[sessionId];
    _clearAgentState(sessionId, current: current);
  }

  bool _outranksScreenHint(
    SessionAttention current,
    AgentSessionInspection title,
  ) =>
      title.isConfirmedAgent ||
      current.agentHint == 'agent' ||
      current.agentHint == 'unknown';

  /// 화면 판별과 제목 판별을 합쳐 Agent 이름을 정한다. 확정 근거를 우선하고,
  /// 둘 다 느슨하면 제목(셸 제목이 아닌 TUI 제목)을 믿는다.
  String? _resolveHint(
    String sessionId,
    AgentAttentionAssessment assessment,
    SessionAttention? previous,
  ) {
    final title = _titleHints[sessionId];
    if (assessment.confidence == AgentDetectionConfidence.confirmed) {
      return assessment.agentHint;
    }
    if (title != null) return title.agentHint;
    // Agent 화면을 확인한 경우에만 이전 이름을 유지한다. 일반 셸 화면에서도
    // 이전 이름을 무조건 재사용하면 Agent 프로세스가 끝난 뒤 레이블이 남는다.
    if (assessment.isAgent && previous != null) {
      return previous.agentHint ?? assessment.agentHint;
    }
    return assessment.isAgent ? assessment.agentHint : null;
  }

  void markWorking(String sessionId, String screen) {
    final assessment = _classifier.inspect(screen);
    final previous = state[sessionId];
    final agentHint = _resolveHint(sessionId, assessment, previous);
    if (agentHint == null) {
      // 빈 화면은 resize/startup 중에도 잠깐 나타날 수 있으므로, 실제 셸
      // 출력이 확인된 경우에만 Agent 상태를 종료한다.
      if (assessment.preview != '(화면 내용 없음)') {
        _clearAgentState(sessionId, current: previous);
      }
      return;
    }
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
        agentHint: agentHint,
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
    final agentHint = _resolveHint(sessionId, assessment, previous);
    if (agentHint == null) {
      if (assessment.preview != '(화면 내용 없음)') {
        _clearAgentState(sessionId, current: previous);
      }
      return null;
    }

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
      agentHint: agentHint,
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
    if (event.phase == AgentSemanticPhase.stopped) {
      _clearAgentState(sessionId, current: state[sessionId]);
      return;
    }
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
    _titleHints.remove(sessionId);
    if (!state.containsKey(sessionId)) return;
    state = {...state}..remove(sessionId);
  }

  /// Agent가 종료되어 일반 셸로 돌아왔을 때 Agent 식별 상태를 정리한다.
  ///
  /// 외부 차단(예: Git 충돌)이 남아 있으면 그 알림은 보존하되, 현재 세션을
  /// Agent로 표시할 근거는 제거한다. 외부 차단이 없으면 attention 자체도
  /// 제거해 일반 세션으로 되돌린다.
  void _clearAgentState(String sessionId, {SessionAttention? current}) {
    _titleHints.remove(sessionId);
    _semanticSignals.remove(sessionId);
    final attention = current ?? state[sessionId];
    if (attention == null) return;
    if (_externalBlocks.containsKey(sessionId)) {
      _set(attention.copyWith(agentHint: null));
      return;
    }
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

  /// 상태·이름·메시지·출처가 그대로면 갱신하지 않는다.
  ///
  /// [markWorking]은 세션 출력 flush마다(최대 16ms 간격) 호출된다. 그때마다
  /// `updatedAt`만 다른 새 객체로 state를 바꾸면 이 provider를 watch 하는
  /// 앱 셸 중앙(모든 터미널 칸)과 세션 레일이 세션 수 × 60Hz 로 다시 빌드돼
  /// 세션이 많을 때 앱 전체가 느려지고 IME(한글 조합) 이벤트가 밀린다.
  void _set(SessionAttention attention) {
    final previous = state[attention.sessionId];
    if (previous != null && previous.sameAs(attention)) return;
    state = {...state, attention.sessionId: attention};
  }
}

final sessionAttentionProvider =
    NotifierProvider<SessionAttentionTracker, Map<String, SessionAttention>>(
      SessionAttentionTracker.new,
    );
