/// 터미널의 일반 화면 출력과 함께 전달되는 앱 전용 OSC 메시지.
class TerminalSidebandMessage {
  const TerminalSidebandMessage({required this.channel, required this.payload});

  final String channel;
  final String payload;
}

/// 청크 경계와 무관하게 Vibe Terminal 전용 OSC 777 메시지를 추출한다.
///
/// 형식은 `OSC 777 ; <channel> ; <payload> ST`이며 BEL과 ESC `\\` 종료를
/// 모두 지원한다. payload는 제어 문자를 피하도록 호출자가 base64url 등으로
/// 인코딩해야 한다. 메시지는 xterm에도 그대로 전달되며 알려지지 않은 OSC로
/// 화면에는 렌더링되지 않는다.
class TerminalSidebandDecoder {
  static const _prefix = '\x1b]777;';
  static const _maximumBufferedCharacters = 24 * 1024;

  String _buffer = '';

  List<TerminalSidebandMessage> add(String chunk) {
    if (chunk.isEmpty) return const [];
    _buffer += chunk;
    final messages = <TerminalSidebandMessage>[];

    while (true) {
      final start = _buffer.indexOf(_prefix);
      if (start < 0) {
        _retainPossiblePrefix();
        break;
      }
      if (start > 0) _buffer = _buffer.substring(start);

      final contentStart = _prefix.length;
      final bell = _buffer.indexOf('\x07', contentStart);
      final stringTerminator = _buffer.indexOf('\x1b\\', contentStart);
      final end = switch ((bell, stringTerminator)) {
        (-1, -1) => -1,
        (-1, final st) => st,
        (final bel, -1) => bel,
        (final bel, final st) => bel < st ? bel : st,
      };
      if (end < 0) {
        if (_buffer.length > _maximumBufferedCharacters) {
          _buffer = _buffer.substring(_prefix.length);
          continue;
        }
        break;
      }

      final body = _buffer.substring(contentStart, end);
      final separator = body.indexOf(';');
      if (separator > 0 && separator < body.length - 1) {
        final channel = body.substring(0, separator);
        final payload = body.substring(separator + 1);
        if (_validChannel(channel) && payload.length <= 16 * 1024) {
          messages.add(
            TerminalSidebandMessage(channel: channel, payload: payload),
          );
        }
      }
      final terminatorLength = end == stringTerminator ? 2 : 1;
      _buffer = _buffer.substring(end + terminatorLength);
    }

    return messages;
  }

  void reset() => _buffer = '';

  void _retainPossiblePrefix() {
    final keep = (_prefix.length - 1).clamp(0, _buffer.length).toInt();
    _buffer = keep == 0 ? '' : _buffer.substring(_buffer.length - keep);
  }

  static bool _validChannel(String value) =>
      value.length <= 64 && RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(value);
}

/// 셸 통합이 보내는 OSC 7(`file://host/path`) 현재 작업 디렉터리 보고를
/// 청크 경계와 무관하게 추출한다. bash/zsh의 PROMPT_COMMAND/precmd 나 fish가
/// 기본으로 내보내며, 키 입력 추측보다 정확한 cwd 원천이다.
class TerminalWorkingDirectoryDecoder {
  static const _prefix = '\x1b]7;';
  static const _maximumBufferedCharacters = 8 * 1024;

  String _buffer = '';

  List<String> add(String chunk) {
    if (chunk.isEmpty) return const [];
    _buffer += chunk;
    final paths = <String>[];
    while (true) {
      final start = _buffer.indexOf(_prefix);
      if (start < 0) {
        _retainPossiblePrefix();
        break;
      }
      if (start > 0) _buffer = _buffer.substring(start);
      final contentStart = _prefix.length;
      final bell = _buffer.indexOf('\x07', contentStart);
      final st = _buffer.indexOf('\x1b\\', contentStart);
      final end = switch ((bell, st)) {
        (-1, -1) => -1,
        (-1, final s) => s,
        (final b, -1) => b,
        (final b, final s) => b < s ? b : s,
      };
      if (end < 0) {
        if (_buffer.length > _maximumBufferedCharacters) {
          _buffer = _buffer.substring(_prefix.length);
          continue;
        }
        break;
      }
      final path = _pathOf(_buffer.substring(contentStart, end));
      if (path != null) paths.add(path);
      _buffer = _buffer.substring(end + (end == st ? 2 : 1));
    }
    return paths;
  }

  void reset() => _buffer = '';

  void _retainPossiblePrefix() {
    final keep = (_prefix.length - 1).clamp(0, _buffer.length).toInt();
    _buffer = keep == 0 ? '' : _buffer.substring(_buffer.length - keep);
  }

  /// `file://[host]/abs/path` → `/abs/path`. 그 외 스킴·상대 경로는 버린다.
  static String? _pathOf(String body) {
    const scheme = 'file://';
    if (!body.startsWith(scheme)) return null;
    final rest = body.substring(scheme.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final String decoded;
    try {
      decoded = Uri.decodeComponent(rest.substring(slash));
    } on ArgumentError {
      return null;
    }
    return decoded.startsWith('/') ? decoded : null;
  }
}
