enum TerminalInputAction {
  defaultBehavior('기본 동작'),
  none('동작 없음'),
  tab('Tab'),
  shiftTab('Shift+Tab'),
  enter('Enter'),
  escape('Esc'),
  interrupt('Ctrl+C · 실행 중단'),
  eof('Ctrl+D'),
  clearScreen('Ctrl+L'),
  suspend('Ctrl+Z'),
  up('↑'),
  down('↓'),
  left('←'),
  right('→'),
  home('Home'),
  end('End'),
  pageUp('PageUp'),
  pageDown('PageDown'),
  copy('선택 영역 복사'),
  paste('붙여넣기'),
  keyboard('화면 키보드 표시 / 숨김'),
  customKey('사용자 정의 키 조합');

  const TerminalInputAction(this.label);
  final String label;
}

enum TerminalInputTrigger {
  touchDoubleTap('터치 두 번 탭'),
  mouseDoubleClick('마우스 더블 클릭'),
  volumeUpSingle('볼륨 위 · 한 번'),
  volumeUpDouble('볼륨 위 · 두 번'),
  volumeDownSingle('볼륨 아래 · 한 번'),
  volumeDownDouble('볼륨 아래 · 두 번');

  const TerminalInputTrigger(this.label);
  final String label;
  bool get physical => index >= volumeUpSingle.index;
  bool get doublePress => this == volumeUpDouble || this == volumeDownDouble;
}

class TerminalInputBinding {
  const TerminalInputBinding(this.action, {this.shortcut = ''});
  final TerminalInputAction action;
  final String shortcut;
  static const defaultBehavior = TerminalInputBinding(
    TerminalInputAction.defaultBehavior,
  );
  static const none = TerminalInputBinding(TerminalInputAction.none);

  String? get keyBinding => switch (action) {
    TerminalInputAction.tab => 'Tab',
    TerminalInputAction.shiftTab => 'Shift+Tab',
    TerminalInputAction.enter => 'Enter',
    TerminalInputAction.escape => 'Esc',
    TerminalInputAction.interrupt => 'Ctrl+C',
    TerminalInputAction.eof => 'Ctrl+D',
    TerminalInputAction.clearScreen => 'Ctrl+L',
    TerminalInputAction.suspend => 'Ctrl+Z',
    TerminalInputAction.up => 'Up',
    TerminalInputAction.down => 'Down',
    TerminalInputAction.left => 'Left',
    TerminalInputAction.right => 'Right',
    TerminalInputAction.home => 'Home',
    TerminalInputAction.end => 'End',
    TerminalInputAction.pageUp => 'PageUp',
    TerminalInputAction.pageDown => 'PageDown',
    TerminalInputAction.customKey => shortcut,
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'action': action.name,
    if (shortcut.isNotEmpty) 'shortcut': shortcut,
  };

  static TerminalInputBinding fromJson(
    Object? value,
    TerminalInputBinding fallback,
  ) {
    if (value is! Map) return fallback;
    final actions = TerminalInputAction.values.where(
      (a) => a.name == value['action'],
    );
    if (actions.isEmpty) return fallback;
    final shortcut = value['shortcut'];
    return TerminalInputBinding(
      actions.first,
      shortcut: shortcut is String && shortcut.length <= 80 ? shortcut : '',
    );
  }
}

class TerminalInputBindings {
  const TerminalInputBindings({
    this.bindings = const {},
    this.doublePressMilliseconds = 300,
  });
  final Map<TerminalInputTrigger, TerminalInputBinding> bindings;
  final int doublePressMilliseconds;

  TerminalInputBinding forTrigger(TerminalInputTrigger trigger) =>
      bindings[trigger] ??
      (trigger.doublePress
          ? TerminalInputBinding.none
          : TerminalInputBinding.defaultBehavior);

  bool interceptVolume(bool up) =>
      forTrigger(
            up
                ? TerminalInputTrigger.volumeUpSingle
                : TerminalInputTrigger.volumeDownSingle,
          ).action !=
          TerminalInputAction.defaultBehavior ||
      forTrigger(
            up
                ? TerminalInputTrigger.volumeUpDouble
                : TerminalInputTrigger.volumeDownDouble,
          ).action !=
          TerminalInputAction.none;

  TerminalInputBindings withBinding(
    TerminalInputTrigger trigger,
    TerminalInputBinding binding,
  ) => TerminalInputBindings(
    bindings: Map.unmodifiable({...bindings, trigger: binding}),
    doublePressMilliseconds: doublePressMilliseconds,
  );

  TerminalInputBindings withDelay(int milliseconds) => TerminalInputBindings(
    bindings: bindings,
    doublePressMilliseconds: milliseconds.clamp(200, 600),
  );

  Map<String, Object?> toJson() => {
    'doublePressMilliseconds': doublePressMilliseconds,
    'bindings': {
      for (final item in bindings.entries) item.key.name: item.value.toJson(),
    },
  };

  factory TerminalInputBindings.fromJson(Object? value) {
    if (value is! Map) return const TerminalInputBindings();
    final entries = value['bindings'];
    var result = const TerminalInputBindings();
    if (entries is Map) {
      for (final trigger in TerminalInputTrigger.values) {
        result = result.withBinding(
          trigger,
          TerminalInputBinding.fromJson(
            entries[trigger.name],
            result.forTrigger(trigger),
          ),
        );
      }
    }
    final delay = value['doublePressMilliseconds'];
    return result.withDelay(
      delay is num && delay.isFinite ? delay.round() : 300,
    );
  }
}
