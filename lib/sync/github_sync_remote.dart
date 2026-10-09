import '../settings/app_settings.dart';
import 'github_sync_service.dart';
import 'sync_remote.dart';

/// 만료가 가까운 GitHub App 사용자 token을 갱신하고 새 값을 저장한다.
class GitHubTokenRefresher {
  GitHubTokenRefresher({
    required this._service,
    required this._save,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GitHubSyncService _service;
  final void Function(GitHubAppAuthorization authorization) _save;
  final DateTime Function() _clock;

  static const _refreshMargin = Duration(minutes: 5);

  Future<GitHubSyncSettings> fresh(GitHubSyncSettings settings) async {
    final expiresAt = settings.tokenExpiresAt;
    final shouldRefresh =
        expiresAt != null &&
        settings.refreshToken.trim().isNotEmpty &&
        expiresAt.isBefore(_clock().toUtc().add(_refreshMargin));
    if (!shouldRefresh) return settings;

    final authorization = await _service.refreshUserAccessToken(
      settings: settings,
    );
    _save(authorization);
    return settings.copyWith(
      token: authorization.accessToken,
      refreshToken: authorization.refreshToken ?? settings.refreshToken,
      tokenExpiresAt: authorization.expiresAt,
      refreshTokenExpiresAt:
          authorization.refreshTokenExpiresAt ?? settings.refreshTokenExpiresAt,
    );
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
