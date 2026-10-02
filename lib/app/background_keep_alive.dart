import 'dart:io';

import 'package:flutter/services.dart';

import 'error_reporter.dart';

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
  PlatformBackgroundKeepAlive({
    MethodChannel? channel,
    bool? enabled,
    this.onStateChanged,
  }) : _channel = channel ?? const MethodChannel('vibe_terminal/app'),
       _enabled = enabled ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _enabled;

  /// 플랫폼 서비스가 실제로 켜지거나 꺼진 뒤 호출된다(원격 텔레메트리 키 등).
  /// 채널 호출이 실패하면 호출하지 않는다.
  final void Function(bool active)? onStateChanged;

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
        onStateChanged?.call(true);
      } else if (previous > 0) {
        await _channel.invokeMethod<void>('stopKeepAlive');
        onStateChanged?.call(false);
      }
    } on PlatformException catch (e, stack) {
      // 백그라운드에서 포그라운드 서비스 시작이 거부되는 등(Android 12+)의 실패.
      // 세션 동작에는 영향이 없으므로 앱은 계속 가되, 원인은 crash.log 에 남기고
      // 다음 세션 수 변화 때 다시 시도할 수 있게 마지막 값을 되돌린다.
      _lastCount = 0;
      appErrorReporter.report(
        e,
        stack,
        source: 'keepalive',
        context: 'background keep-alive update($sessionCount)',
      );
    } on MissingPluginException {
      // 채널 미구현 환경(테스트 등)에서도 안전하게 무시한다.
    }
  }

  /// 네이티브 서비스가 스스로 내려갔을 때(하루 한도 초과 시간 초과, 시작 실패)
  /// 호출한다. 다음 갱신이 다시 start 를 보내도록 상태를 초기화한다.
  void markServiceStopped() => _lastCount = 0;
}
