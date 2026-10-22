import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 모아 둔 터미널 출력을 언제 반영할지 정한다.
///
/// 화면은 프레임(vsync)마다 한 번 그려지므로, 출력은 "다음 프레임 시작"에
/// 반영하는 것이 가장 빠르면서도 프레임당 write/notify를 한 번으로 묶는다.
/// 첫 청크부터 16ms 타이머를 기다리면 키 에코가 최대 16ms 늦게 반영되고, 그
/// 뒤 다시 다음 프레임을 기다려야 해 지연 연결에서 한 글자 에코가 한 프레임
/// 더 밀린다.
///
/// 프레임이 오지 않는 환경(창 최소화·가려짐, 바인딩 없는 순수 Dart 테스트)에서도
/// 출력이 멈추지 않도록 [fallback] 타이머를 함께 건다. 먼저 발동한 쪽이 flush하고
/// 다른 쪽은 취소된다.
///
/// 화면에 그려지지 않는 출력(보이는 뷰가 없는 세션)은 프레임을 강제로 요청하지
/// 않고 타이머로만 버퍼에 반영한다(`request(frame: false)`). 다른 작업공간에서
/// 빌드 로그·`tail -f`가 흐르는 동안 쓸모없는 프레임이 계속 돌지 않게 한다.
class TerminalFlushScheduler {
  TerminalFlushScheduler(
    this._flush, {
    this.fallback = const Duration(milliseconds: 16),
    SchedulerBinding? Function()? scheduler,
  }) : _scheduler = scheduler ?? _currentScheduler;

  final VoidCallback _flush;
  final Duration fallback;
  final SchedulerBinding? Function() _scheduler;

  Timer? _timer;
  SchedulerBinding? _frameBinding;
  int? _frameCallbackId;

  /// flush가 예약돼 있는지.
  bool get isScheduled => _timer != null;

  /// 아직 예약되지 않았다면 [fallback] 뒤 flush를 예약한다. [frame]이면
  /// 다음 프레임 시작에 더 일찍 flush하도록 프레임도 요청한다. 타이머만 걸린
  /// 상태에서 [frame] 요청이 오면(뷰가 막 보이기 시작함) 프레임을 덧붙인다.
  void request({bool frame = true}) {
    _timer ??= Timer(fallback, _run);
    if (!frame || _frameCallbackId != null) return;
    final binding = _scheduler();
    if (binding == null) return;
    _frameBinding = binding;
    _frameCallbackId = binding.scheduleFrameCallback((_) {
      _frameCallbackId = null;
      _run();
    });
    binding.scheduleFrame();
  }

  /// 예약을 취소한다. 이미 flush했거나 예약이 없으면 아무 일도 없다.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    final id = _frameCallbackId;
    if (id != null) _frameBinding?.cancelFrameCallbackWithId(id);
    _frameCallbackId = null;
    _frameBinding = null;
  }

  void _run() {
    cancel();
    _flush();
  }

  static SchedulerBinding? _currentScheduler() {
    try {
      return SchedulerBinding.instance;
    } on FlutterError {
      // 바인딩 없이 엔진만 쓰는 순수 Dart 테스트. 타이머만으로 flush한다.
      return null;
    }
  }
}
