import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../settings/app_settings.dart';
import '../../settings/terminal_preferences.dart';
import 'terminal_font_dropdown.dart';

/// 실제 터미널 렌더러로 색상·글꼴·줄 간격을 보여준다.
class TerminalPreferencesPreview extends StatefulWidget {
  const TerminalPreferencesPreview({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<TerminalPreferencesPreview> createState() =>
      _TerminalPreferencesPreviewState();
}

class _TerminalPreferencesPreviewState
    extends State<TerminalPreferencesPreview> {
  final _terminal = Terminal(maxLines: 30)
    ..write(
      '\x1b[32muser@server\x1b[0m:\x1b[34m~/project\x1b[0m\$ ls\r\n'
      '\x1b[36msrc/\x1b[0m  README.md  \x1b[33mconfig.yaml\x1b[0m\r\n'
      '한글 미리보기 · ABC abc 0123456789\r\n'
      '\x1b[32m✓ Connected\x1b[0m  \x1b[31mError\x1b[0m  >_\r\n',
    );

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('미리보기'),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 156,
            child: ExcludeFocus(
              child: IgnorePointer(
                child: TerminalView(
                  _terminal,
                  readOnly: true,
                  hardwareKeyboardOnly: true,
                  padding: const EdgeInsets.all(12),
                  theme: settings.resolvedTerminalTheme,
                  textStyle: TerminalStyle(
                    fontFamily: settings.terminalFontFamily,
                    fontFamilyFallback: settings.fontFallback,
                    fontSize: settings.terminalFontSize,
                    height: settings.terminalLineHeight,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<TerminalPreferences?> showTerminalPreferencesDialog(
  BuildContext context, {
  required String title,
  required String description,
  required TerminalPreferences initialValue,
  required AppSettings defaults,
  bool hostDefaults = false,
}) => showDialog<TerminalPreferences>(
  context: context,
  builder: (_) => _TerminalPreferencesDialog(
    title: title,
    description: description,
    initialValue: initialValue,
    defaults: defaults,
    hostDefaults: hostDefaults,
  ),
);

class _TerminalPreferencesDialog extends StatefulWidget {
  const _TerminalPreferencesDialog({
    required this.title,
    required this.description,
    required this.initialValue,
    required this.defaults,
    required this.hostDefaults,
  });
  final String title;
  final String description;
  final TerminalPreferences initialValue;
  final AppSettings defaults;
  final bool hostDefaults;

  @override
  State<_TerminalPreferencesDialog> createState() =>
      _TerminalPreferencesDialogState();
}

class _TerminalPreferencesDialogState
    extends State<_TerminalPreferencesDialog> {
  late TerminalPreferences _value = widget.initialValue;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: SizedBox(
      width: 620,
      height: math.min(740, MediaQuery.sizeOf(context).height * .9),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 520;
            final preview = TerminalPreferencesPreview(
              settings: _value.applyTo(widget.defaults),
            );
            final introduction = <Widget>[
              Text(widget.description),
              const SizedBox(height: 12),
              preview,
              const SizedBox(height: 12),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (!compact) ...introduction,
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (compact) ...introduction,
                        TerminalPreferencesEditor(
                          value: _value,
                          defaults: widget.defaults,
                          allowInheritance: widget.hostDefaults,
                          onChanged: (value) => setState(() => _value = value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => _value = widget.hostDefaults
                            ? const TerminalPreferences()
                            : TerminalPreferences.fromSettings(
                                widget.defaults,
                              ).copyWith(
                                scrollbackLines:
                                    widget.initialValue.scrollbackLines,
                              ),
                      ),
                      child: Text(
                        widget.hostDefaults ? '전역 기본값 상속' : '호스트 기본값 적용',
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_value),
                      child: const Text('적용'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// 호스트의 null 항목은 계속 전역 기본값을 상속한다.
class TerminalPreferencesEditor extends StatelessWidget {
  const TerminalPreferencesEditor({
    super.key,
    required this.value,
    required this.defaults,
    required this.onChanged,
    this.allowInheritance = false,
  });
  final TerminalPreferences value;
  final AppSettings defaults;
  final ValueChanged<TerminalPreferences> onChanged;
  final bool allowInheritance;

  Widget _field(
    String label,
    bool inherited,
    VoidCallback reset,
    Widget child,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label),
            if (allowInheritance)
              TextButton(
                onPressed: inherited ? null : reset,
                child: Text(inherited ? '전역값 상속 중' : '전역값 사용'),
              ),
          ],
        ),
        child,
      ],
    ),
  );

  Widget _dropdown<T>(
    String label,
    T selected,
    Iterable<T> values,
    String Function(T) text,
    ValueChanged<T> change,
  ) => DropdownButtonFormField<T>(
    key: ValueKey('$label:$selected'),
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final item in values)
        DropdownMenuItem(
          value: item,
          child: Text(text(item), overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (item) {
      if (item != null) change(item);
    },
  );

  @override
  Widget build(BuildContext context) {
    final effective = value.applyTo(defaults);
    return Column(
      children: [
        _field(
          '터미널 테마',
          value.theme == null,
          () => onChanged(value.copyWith(theme: null)),
          _dropdown(
            '테마',
            effective.terminalTheme,
            TerminalThemePreset.values,
            (v) => v.label,
            (v) => onChanged(value.copyWith(theme: v)),
          ),
        ),
        _field(
          '폰트',
          value.fontFamily == null,
          () => onChanged(value.copyWith(fontFamily: null)),
          TerminalFontDropdown(
            value: effective.terminalFontFamily,
            label: '글꼴',
            onChanged: (v) => onChanged(value.copyWith(fontFamily: v)),
          ),
        ),
        _field(
          '폰트 크기: ${effective.terminalFontSize.toStringAsFixed(0)}',
          value.fontSize == null,
          () => onChanged(value.copyWith(fontSize: null)),
          Slider(
            key: const ValueKey('terminal-font-size'),
            value: effective.terminalFontSize,
            min: AppSettings.minFontSize,
            max: AppSettings.maxFontSize,
            divisions: (AppSettings.maxFontSize - AppSettings.minFontSize)
                .round(),
            label: effective.terminalFontSize.toStringAsFixed(0),
            onChanged: (v) => onChanged(value.copyWith(fontSize: v)),
          ),
        ),
        _field(
          '줄 간격: ${effective.terminalLineHeight.toStringAsFixed(2)}',
          value.lineHeight == null,
          () => onChanged(value.copyWith(lineHeight: null)),
          Slider(
            value: effective.terminalLineHeight,
            min: AppSettings.minLineHeight,
            max: AppSettings.maxLineHeight,
            divisions: 12,
            onChanged: (v) => onChanged(value.copyWith(lineHeight: v)),
          ),
        ),
        if (allowInheritance)
          _field(
            '스크롤백',
            value.scrollbackLines == null,
            () => onChanged(value.copyWith(scrollbackLines: null)),
            _dropdown(
              '보관할 줄 수',
              effective.terminalScrollbackLines,
              ({
                500,
                1000,
                5000,
                10000,
                25000,
                50000,
                100000,
                effective.terminalScrollbackLines,
              }.toList()..sort()),
              (v) => '$v줄',
              (v) => onChanged(value.copyWith(scrollbackLines: v)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '스크롤백 ${effective.terminalScrollbackLines}줄 · 세션 생성 시 확정됩니다.',
            ),
          ),
        _field(
          '선택 시 복사',
          value.copyOnSelection == null,
          () => onChanged(value.copyWith(copyOnSelection: null)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('선택한 텍스트 자동 복사'),
            value: effective.copyOnSelection,
            onChanged: (v) => onChanged(value.copyWith(copyOnSelection: v)),
          ),
        ),
        _field(
          '우클릭 붙여넣기',
          value.rightClickPaste == null,
          () => onChanged(value.copyWith(rightClickPaste: null)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('터미널 우클릭으로 붙여넣기'),
            value: effective.rightClickPaste,
            onChanged: (v) => onChanged(value.copyWith(rightClickPaste: v)),
          ),
        ),
        _field(
          '여러 줄 붙여넣기',
          value.confirmMultilinePaste == null,
          () => onChanged(value.copyWith(confirmMultilinePaste: null)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('여러 줄 붙여넣기 전 확인'),
            value: effective.confirmMultilinePaste,
            onChanged: (v) =>
                onChanged(value.copyWith(confirmMultilinePaste: v)),
          ),
        ),
        _field(
          'Ctrl+C 동작',
          value.ctrlCBehavior == null,
          () => onChanged(value.copyWith(ctrlCBehavior: null)),
          _dropdown(
            '동작',
            effective.ctrlCBehavior,
            CtrlCBehavior.values,
            (v) => v.label,
            (v) => onChanged(value.copyWith(ctrlCBehavior: v)),
          ),
        ),
      ],
    );
  }
}
