import 'dart:convert';
import 'dart:io';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.name,
    required this.htmlUrl,
    required this.publishedAt,
    required this.body,
  });

  final String version;
  final String name;
  final Uri htmlUrl;
  final DateTime? publishedAt;
  final String body;
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestRelease,
    required this.updateAvailable,
  });

  final String currentVersion;
  final ReleaseInfo latestRelease;
  final bool updateAvailable;
}

class UpdateChecker {
  const UpdateChecker({
    this.owner = 'jhl-labs',
    this.repo = 'vibe-terminal-public',
    this.httpClientFactory,
  });

  /// 업데이트 확인은 백그라운드 부가 기능이므로, 느린 네트워크에서 소켓을
  /// 붙들고 있지 않도록 짧게 끊는다. 실패는 그냥 null로 흡수된다.
  static const _connectTimeout = Duration(seconds: 10);
  static const _responseTimeout = Duration(seconds: 15);

  final String owner;
  final String repo;
  final HttpClient Function()? httpClientFactory;

  /// 저장소의 릴리즈 목록 페이지. 헤더의 버전 라벨을 더블 클릭했을 때 연다.
  Uri get releasesPageUrl => Uri.https('github.com', '/$owner/$repo/releases');

  Future<UpdateCheckResult?> check(String currentVersion) async {
    final normalizedCurrent = _normalizeVersion(currentVersion);
    if (normalizedCurrent.isEmpty) return null;

    try {
      final json = await _getJson('/repos/$owner/$repo/releases/latest');
      if (json is! Map<String, Object?>) return null;
      final release = parseRelease(json);
      if (release == null) return null;
      return UpdateCheckResult(
        currentVersion: normalizedCurrent,
        latestRelease: release,
        updateAvailable:
            compareVersions(release.version, normalizedCurrent) > 0,
      );
    } on Object {
      return null;
    }
  }

  /// 최근 정식 릴리즈를 최신순으로 준다. 릴리즈 노트 화면이 쓴다.
  /// draft·prerelease는 제외하며, 실패하면 빈 목록이 아니라 예외를 던져
  /// 화면이 "불러오지 못함"을 구분해 보여줄 수 있게 한다.
  Future<List<ReleaseInfo>> listReleases({int perPage = 30}) async {
    final json = await _getJson(
      '/repos/$owner/$repo/releases',
      query: {'per_page': '$perPage'},
    );
    if (json is! List) {
      throw const FormatException('unexpected releases payload');
    }
    return [
      for (final item in json)
        if (item is Map<String, Object?>) ?parseRelease(item),
    ];
  }

  /// GitHub Release JSON 하나를 [ReleaseInfo]로 바꾼다. draft·prerelease나
  /// 태그를 버전으로 읽을 수 없는 항목은 null.
  static ReleaseInfo? parseRelease(Map<String, Object?> json) {
    final draft = json['draft'] as bool? ?? false;
    final prerelease = json['prerelease'] as bool? ?? false;
    final tagName = json['tag_name'] as String?;
    final htmlUrl = Uri.tryParse(json['html_url'] as String? ?? '');
    if (draft || prerelease || tagName == null || htmlUrl == null) {
      return null;
    }
    final version = _normalizeVersion(tagName);
    if (version.isEmpty) return null;
    final name = (json['name'] as String?)?.trim();
    return ReleaseInfo(
      version: version,
      name: name != null && name.isNotEmpty ? name : tagName,
      htmlUrl: htmlUrl,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      body: json['body'] as String? ?? '',
    );
  }

  /// GitHub API GET. [check]는 어떤 실패든 null로 흡수하고, [listReleases]는
  /// 예외를 그대로 올린다.
  Future<Object?> _getJson(String path, {Map<String, String>? query}) async {
    final client =
        httpClientFactory?.call() ??
        (HttpClient()..connectionTimeout = _connectTimeout);
    try {
      final uri = Uri.https('api.github.com', path, query);
      final request = await client.getUrl(uri).timeout(_responseTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'VibeTerminalUpdateChecker');
      final response = await request.close().timeout(_responseTimeout);
      final payload = await utf8
          .decodeStream(response)
          .timeout(_responseTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub responded ${response.statusCode}',
          uri: uri,
        );
      }
      return jsonDecode(payload);
    } finally {
      client.close(force: true);
    }
  }
}

String _normalizeVersion(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final withoutBuild = trimmed.split('+').first;
  return withoutBuild.startsWith('v') || withoutBuild.startsWith('V')
      ? withoutBuild.substring(1)
      : withoutBuild;
}

int compareVersions(String a, String b) {
  List<int> parseCore(String value) {
    final core = value.split('-').first;
    return core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  final left = parseCore(a);
  final right = parseCore(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}
