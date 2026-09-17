import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import '../state/providers.dart';

/// 세션별 터미널 글꼴 크기 재정의(줌).
///
/// 설정의 `terminalFontSize`는 모든 세션의 기본값이고, 확대/축소는 **그 세션만**
/// 바꾼다. 분할 화면에서 한 칸을 키워도 다른 칸은 그대로다. `줌 초기화`는
/// 재정의를 지워 설정값으로 돌아간다. 세션이 닫히면 항목도 지운다.
class TerminalZoomController extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() {
    ref.listen(sessionManagerProvider, (_, sessions) {
      final alive = {for (final s in sessions) s.id};
      if (state.keys.every(alive.contains)) return;
      state = {
        for (final entry in state.entries)
          if (alive.contains(entry.key)) entry.key: entry.value,
      };
    });
    return const {};
  }

  /// [sessionId]의 실제 글꼴 크기. 재정의가 없으면 설정값.
  double fontSizeFor(String sessionId) =>
      state[sessionId] ?? ref.read(appSettingsProvider).terminalFontSize;

  void zoomIn(String sessionId) =>
      _set(sessionId, fontSizeFor(sessionId) + AppSettings.fontSizeStep);

  void zoomOut(String sessionId) =>
      _set(sessionId, fontSizeFor(sessionId) - AppSettings.fontSizeStep);

  /// 설정값으로 되돌린다.
  void reset(String sessionId) {
    if (!state.containsKey(sessionId)) return;
    state = {...state}..remove(sessionId);
  }

  /// 핀치 줌처럼 절대값으로 지정할 때. 범위를 벗어나면 잘라낸다.
  void setFontSize(String sessionId, double fontSize) =>
      _set(sessionId, fontSize);

  void _set(String sessionId, double fontSize) {
    state = {
      ...state,
      sessionId: fontSize.clamp(
        AppSettings.minFontSize,
        AppSettings.maxFontSize,
      ),
    };
  }
}

final terminalZoomProvider =
    NotifierProvider<TerminalZoomController, Map<String, double>>(
      TerminalZoomController.new,
    );

/// [sessionId]의 실제 글꼴 크기(재정의 ?? 설정값)를 watch한다.
double watchTerminalFontSize(WidgetRef ref, String sessionId) {
  final override = ref.watch(
    terminalZoomProvider.select((zoom) => zoom[sessionId]),
  );
  return override ??
      ref.watch(appSettingsProvider.select((s) => s.terminalFontSize));
}
