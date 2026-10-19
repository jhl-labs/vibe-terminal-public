import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import '../settings/shortcut_bindings.dart';

/// One explicit terminal key, independent of sticky/hardware modifier state.
class TerminalMappedKey {
  const TerminalMappedKey(this.key, this.activator);
  final TerminalKey key;
  final SingleActivator activator;

  bool send(Terminal terminal) {
    var character = activator.trigger == LogicalKeyboardKey.space
        ? ' '
        : activator.trigger.keyLabel.toLowerCase();
    if (character.length == 1 &&
        character.codeUnitAt(0) >= 0x20 &&
        character.codeUnitAt(0) <= 0x7e) {
      if (activator.shift) {
        const shifted = {
          '1': '!',
          '2': '@',
          '3': '#',
          '4': r'$',
          '5': '%',
          '6': '^',
          '7': '&',
          '8': '*',
          '9': '(',
          '0': ')',
          '-': '_',
          '=': '+',
          '[': '{',
          ']': '}',
          r'\': '|',
          ';': ':',
          "'": '"',
          ',': '<',
          '.': '>',
          '/': '?',
          '`': '~',
        };
        character = shifted[character] ?? character.toUpperCase();
      }
      var code = character.codeUnitAt(0);
      if (activator.control) {
        if (code >= 0x61 && code <= 0x7a) {
          code -= 0x60;
        } else if (code >= 0x40 && code <= 0x5f) {
          code &= 0x1f;
        } else if (code == 0x20) {
          code = 0;
        } else if (code == 0x3f) {
          code = 0x7f;
        }
      }
      terminal.textInput(
        '${activator.alt ? '\x1b' : ''}${String.fromCharCode(code)}',
      );
      return true;
    }

    if (terminal.keyInput(
      key,
      ctrl: activator.control,
      alt: activator.alt,
      shift: activator.shift,
    )) {
      return true;
    }
    final arrow = switch (key) {
      TerminalKey.arrowUp => 'A',
      TerminalKey.arrowDown => 'B',
      TerminalKey.arrowRight => 'C',
      TerminalKey.arrowLeft => 'D',
      _ => null,
    };
    if (arrow != null) {
      final modifier =
          1 +
          (activator.shift ? 1 : 0) +
          (activator.alt ? 2 : 0) +
          (activator.control ? 4 : 0);
      terminal.textInput('\x1b[1;$modifier$arrow');
      return true;
    }
    return false;
  }
}

TerminalMappedKey? terminalMappedKey(String binding) {
  final activator = shortcutActivatorFromBinding(binding);
  if (activator == null || activator.meta) return null;
  final logical = activator.trigger;
  TerminalKey? key;
  if (logical.keyId >= LogicalKeyboardKey.keyA.keyId &&
      logical.keyId <= LogicalKeyboardKey.keyZ.keyId) {
    key =
        TerminalKey.values[TerminalKey.keyA.index +
            logical.keyId -
            LogicalKeyboardKey.keyA.keyId];
  } else if (logical.keyId >= LogicalKeyboardKey.digit0.keyId &&
      logical.keyId <= LogicalKeyboardKey.digit9.keyId) {
    const digits = [
      TerminalKey.digit0,
      TerminalKey.digit1,
      TerminalKey.digit2,
      TerminalKey.digit3,
      TerminalKey.digit4,
      TerminalKey.digit5,
      TerminalKey.digit6,
      TerminalKey.digit7,
      TerminalKey.digit8,
      TerminalKey.digit9,
    ];
    key = digits[logical.keyId - LogicalKeyboardKey.digit0.keyId];
  } else if (logical.keyId >= LogicalKeyboardKey.f1.keyId &&
      logical.keyId <= LogicalKeyboardKey.f12.keyId) {
    key =
        TerminalKey.values[TerminalKey.f1.index +
            logical.keyId -
            LogicalKeyboardKey.f1.keyId];
  } else {
    key = switch (logical) {
      LogicalKeyboardKey.enter => TerminalKey.enter,
      LogicalKeyboardKey.tab => TerminalKey.tab,
      LogicalKeyboardKey.escape => TerminalKey.escape,
      LogicalKeyboardKey.minus => TerminalKey.minus,
      LogicalKeyboardKey.equal => TerminalKey.equal,
      LogicalKeyboardKey.bracketLeft => TerminalKey.bracketLeft,
      LogicalKeyboardKey.bracketRight => TerminalKey.bracketRight,
      LogicalKeyboardKey.backslash => TerminalKey.backslash,
      LogicalKeyboardKey.semicolon => TerminalKey.semicolon,
      LogicalKeyboardKey.quote => TerminalKey.quote,
      LogicalKeyboardKey.comma => TerminalKey.comma,
      LogicalKeyboardKey.period => TerminalKey.period,
      LogicalKeyboardKey.slash => TerminalKey.slash,
      LogicalKeyboardKey.backquote => TerminalKey.backquote,
      LogicalKeyboardKey.backspace => TerminalKey.backspace,
      LogicalKeyboardKey.space => TerminalKey.space,
      LogicalKeyboardKey.insert => TerminalKey.insert,
      LogicalKeyboardKey.delete => TerminalKey.delete,
      LogicalKeyboardKey.home => TerminalKey.home,
      LogicalKeyboardKey.end => TerminalKey.end,
      LogicalKeyboardKey.pageUp => TerminalKey.pageUp,
      LogicalKeyboardKey.pageDown => TerminalKey.pageDown,
      LogicalKeyboardKey.arrowUp => TerminalKey.arrowUp,
      LogicalKeyboardKey.arrowDown => TerminalKey.arrowDown,
      LogicalKeyboardKey.arrowLeft => TerminalKey.arrowLeft,
      LogicalKeyboardKey.arrowRight => TerminalKey.arrowRight,
      _ => null,
    };
  }
  return key == null ? null : TerminalMappedKey(key, activator);
}
