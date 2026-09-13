import 'dart:io';

import 'host.dart';

class SessionLog {
  const SessionLog({
    required this.id,
    required this.sessionId,
    required this.hostId,
    required this.hostAlias,
    required this.connectionType,
    required this.endpoint,
    required this.startedAt,
    required this.endedAt,
    required this.endReason,
    required this.logPath,
    required this.byteCount,
    required this.lineCount,
  });

  final String id;
  final String sessionId;
  final String hostId;
  final String hostAlias;
  final HostConnectionType connectionType;
  final String endpoint;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? endReason;
  final String logPath;
  final int byteCount;
  final int lineCount;

  bool get active => endedAt == null;

  File get file => File(logPath);

  String get connectionLabel => connectionType.label;

  String get endLabel {
    if (active) return '기록 중';
    return switch (endReason) {
      'closed' => '닫힘',
      'disconnected' => '연결 종료',
      'error' => '오류',
      'abandoned' => '앱 종료',
      _ => '종료',
    };
  }
}
