/// 연결된 SSH 서버의 식별 정보. 접속 주소는 Host 설정에서 별도로 표시한다.
class RemoteServerInfo {
  const RemoteServerInfo({this.hostname, this.operatingSystem, this.ipAddress});

  final String? hostname;
  final String? operatingSystem;
  final String? ipAddress;

  static const command =
      r'''printf '%s\n' "$(hostname 2>/dev/null)" "$(uname -srm 2>/dev/null)" "${SSH_CONNECTION-}"''';

  factory RemoteServerInfo.parse(String output) {
    final lines = output.split('\n');
    String? field(int index) {
      if (index >= lines.length) return null;
      final value = lines[index].trim();
      return value.isEmpty ? null : value;
    }

    final connection = field(2)?.split(RegExp(r'\s+'));
    return RemoteServerInfo(
      hostname: field(0),
      operatingSystem: field(1),
      ipAddress: connection != null && connection.length == 4
          ? connection[2]
          : null,
    );
  }
}
