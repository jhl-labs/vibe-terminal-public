import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../community/github_community_service.dart';
import '../../state/providers.dart';
import '../../sync/github_sync_service.dart';

class CommunityPanel extends ConsumerStatefulWidget {
  const CommunityPanel({super.key});

  @override
  ConsumerState<CommunityPanel> createState() => _CommunityPanelState();
}

class _CommunityPanelState extends ConsumerState<CommunityPanel> {
  static const _tokenExpiredMessage = '토큰이 만료되었습니다. 다시 로그인하세요.';
  static const _rateLimitedMessage = '토큰 사용량이 초과되었습니다.';

  /// 설정 화면과 같은 기준으로, 만료까지 이 시간이 남지 않으면 미리 갱신한다.
  static const _refreshLeadTime = Duration(minutes: 5);

  final _tokenController = TextEditingController();
  String? _loadedToken;
  bool _loading = false;
  bool _submitting = false;
  bool _authorizing = false;
  bool _rateLimited = false;

  /// token이 만료됐거나 401을 받아 GitHub App으로 다시 로그인해야 하는 상태.
  bool _authRequired = false;
  String? _error;
  String? _discussionError;
  GitHubCommunityRateLimit? _rateLimit;
  List<GitHubCommunityIssue> _issues = const [];
  List<GitHubCommunityDiscussion> _discussions = const [];
  List<GitHubDiscussionCategory> _categories = const [];
  String? _repositoryId;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  /// setState 안에서만 부른다. 목록과 작성용 메타데이터를 비운다.
  void _clearContent() {
    _issues = const [];
    _discussions = const [];
    _categories = const [];
    _repositoryId = null;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 만료가 임박한 GitHub App token을 refresh token으로 갱신한다.
  /// 갱신할 수 없고 이미 만료됐으면 null을 돌려주어 재로그인 화면을 띄운다.
  Future<String?> _refreshTokenIfNeeded(String token) async {
    final settings = ref.read(appSettingsProvider).cloudSync.github;
    if (settings.token.trim() != token) return token;
    final expiresAt = settings.tokenExpiresAt?.toUtc();
    if (expiresAt == null) return token;

    final now = DateTime.now().toUtc();
    if (expiresAt.isAfter(now.add(_refreshLeadTime))) return token;
    final stillValid = expiresAt.isAfter(now);

    final refreshExpiresAt = settings.refreshTokenExpiresAt?.toUtc();
    final canRefresh =
        settings.refreshToken.trim().isNotEmpty &&
        (refreshExpiresAt == null || refreshExpiresAt.isAfter(now));
    if (!canRefresh) return stillValid ? token : null;

    try {
      final authorization = await ref
          .read(gitHubSyncServiceProvider)
          .refreshUserAccessToken(settings: settings);
      if (!mounted) return null;
      ref
          .read(appSettingsProvider.notifier)
          .setGitHubSyncAuthorization(authorization);
      return authorization.accessToken;
    } on GitHubSyncException {
      // 갱신 실패는 아직 유효한 token이라면 그대로 쓰고, 만료됐으면 재로그인.
      return stillValid ? token : null;
    }
  }

  Future<void> _load(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return;
    setState(() {
      _loadedToken = normalizedToken;
      _loading = true;
      _rateLimited = false;
      _authRequired = false;
      _error = null;
      _discussionError = null;
    });
    try {
      final activeToken = await _refreshTokenIfNeeded(normalizedToken);
      if (!mounted) return;
      if (activeToken == null) {
        setState(() {
          _authRequired = true;
          _error = _tokenExpiredMessage;
          _clearContent();
        });
        return;
      }
      // 갱신된 token은 설정에도 저장되므로 build가 다시 load하지 않게 맞춘다.
      _loadedToken = activeToken;

      final service = ref.read(gitHubCommunityServiceProvider);
      final rateLimit = await service.fetchRateLimit(activeToken);
      if (!mounted) return;
      if (rateLimit.exhausted) {
        setState(() {
          _rateLimit = rateLimit;
          _rateLimited = true;
          _clearContent();
        });
        return;
      }

      final issues = await service.listIssues(activeToken);
      GitHubCommunityDiscussionsResult? discussions;
      String? discussionError;
      try {
        discussions = await service.listDiscussions(activeToken);
      } on GitHubCommunityException catch (error) {
        if (error.rateLimited || error.unauthorized) rethrow;
        discussionError = error.message;
      }
      if (!mounted) return;

      setState(() {
        _rateLimit = discussions?.rateLimit ?? rateLimit;
        _issues = issues;
        _discussions = discussions?.discussions ?? const [];
        _categories = discussions?.categories ?? const [];
        _repositoryId = discussions?.repositoryId;
        _discussionError = discussionError;
      });
    } on GitHubCommunityException catch (error) {
      if (!mounted) return;
      setState(() {
        _rateLimited = error.rateLimited;
        _authRequired = error.unauthorized;
        _error = error.rateLimited ? _rateLimitedMessage : error.message;
        _clearContent();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'GitHub API 요청 중 오류가 발생했습니다: $error';
        _clearContent();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 직접 붙여넣은 PAT에는 만료/refresh 정보가 없다. 이전 GitHub App 로그인의
  /// 만료 시각이 남아 새 token을 만료로 오판하지 않도록 한 번의 업데이트로
  /// token과 만료 정보를 함께 갈아 끼운다.
  void _storePersonalToken(String token) {
    ref
        .read(appSettingsProvider.notifier)
        .setGitHubSyncAuthorization(
          GitHubAppAuthorization(accessToken: token, tokenType: 'bearer'),
        );
  }

  void _saveToken() {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'GitHub access token을 입력하세요.');
      return;
    }
    _storePersonalToken(token);
    unawaited(_load(token));
  }

  Future<void> _changeToken(String currentToken) async {
    final controller = TextEditingController(text: currentToken);
    try {
      final token = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('GitHub token'),
          content: TextField(
            controller: controller,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Access token',
              prefixIcon: Icon(Icons.key),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('저장'),
            ),
          ],
        ),
      );
      if (token == null || !mounted) return;
      if (token.isEmpty) {
        ref.read(appSettingsProvider.notifier).setGitHubSyncToken('');
      } else if (token != currentToken) {
        _storePersonalToken(token);
      }
      setState(() {
        _loadedToken = null;
        _authRequired = false;
        _error = null;
      });
      if (token.isNotEmpty) unawaited(_load(token));
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('토큰을 변경하지 못했습니다: $error');
    } finally {
      controller.dispose();
    }
  }

  /// 설정 화면과 같은 GitHub App device flow로 로그인한다. 인증 코드와 URL을
  /// 다이얼로그로 보여주고, 승인이 끝나면 설정 화면과 같은 방식으로 저장한다.
  Future<void> _loginWithGitHubApp() async {
    if (_authorizing) return;
    setState(() {
      _authorizing = true;
      _error = null;
    });
    var dialogOpen = false;
    void closeDialog() {
      if (!dialogOpen || !mounted) return;
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop(true);
    }

    Future<GitHubAppAuthorization>? authorizationFuture;
    try {
      final service = ref.read(gitHubSyncServiceProvider);
      final settings = ref.read(appSettingsProvider).cloudSync.github;
      final code = await service.requestDeviceCode(settings: settings);
      if (!mounted) return;
      unawaited(
        Clipboard.setData(
          ClipboardData(text: code.userCode),
        ).catchError((_) {}),
      );

      authorizationFuture = service.waitForDeviceAuthorization(
        settings: settings,
        deviceCode: code,
      );
      dialogOpen = true;
      final dialogFuture = showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeviceCodeDialog(
          code: code,
          onOpenBrowser: () => _open(code.verificationUri),
        ),
      ).whenComplete(() => dialogOpen = false);

      final result = await Future.any<Object?>([
        authorizationFuture,
        dialogFuture,
      ]);
      if (result is! GitHubAppAuthorization) {
        // 사용자가 취소했다. 진행 중인 polling 결과는 무시한다.
        authorizationFuture.ignore();
        return;
      }
      if (!mounted) return;
      ref.read(appSettingsProvider.notifier).setGitHubSyncAuthorization(result);
      closeDialog();
      setState(() {
        _authRequired = false;
        _error = null;
      });
      unawaited(_load(result.accessToken));
    } on GitHubSyncException catch (error) {
      closeDialog();
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      authorizationFuture?.ignore();
      closeDialog();
      if (!mounted) return;
      setState(() => _error = 'GitHub App 로그인 중 오류가 발생했습니다: $error');
    } finally {
      if (mounted) setState(() => _authorizing = false);
    }
  }

  Future<void> _createIssue(String token) async {
    final draft = await showDialog<_CommunityDraft>(
      context: context,
      builder: (_) => const _ComposeCommunityDialog(title: '새 Issue'),
    );
    if (draft == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(gitHubCommunityServiceProvider)
          .createIssue(token: token, title: draft.title, body: draft.body);
      if (!mounted) return;
      _showSnackBar('Issue를 작성했습니다.');
      unawaited(_load(token));
    } on GitHubCommunityException catch (error) {
      if (!mounted) return;
      setState(() {
        _rateLimited = error.rateLimited;
        _authRequired = error.unauthorized;
        _error = error.rateLimited ? _rateLimitedMessage : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Issue 작성 중 오류가 발생했습니다: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _createDiscussion(String token) async {
    final repositoryId = _repositoryId;
    if (repositoryId == null || repositoryId.isEmpty || _categories.isEmpty) {
      setState(() => _discussionError = 'Discussion category를 찾지 못했습니다.');
      return;
    }
    final draft = await showDialog<_DiscussionDraft>(
      context: context,
      builder: (_) => _ComposeDiscussionDialog(categories: _categories),
    );
    if (draft == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(gitHubCommunityServiceProvider)
          .createDiscussion(
            token: token,
            repositoryId: repositoryId,
            categoryId: draft.category.id,
            title: draft.title,
            body: draft.body,
          );
      if (!mounted) return;
      _showSnackBar('Discussion을 작성했습니다.');
      unawaited(_load(token));
    } on GitHubCommunityException catch (error) {
      if (!mounted) return;
      setState(() {
        _rateLimited = error.rateLimited;
        _authRequired = error.unauthorized;
        _error = error.rateLimited ? _rateLimitedMessage : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Discussion 작성 중 오류가 발생했습니다: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _open(Uri url) async {
    var launched = false;
    try {
      launched = await ref.read(externalUrlLauncherProvider)(url);
    } catch (_) {
      launched = false;
    }
    if (launched || !mounted) return;
    _showSnackBar('링크를 열 수 없습니다.');
  }

  String? _discussionUnavailableReason({required bool canCreate}) {
    if (canCreate) return null;
    if (_loading) return 'Discussions를 불러오는 중입니다.';
    return _discussionError ?? 'Discussion category를 찾지 못했습니다.';
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(appSettingsProvider).cloudSync.github.token.trim();
    if (token.isNotEmpty && _loadedToken != token && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load(token));
      });
    }
    final canCreateDiscussion =
        (_repositoryId ?? '').isNotEmpty && _categories.isNotEmpty;

    return Material(
      color: VibeColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CommunityHeader(
            rateLimit: _rateLimit,
            loading: _loading,
            hasToken: token.isNotEmpty,
            onRefresh: token.isEmpty ? null : () => _load(token),
            onChangeToken: token.isEmpty ? null : () => _changeToken(token),
          ),
          const Divider(height: 1, color: VibeColors.borderSoft),
          Expanded(
            child: token.isEmpty
                ? _TokenRequiredView(
                    controller: _tokenController,
                    error: _error,
                    authorizing: _authorizing,
                    onSave: _saveToken,
                    onLogin: _loginWithGitHubApp,
                  )
                : _authRequired
                ? _BlockedView(
                    title: 'GitHub 로그인이 필요합니다.',
                    message: _error ?? _tokenExpiredMessage,
                    icon: Icons.lock_clock_outlined,
                    retryLabel: '다시 시도',
                    onRetry: () => _load(token),
                    authorizing: _authorizing,
                    onLogin: _loginWithGitHubApp,
                  )
                : _rateLimited
                ? _BlockedView(
                    title: _rateLimitedMessage,
                    message: 'GitHub API rate limit이 reset된 뒤 다시 시도하세요.',
                    icon: Icons.speed_outlined,
                    resetAt: _rateLimit?.resetAt,
                    retryLabel: '다시 확인',
                    onRetry: () => _load(token),
                  )
                : _CommunityContent(
                    loading: _loading,
                    submitting: _submitting,
                    error: _error,
                    discussionError: _discussionError,
                    issues: _issues,
                    discussions: _discussions,
                    canCreateDiscussion: canCreateDiscussion,
                    discussionUnavailableReason: _discussionUnavailableReason(
                      canCreate: canCreateDiscussion,
                    ),
                    onRetry: () => _load(token),
                    onRefresh: () => _load(token),
                    onCreateIssue: () => _createIssue(token),
                    onCreateDiscussion: () => _createDiscussion(token),
                    onOpenIssue: (issue) => _open(issue.url),
                    onOpenDiscussion: (discussion) => _open(discussion.url),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({
    required this.rateLimit,
    required this.loading,
    required this.hasToken,
    required this.onRefresh,
    required this.onChangeToken,
  });

  final GitHubCommunityRateLimit? rateLimit;
  final bool loading;
  final bool hasToken;
  final VoidCallback? onRefresh;
  final VoidCallback? onChangeToken;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Row(
        children: [
          const Icon(
            Icons.groups_2_outlined,
            color: VibeColors.accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Community',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Issues & Discussions',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          _RateLimitMeter(rateLimit: rateLimit),
          IconButton(
            tooltip: '새로고침',
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
          ),
          IconButton(
            tooltip: hasToken ? 'GitHub token 변경' : 'GitHub token 없음',
            onPressed: onChangeToken,
            icon: const Icon(Icons.key_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _RateLimitMeter extends StatelessWidget {
  const _RateLimitMeter({required this.rateLimit});

  final GitHubCommunityRateLimit? rateLimit;

  @override
  Widget build(BuildContext context) {
    final rate = rateLimit;
    final label = rate == null ? '--/--' : '${rate.used}/${rate.limit}';
    final value = rate == null || rate.limit <= 0
        ? 0.0
        : (rate.used / rate.limit).clamp(0.0, 1.0);
    return SizedBox(
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: VibeColors.onSurfaceMuted,
              fontFamily: kMonoFontFamily,
              fontFamilyFallback: kMonoFontFallback,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              color: VibeColors.accent,
              backgroundColor: VibeColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenRequiredView extends StatelessWidget {
  const _TokenRequiredView({
    required this.controller,
    required this.error,
    required this.authorizing,
    required this.onSave,
    required this.onLogin,
  });

  final TextEditingController controller;
  final String? error;
  final bool authorizing;
  final VoidCallback onSave;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.lock_outline,
                color: VibeColors.onSurfaceDim,
                size: 42,
              ),
              const SizedBox(height: 16),
              const Text(
                'GitHub 로그인이 필요합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: VibeColors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '토큰이 없으면 커뮤니티 활동을 사용할 수 없습니다. GitHub App으로 로그인하거나 Issues와 Discussions 조회/작성 권한이 있는 token을 입력하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
              ),
              const SizedBox(height: 18),
              _GitHubAppLoginButton(authorizing: authorizing, onLogin: onLogin),
              const SizedBox(height: 18),
              const _OrDivider(),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'GitHub access token',
                  prefixIcon: Icon(Icons.key),
                ),
                onSubmitted: (_) => onSave(),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(
                    color: VibeColors.statusError,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('토큰 저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GitHubAppLoginButton extends StatelessWidget {
  const _GitHubAppLoginButton({
    required this.authorizing,
    required this.onLogin,
  });

  final bool authorizing;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: authorizing ? null : onLogin,
      icon: authorizing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login),
      label: Text(authorizing ? '인증을 기다리는 중...' : 'GitHub App으로 로그인'),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: VibeColors.borderSoft)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '또는 token 직접 입력',
            style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 11),
          ),
        ),
        Expanded(child: Divider(color: VibeColors.borderSoft)),
      ],
    );
  }
}

class _BlockedView extends StatelessWidget {
  const _BlockedView({
    required this.title,
    required this.message,
    required this.icon,
    required this.retryLabel,
    required this.onRetry,
    this.resetAt,
    this.authorizing = false,
    this.onLogin,
  });

  final String title;
  final String message;
  final IconData icon;
  final String retryLabel;
  final VoidCallback onRetry;

  /// rate limit이 풀리는 시각. 있으면 현지 시각으로 보여준다.
  final DateTime? resetAt;
  final bool authorizing;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    final reset = resetAt;
    final login = onLogin;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: VibeColors.statusError),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
              ),
            ),
            if (reset != null) ...[
              const SizedBox(height: 8),
              Text(
                'reset ${formatLocalHourMinute(reset)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VibeColors.onSurface,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (login != null) ...[
              _GitHubAppLoginButton(authorizing: authorizing, onLogin: login),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityContent extends StatelessWidget {
  const _CommunityContent({
    required this.loading,
    required this.submitting,
    required this.error,
    required this.discussionError,
    required this.issues,
    required this.discussions,
    required this.canCreateDiscussion,
    required this.discussionUnavailableReason,
    required this.onRetry,
    required this.onRefresh,
    required this.onCreateIssue,
    required this.onCreateDiscussion,
    required this.onOpenIssue,
    required this.onOpenDiscussion,
  });

  final bool loading;
  final bool submitting;
  final String? error;
  final String? discussionError;
  final List<GitHubCommunityIssue> issues;
  final List<GitHubCommunityDiscussion> discussions;
  final bool canCreateDiscussion;

  /// Discussion 작성 버튼이 비활성인 이유. 버튼 tooltip으로 보여준다.
  final String? discussionUnavailableReason;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreateIssue;
  final VoidCallback onCreateDiscussion;
  final ValueChanged<GitHubCommunityIssue> onOpenIssue;
  final ValueChanged<GitHubCommunityDiscussion> onOpenDiscussion;

  @override
  Widget build(BuildContext context) {
    final discussionButton = OutlinedButton.icon(
      onPressed: submitting || !canCreateDiscussion ? null : onCreateDiscussion,
      icon: const Icon(Icons.forum_outlined),
      label: const Text('Discussion 작성'),
    );
    final reason = discussionUnavailableReason;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) _InlineError(message: error!, onRetry: onRetry),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: submitting ? null : onCreateIssue,
                  icon: const Icon(Icons.add),
                  label: const Text('Issue 작성'),
                ),
                if (reason != null && !canCreateDiscussion)
                  Tooltip(message: reason, child: discussionButton)
                else
                  discussionButton,
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Issues'),
              Tab(text: 'Discussions'),
            ],
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _IssueList(
                        issues: issues,
                        onRefresh: onRefresh,
                        onOpen: onOpenIssue,
                      ),
                      _DiscussionList(
                        discussions: discussions,
                        error: discussionError,
                        onRefresh: onRefresh,
                        onOpen: onOpenDiscussion,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: VibeColors.statusError.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: VibeColors.statusError.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: VibeColors.statusError,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: VibeColors.onSurface, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

/// 당겨서 새로고침이 되는 목록. 비어 있을 때도 당길 수 있도록 빈 화면을
/// 항상 스크롤 가능한 영역으로 감싼다.
class _RefreshableList extends StatelessWidget {
  const _RefreshableList({
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
    required this.empty,
  });

  final Future<void> Function() onRefresh;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: itemCount == 0
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: empty,
                ),
              ),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: itemBuilder,
            ),
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({
    required this.issues,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<GitHubCommunityIssue> issues;
  final Future<void> Function() onRefresh;
  final ValueChanged<GitHubCommunityIssue> onOpen;

  @override
  Widget build(BuildContext context) {
    return _RefreshableList(
      onRefresh: onRefresh,
      itemCount: issues.length,
      empty: const _EmptyList(
        icon: Icons.task_alt_outlined,
        message: '열린 Issue가 없습니다.',
      ),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return _CommunityTile(
          icon: Icons.error_outline,
          title: issue.title,
          meta:
              '#${issue.number} · ${issue.author} · comments ${issue.commentCount}',
          onOpen: () => onOpen(issue),
        );
      },
    );
  }
}

class _DiscussionList extends StatelessWidget {
  const _DiscussionList({
    required this.discussions,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<GitHubCommunityDiscussion> discussions;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<GitHubCommunityDiscussion> onOpen;

  @override
  Widget build(BuildContext context) {
    return _RefreshableList(
      onRefresh: onRefresh,
      itemCount: error != null ? 0 : discussions.length,
      empty: error != null
          ? _EmptyList(
              icon: Icons.forum_outlined,
              message: 'Discussions를 사용할 수 없습니다.',
              detail: error,
            )
          : const _EmptyList(
              icon: Icons.forum_outlined,
              message: 'Discussion 글이 없습니다.',
            ),
      itemBuilder: (context, index) {
        final discussion = discussions[index];
        return _CommunityTile(
          icon: Icons.forum_outlined,
          title: discussion.title,
          meta:
              '#${discussion.number} · ${discussion.category} · ${discussion.author} · comments ${discussion.commentCount}',
          onOpen: () => onOpen(discussion),
        );
      },
    );
  }
}

class _CommunityTile extends StatelessWidget {
  const _CommunityTile({
    required this.icon,
    required this.title,
    required this.meta,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VibeColors.borderSoft),
          ),
          child: Row(
            children: [
              Icon(icon, color: VibeColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontFamily: kMonoFontFamily,
                        fontFamilyFallback: kMonoFontFallback,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.open_in_new,
                color: VibeColors.onSurfaceDim,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.icon, required this.message, this.detail});

  final IconData icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: VibeColors.onSurfaceDim, size: 38),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommunityDraft {
  const _CommunityDraft({required this.title, required this.body});

  final String title;
  final String body;
}

class _DiscussionDraft extends _CommunityDraft {
  const _DiscussionDraft({
    required super.title,
    required super.body,
    required this.category,
  });

  final GitHubDiscussionCategory category;
}

class _ComposeCommunityDialog extends StatefulWidget {
  const _ComposeCommunityDialog({required this.title});

  final String title;

  @override
  State<_ComposeCommunityDialog> createState() =>
      _ComposeCommunityDialogState();
}

class _ComposeCommunityDialogState extends State<_ComposeCommunityDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(
      context,
    ).pop(_CommunityDraft(title: title, body: _bodyController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '제목'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: '본문',
                alignLabelWithHint: true,
              ),
              minLines: 8,
              maxLines: 12,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('작성')),
      ],
    );
  }
}

class _ComposeDiscussionDialog extends StatefulWidget {
  const _ComposeDiscussionDialog({required this.categories});

  final List<GitHubDiscussionCategory> categories;

  @override
  State<_ComposeDiscussionDialog> createState() =>
      _ComposeDiscussionDialogState();
}

class _ComposeDiscussionDialogState extends State<_ComposeDiscussionDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  late GitHubDiscussionCategory _category = widget.categories.first;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      _DiscussionDraft(
        title: title,
        body: _bodyController.text.trim(),
        category: _category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('새 Discussion'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<GitHubDiscussionCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final category in widget.categories)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '제목'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: '본문',
                alignLabelWithHint: true,
              ),
              minLines: 8,
              maxLines: 12,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('작성')),
      ],
    );
  }
}

/// GitHub App device flow의 인증 코드와 URL을 보여주고 승인을 기다린다.
/// 승인이 끝나면 호출자가 닫고, 사용자는 취소로 닫을 수 있다.
class _DeviceCodeDialog extends StatelessWidget {
  const _DeviceCodeDialog({required this.code, required this.onOpenBrowser});

  final GitHubDeviceCode code;
  final VoidCallback onOpenBrowser;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('GitHub App 로그인'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '브라우저에서 아래 URL을 열고 인증 코드를 입력하세요.',
              style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SelectableText(
              code.verificationUri.toString(),
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: VibeColors.accentSoft,
                border: Border.all(color: VibeColors.accent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      code.userCode,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontFamily: kMonoFontFamily,
                        fontFamilyFallback: kMonoFontFallback,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => unawaited(
                      Clipboard.setData(
                        ClipboardData(text: code.userCode),
                      ).catchError((_) {}),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('복사'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '브라우저에서 승인하면 자동으로 닫힙니다.',
                    style: TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: onOpenBrowser,
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('브라우저 열기'),
        ),
      ],
    );
  }
}

/// 현지 시각 HH:mm. rate limit reset 표시에 쓴다.
String formatLocalHourMinute(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
