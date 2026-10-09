import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import '../state/providers.dart';

/// 세션의 저장 가능한 화면 설정을 통해 줌을 변경한다.
class TerminalZoomController extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {
    for (final session in ref.watch(sessionManagerProvider))
      if (session.terminalPreferences.fontSize !=
          session.terminalDefaults.fontSize)
        session.id: session.terminalPreferences.fontSize!,
  };

  double fontSizeFor(String sessionId) {
    final session = ref
        .read(sessionManagerProvider)
        .where((s) => s.id == sessionId)
        .firstOrNull;
    return session?.terminalPreferences.fontSize ??
        AppSettings.defaultSettings.terminalFontSize;
  }

  void zoomIn(String sessionId) =>
      setFontSize(sessionId, fontSizeFor(sessionId) + AppSettings.fontSizeStep);
  void zoomOut(String sessionId) =>
      setFontSize(sessionId, fontSizeFor(sessionId) - AppSettings.fontSizeStep);

  /// 세션의 현재 기본 크기(전역·호스트 기본값)로 되돌린다.
  void reset(String sessionId) {
    final session = ref
        .read(sessionManagerProvider)
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (session != null) {
      setFontSize(sessionId, session.terminalDefaults.fontSize!);
    }
  }

  void setFontSize(String sessionId, double fontSize, {bool persist = true}) {
    if (!fontSize.isFinite) return;
    final session = ref
        .read(sessionManagerProvider)
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (session == null) return;
    final size = fontSize.clamp(
      AppSettings.minFontSize,
      AppSettings.maxFontSize,
    );
    if (size == session.terminalPreferences.fontSize) return;
    ref
        .read(sessionManagerProvider.notifier)
        .setTerminalPreferences(
          sessionId,
          session.terminalPreferences.copyWith(fontSize: size),
          persist: persist,
        );
  }
}

final terminalZoomProvider =
    NotifierProvider<TerminalZoomController, Map<String, double>>(
      TerminalZoomController.new,
    );

double watchTerminalFontSize(WidgetRef ref, String sessionId) => ref.watch(
  sessionManagerProvider.select(
    (sessions) =>
        sessions
            .where((s) => s.id == sessionId)
            .firstOrNull
            ?.terminalPreferences
            .fontSize ??
        AppSettings.defaultSettings.terminalFontSize,
  ),
);
