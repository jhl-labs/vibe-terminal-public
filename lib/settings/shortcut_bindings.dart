import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_settings.dart';

Map<ShortcutActivator, VoidCallback> shortcutCallbacksForActions({
  required AppSettings settings,
  required Map<String, VoidCallback> actions,
}) {
  final callbacks = <ShortcutActivator, VoidCallback>{};
  for (final action in actions.entries) {
    for (final activator in shortcutActivatorsForAction(settings, action.key)) {
      callbacks[activator] = action.value;
    }
  }
  return callbacks;
}

Iterable<ShortcutActivator> shortcutActivatorsForAction(
  AppSettings settings,
  String action,
) sync* {
  final bindings =
      settings.shortcutBindings[action] ??
      kDefaultShortcutBindings[action] ??
      const <String>[];
  for (final binding in bindings) {
    final activator = shortcutActivatorFromBinding(binding);
    if (activator != null) yield activator;
  }
}

SingleActivator? shortcutActivatorFromBinding(String binding) {
  final parts = binding
      .toLowerCase()
      .split('+')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toSet();
  final wantsCtrl = parts.remove('ctrl') || parts.remove('control');
  final wantsAlt = parts.remove('alt') || parts.remove('option');
  final wantsMeta =
      parts.remove('cmd') || parts.remove('command') || parts.remove('meta');
  final wantsShift = parts.remove('shift');
  if (parts.length != 1) return null;

  final key = _logicalKeyForToken(parts.single);
  if (key == null) return null;
  return SingleActivator(
    key,
    control: wantsCtrl,
    alt: wantsAlt,
    meta: wantsMeta,
    shift: wantsShift,
  );
}

String? shortcutBindingFromKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final key = event.logicalKey;
  if (_isModifierKey(key)) return null;

  final token = shortcutTokenForKey(key);
  if (token == null) return null;

  final parts = <String>[];
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isControlPressed) parts.add('Ctrl');
  if (keyboard.isAltPressed) parts.add('Alt');
  if (keyboard.isMetaPressed) parts.add('Cmd');
  if (keyboard.isShiftPressed) parts.add('Shift');
  parts.add(token);
  return parts.join('+');
}

String? shortcutTokenForKey(LogicalKeyboardKey key) {
  if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
      key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
    final offset = key.keyId - LogicalKeyboardKey.keyA.keyId;
    return String.fromCharCode('A'.codeUnitAt(0) + offset);
  }
  if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
      key.keyId <= LogicalKeyboardKey.digit9.keyId) {
    final offset = key.keyId - LogicalKeyboardKey.digit0.keyId;
    return String.fromCharCode('0'.codeUnitAt(0) + offset);
  }

  return switch (key) {
    LogicalKeyboardKey.equal => '=',
    LogicalKeyboardKey.minus => '-',
    LogicalKeyboardKey.slash => '/',
    LogicalKeyboardKey.backslash => r'\',
    LogicalKeyboardKey.comma => ',',
    LogicalKeyboardKey.period => '.',
    LogicalKeyboardKey.semicolon => ';',
    LogicalKeyboardKey.quote => "'",
    LogicalKeyboardKey.backquote => '`',
    LogicalKeyboardKey.bracketLeft => '[',
    LogicalKeyboardKey.bracketRight => ']',
    LogicalKeyboardKey.tab => 'Tab',
    LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => 'Enter',
    LogicalKeyboardKey.escape => 'Esc',
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.insert => 'Insert',
    LogicalKeyboardKey.delete => 'Delete',
    LogicalKeyboardKey.home => 'Home',
    LogicalKeyboardKey.end => 'End',
    LogicalKeyboardKey.pageUp => 'PageUp',
    LogicalKeyboardKey.pageDown => 'PageDown',
    LogicalKeyboardKey.arrowLeft => 'Left',
    LogicalKeyboardKey.arrowRight => 'Right',
    LogicalKeyboardKey.arrowUp => 'Up',
    LogicalKeyboardKey.arrowDown => 'Down',
    _ => null,
  };
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.controlLeft ||
    LogicalKeyboardKey.controlRight ||
    LogicalKeyboardKey.altLeft ||
    LogicalKeyboardKey.altRight ||
    LogicalKeyboardKey.metaLeft ||
    LogicalKeyboardKey.metaRight ||
    LogicalKeyboardKey.shiftLeft ||
    LogicalKeyboardKey.shiftRight => true,
    _ => false,
  };
}

LogicalKeyboardKey? _logicalKeyForToken(String token) {
  if (token.length == 1) {
    final code = token.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7a) {
      return LogicalKeyboardKey.findKeyByKeyId(
        LogicalKeyboardKey.keyA.keyId + code - 0x61,
      );
    }
    if (code >= 0x30 && code <= 0x39) {
      return LogicalKeyboardKey.findKeyByKeyId(
        LogicalKeyboardKey.digit0.keyId + code - 0x30,
      );
    }
    if (token == '=') return LogicalKeyboardKey.equal;
    if (token == '-') return LogicalKeyboardKey.minus;
    if (token == '/') return LogicalKeyboardKey.slash;
    if (token == r'\') return LogicalKeyboardKey.backslash;
    if (token == ',') return LogicalKeyboardKey.comma;
    if (token == '.') return LogicalKeyboardKey.period;
    if (token == ';') return LogicalKeyboardKey.semicolon;
    if (token == "'") return LogicalKeyboardKey.quote;
    if (token == '`') return LogicalKeyboardKey.backquote;
    if (token == '[') return LogicalKeyboardKey.bracketLeft;
    if (token == ']') return LogicalKeyboardKey.bracketRight;
  }

  return switch (token) {
    'tab' => LogicalKeyboardKey.tab,
    'enter' || 'return' => LogicalKeyboardKey.enter,
    'esc' || 'escape' => LogicalKeyboardKey.escape,
    'space' => LogicalKeyboardKey.space,
    'insert' => LogicalKeyboardKey.insert,
    'delete' || 'del' => LogicalKeyboardKey.delete,
    'home' => LogicalKeyboardKey.home,
    'end' => LogicalKeyboardKey.end,
    'pageup' || 'page up' => LogicalKeyboardKey.pageUp,
    'pagedown' || 'page down' => LogicalKeyboardKey.pageDown,
    'left' || 'arrowleft' => LogicalKeyboardKey.arrowLeft,
    'right' || 'arrowright' => LogicalKeyboardKey.arrowRight,
    'up' || 'arrowup' => LogicalKeyboardKey.arrowUp,
    'down' || 'arrowdown' => LogicalKeyboardKey.arrowDown,
    _ => null,
  };
}
