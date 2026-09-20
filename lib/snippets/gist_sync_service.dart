import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/models/snippet.dart';

/// 스니펫 Gist 파일 안의 파일명. 고정해 두면 매번 같은 위치를 갱신/조회한다.
const gistSnippetsFileName = 'vibe-terminal-snippets.json';

class GistSyncException implements Exception {
  const GistSyncException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// 토큰에 Gists 권한이 없거나 만료된 경우. GitHub App은 repo 권한과
  /// 별개로 Gists 권한을 명시적으로 켜야 하므로, 기존 로그인 토큰을 그대로
  /// 재사용하면 이 상태가 나올 수 있다.
  bool get forbidden => statusCode == HttpStatus.forbidden;

  bool get notFound => statusCode == HttpStatus.notFound;

  bool get unauthorized => statusCode == HttpStatus.unauthorized;

  @override
  String toString() => message;
}

class GistUploadResult {
  const GistUploadResult({required this.gistId, required this.htmlUrl});

  final String gistId;
  final String htmlUrl;
}

/// GitHub Gist API로 스니펫을 내보내고/가져온다. 파일 하나(JSON 배열)에
/// 전체 스니펫을 담아 gist 하나를 계속 갱신하는 단순한 export/import
/// 모델이다(양방향 자동 동기화 아님).
class GistSyncService {
  GistSyncService({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _connectTimeout);

  static const _connectTimeout = Duration(seconds: 15);
  static const _responseTimeout = Duration(seconds: 30);

  final HttpClient _client;

  String encodeSnippets(List<Snippet> snippets) {
    final payload = [
      for (final s in snippets)
        {
          'id': s.id,
          'name': s.name,
          'body': s.body,
          'scope': s.scope.name,
          'hostId': s.hostId,
          'defaultRunMode': s.defaultRunMode.name,
          'sortOrder': s.sortOrder,
          'createdAt': s.createdAt.toIso8601String(),
          'updatedAt': s.updatedAt.toIso8601String(),
        },
    ];
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  List<Snippet> decodeSnippets(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      throw const GistSyncException('Gist 내용을 스니펫 목록으로 해석하지 못했습니다.');
    }
    return [
      for (final raw in decoded)
        if (raw is Map) _snippetFromJson(Map<String, Object?>.from(raw)),
    ];
  }

  Snippet _snippetFromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final body = json['body'] as String?;
    if (id == null || name == null || body == null) {
      throw const GistSyncException('스니펫 항목에 id/name/body가 없습니다.');
    }
    final createdAt =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    final updatedAt =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? createdAt;
    return Snippet(
      id: id,
      name: name,
      body: body,
      scope: enumValue(SnippetScope.values, json['scope'], SnippetScope.global),
      hostId: json['hostId'] as String?,
      defaultRunMode: enumValue(
        SnippetRunMode.values,
        json['defaultRunMode'],
        SnippetRunMode.paste,
      ),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// [gistId]가 없으면 새 secret gist를 만들고, 있으면 그 gist의 파일을
  /// 덮어쓴다. 매번 새 gist를 만들지 않도록 호출자가 [gistId]를 저장해
  /// 재사용해야 한다.
  Future<GistUploadResult> upload({
    required String token,
    required String content,
    String? gistId,
  }) async {
    final body = jsonEncode({
      if (gistId == null) 'description': 'Vibe Terminal snippets',
      if (gistId == null) 'public': false,
      'files': {
        gistSnippetsFileName: {'content': content},
      },
    });
    final uri = gistId == null
        ? Uri.https('api.github.com', '/gists')
        : Uri.https('api.github.com', '/gists/$gistId');
    final response = await _send(
      gistId == null ? 'POST' : 'PATCH',
      uri,
      token,
      body: body,
    );
    final decoded = _decodeObject(response);
    final id = decoded['id'] as String?;
    final htmlUrl = decoded['html_url'] as String?;
    if (id == null || htmlUrl == null) {
      throw const GistSyncException('Gist 생성/갱신 응답을 해석하지 못했습니다.');
    }
    return GistUploadResult(gistId: id, htmlUrl: htmlUrl);
  }

  /// [gistId]의 [gistSnippetsFileName] 파일 내용을 가져온다.
  Future<String> download({
    required String token,
    required String gistId,
  }) async {
    final response = await _send(
      'GET',
      Uri.https('api.github.com', '/gists/$gistId'),
      token,
    );
    final decoded = _decodeObject(response);
    final files = decoded['files'];
    if (files is! Map) {
      throw const GistSyncException('Gist 파일 목록을 해석하지 못했습니다.');
    }
    final file = files[gistSnippetsFileName];
    if (file is! Map) {
      throw const GistSyncException('Gist에 $gistSnippetsFileName 파일이 없습니다.');
    }
    final content = file['content'];
    if (content is! String) {
      throw const GistSyncException('Gist 파일 내용을 읽지 못했습니다.');
    }
    return content;
  }

  Map<String, Object?> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const GistSyncException('GitHub 응답을 해석하지 못했습니다.');
    }
    return decoded;
  }

  Future<String> _send(
    String method,
    Uri uri,
    String token, {
    String? body,
  }) async {
    HttpClientRequest request;
    try {
      request = await _client.openUrl(method, uri).timeout(_connectTimeout);
    } on TimeoutException {
      throw const GistSyncException('GitHub 연결 시간이 초과되었습니다.');
    } on SocketException catch (e) {
      throw GistSyncException('GitHub에 연결할 수 없습니다: ${e.message}');
    }
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.userAgentHeader, 'vibe-terminal');
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(body);
    }
    HttpClientResponse response;
    try {
      response = await request.close().timeout(_responseTimeout);
    } on TimeoutException {
      throw const GistSyncException('GitHub 응답 시간이 초과되었습니다.');
    }
    final responseBody = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_responseTimeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return responseBody;
    }
    final message = switch (response.statusCode) {
      HttpStatus.unauthorized => '로그인이 만료되었습니다. 설정에서 GitHub로 다시 로그인해주세요.',
      HttpStatus.forbidden =>
        'Gists 권한이 없는 토큰입니다. GitHub App 설정에서 Gists 권한을 켠 뒤 '
            '다시 로그인해주세요.',
      HttpStatus.notFound => 'Gist를 찾을 수 없습니다. 삭제되었거나 접근 권한이 없습니다.',
      _ => 'GitHub 요청이 실패했습니다 (${response.statusCode}).',
    };
    throw GistSyncException(message, statusCode: response.statusCode);
  }
}
