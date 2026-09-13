import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Vibe Terminal 시각 토큰.
///
/// 방향: SSH 콘솔 워크벤치. 장식보다 상태, 입력, 반복 작업의 밀도를 우선한다.
abstract class VibeColors {
  static const bg = Color(0xFF080B10);
  static const terminal = Color(0xFF05070A);
  static const surface = Color(0xFF101720);
  static const surfaceHigh = Color(0xFF17212B);
  static const surfacePressed = Color(0xFF1D2A36);
  static const border = Color(0xFF263241);
  static const borderSoft = Color(0xFF1A2430);
  static const accent = Color(0xFF43D9C5);
  static const accentSoft = Color(0xFF123D3B);
  static const secondary = Color(0xFF79A7FF);
  static const warning = Color(0xFFF2B84B);
  static const onAccent = Color(0xFF031412);
  static const onSurface = Color(0xFFE6EDF3);
  static const onSurfaceMuted = Color(0xFFB4C2CF);
  static const onSurfaceDim = Color(0xFF7F91A3);

  // 세션 상태 인디케이터
  static const statusConnecting = warning;
  static const statusConnected = Color(0xFF56D364);
  static const statusDisconnected = Color(0xFF687684);
  static const statusError = Color(0xFFFF6B6B);
}

/// 콘솔/모노 강조용 폰트 패밀리(시스템 모노스페이스).
const String kMonoFontFamily = 'Cascadia Mono';
const List<String> kMonoFontFallback = [
  'Cascadia Code',
  'Consolas',
  'Menlo',
  'Noto Sans Mono CJK KR',
  'monospace',
];

const TerminalTheme kVibeTerminalTheme = TerminalTheme(
  cursor: VibeColors.accent,
  selection: Color(0x6643D9C5),
  foreground: VibeColors.onSurface,
  background: VibeColors.terminal,
  black: Color(0xFF0A0E14),
  red: VibeColors.statusError,
  green: VibeColors.statusConnected,
  yellow: VibeColors.warning,
  blue: VibeColors.secondary,
  magenta: Color(0xFFD18CFF),
  cyan: VibeColors.accent,
  white: VibeColors.onSurface,
  brightBlack: Color(0xFF52616F),
  brightRed: Color(0xFFFF8C8C),
  brightGreen: Color(0xFF79E089),
  brightYellow: Color(0xFFFFD479),
  brightBlue: Color(0xFF9CBDFF),
  brightMagenta: Color(0xFFE0B0FF),
  brightCyan: Color(0xFF7FF4E5),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xAA8A6A18),
  searchHitBackgroundCurrent: VibeColors.warning,
  searchHitForeground: VibeColors.terminal,
);

ThemeData buildVibeTerminalTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: VibeColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: VibeColors.accent,
        onPrimary: VibeColors.onAccent,
        surface: VibeColors.surface,
        surfaceContainerHighest: VibeColors.surfaceHigh,
        onSurface: VibeColors.onSurface,
        error: VibeColors.statusError,
      );

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Segoe UI',
    colorScheme: scheme,
    scaffoldBackgroundColor: VibeColors.bg,
    canvasColor: VibeColors.bg,
    dividerTheme: const DividerThemeData(
      color: VibeColors.border,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VibeColors.surface,
      foregroundColor: VibeColors.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kMonoFontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: VibeColors.onSurface,
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: VibeColors.surface),
    listTileTheme: const ListTileThemeData(
      iconColor: VibeColors.onSurfaceDim,
      textColor: VibeColors.onSurface,
      selectedColor: VibeColors.accent,
      selectedTileColor: VibeColors.surfacePressed,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VibeColors.surfaceHigh,
      isDense: true,
      border: border(VibeColors.border),
      enabledBorder: border(VibeColors.border),
      focusedBorder: border(VibeColors.accent, 1.5),
      labelStyle: const TextStyle(color: VibeColors.onSurfaceDim),
      hintStyle: const TextStyle(color: VibeColors.onSurfaceDim),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VibeColors.accent,
        foregroundColor: VibeColors.onAccent,
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VibeColors.onSurface,
        side: const BorderSide(color: VibeColors.border),
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: VibeColors.onSurfaceMuted,
        hoverColor: VibeColors.surfacePressed,
        focusColor: VibeColors.accentSoft,
        highlightColor: VibeColors.accentSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: VibeColors.accent,
      unselectedLabelColor: VibeColors.onSurfaceDim,
      indicatorColor: VibeColors.accent,
      dividerColor: VibeColors.borderSoft,
      labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VibeColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: VibeColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: VibeColors.surfaceHigh,
      contentTextStyle: TextStyle(color: VibeColors.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
    visualDensity: VisualDensity.compact,
  );
}
