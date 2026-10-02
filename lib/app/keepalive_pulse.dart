import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'error_reporter.dart';

/// keepalive 박자 공급원. 박자가 울릴 때마다 [onPulse]가 호출된다.
///
/// 박자 이후의 로직(세션 ping)은 전 플랫폼 공용이고, "누가 박자를 치는가"만
/// 플랫폼별로 다르다: Android는 포그라운드 서비스의 네이티브 틱(화면꺼짐/
/// Doze에도 동작), 그 외 플랫폼은 Dart 타이머(Doze가 없어 충분).
abstract class KeepalivePulse {
  void start(void Function() onPulse);
  void stop();
}

/// Dart 타이머 기반 박자(Desktop/iOS). 기본 20초.
class TimerKeepalivePulse implements KeepalivePulse {
  TimerKeepalivePulse({this.interval = const Duration(seconds: 20)});

  final Duration interval;
  Timer? _timer;

  @override
  void start(void Function() onPulse) {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => onPulse());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Android 네이티브 서비스 틱을 수신하는 박자.
/// SshKeepAliveService가 20초마다 `keepalivePulse` 메서드콜을 보낸다.
class ChannelKeepalivePulse implements KeepalivePulse {
  ChannelKeepalivePulse({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('vibe_terminal/app');

  final MethodChannel _channel;
  void Function()? _onPulse;
  bool _listening = false;

  /// 네이티브 서비스가 스스로 멈췄을 때(시간 한도·시작 실패) 호출된다.
  void Function()? onServiceStopped;

  @override
  void start(void Function() onPulse) {
    _onPulse = onPulse;
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'keepalivePulse':
          _onPulse?.call();
        case 'keepaliveTimeout':
          // Android 15+ dataSync 포그라운드 서비스의 하루 6시간 한도. 서비스는
          // 이미 내려갔고 세션은 앱이 포그라운드일 때만 유지된다. 원인을 남겨
          // 사용자가 "왜 백그라운드에서 끊겼는지" 볼 수 있게 한다.
          appErrorReporter.report(
            '포그라운드 서비스가 시스템 시간 한도(하루 6시간)에 도달해 중지됐습니다. '
            '앱이 백그라운드에 있는 동안 SSH 연결이 끊길 수 있습니다.',
            null,
            source: 'keepalive',
            context: 'service timeout',
          );
          onServiceStopped?.call();
        case 'keepaliveError':
          appErrorReporter.report(
            call.arguments?.toString() ?? 'unknown',
            null,
            source: 'keepalive',
            context: 'service startForeground failed',
          );
          onServiceStopped?.call();
      }
    });
  }

  @override
  void stop() {
    _onPulse = null;
    // 핸들러는 유지해도 _onPulse가 null이라 no-op. 세션 재시작 시 start만
    // 다시 부르면 된다.
  }
}

/// 플랫폼에 맞는 기본 박자 구현을 고른다.
KeepalivePulse createPlatformKeepalivePulse() {
  if (Platform.isAndroid) return ChannelKeepalivePulse();
  return TimerKeepalivePulse();
}
