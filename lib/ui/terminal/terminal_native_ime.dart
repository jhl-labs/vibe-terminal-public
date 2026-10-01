import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 네이티브 IME 브리지가 전달하는 조합 이벤트를 받는 터미널 입력.
abstract interface class TerminalNativeImeClient {
  /// IME가 확정한 텍스트. 순서대로 한 번만 전달된다.
  void handleNativeImeCommit(String text);

  /// 현재 조합 중인 텍스트. 빈 문자열이면 조합이 끝났거나 취소된 것이다.
  void handleNativeImeComposing(String text);
}

/// Windows 러너의 `TerminalImeBridge`(windows/runner/terminal_ime_bridge.cpp)와
/// 연결한다.
///
/// Flutter 엔진의 편집 모델을 거치면 MS 한글 IME로 빠르게 칠 때 조합 순서가
/// 뒤바뀐다. 터미널 입력에 포커스가 있는 동안만 브리지를 켜서 IME 확정/조합
/// 문자열을 직접 받는다. 브리지가 없는 빌드(다른 플랫폼, 러너 미포함 빌드)에서는
/// 아무 것도 하지 않으므로 기존 EditableText 경로가 그대로 쓰인다.
class TerminalNativeIme {
  TerminalNativeIme._() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static final TerminalNativeIme instance = TerminalNativeIme._();

  static const _channel = MethodChannel('vibe_terminal/terminal_ime');

  static bool get platformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  TerminalNativeImeClient? _active;
  // 포커스를 잃은 직후 브리지가 비활성화되며 확정한 조합을 받을 대상.
  TerminalNativeImeClient? _lastActive;
  bool _unavailable = false;
  bool _traceRequested = false;

  /// 진단 전용 입력 트레이스 출력. 설정되면 브리지가 받은 원본 IME 메시지도
  /// 함께 기록한다.
  void Function(String message)? traceSink;
  Rect? _lastCaretRect;

  /// [client]가 터미널 입력 포커스를 얻었다.
  void attach(TerminalNativeImeClient client) {
    if (!platformSupported || _unavailable) return;
    _active = client;
    _lastActive = client;
    if (traceSink != null && !_traceRequested) {
      _traceRequested = true;
      unawaited(_invoke('setTrace', true));
    }
    unawaited(_setEnabled(true));
  }

  /// [client]가 포커스를 잃었다. 다른 터미널이 이미 포커스를 가져갔다면
  /// 브리지를 끄지 않는다.
  void detach(TerminalNativeImeClient client) {
    if (!identical(_active, client)) return;
    _active = null;
    unawaited(_setEnabled(false));
  }

  /// [client]가 폐기된다.
  void dispose(TerminalNativeImeClient client) {
    detach(client);
    if (identical(_lastActive, client)) _lastActive = null;
  }

  /// IME 후보 창 위치(Flutter 뷰 기준 물리 픽셀).
  void setCaretRect(Rect rect) {
    if (!platformSupported || _unavailable || _active == null) return;
    if (rect == _lastCaretRect) return;
    _lastCaretRect = rect;
    unawaited(
      _invoke('setCaretRect', {
        'x': rect.left.round(),
        'y': rect.top.round(),
        'width': rect.width.round(),
        'height': rect.height.round(),
      }),
    );
  }

  Future<void> _setEnabled(bool enabled) async {
    if (!enabled) _lastCaretRect = null;
    await _invoke('setEnabled', enabled);
  }

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // 브리지가 없는 러너. 이후 호출을 모두 건너뛰고 기존 경로를 쓴다.
      _unavailable = true;
      _active = null;
      _lastActive = null;
    } on PlatformException catch (error) {
      debugPrint('TerminalNativeIme.$method failed: $error');
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == 'trace') {
      traceSink?.call('nativeMsg ${call.arguments}');
      return null;
    }
    if (call.method != 'composition' || _unavailable) return null;
    final target = _active ?? _lastActive;
    final args = call.arguments;
    if (target == null || args is! Map) return null;
    final commit = args['commit'];
    final composing = args['composing'];
    if (commit is String && commit.isNotEmpty) {
      target.handleNativeImeCommit(commit);
    }
    if (composing is String) {
      target.handleNativeImeComposing(composing);
    } else if (commit is String) {
      // 확정만 오고 다음 조합이 없으면 조합 표시를 지운다.
      target.handleNativeImeComposing('');
    }
    return null;
  }

  @visibleForTesting
  void resetForTest() {
    _active = null;
    _lastActive = null;
    _unavailable = false;
    _traceRequested = false;
    _lastCaretRect = null;
  }
}
