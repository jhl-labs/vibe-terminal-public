import 'dart:async';
import 'dart:io';

enum AgentWorkspaceProbeStatus { ready, unreachable, unsupported }

class AgentWorkspaceProbeResult {
  const AgentWorkspaceProbeResult({
    required this.sourceUri,
    required this.targetUri,
    required this.status,
    required this.checkedAt,
    required this.latency,
    this.statusCode,
    this.detail,
  });

  final Uri sourceUri;
  final Uri targetUri;
  final AgentWorkspaceProbeStatus status;
  final DateTime checkedAt;
  final Duration latency;
  final int? statusCode;
  final String? detail;

  bool get ready => status == AgentWorkspaceProbeStatus.ready;
}

typedef AgentWorkspaceHttpProbe =
    Future<int> Function(Uri uri, Duration timeout);

/// 브라우저가 실제로 사용할 URL에 가벼운 HEAD 요청을 보내 readiness를 판정한다.
/// HTTP 상태 코드의 종류와 무관하게 응답 헤더를 받으면 서버 transport는 준비된
/// 것으로 본다. 프레임워크가 아직 부팅 중이면 연결 실패 후 다음 poll에서 재시도한다.
class AgentWorkspaceRunProbe {
  const AgentWorkspaceRunProbe([this._request]);

  static const timeout = Duration(seconds: 3);

  final AgentWorkspaceHttpProbe? _request;

  Future<AgentWorkspaceProbeResult> probe({
    required Uri sourceUri,
    required Uri targetUri,
  }) async {
    final started = DateTime.now();
    if (!isAgentWorkspaceAutoProbeUrl(sourceUri)) {
      return AgentWorkspaceProbeResult(
        sourceUri: sourceUri,
        targetUri: targetUri,
        status: AgentWorkspaceProbeStatus.unsupported,
        checkedAt: DateTime.now(),
        latency: Duration.zero,
        detail: '안전상 loopback 개발 서버만 자동 확인합니다.',
      );
    }
    if (targetUri.scheme != 'http' && targetUri.scheme != 'https') {
      return AgentWorkspaceProbeResult(
        sourceUri: sourceUri,
        targetUri: targetUri,
        status: AgentWorkspaceProbeStatus.unsupported,
        checkedAt: DateTime.now(),
        latency: Duration.zero,
        detail: '${targetUri.scheme} URL은 HTTP readiness를 확인할 수 없습니다.',
      );
    }
    try {
      final statusCode = await (_request ?? _head)(targetUri, timeout);
      return AgentWorkspaceProbeResult(
        sourceUri: sourceUri,
        targetUri: targetUri,
        status: AgentWorkspaceProbeStatus.ready,
        checkedAt: DateTime.now(),
        latency: DateTime.now().difference(started),
        statusCode: statusCode,
      );
    } catch (error) {
      return AgentWorkspaceProbeResult(
        sourceUri: sourceUri,
        targetUri: targetUri,
        status: AgentWorkspaceProbeStatus.unreachable,
        checkedAt: DateTime.now(),
        latency: DateTime.now().difference(started),
        detail: _message(error),
      );
    }
  }

  static Future<int> _head(Uri uri, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.headUrl(uri).timeout(timeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.userAgentHeader, 'Vibe-Terminal-Readiness/1');
      final response = await request.close().timeout(timeout);
      final statusCode = response.statusCode;
      await response.listen((_) {}).cancel();
      return statusCode;
    } finally {
      client.close(force: true);
    }
  }

  static String _message(Object error) {
    if (error is TimeoutException) return '응답 제한 시간 3초를 넘었습니다.';
    if (error is SocketException) return error.message;
    if (error is HandshakeException) return 'TLS 연결을 확인하지 못했습니다.';
    if (error is HttpException) return error.message;
    return '$error'.replaceFirst('Exception: ', '');
  }
}

bool isAgentWorkspaceAutoProbeUrl(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  if (host == '0.0.0.0' || host == '::') return true;
  final address = InternetAddress.tryParse(host);
  return address?.isLoopback == true;
}
