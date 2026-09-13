import 'dart:async';
import 'dart:convert';
import 'dart:io';

class GitHubCommunityRateLimit {
  const GitHubCommunityRateLimit({
    required this.limit,
    required this.remaining,
    required this.used,
    required this.resetAt,
    required this.resource,
  });

  final int limit;
  final int remaining;
  final int used;
  final DateTime resetAt;
  final String resource;

  bool get exhausted => limit > 0 && remaining <= 0;
}

class GitHubCommunityIssue {
  const GitHubCommunityIssue({
    required this.number,
    required this.title,
    required this.url,
    required this.author,
    required this.state,
    required this.commentCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int number;
  final String title;
  final Uri url;
  final String author;
  final String state;
  final int commentCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class GitHubDiscussionCategory {
  const GitHubDiscussionCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class GitHubCommunityDiscussion {
  const GitHubCommunityDiscussion({
    required this.id,
    required this.number,
    required this.title,
    required this.url,
    required this.author,
    required this.category,
    required this.commentCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final int number;
  final String title;
  final Uri url;
  final String author;
  final String category;
  final int commentCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class GitHubCommunityDiscussionsResult {
  const GitHubCommunityDiscussionsResult({
    required this.repositoryId,
    required this.categories,
    required this.discussions,
    required this.rateLimit,
  });

  final String repositoryId;
  final List<GitHubDiscussionCategory> categories;
  final List<GitHubCommunityDiscussion> discussions;
  final GitHubCommunityRateLimit? rateLimit;
}

class GitHubCommunityException implements Exception {
  const GitHubCommunityException(
    this.message, {
    this.rateLimited = false,
    this.statusCode,
  });

  final String message;
  final bool rateLimited;

  /// REST 응답에서 온 예외라면 HTTP 상태 코드. GraphQL/네트워크 오류는 null.
  final int? statusCode;

  /// token이 만료되었거나 유효하지 않아 다시 로그인해야 하는 경우.
  bool get unauthorized => statusCode == HttpStatus.unauthorized;

  @override
  String toString() => message;
}

class GitHubCommunityService {
  GitHubCommunityService({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _connectTimeout);

  static const owner = 'jhl-labs';
  static const repo = 'vibe_terminal';

  /// 응답이 없는 서버에서 커뮤니티 패널이 영원히 로딩 상태로 남지 않게 한다.
  static const _connectTimeout = Duration(seconds: 15);
  static const _responseTimeout = Duration(seconds: 30);

  final HttpClient _client;

  Future<T> _withTimeout<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_responseTimeout);
    } on TimeoutException {
      throw const GitHubCommunityException('GitHub 응답 시간이 초과되었습니다.');
    } on SocketException catch (e) {
      throw GitHubCommunityException('GitHub에 연결할 수 없습니다: ${e.message}');
    }
  }

  Future<GitHubCommunityRateLimit> fetchRateLimit(String token) async {
    final response = await _sendRest(
      'GET',
      Uri.https('api.github.com', '/rate_limit'),
      token,
    );
    return rateLimitFromRestJson(decodeObject(response.body));
  }

  /// `/rate_limit` REST 응답에서 core 사용량을 읽는다.
  static GitHubCommunityRateLimit rateLimitFromRestJson(
    Map<dynamic, dynamic> decoded,
  ) {
    final resources = decoded['resources'];
    if (resources is! Map) {
      throw const GitHubCommunityException('GitHub rate limit 응답을 해석하지 못했습니다.');
    }
    final core = resources['core'];
    if (core is! Map) {
      throw const GitHubCommunityException('GitHub core rate limit 정보가 없습니다.');
    }
    return GitHubCommunityRateLimit(
      resource: 'core',
      limit: (core['limit'] as num?)?.toInt() ?? 0,
      remaining: (core['remaining'] as num?)?.toInt() ?? 0,
      used: (core['used'] as num?)?.toInt() ?? 0,
      resetAt: _epochSeconds(core['reset']),
    );
  }

  Future<List<GitHubCommunityIssue>> listIssues(String token) async {
    final response = await _sendRest(
      'GET',
      Uri.https('api.github.com', '/repos/$owner/$repo/issues', {
        'state': 'open',
        'per_page': '30',
        'sort': 'updated',
        'direction': 'desc',
      }),
      token,
    );
    return issuesFromJson(decodeJson(response.body));
  }

  /// issues 목록 응답을 해석한다. pull request는 issues API에도 섞여 오므로 제외한다.
  static List<GitHubCommunityIssue> issuesFromJson(Object? decoded) {
    if (decoded is! List) {
      throw const GitHubCommunityException('GitHub issues 응답을 해석하지 못했습니다.');
    }
    return [
      for (final item in decoded)
        if (item is Map && item['pull_request'] == null) issueFromJson(item),
    ];
  }

  Future<GitHubCommunityIssue> createIssue({
    required String token,
    required String title,
    required String body,
  }) async {
    final response = await _sendRest(
      'POST',
      Uri.https('api.github.com', '/repos/$owner/$repo/issues'),
      token,
      body: jsonEncode({'title': title, 'body': body}),
    );
    return issueFromJson(decodeObject(response.body));
  }

  Future<GitHubCommunityDiscussionsResult> listDiscussions(String token) async {
    final decoded = await _sendGraphQl(token, _discussionListQuery, {
      'owner': owner,
      'name': repo,
    });
    return discussionsFromGraphQlData(decoded);
  }

  /// discussions GraphQL query의 `data`를 해석한다.
  static GitHubCommunityDiscussionsResult discussionsFromGraphQlData(
    Map<dynamic, dynamic> decoded,
  ) {
    final repository = decoded['repository'];
    if (repository is! Map) {
      throw const GitHubCommunityException('GitHub repository 정보를 찾지 못했습니다.');
    }
    final repositoryId = repository['id'] as String? ?? '';
    final categoryNodes =
        ((repository['discussionCategories'] as Map?)?['nodes'] as List?) ??
        const [];
    final discussionNodes =
        ((repository['discussions'] as Map?)?['nodes'] as List?) ?? const [];
    return GitHubCommunityDiscussionsResult(
      repositoryId: repositoryId,
      categories: [
        for (final item in categoryNodes)
          if (item is Map)
            GitHubDiscussionCategory(
              id: item['id'] as String? ?? '',
              name: item['name'] as String? ?? 'General',
            ),
      ],
      discussions: [
        for (final item in discussionNodes)
          if (item is Map) discussionFromJson(item),
      ],
      rateLimit: graphQlRateLimit(decoded['rateLimit']),
    );
  }

  Future<GitHubCommunityDiscussion> createDiscussion({
    required String token,
    required String repositoryId,
    required String categoryId,
    required String title,
    required String body,
  }) async {
    final decoded = await _sendGraphQl(token, _createDiscussionMutation, {
      'repositoryId': repositoryId,
      'categoryId': categoryId,
      'title': title,
      'body': body,
    });
    final discussion = ((decoded['createDiscussion'] as Map?)?['discussion']);
    if (discussion is! Map) {
      throw const GitHubCommunityException(
        'GitHub discussion 생성 결과를 해석하지 못했습니다.',
      );
    }
    return discussionFromJson(discussion);
  }

  Future<_GitHubCommunityResponse> _sendRest(
    String method,
    Uri uri,
    String token, {
    String? body,
  }) async {
    final request = await _withTimeout(() => _client.openUrl(method, uri));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.userAgentHeader, 'VibeTerminalCommunity')
      ..set('X-GitHub-Api-Version', '2022-11-28');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final response = await _withTimeout(request.close);
    final text = await _withTimeout(() => utf8.decodeStream(response));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw exceptionForResponse(
        statusCode: response.statusCode,
        body: text,
        rateLimitRemaining: response.headers.value('x-ratelimit-remaining'),
        acceptedPermissions: response.headers.value(
          'x-accepted-github-permissions',
        ),
      );
    }
    return _GitHubCommunityResponse(text, response.headers);
  }

  Future<Map<String, Object?>> _sendGraphQl(
    String token,
    String query,
    Map<String, Object?> variables,
  ) async {
    final response = await _sendRest(
      'POST',
      Uri.https('api.github.com', '/graphql'),
      token,
      body: jsonEncode({'query': query, 'variables': variables}),
    );
    return graphQlDataFromJson(decodeObject(response.body));
  }

  /// GraphQL 응답 envelope에서 `data`를 꺼낸다. `errors`가 있으면
  /// rate limit/권한 오류를 구분해 예외로 바꾼다.
  static Map<String, Object?> graphQlDataFromJson(
    Map<dynamic, dynamic> decoded,
  ) {
    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map ? first['message'] as String? : null;
      final type = first is Map ? first['type'] as String? : null;
      final rateLimited =
          type == 'RATE_LIMITED' ||
          (message?.toLowerCase().contains('rate limit') ?? false);
      final permissionDenied =
          type == 'FORBIDDEN' ||
          type == 'UNAUTHORIZED' ||
          (message?.toLowerCase().contains('resource not accessible') ??
              false) ||
          (message?.toLowerCase().contains('permission') ?? false);
      throw GitHubCommunityException(
        rateLimited
            ? 'GitHub API token 사용량이 초과되었습니다.'
            : permissionDenied
            ? _communityWritePermissionMessage(message)
            : (message ?? 'GitHub GraphQL 오류가 발생했습니다.'),
        rateLimited: rateLimited,
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw const GitHubCommunityException('GitHub GraphQL 응답을 해석하지 못했습니다.');
    }
    return Map<String, Object?>.from(data);
  }

  /// 2xx가 아닌 REST 응답을 사용자에게 보여줄 예외로 바꾼다.
  static GitHubCommunityException exceptionForResponse({
    required int statusCode,
    required String body,
    String? rateLimitRemaining,
    String? acceptedPermissions,
  }) {
    final remaining = int.tryParse(rateLimitRemaining ?? '');
    final rateLimited =
        (statusCode == HttpStatus.forbidden ||
            statusCode == HttpStatus.tooManyRequests) &&
        remaining == 0;
    if (rateLimited) {
      return GitHubCommunityException(
        'GitHub API token 사용량이 초과되었습니다.',
        rateLimited: true,
        statusCode: statusCode,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      return GitHubCommunityException(
        '커뮤니티 저장소를 찾지 못했거나 token 접근 권한이 없습니다. '
        'private repo라면 token에 Issues/Discussions 접근 권한이 필요합니다.',
        statusCode: statusCode,
      );
    }
    if (statusCode == HttpStatus.unauthorized) {
      return GitHubCommunityException(
        'GitHub token이 만료되었거나 유효하지 않습니다. GitHub App으로 다시 로그인하세요.',
        statusCode: statusCode,
      );
    }
    if (statusCode == HttpStatus.forbidden) {
      return GitHubCommunityException(
        _communityWritePermissionMessage(
          _errorBody(body),
          acceptedPermissions: acceptedPermissions,
        ),
        statusCode: statusCode,
      );
    }
    return GitHubCommunityException(
      'GitHub API $statusCode: ${_errorBody(body)}',
      statusCode: statusCode,
    );
  }

  static String _communityWritePermissionMessage(
    String? githubMessage, {
    String? acceptedPermissions,
  }) {
    final permissions =
        acceptedPermissions == null || acceptedPermissions.isEmpty
        ? ''
        : ' GitHub 요구 권한: $acceptedPermissions.';
    final raw = githubMessage == null || githubMessage.trim().isEmpty
        ? ''
        : ' GitHub 응답: ${githubMessage.trim()}';
    return '글 작성 권한이 없습니다. GitHub App token이라면 앱이 '
        '$owner/$repo 저장소에 설치되어 있고 Issues/Discussions 쓰기 권한이 승인되어야 합니다. '
        'PAT라면 public repo 쓰기용 scope 또는 fine-grained Issues/Discussions write 권한이 필요합니다.'
        '$permissions$raw';
  }

  static String _errorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {
      // Fall through to raw body.
    }
    return body;
  }

  /// 본문을 JSON으로 해석한다. 깨진 본문(HTML 오류 페이지 등)은
  /// [FormatException] 대신 [GitHubCommunityException]으로 바꿔
  /// 호출자가 한 종류의 예외만 다루게 한다.
  static Object? decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException catch (error) {
      throw GitHubCommunityException(
        'GitHub 응답을 JSON으로 해석하지 못했습니다: ${error.message}',
      );
    }
  }

  /// [decodeJson]에 더해 결과가 JSON object인지 확인한다.
  static Map<String, Object?> decodeObject(String body) {
    final decoded = decodeJson(body);
    if (decoded is! Map) {
      throw const GitHubCommunityException('GitHub 응답이 JSON object가 아닙니다.');
    }
    return Map<String, Object?>.from(decoded);
  }

  /// REST issue 객체를 [GitHubCommunityIssue]로 바꾼다.
  static GitHubCommunityIssue issueFromJson(Map<dynamic, dynamic> item) {
    final url =
        item['html_url'] as String? ?? 'https://github.com/$owner/$repo';
    return GitHubCommunityIssue(
      number: (item['number'] as num?)?.toInt() ?? 0,
      title: item['title'] as String? ?? 'Untitled issue',
      url: Uri.parse(url),
      author: ((item['user'] as Map?)?['login'] as String?) ?? 'unknown',
      state: item['state'] as String? ?? 'open',
      commentCount: (item['comments'] as num?)?.toInt() ?? 0,
      createdAt: _dateTime(item['created_at']),
      updatedAt: _dateTime(item['updated_at']),
    );
  }

  /// GraphQL discussion 노드를 [GitHubCommunityDiscussion]으로 바꾼다.
  static GitHubCommunityDiscussion discussionFromJson(
    Map<dynamic, dynamic> item,
  ) {
    final url =
        item['url'] as String? ?? 'https://github.com/$owner/$repo/discussions';
    return GitHubCommunityDiscussion(
      id: item['id'] as String? ?? '',
      number: (item['number'] as num?)?.toInt() ?? 0,
      title: item['title'] as String? ?? 'Untitled discussion',
      url: Uri.parse(url),
      author: ((item['author'] as Map?)?['login'] as String?) ?? 'unknown',
      category: ((item['category'] as Map?)?['name'] as String?) ?? 'General',
      commentCount:
          (((item['comments'] as Map?)?['totalCount']) as num?)?.toInt() ?? 0,
      createdAt: _dateTime(item['createdAt']),
      updatedAt: _dateTime(item['updatedAt']),
    );
  }

  /// GraphQL 응답의 `rateLimit` 필드를 읽는다. 없으면 null.
  static GitHubCommunityRateLimit? graphQlRateLimit(Object? value) {
    if (value is! Map) return null;
    return GitHubCommunityRateLimit(
      resource: 'graphql',
      limit: (value['limit'] as num?)?.toInt() ?? 0,
      remaining: (value['remaining'] as num?)?.toInt() ?? 0,
      used: (value['used'] as num?)?.toInt() ?? 0,
      resetAt: _dateTime(value['resetAt']),
    );
  }

  static DateTime _epochSeconds(Object? value) {
    final seconds = (value as num?)?.toInt() ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static DateTime _dateTime(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

class _GitHubCommunityResponse {
  const _GitHubCommunityResponse(this.body, this.headers);

  final String body;
  final HttpHeaders headers;
}

const _discussionListQuery = r'''
query VibeCommunityDiscussions($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    id
    discussionCategories(first: 30) {
      nodes {
        id
        name
      }
    }
    discussions(first: 30, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        id
        number
        title
        url
        createdAt
        updatedAt
        author {
          login
        }
        category {
          name
        }
        comments {
          totalCount
        }
      }
    }
  }
  rateLimit {
    limit
    remaining
    used
    resetAt
  }
}
''';

const _createDiscussionMutation = r'''
mutation VibeCreateDiscussion(
  $repositoryId: ID!
  $categoryId: ID!
  $title: String!
  $body: String!
) {
  createDiscussion(input: {
    repositoryId: $repositoryId
    categoryId: $categoryId
    title: $title
    body: $body
  }) {
    discussion {
      id
      number
      title
      url
      createdAt
      updatedAt
      author {
        login
      }
      category {
        name
      }
      comments {
        totalCount
      }
    }
  }
}
''';
