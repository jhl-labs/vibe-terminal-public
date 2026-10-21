import 'dart:async';

import 'package:clock/clock.dart';

import '../../session_port.dart';
import '../autopilot_gate.dart';
import '../autopilot_runtime.dart';
import '../autopilot_state.dart';
import '../resume/resume_prompts.dart';
import 'usage_limit_parser.dart';
import 'usage_wait_planner.dart';

/// 사용량 한도 대기 흐름: 한도 공지를 보면 리셋 시각까지 기다렸다가 "계속 진행해"를
/// 보낸다. 대기 판단은 [UsageWaitPlanner], 타이머·작업 토큰·주입 표시는
/// [AutopilotRuntime]이 맡는다.
class UsageLimitFlow {
  UsageLimitFlow(
    this._runtime,
    this._gate, {
    required this.parser,
    required this.planner,
  });

  final AutopilotRuntime _runtime;
  final AutopilotGate _gate;
  final UsageLimitParser parser;
  final UsageWaitPlanner planner;

  /// 사용자가 마지막으로 제출할 때 화면에 있던 한도 공지와 그 줄 수. 사용자가
  /// 직접 이어간 뒤 남은 지난 공지로 새 대기·재개를 시작하지 않게 한다.
  final Map<String, ({String evidence, int count})> _submittedUsageNotice = {};

  /// 한도 문구를 봤다. 리셋 시각 + 여유(모르면 재시도 간격) 뒤 재개를 예약한다.
  /// 재개 뒤 다시 한도면 [AutopilotState.usageWaitStartedAt]을 유지해 같은
  /// 대기의 연장으로 세고, 최대 대기를 넘으면 포기한다.
  void scheduleResume(
    String id,
    AutopilotState current,
    SessionPort port,
    UsageLimitHit hit,
  ) {
    final blocked = _gate.check(
      id,
      current,
      requireQuiet: false,
      forUsageLimit: true,
    );
    if (blocked != null) {
      final recheck = _gate.recheckWhenTimedGateLifts(id, forApproval: false);
      _runtime.record(id, '한도 대기 생략: $blocked$recheck');
      return;
    }
    final now = clock.now();
    switch (planner.plan(current, hit, now, _runtime.timing)) {
      case UsageGiveUp():
        _runtime.setState(
          id,
          current.copyWith(
            phase: AutopilotPhase.exhausted,
            usageResetAt: null,
            usageWaitStartedAt: null,
            lastAction: '한도 대기 포기',
          ),
        );
        _runtime.record(
          id,
          '한도 대기 포기: 최대 ${_runtime.timing.usageMaxWait.inHours}시간 초과',
        );
        unawaited(_runtime.notify(id, '한도 대기 포기', hit.evidence));
      case UsageNotifyOnly(:final wakeAt, :final notify):
        if (!notify) return;
        _runtime.setState(
          id,
          current.copyWith(usageResetAt: wakeAt, lastAction: '한도 감지(알림만)'),
        );
        _runtime.record(id, '한도 감지(알림만): ${hit.evidence}');
        unawaited(
          _runtime.notify(
            id,
            '사용량 한도 (알림만) · ${_hhmm(wakeAt)} 리셋',
            hit.evidence,
          ),
        );
      case UsageWait(:final wakeAt, :final startedAt, :final notifyStart):
        final operation = _runtime.beginOperation(id);
        final identity = port.connectionIdentity;
        _runtime.setState(
          id,
          current.copyWith(
            phase: AutopilotPhase.waitingUsageReset,
            usageResetAt: wakeAt,
            usageWaitStartedAt: startedAt,
            lastAction: '한도 대기: ${hit.evidence}',
          ),
        );
        final basis = hit.resetAt == null ? '시각 불명' : '리셋 시각';
        _runtime.record(id, '한도 대기 → ${_hhmm(wakeAt)} 재개 ($basis)');
        if (notifyStart) {
          unawaited(
            _runtime.notify(id, '한도 대기 · ${_hhmm(wakeAt)} 재개', hit.evidence),
          );
        }
        _runtime.schedule(
          id,
          wakeAt.difference(now),
          () => _resume(id, port, identity, operation),
        );
    }
  }

  /// 한도 대기가 끝났다. 게이트·연결·한도 문구를 다시 확인하고 "계속 진행해"를
  /// 보낸다. 이 재개는 [AutopilotState.resumeAttempt]에 세지 않는다.
  Future<void> _resume(
    String id,
    SessionPort port,
    Object identity,
    Object operation,
  ) async {
    if (!_runtime.isCurrent(id, operation)) return;
    final current = _runtime.stateAt(id);
    if (current == null || current.phase != AutopilotPhase.waitingUsageReset) {
      return;
    }
    final idle = current.copyWith(phase: AutopilotPhase.idle);
    if (!_runtime.sameConnection(port, identity)) {
      _runtime.setState(id, idle);
      _runtime.record(id, '한도 재개 취소: 세션 연결이 바뀜');
      return;
    }
    final notice = freshLimit(id, port);
    final blocked =
        _gate.check(id, current, requireQuiet: true, forUsageLimit: true) ??
        (notice == null ? '한도 문구가 사라짐' : null);
    if (blocked != null) {
      _runtime.setState(id, idle);
      _runtime.record(id, '한도 재개 취소: $blocked');
      return;
    }
    _runtime.inject(id, () => port.sendText(ResumePrompts.continuationText));
    await _runtime.sleep(_runtime.timing.submitDelay);
    // 사람 입력·끄기는 컨트롤러가 작업을 무효화하며 이미 idle로 돌렸다.
    if (!_runtime.isCurrent(id, operation)) return;
    final beforeEnter = _runtime.sameConnection(port, identity)
        ? _gate.check(
            id,
            _runtime.stateOf(id),
            requireQuiet: false,
            forUsageLimit: true,
          )
        : '세션 연결이 바뀜';
    if (beforeEnter != null) {
      _runtime.setState(
        id,
        _runtime.stateOf(id).copyWith(phase: AutopilotPhase.idle),
      );
      _runtime.record(id, '한도 재개 중단(Enter 전): $beforeEnter');
      return;
    }
    _runtime.inject(id, port.submit);
    _runtime.markTaskSubmitted(id);
    _runtime.record(id, '한도 재개: ${ResumePrompts.continuationText}');
    unawaited(_runtime.notify(id, '한도 해제 · 작업 재개', notice?.evidence ?? ''));
    // usageWaitStartedAt은 유지한다. 다시 한도면 같은 대기의 연장으로 센다.
    _runtime.setState(
      id,
      _runtime
          .stateOf(id)
          .copyWith(
            phase: AutopilotPhase.idle,
            usageResetAt: null,
            lastAction: '한도 재개',
          ),
    );
  }

  void rememberSubmittedNotice(String id) {
    final port = _runtime.portOf(id);
    final screen = port?.readScreen(maxLines: 60);
    final hit = screen == null ? null : parser.detect(screen, now: clock.now());
    if (hit == null) {
      _submittedUsageNotice.remove(id);
      return;
    }
    _submittedUsageNotice[id] = (
      evidence: hit.evidence,
      count: UsageLimitParser.occurrences(screen!, hit.evidence),
    );
  }

  /// 화면의 한도 공지. 사용자가 제출할 때 이미 있던 공지(같은 문구가 새로 더
  /// 뜨지 않음)는 지난 공지라 무시한다. 기간 문구(`try again in 45 minutes`)는
  /// 읽을 때마다 지금부터 다시 계산되므로 지난 공지로 대기하면 안 된다.
  UsageLimitHit? freshLimit(String id, SessionPort port) {
    final screen = port.readScreen(maxLines: 60);
    final hit = parser.detect(screen, now: clock.now());
    if (hit == null) return null;
    final submitted = _submittedUsageNotice[id];
    if (submitted != null &&
        submitted.evidence == hit.evidence &&
        UsageLimitParser.occurrences(screen, hit.evidence) <= submitted.count) {
      return null;
    }
    return hit;
  }

  /// 사람 입력으로 한도 대기를 접는다. 제출이면 대기 연장 기록도 지운다.
  void clearWait(String id, {required bool endWait}) {
    final current = _runtime.stateAt(id);
    if (current == null) return;
    if (current.usageResetAt == null &&
        (!endWait || current.usageWaitStartedAt == null)) {
      return;
    }
    _runtime.setState(
      id,
      current.copyWith(
        usageResetAt: null,
        usageWaitStartedAt: endWait ? null : current.usageWaitStartedAt,
      ),
    );
    _runtime.record(id, '사용자 입력 → 한도 대기 취소');
  }

  /// 세션이 사라졌다. 제출 때 기억한 한도 공지를 지운다.
  void forget(String id) => _submittedUsageNotice.remove(id);

  static String _hhmm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}
