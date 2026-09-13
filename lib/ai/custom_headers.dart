import 'dart:convert';

class CustomHeaderFormatException implements Exception {
  const CustomHeaderFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _validHeaderName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

String normalizeCustomHeadersInput(String rawHeaders) {
  final trimmed = rawHeaders.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (!_looksLikeJsonObject(trimmed)) {
    return rawHeaders;
  }

  try {
    return _formatHeaderLines(_parseJsonHeaders(trimmed));
  } on FormatException {
    return rawHeaders;
  } on CustomHeaderFormatException {
    return rawHeaders;
  }
}

Map<String, String> parseCustomHeaders(String rawHeaders) {
  final trimmed = rawHeaders.trim();
  if (trimmed.isEmpty) {
    return const <String, String>{};
  }

  if (_looksLikeJsonObject(trimmed)) {
    try {
      return _parseJsonHeaders(trimmed);
    } on FormatException catch (error) {
      throw CustomHeaderFormatException(
        'Custom headers JSON을 해석할 수 없습니다: ${error.message}',
      );
    }
  }

  final parsed = <String, String>{};
  for (final line in const LineSplitter().convert(rawHeaders)) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty) {
      continue;
    }

    final separator = trimmedLine.indexOf(':');
    if (separator <= 0) {
      throw const CustomHeaderFormatException(
        'Custom header는 "Header-Name: value" 또는 JSON object 형식이어야 합니다.',
      );
    }

    final name = trimmedLine.substring(0, separator).trim();
    final value = trimmedLine.substring(separator + 1).trim();
    _validateHeaderName(name);
    parsed[name] = value;
  }

  return parsed;
}

bool _looksLikeJsonObject(String text) =>
    text.startsWith('{') && text.endsWith('}');

Map<String, String> _parseJsonHeaders(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map) {
    throw const CustomHeaderFormatException(
      'Custom headers JSON은 object여야 합니다.',
    );
  }

  final parsed = <String, String>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const CustomHeaderFormatException('Custom header 이름은 문자열이어야 합니다.');
    }

    _validateHeaderName(key);

    final value = entry.value;
    if (value == null) {
      parsed[key] = '';
    } else if (value is String || value is num || value is bool) {
      parsed[key] = value.toString();
    } else {
      throw CustomHeaderFormatException(
        'Custom header 값은 문자열/숫자/불리언/null이어야 합니다: $key',
      );
    }
  }

  return parsed;
}

String _formatHeaderLines(Map<String, String> headers) {
  return headers.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join('\n');
}

void _validateHeaderName(String name) {
  if (!_validHeaderName.hasMatch(name)) {
    throw CustomHeaderFormatException('Custom header 이름이 올바르지 않습니다: $name');
  }
}
