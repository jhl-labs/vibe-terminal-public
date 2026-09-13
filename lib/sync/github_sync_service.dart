import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../settings/app_settings.dart';
import 'sync_crypto.dart';

class GitHubRateLimit {
  const GitHubRateLimit({
    required this.limit,
    required this.remaining,
    required this.resetAt,
    required this.resource,
  });

  final int limit;
  final int remaining;
  final DateTime resetAt;
  final String resource;

  String get displayText =>
      '$remaining / $limit remaining · reset ${resetAt.toLocal()}';
}

class GitHubSyncUploadResult {
  const GitHubSyncUploadResult({
    required this.path,
    required this.commitSha,
    this.rateLimit,
  });

  final String path;
  final String commitSha;
  final GitHubRateLimit? rateLimit;
}

class GitHubDeviceCode {
  const GitHubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration interval;
}

class GitHubAppAuthorization {
  const GitHubAppAuthorization({
    required this.accessToken,
    required this.tokenType,
    this.expiresAt,
    this.refreshToken,
    this.refreshTokenExpiresAt,
  });

  final String accessToken;
  final String tokenType;
  final DateTime? expiresAt;
  final String? refreshToken;
  final DateTime? refreshTokenExpiresAt;
}

class GitHubSyncException implements Exception {
  const GitHubSyncException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class GitHubSyncService {
  GitHubSyncService({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _connectTimeout);

  /// 응답이 오지 않는 서버를 만나면 동기화 UI가 영원히 스피너를 돌기 때문에
  /// 연결과 응답 모두에 상한을 둔다.
  static const _connectTimeout = Duration(seconds: 15);
  static const _responseTimeout = Duration(seconds: 30);

  final HttpClient _client;

  /// 네트워크 호출을 감싸 시간 초과를 사용자에게 보여줄 메시지로 바꾼다.
  Future<T> _withTimeout<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_responseTimeout);
    } on TimeoutException {
      throw const GitHubSyncException('GitHub 응답 시간이 초과되었습니다.');
    } on SocketException catch (e) {
      throw GitHubSyncException('GitHub에 연결할 수 없습니다: ${e.message}');
    }
  }

  Future<GitHubDeviceCode> requestDeviceCode({
    required GitHubSyncSettings settings,
  }) async {
    final clientId = settings.effectiveAppClientId;
    if (clientId.isEmpty) {
      throw const GitHubSyncException('GitHub App Client ID를 입력하세요.');
    }
    final response = await _sendOAuthForm(
      settings.effectiveServerUrl,
      '/login/device/code',
      {'client_id': clientId, 'scope': 'repo'},
    );
    final decoded = _decodeResponseObject(response);
    _throwIfOAuthError(decoded);

    final deviceCode = decoded['device_code'] as String?;
    final userCode = decoded['user_code'] as String?;
    final verificationUri = decoded['verification_uri'] as String?;
    if (deviceCode == null ||
        deviceCode.isEmpty ||
        userCode == null ||
        userCode.isEmpty ||
        verificationUri == null ||
        verificationUri.isEmpty) {
      throw const GitHubSyncException('GitHub device code 응답을 해석하지 못했습니다.');
    }
    final expiresIn = (decoded['expires_in'] as num?)?.toInt() ?? 900;
    final interval = (decoded['interval'] as num?)?.toInt() ?? 5;
    return GitHubDeviceCode(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: Uri.parse(verificationUri),
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      interval: Duration(seconds: interval),
    );
  }

  Future<GitHubAppAuthorization> waitForDeviceAuthorization({
    required GitHubSyncSettings settings,
    required GitHubDeviceCode deviceCode,
  }) async {
    final clientId = settings.effectiveAppClientId;
    if (clientId.isEmpty) {
      throw const GitHubSyncException('GitHub App Client ID를 입력하세요.');
    }
    var interval = deviceCode.interval;
    while (DateTime.now().toUtc().isBefore(deviceCode.expiresAt)) {
      await Future<void>.delayed(interval);
      final response = await _sendOAuthForm(
        settings.effectiveServerUrl,
        '/login/oauth/access_token',
        {
          'client_id': clientId,
          'device_code': deviceCode.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      final decoded = _decodeResponseObject(response);
      final error = decoded['error'] as String?;
      if (error == null) return _authorizationFromJson(decoded);
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        final seconds = (decoded['interval'] as num?)?.toInt();
        interval = Duration(seconds: seconds ?? interval.inSeconds + 5);
        continue;
      }
      throw GitHubSyncException(_oauthErrorMessage(decoded));
    }
    throw const GitHubSyncException('GitHub device code가 만료되었습니다.');
  }

  Future<GitHubAppAuthorization> refreshUserAccessToken({
    required GitHubSyncSettings settings,
  }) async {
    final clientId = settings.effectiveAppClientId;
    final refreshToken = settings.refreshToken.trim();
    if (clientId.isEmpty || refreshToken.isEmpty) {
      throw const GitHubSyncException('GitHub App refresh token이 없습니다.');
    }
    final response = await _sendOAuthForm(
      settings.effectiveServerUrl,
      '/login/oauth/access_token',
      {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    final decoded = _decodeResponseObject(response);
    return _authorizationFromJson(decoded);
  }

  Future<GitHubRateLimit> fetchRateLimit(GitHubSyncSettings settings) async {
    _requireToken(settings);
    final uri = _apiUri(settings.effectiveServerUrl, '/rate_limit');
    final response = await _send('GET', uri, settings.token);
    final decoded = _decodeResponseObject(response);
    final resources = decoded['resources'];
    if (resources is! Map) {
      throw const GitHubSyncException('GitHub rate limit 응답을 해석하지 못했습니다.');
    }
    final core = resources['core'];
    if (core is! Map) {
      throw const GitHubSyncException('GitHub core rate limit 응답이 없습니다.');
    }
    return GitHubRateLimit(
      resource: 'core',
      limit: (core['limit'] as num?)?.toInt() ?? 0,
      remaining: (core['remaining'] as num?)?.toInt() ?? 0,
      resetAt: DateTime.fromMillisecondsSinceEpoch(
        ((core['reset'] as num?)?.toInt() ?? 0) * 1000,
        isUtc: true,
      ),
    );
  }

  Future<GitHubRateLimit> validateToken(GitHubSyncSettings settings) async {
    final rateLimit = await fetchRateLimit(settings);
    await _validateRepositoryTarget(settings, requireWrite: true);
    return rateLimit;
  }

  Future<GitHubSyncUploadResult> uploadEncryptedSnapshot({
    required GitHubSyncSettings settings,
    required EncryptedSyncBlob blob,
  }) async {
    _requireConfiguredTarget(settings);
    await _validateRepositoryTarget(settings, requireWrite: true);
    final path = settings.path.trim();
    final existingSha = await _existingContentSha(settings, path);
    final uri = _apiUri(
      settings.effectiveServerUrl,
      '/repos/${_encodePath(settings.owner)}/${_encodePath(settings.repo)}'
      '/contents/${_encodeContentPath(path)}',
    );
    final body = <String, Object?>{
      'message': 'Sync Vibe Terminal data',
      'content': base64Encode(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(blob.toJson())),
      ),
      'branch': settings.branch.trim(),
      'sha': ?existingSha,
    };
    final response = await _send(
      'PUT',
      uri,
      settings.token,
      body: jsonEncode(body),
    );
    final decoded = _decodeResponseObject(response);
    final commit = decoded['commit'];
    final commitSha = commit is Map ? commit['sha'] as String? : null;
    if (commitSha == null || commitSha.isEmpty) {
      throw const GitHubSyncException('GitHub 업로드 결과에 commit SHA가 없습니다.');
    }
    return GitHubSyncUploadResult(
      path: path,
      commitSha: commitSha,
      rateLimit: _rateLimitFromHeaders(response.headers),
    );
  }

  Future<void> _validateRepositoryTarget(
    GitHubSyncSettings settings, {
    required bool requireWrite,
  }) async {
    _requireToken(settings);
    final owner = settings.owner.trim();
    final repo = settings.repo.trim();
    if (owner.isEmpty || repo.isEmpty) return;

    final repoResponse = await _sendWithContext(
      () => _send(
        'GET',
        _apiUri(
          settings.effectiveServerUrl,
          '/repos/${_encodePath(owner)}/${_encodePath(repo)}',
        ),
        settings.token,
      ),
      'GitHub 저장소를 찾지 못했거나 접근 권한이 없습니다: $owner/$repo. '
      'private repo는 token에 repo 또는 repository Contents 읽기 권한이 있어야 합니다.',
    );
    if (requireWrite) {
      final decoded = _decodeResponseObject(repoResponse);
      final permissions = decoded['permissions'];
      final canPush = permissions is Map && permissions['push'] == true;
      final canAdmin = permissions is Map && permissions['admin'] == true;
      final canMaintain = permissions is Map && permissions['maintain'] == true;
      if (permissions is Map && !canPush && !canAdmin && !canMaintain) {
        throw const GitHubSyncException(
          'GitHub 저장소 쓰기 권한이 없습니다. GitHub App 또는 token에 repository Contents write 권한을 부여하세요.',
        );
      }
    }

    final branch = settings.branch.trim();
    if (branch.isEmpty) return;
    await _sendWithContext(
      () => _send(
        'GET',
        _apiUri(
          settings.effectiveServerUrl,
          '/repos/${_encodePath(owner)}/${_encodePath(repo)}'
          '/branches/${_encodePath(branch)}',
        ),
        settings.token,
      ),
      'GitHub 브랜치를 찾지 못했거나 접근 권한이 없습니다: $owner/$repo@$branch. '
      'Branch 이름과 token의 private repo 접근 권한을 확인하세요.',
    );
  }

  Future<_GitHubResponse> _sendWithContext(
    Future<_GitHubResponse> Function() request,
    String notFoundMessage,
  ) async {
    try {
      return await request();
    } on GitHubSyncException catch (e) {
      if (e.statusCode == HttpStatus.notFound) {
        throw GitHubSyncException(notFoundMessage);
      }
      rethrow;
    }
  }

  Future<String?> _existingContentSha(
    GitHubSyncSettings settings,
    String path,
  ) async {
    final uri = _apiUri(
      settings.effectiveServerUrl,
      '/repos/${_encodePath(settings.owner)}/${_encodePath(settings.repo)}'
      '/contents/${_encodeContentPath(path)}',
      query: {'ref': settings.branch.trim()},
    );
    final response = await _send(
      'GET',
      uri,
      settings.token,
      allowNotFound: true,
    );
    if (response.statusCode == HttpStatus.notFound) return null;
    final decoded = _decodeResponseObject(response);
    return decoded['sha'] as String?;
  }

  Future<_GitHubResponse> _send(
    String method,
    Uri uri,
    String token, {
    String? body,
    bool allowNotFound = false,
  }) async {
    final request = await _withTimeout(() => _client.openUrl(method, uri));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.userAgentHeader, 'VibeTerminalSync')
      ..set('X-GitHub-Api-Version', '2022-11-28');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final response = await _withTimeout(request.close);
    final text = await _withTimeout(() => utf8.decodeStream(response));
    if (response.statusCode == HttpStatus.notFound && allowNotFound) {
      return _GitHubResponse(response.statusCode, text, response.headers);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GitHubSyncException(
        _errorMessage(response.statusCode, text),
        statusCode: response.statusCode,
      );
    }
    return _GitHubResponse(response.statusCode, text, response.headers);
  }

  Future<_GitHubResponse> _sendOAuthForm(
    String serverUrl,
    String path,
    Map<String, String> form,
  ) async {
    final request = await _withTimeout(
      () => _client.postUrl(_webUri(serverUrl, path)),
    );
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.userAgentHeader, 'VibeTerminalSync')
      ..contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
    request.write(Uri(queryParameters: form).query);
    final response = await _withTimeout(request.close);
    final text = await _withTimeout(() => utf8.decodeStream(response));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GitHubSyncException(
        _errorMessage(response.statusCode, text),
        statusCode: response.statusCode,
      );
    }
    return _GitHubResponse(response.statusCode, text, response.headers);
  }

  Map<String, Object?> _decodeResponseObject(_GitHubResponse response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const GitHubSyncException('GitHub 응답이 JSON object가 아닙니다.');
    }
    return Map<String, Object?>.from(decoded);
  }

  GitHubAppAuthorization _authorizationFromJson(Map<String, Object?> json) {
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      _throwIfOAuthError(json);
      throw const GitHubSyncException('GitHub access token 응답을 해석하지 못했습니다.');
    }
    DateTime? expiresAt(String key) {
      final seconds = (json[key] as num?)?.toInt();
      if (seconds == null || seconds <= 0) return null;
      return DateTime.now().toUtc().add(Duration(seconds: seconds));
    }

    return GitHubAppAuthorization(
      accessToken: accessToken,
      tokenType: json['token_type'] as String? ?? 'bearer',
      expiresAt: expiresAt('expires_in'),
      refreshToken: json['refresh_token'] as String?,
      refreshTokenExpiresAt: expiresAt('refresh_token_expires_in'),
    );
  }

  void _throwIfOAuthError(Map<String, Object?> json) {
    if (json['error'] != null) {
      throw GitHubSyncException(_oauthErrorMessage(json));
    }
  }

  String _oauthErrorMessage(Map<String, Object?> json) {
    final error = json['error'] as String? ?? 'unknown_error';
    final description = json['error_description'] as String?;
    return description == null || description.isEmpty
        ? 'GitHub OAuth: $error'
        : 'GitHub OAuth: $description';
  }

  GitHubRateLimit? _rateLimitFromHeaders(HttpHeaders headers) {
    final limit = int.tryParse(headers.value('x-ratelimit-limit') ?? '');
    final remaining = int.tryParse(
      headers.value('x-ratelimit-remaining') ?? '',
    );
    final reset = int.tryParse(headers.value('x-ratelimit-reset') ?? '');
    if (limit == null || remaining == null || reset == null) return null;
    return GitHubRateLimit(
      resource: headers.value('x-ratelimit-resource') ?? 'core',
      limit: limit,
      remaining: remaining,
      resetAt: DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true),
    );
  }

  Uri _apiUri(String serverUrl, String path, {Map<String, String>? query}) {
    final base = _apiBase(serverUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$path', queryParameters: query);
  }

  Uri _webUri(String serverUrl, String path) {
    final base = _webBase(serverUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$path');
  }

  Uri _apiBase(String serverUrl) {
    final raw = serverUrl.trim().isEmpty
        ? 'https://github.com'
        : serverUrl.trim();
    final uri = Uri.parse(raw.contains('://') ? raw : 'https://$raw');
    if (uri.host.toLowerCase() == 'github.com') {
      return Uri.https('api.github.com', '');
    }
    if (uri.path.endsWith('/api/v3')) return uri;
    final path = uri.path.endsWith('/')
        ? '${uri.path}api/v3'
        : '${uri.path}/api/v3';
    return uri.replace(path: path);
  }

  Uri _webBase(String serverUrl) {
    final raw = serverUrl.trim().isEmpty
        ? 'https://github.com'
        : serverUrl.trim();
    final uri = Uri.parse(raw.contains('://') ? raw : 'https://$raw');
    final path = uri.path.endsWith('/api/v3')
        ? uri.path.substring(0, uri.path.length - '/api/v3'.length)
        : uri.path;
    return uri.replace(path: path);
  }

  String _errorMessage(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return 'GitHub API $statusCode: ${decoded['message']}';
      }
    } catch (_) {
      // Fall back to the raw body below.
    }
    return 'GitHub API $statusCode: $body';
  }

  void _requireToken(GitHubSyncSettings settings) {
    if (settings.token.trim().isEmpty) {
      throw const GitHubSyncException('GitHub token을 입력하세요.');
    }
  }

  void _requireConfiguredTarget(GitHubSyncSettings settings) {
    _requireToken(settings);
    if (!settings.targetConfigured) {
      throw const GitHubSyncException('GitHub org/repo/branch/path를 입력하세요.');
    }
  }

  String _encodePath(String value) => Uri.encodeComponent(value.trim());

  String _encodeContentPath(String value) {
    return value
        .split('/')
        .where((part) => part.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
  }
}

class _GitHubResponse {
  const _GitHubResponse(this.statusCode, this.body, this.headers);

  final int statusCode;
  final String body;
  final HttpHeaders headers;
}
