import 'dart:io';

import 'package:flutter/services.dart';

/// 백그라운드/화면 꺼짐 상태에서도 SSH 세션을 유지하기 위한 플랫폼 서비스
/// 추상화. 열린 세션 수에 따라 OS 포그라운드 서비스를 켜고 끈다.
abstract class BackgroundKeepAlive {
  /// 현재 열려 있는 세션 수에 맞춰 keep-alive 상태를 갱신한다.
  /// 0이면 서비스를 중지하고, 1 이상이면 시작/알림 갱신한다.
  Future<void> update(int sessionCount);
}

/// Android 포그라운드 서비스를 MethodChannel로 제어하는 구현.
/// 지원 플랫폼이 아니면(예: 데스크톱) 아무 동작도 하지 않는다.
class PlatformBackgroundKeepAlive implements BackgroundKeepAlive {
  PlatformBackgroundKeepAlive({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('vibe_terminal/app'),
      _enabled = enabled ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _enabled;

  /// 마지막으로 플랫폼에 알린 세션 수(중복 호출 방지).
  int _lastCount = 0;

  @override
  Future<void> update(int sessionCount) async {
    if (!_enabled) return;
    if (sessionCount == _lastCount) return;
    final previous = _lastCount;
    _lastCount = sessionCount;
    try {
      if (sessionCount > 0) {
        await _channel.invokeMethod<void>('startKeepAlive', {
          'count': sessionCount,
        });
      } else if (previous > 0) {
        await _channel.invokeMethod<void>('stopKeepAlive');
      }
    } on PlatformException {
      // keep-alive 실패는 세션 동작에 영향이 없으므로 무시한다.
    } on MissingPluginException {
      // 채널 미구현 환경(테스트 등)에서도 안전하게 무시한다.
    }
  }
}
