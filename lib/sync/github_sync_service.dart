import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../settings/app_settings.dart';

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

/// 저장소의 동기화 파일. [sha]는 다음 업로드의 낙관적 잠금 값이다.
class GitHubSyncFile {
  const GitHubSyncFile({required this.sha, required this.content});

  final String sha;
  final String content;
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

/// 내려받은 뒤 다른 기기가 먼저 올렸다. 다시 내려받아 합쳐야 한다.
class GitHubSyncConflictException extends GitHubSyncException {
  const GitHubSyncConflictException()
    : super('다른 기기가 먼저 동기화했습니다.', statusCode: HttpStatus.conflict);
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

  /// 동기화 파일을 내려받는다. 파일이 아직 없으면 null.
  Future<GitHubSyncFile?> fetchSyncFile(GitHubSyncSettings settings) async {
    _requireConfiguredTarget(settings);
    final uri = _contentsUri(settings, query: {'ref': settings.branch.trim()});
    final response = await _send(
      'GET',
      uri,
      settings.token,
      allowNotFound: true,
    );
    if (response.statusCode == HttpStatus.notFound) {
      // 파일이 없는 것인지, 저장소·브랜치에 닿지 못한 것인지 구분한다.
      await _validateRepositoryTarget(settings, requireWrite: false);
      return null;
    }
    final decoded = _decodeResponseObject(response);
    final sha = decoded['sha'] as String?;
    if (sha == null || sha.isEmpty) {
      throw const GitHubSyncException('GitHub 동기화 파일 응답에 sha가 없습니다.');
    }
    final encoded = decoded['content'] as String? ?? '';
    // 1MB를 넘는 파일은 contents API가 본문을 비워 돌려주므로 원문으로 받는다.
    if (decoded['encoding'] != 'base64' || encoded.isEmpty) {
      final raw = await _send(
        'GET',
        uri,
        settings.token,
        accept: 'application/vnd.github.raw+json',
      );
      return GitHubSyncFile(sha: sha, content: raw.body);
    }
    final content = utf8.decode(
      base64Decode(encoded.replaceAll(RegExp(r'\s'), '')),
    );
    return GitHubSyncFile(sha: sha, content: content);
  }

  /// 동기화 파일을 올리고 새 sha를 돌려준다. [sha]는 내려받을 때의 값이며,
  /// 그새 다른 기기가 올렸으면 [GitHubSyncConflictException]을 던진다.
  Future<String> putSyncFile({
    required GitHubSyncSettings settings,
    required String content,
    String? sha,
  }) async {
    _requireConfiguredTarget(settings);
    final body = <String, Object?>{
      'message': 'Sync Vibe Terminal data',
      'content': base64Encode(utf8.encode(content)),
      'branch': settings.branch.trim(),
      'sha': ?sha,
    };
    final _GitHubResponse response;
    try {
      response = await _send(
        'PUT',
        _contentsUri(settings),
        settings.token,
        body: jsonEncode(body),
      );
    } on GitHubSyncException catch (e) {
      // sha가 맞지 않으면 409, 있는 파일에 sha를 빠뜨리면 422가 온다.
      if (e.statusCode == HttpStatus.conflict ||
          (e.statusCode == HttpStatus.unprocessableEntity &&
              e.message.contains('sha'))) {
        throw const GitHubSyncConflictException();
      }
      rethrow;
    }
    final decoded = _decodeResponseObject(response);
    final file = decoded['content'];
    final newSha = file is Map ? file['sha'] as String? : null;
    if (newSha == null || newSha.isEmpty) {
      throw const GitHubSyncException('GitHub 업로드 결과에 sha가 없습니다.');
    }
    return newSha;
  }

  Uri _contentsUri(GitHubSyncSettings settings, {Map<String, String>? query}) =>
      _apiUri(
        settings.effectiveServerUrl,
        '/repos/${_encodePath(settings.owner)}/${_encodePath(settings.repo)}'
        '/contents/${_encodeContentPath(settings.path.trim())}',
        query: query,
      );

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
      '저장소 이름을 확인하고, vibe-terminal 앱이 이 저장소에 설치되어 있는지 '
      '확인하세요.',
    );
    if (requireWrite) {
      final decoded = _decodeResponseObject(repoResponse);
      final permissions = decoded['permissions'];
      final canPush = permissions is Map && permissions['push'] == true;
      final canAdmin = permissions is Map && permissions['admin'] == true;
      final canMaintain = permissions is Map && permissions['maintain'] == true;
      if (permissions is Map && !canPush && !canAdmin && !canMaintain) {
        throw const GitHubSyncException(
          'GitHub 저장소 쓰기 권한이 없습니다. 앱 설치 화면에서 이 저장소의 '
          'Contents 쓰기 권한을 허용하세요.',
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

  Future<_GitHubResponse> _send(
    String method,
    Uri uri,
    String token, {
    String? body,
    bool allowNotFound = false,
    String accept = 'application/vnd.github+json',
  }) async {
    final request = await _withTimeout(() => _client.openUrl(method, uri));
    request.headers
      ..set(HttpHeaders.acceptHeader, accept)
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
    String? message;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } catch (_) {
      // Fall back to the raw body below.
    }
    if (statusCode == HttpStatus.unauthorized) {
      return 'GitHub 로그인이 만료되었거나 취소되었습니다. 다시 로그인하세요.';
    }
    // 앱 사용자 token은 앱이 설치된 저장소에만 쓸 수 있다.
    if (statusCode == HttpStatus.forbidden &&
        (message?.contains('not accessible by integration') ?? false)) {
      return 'vibe-terminal 앱이 이 저장소에 설치되지 않았거나 권한이 부족합니다. '
          '앱 설치 단계에서 이 저장소를 추가하세요.';
    }
    return 'GitHub API $statusCode: ${message ?? body}';
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
