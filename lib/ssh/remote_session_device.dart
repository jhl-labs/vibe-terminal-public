import 'dart:convert';
import 'dart:io';

/// 접속한 컴퓨터의 표시 정보. tmux 출력에 안전하게 넣기 위해 base64로 저장한다.
class RemoteSessionDevice {
  const RemoteSessionDevice({
    required this.name,
    required this.operatingSystem,
  });

  factory RemoteSessionDevice.current() => RemoteSessionDevice(
    name: Platform.localHostname,
    operatingSystem: Platform.operatingSystem,
  );

  final String name;
  final String operatingSystem;

  String get displayName => '$name ($operatingSystem)';

  String encode() => base64Encode(
    utf8.encode(
      jsonEncode({'name': _clean(name), 'os': _clean(operatingSystem)}),
    ),
  );

  static RemoteSessionDevice? decode(String value) {
    try {
      final data = jsonDecode(utf8.decode(base64Decode(value)));
      if (data is! Map || data['name'] is! String || data['os'] is! String) {
        return null;
      }
      final name = _clean(data['name'] as String);
      final os = _clean(data['os'] as String);
      if (name.isEmpty || os.isEmpty) return null;
      return RemoteSessionDevice(name: name, operatingSystem: os);
    } catch (_) {
      return null;
    }
  }

  static String _clean(String value) => String.fromCharCodes(
    value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim().runes.take(120),
  );
}

class RemoteSessionClient {
  const RemoteSessionClient({required this.device, required this.connectedAt});

  final RemoteSessionDevice? device;
  final DateTime? connectedAt;
}
