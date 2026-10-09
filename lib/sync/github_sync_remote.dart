import '../settings/app_settings.dart';
import 'github_sync_service.dart';
import 'sync_remote.dart';

/// 만료가 가까운 GitHub App 사용자 token을 갱신하고 새 값을 저장한다.
///
/// 앱 전체에서 하나만 쓴다. GitHub App의 갱신 토큰은 한 번 쓰면 바뀌므로,
/// 동기화와 커뮤니티 패널이 동시에 갱신하면 늦은 쪽이 이미 쓴 토큰을 보내
/// 실패한다. 진행 중인 갱신이 있으면 그 결과를 함께 쓴다.
class GitHubTokenRefresher {
  GitHubTokenRefresher({
    required this._service,
    required this._save,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GitHubSyncService _service;
  final void Function(GitHubAppAuthorization authorization) _save;
  final DateTime Function() _clock;
  Future<GitHubAppAuthorization>? _inflight;

  static const refreshMargin = Duration(minutes: 5);

  /// [settings]의 token이 곧 만료되면 갱신한 설정을, 아니면 그대로 돌려준다.
  Future<GitHubSyncSettings> fresh(GitHubSyncSettings settings) async {
    final now = _clock().toUtc();
    final expiresAt = settings.tokenExpiresAt;
    final shouldRefresh =
        expiresAt != null &&
        settings.refreshToken.trim().isNotEmpty &&
        expiresAt.isBefore(now.add(refreshMargin));
    if (!shouldRefresh) return settings;

    final refreshExpiresAt = settings.refreshTokenExpiresAt;
    if (refreshExpiresAt != null && refreshExpiresAt.isBefore(now)) {
      // 갱신은 못 하지만 지금 token이 아직 유효하면 만료될 때까지 쓴다.
      if (expiresAt.isAfter(now)) return settings;
      throw const GitHubSyncException(
        GitHubSyncService.signInExpiredMessage,
        statusCode: 401,
      );
    }
    final authorization = await refreshNow(settings);
    return settings.copyWith(
      token: authorization.accessToken,
      refreshToken: authorization.refreshToken ?? settings.refreshToken,
      tokenExpiresAt: authorization.expiresAt,
      refreshTokenExpiresAt:
          authorization.refreshTokenExpiresAt ?? settings.refreshTokenExpiresAt,
    );
  }

  /// 지금 갱신하고 저장한다. 이미 진행 중인 갱신이 있으면 그 결과를 쓴다.
  Future<GitHubAppAuthorization> refreshNow(GitHubSyncSettings settings) {
    return _inflight ??= () async {
      try {
        final authorization = await _service.refreshUserAccessToken(
          settings: settings,
        );
        _save(authorization);
        return authorization;
      } finally {
        _inflight = null;
      }
    }();
  }
}

/// GitHub 저장소의 파일 하나를 동기화 원격으로 쓴다.
class GitHubSyncRemote implements SyncRemote {
  GitHubSyncRemote({required this._service, required this._settings});

  final GitHubSyncService _service;
  final Future<GitHubSyncSettings> Function() _settings;

  @override
  Future<SyncRemoteFile?> download() async {
    final file = await _service.fetchSyncFile(await _settings());
    return file == null
        ? null
        : SyncRemoteFile(sha: file.sha, content: file.content);
  }

  @override
  Future<String> upload(String content, {String? sha}) async {
    try {
      return await _service.putSyncFile(
        settings: await _settings(),
        content: content,
        sha: sha,
      );
    } on GitHubSyncConflictException {
      throw const SyncRemoteConflictException();
    }
  }
}
