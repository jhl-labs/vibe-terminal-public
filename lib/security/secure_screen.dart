import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 민감한 화면(Vault, SSH 키 생성·가져오기, 비밀번호 입력)이 떠 있는 동안
/// OS 화면 캡처를 막는다.
///
/// Android에서만 동작한다(`FLAG_SECURE`: 최근 앱 썸네일·스크린샷·화면 녹화
/// 차단). iOS에는 같은 API가 없고, 데스크톱은 스크린샷이 일상 작업이라 일부러
/// 적용하지 않는다. 겹쳐 뜬 시트가 먼저 닫혀도 남은 화면이 보호되도록 참조
/// 수를 센다.
class SecureScreen {
  SecureScreen._();

  static const _channel = MethodChannel('vibe_terminal/app');

  static int _holders = 0;

  /// 테스트에서 채널 호출을 가로채거나 플랫폼을 흉내 낼 때 바꾼다.
  @visibleForTesting
  static Future<void> Function(bool secure)? applyOverride;

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 현재 보호가 걸려 있는지(참조 수 > 0).
  static bool get isActive => _holders > 0;

  static Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _apply(true);
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _apply(false);
  }

  static Future<void> _apply(bool secure) async {
    final override = applyOverride;
    if (override != null) return override(secure);
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setSecureScreen', {'secure': secure});
    } on MissingPluginException {
      // 네이티브 핸들러가 없는 환경(테스트·구버전 엔진)은 조용히 넘어간다.
    } on PlatformException {
      // 창이 아직 없거나 이미 사라진 경우. 보호 실패가 화면 자체를 막으면 안 된다.
    }
  }

  @visibleForTesting
  static void resetForTest() => _holders = 0;
}

/// [child]가 트리에 있는 동안 [SecureScreen]을 잡는다.
class SecureScreenScope extends StatefulWidget {
  const SecureScreenScope({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreenScope> createState() => _SecureScreenScopeState();
}

class _SecureScreenScopeState extends State<SecureScreenScope> {
  @override
  void initState() {
    super.initState();
    SecureScreen.acquire();
  }

  @override
  void dispose() {
    SecureScreen.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
