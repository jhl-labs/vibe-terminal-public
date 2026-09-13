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
    this.repo = 'vibe_terminal',
    this.httpClientFactory,
  });

  /// 업데이트 확인은 백그라운드 부가 기능이므로, 느린 네트워크에서 소켓을
  /// 붙들고 있지 않도록 짧게 끊는다. 실패는 그냥 null로 흡수된다.
  static const _connectTimeout = Duration(seconds: 10);
  static const _responseTimeout = Duration(seconds: 15);

  final String owner;
  final String repo;
  final HttpClient Function()? httpClientFactory;

  Future<UpdateCheckResult?> check(String currentVersion) async {
    final normalizedCurrent = _normalizeVersion(currentVersion);
    if (normalizedCurrent.isEmpty) return null;

    final client =
        httpClientFactory?.call() ??
        (HttpClient()..connectionTimeout = _connectTimeout);
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/releases/latest',
      );
      final request = await client.getUrl(uri).timeout(_responseTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'VibeTerminalUpdateChecker');
      final response = await request.close().timeout(_responseTimeout);
      final payload = await utf8
          .decodeStream(response)
          .timeout(_responseTimeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final json = jsonDecode(payload);
      if (json is! Map<String, Object?>) return null;
      final draft = json['draft'] as bool? ?? false;
      final prerelease = json['prerelease'] as bool? ?? false;
      final tagName = json['tag_name'] as String?;
      final htmlUrl = Uri.tryParse(json['html_url'] as String? ?? '');
      if (draft || prerelease || tagName == null || htmlUrl == null) {
        return null;
      }

      final latestVersion = _normalizeVersion(tagName);
      if (latestVersion.isEmpty) return null;
      final publishedAt = DateTime.tryParse(
        json['published_at'] as String? ?? '',
      );
      final release = ReleaseInfo(
        version: latestVersion,
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : tagName,
        htmlUrl: htmlUrl,
        publishedAt: publishedAt,
        body: json['body'] as String? ?? '',
      );
      return UpdateCheckResult(
        currentVersion: normalizedCurrent,
        latestRelease: release,
        updateAvailable: compareVersions(latestVersion, normalizedCurrent) > 0,
      );
    } on Object {
      return null;
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
