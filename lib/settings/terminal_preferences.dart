import 'app_settings.dart';

const _keepTerminalPreference = Object();

/// null은 상위 기본값 상속. 세션 생성 시 resolved()로 모든 값을 확정한다.
class TerminalPreferences {
  const TerminalPreferences({
    this.theme,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
    this.scrollbackLines,
    this.copyOnSelection,
    this.rightClickPaste,
    this.confirmMultilinePaste,
    this.ctrlCBehavior,
  });

  final TerminalThemePreset? theme;
  final String? fontFamily;
  final double? fontSize;
  final double? lineHeight;
  final int? scrollbackLines;
  final bool? copyOnSelection;
  final bool? rightClickPaste;
  final bool? confirmMultilinePaste;
  final CtrlCBehavior? ctrlCBehavior;

  factory TerminalPreferences.fromSettings(AppSettings settings) =>
      TerminalPreferences(
        theme: settings.terminalTheme,
        fontFamily: settings.terminalFontFamily,
        fontSize: settings.terminalFontSize,
        lineHeight: settings.terminalLineHeight,
        scrollbackLines: settings.terminalScrollbackLines,
        copyOnSelection: settings.copyOnSelection,
        rightClickPaste: settings.rightClickPaste,
        confirmMultilinePaste: settings.confirmMultilinePaste,
        ctrlCBehavior: settings.ctrlCBehavior,
      );

  AppSettings applyTo(AppSettings defaults) => defaults.copyWith(
    terminalTheme: theme,
    terminalFontFamily: fontFamily,
    terminalFontSize: fontSize,
    terminalLineHeight: lineHeight,
    terminalScrollbackLines: scrollbackLines,
    copyOnSelection: copyOnSelection,
    rightClickPaste: rightClickPaste,
    confirmMultilinePaste: confirmMultilinePaste,
    ctrlCBehavior: ctrlCBehavior,
  );

  TerminalPreferences resolved(AppSettings defaults) =>
      TerminalPreferences.fromSettings(applyTo(defaults));

  /// 기본값이 [from]에서 [to]로 바뀌었을 때 열린 세션의 값을 따라 바꾼다.
  /// [from]과 같은 항목(기본값을 따르던 항목)만 [to]로 바꾸고, 세션에서 직접
  /// 바꾼 항목은 유지한다. 스크롤백은 엔진 생성 때 정해지므로 유지한다.
  TerminalPreferences rebase({
    required TerminalPreferences from,
    required TerminalPreferences to,
  }) {
    T follow<T>(T own, T before, T after) => own == before ? after : own;
    return TerminalPreferences(
      theme: follow(theme, from.theme, to.theme),
      fontFamily: follow(fontFamily, from.fontFamily, to.fontFamily),
      fontSize: follow(fontSize, from.fontSize, to.fontSize),
      lineHeight: follow(lineHeight, from.lineHeight, to.lineHeight),
      scrollbackLines: scrollbackLines,
      copyOnSelection: follow(
        copyOnSelection,
        from.copyOnSelection,
        to.copyOnSelection,
      ),
      rightClickPaste: follow(
        rightClickPaste,
        from.rightClickPaste,
        to.rightClickPaste,
      ),
      confirmMultilinePaste: follow(
        confirmMultilinePaste,
        from.confirmMultilinePaste,
        to.confirmMultilinePaste,
      ),
      ctrlCBehavior: follow(
        ctrlCBehavior,
        from.ctrlCBehavior,
        to.ctrlCBehavior,
      ),
    );
  }

  TerminalPreferences copyWith({
    Object? theme = _keepTerminalPreference,
    Object? fontFamily = _keepTerminalPreference,
    Object? fontSize = _keepTerminalPreference,
    Object? lineHeight = _keepTerminalPreference,
    Object? scrollbackLines = _keepTerminalPreference,
    Object? copyOnSelection = _keepTerminalPreference,
    Object? rightClickPaste = _keepTerminalPreference,
    Object? confirmMultilinePaste = _keepTerminalPreference,
    Object? ctrlCBehavior = _keepTerminalPreference,
  }) => TerminalPreferences(
    theme: identical(theme, _keepTerminalPreference)
        ? this.theme
        : theme as TerminalThemePreset?,
    fontFamily: identical(fontFamily, _keepTerminalPreference)
        ? this.fontFamily
        : fontFamily as String?,
    fontSize: identical(fontSize, _keepTerminalPreference)
        ? this.fontSize
        : (fontSize as num?)?.toDouble(),
    lineHeight: identical(lineHeight, _keepTerminalPreference)
        ? this.lineHeight
        : (lineHeight as num?)?.toDouble(),
    scrollbackLines: identical(scrollbackLines, _keepTerminalPreference)
        ? this.scrollbackLines
        : (scrollbackLines as num?)?.toInt(),
    copyOnSelection: identical(copyOnSelection, _keepTerminalPreference)
        ? this.copyOnSelection
        : copyOnSelection as bool?,
    rightClickPaste: identical(rightClickPaste, _keepTerminalPreference)
        ? this.rightClickPaste
        : rightClickPaste as bool?,
    confirmMultilinePaste:
        identical(confirmMultilinePaste, _keepTerminalPreference)
        ? this.confirmMultilinePaste
        : confirmMultilinePaste as bool?,
    ctrlCBehavior: identical(ctrlCBehavior, _keepTerminalPreference)
        ? this.ctrlCBehavior
        : ctrlCBehavior as CtrlCBehavior?,
  );

  Map<String, Object?> toJson() => {
    if (theme != null) 'theme': theme!.name,
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontSize != null) 'fontSize': fontSize,
    if (lineHeight != null) 'lineHeight': lineHeight,
    if (scrollbackLines != null) 'scrollbackLines': scrollbackLines,
    if (copyOnSelection != null) 'copyOnSelection': copyOnSelection,
    if (rightClickPaste != null) 'rightClickPaste': rightClickPaste,
    if (confirmMultilinePaste != null)
      'confirmMultilinePaste': confirmMultilinePaste,
    if (ctrlCBehavior != null) 'ctrlCBehavior': ctrlCBehavior!.name,
  };

  static TerminalPreferences fromJson(Object? value) {
    if (value is! Map) return const TerminalPreferences();
    T? enumValue<T extends Enum>(List<T> values, Object? name) {
      for (final item in values) {
        if (item.name == name) return item;
      }
      return null;
    }

    double? number(String key, double min, double max) {
      final n = value[key];
      return n is num && n.isFinite ? n.toDouble().clamp(min, max) : null;
    }

    return TerminalPreferences(
      theme: enumValue(TerminalThemePreset.values, value['theme']),
      fontFamily: AppSettings.fontFamilies.contains(value['fontFamily'])
          ? value['fontFamily'] as String
          : null,
      fontSize: number(
        'fontSize',
        AppSettings.minFontSize,
        AppSettings.maxFontSize,
      ),
      lineHeight: number(
        'lineHeight',
        AppSettings.minLineHeight,
        AppSettings.maxLineHeight,
      ),
      scrollbackLines: number(
        'scrollbackLines',
        AppSettings.minScrollbackLines.toDouble(),
        AppSettings.maxScrollbackLines.toDouble(),
      )?.toInt(),
      copyOnSelection: value['copyOnSelection'] is bool
          ? value['copyOnSelection'] as bool
          : null,
      rightClickPaste: value['rightClickPaste'] is bool
          ? value['rightClickPaste'] as bool
          : null,
      confirmMultilinePaste: value['confirmMultilinePaste'] is bool
          ? value['confirmMultilinePaste'] as bool
          : null,
      ctrlCBehavior: enumValue(CtrlCBehavior.values, value['ctrlCBehavior']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalPreferences &&
          theme == other.theme &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize &&
          lineHeight == other.lineHeight &&
          scrollbackLines == other.scrollbackLines &&
          copyOnSelection == other.copyOnSelection &&
          rightClickPaste == other.rightClickPaste &&
          confirmMultilinePaste == other.confirmMultilinePaste &&
          ctrlCBehavior == other.ctrlCBehavior;

  @override
  int get hashCode => Object.hash(
    theme,
    fontFamily,
    fontSize,
    lineHeight,
    scrollbackLines,
    copyOnSelection,
    rightClickPaste,
    confirmMultilinePaste,
    ctrlCBehavior,
  );
}
