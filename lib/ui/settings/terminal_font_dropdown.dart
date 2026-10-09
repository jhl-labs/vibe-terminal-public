import 'package:flutter/material.dart';

import '../../settings/app_settings.dart';
import 'terminal_font_availability.dart';

/// 터미널·AI Chat 폰트 선택. 이 시스템에 없는 폰트는 표시하고, 고른 폰트가
/// 없으면 대체 폰트로 그려진다고 안내한다.
class TerminalFontDropdown extends StatelessWidget {
  const TerminalFontDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.availability,
  });

  final String value;
  final String label;
  final ValueChanged<String> onChanged;
  final TerminalFontAvailability? availability;

  static const missingSuffix = ' (설치 안 됨)';
  static const missingHelp = '이 시스템에 설치되어 있지 않아 대체 폰트로 표시됩니다.';

  @override
  Widget build(BuildContext context) {
    final fonts = availability ?? terminalFontAvailability;
    String text(String font) =>
        fonts.isAvailable(font) ? font : '$font$missingSuffix';
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: fonts.isAvailable(value) ? null : missingHelp,
        helperMaxLines: 2,
      ),
      selectedItemBuilder: (context) => [
        for (final font in AppSettings.fontFamilies)
          Text(text(font), overflow: TextOverflow.ellipsis),
      ],
      items: [
        for (final font in AppSettings.fontFamilies)
          DropdownMenuItem(
            value: font,
            child: Text(text(font), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (font) {
        if (font != null) onChanged(font);
      },
    );
  }
}
