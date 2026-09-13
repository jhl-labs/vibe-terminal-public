class TerminalInputCodec {
  const TerminalInputCodec._();

  static TerminalInput decode(String source) {
    final buffer = StringBuffer();
    var sawExplicitKey = false;

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char == '<') {
        final end = source.indexOf('>', i + 1);
        if (end != -1) {
          final token = source.substring(i + 1, end);
          final decoded = _decodeAngleToken(token);
          if (decoded != null) {
            buffer.write(decoded);
            sawExplicitKey = true;
            i = end;
            continue;
          }
        }
      }
      if (char == '\\' && i + 1 < source.length) {
        final decoded = _decodeBackslash(source, i + 1);
        if (decoded != null) {
          buffer.write(decoded.value);
          sawExplicitKey = true;
          i += decoded.consumed;
          continue;
        }
      }
      buffer.write(char);
    }

    return TerminalInput(buffer.toString(), sawExplicitKey: sawExplicitKey);
  }

  static String? _decodeAngleToken(String rawToken) {
    final token = rawToken.trim().toLowerCase().replaceAll('-', '');
    if (token.length == 2 && token.startsWith('c')) {
      return _control(token.codeUnitAt(1));
    }
    if (token.length == 5 && token.startsWith('ctrl')) {
      return _control(token.codeUnitAt(4));
    }
    return switch (token) {
      'esc' || 'escape' => '\x1b',
      'enter' || 'return' => '\r',
      'tab' => '\t',
      'backspace' || 'bs' => '\x7f',
      'delete' || 'del' => '\x1b[3~',
      'insert' || 'ins' => '\x1b[2~',
      'up' => '\x1b[A',
      'down' => '\x1b[B',
      'right' => '\x1b[C',
      'left' => '\x1b[D',
      'home' => '\x1b[H',
      'end' => '\x1b[F',
      'pageup' || 'pgup' => '\x1b[5~',
      'pagedown' || 'pgdn' => '\x1b[6~',
      'space' => ' ',
      _ => null,
    };
  }

  static _DecodedEscape? _decodeHex(String source, int start) {
    if (start + 2 > source.length) return null;
    final hex = source.substring(start, start + 2);
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return _DecodedEscape(String.fromCharCode(value), consumed: 3);
  }

  static _DecodedEscape? _decodeBackslash(String source, int start) {
    final next = source[start];
    return switch (next) {
      'n' => const _DecodedEscape('\n', consumed: 1),
      'r' => const _DecodedEscape('\r', consumed: 1),
      't' => const _DecodedEscape('\t', consumed: 1),
      'e' => const _DecodedEscape('\x1b', consumed: 1),
      '\\' => const _DecodedEscape('\\', consumed: 1),
      'x' => _decodeHex(source, start + 1),
      _ => null,
    };
  }

  static String? _control(int codeUnit) {
    final lower = codeUnit >= 0x41 && codeUnit <= 0x5a
        ? codeUnit + 0x20
        : codeUnit;
    if (lower >= 0x61 && lower <= 0x7a) {
      return String.fromCharCode(lower - 0x60);
    }
    if (lower == 0x5b) return '\x1b'; // [
    if (lower == 0x5c) return '\x1c'; // \
    if (lower == 0x5d) return '\x1d'; // ]
    if (lower == 0x5e) return '\x1e'; // ^
    if (lower == 0x5f) return '\x1f'; // _
    return null;
  }
}

class TerminalInput {
  const TerminalInput(this.text, {required this.sawExplicitKey});

  final String text;
  final bool sawExplicitKey;
}

class _DecodedEscape {
  const _DecodedEscape(this.value, {required this.consumed});

  final String value;
  final int consumed;
}
