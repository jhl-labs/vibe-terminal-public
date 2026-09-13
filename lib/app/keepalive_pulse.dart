import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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

  @override
  void start(void Function() onPulse) {
    _onPulse = onPulse;
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'keepalivePulse') {
        _onPulse?.call();
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
