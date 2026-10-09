part of 'settings_sheet.dart';

/// GitHub 동기화 설정. 처음 쓰는 사람이 위에서부터 차례로 끝낼 수 있게
/// 단계로 나누고, 맨 위에 현재 동기화 상태를 보여 준다.
class _GitHubSyncSettingsTab extends ConsumerStatefulWidget {
  const _GitHubSyncSettingsTab({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_GitHubSyncSettingsTab> createState() =>
      _GitHubSyncSettingsTabState();
}

class _GitHubSyncSettingsTabState
    extends ConsumerState<_GitHubSyncSettingsTab> {
  late final TextEditingController _serverUrlController;
  late final TextEditingController _appClientIdController;
  late final TextEditingController _tokenController;
  late final TextEditingController _ownerController;
  late final TextEditingController _repoController;
  late final TextEditingController _branchController;
  late final TextEditingController _pathController;
  late final TextEditingController _encryptionKeyController;
  bool _checkingConnection = false;
  bool _authorizing = false;
  bool _connectionOk = false;
  GitHubDeviceCode? _deviceCode;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    final sync = widget.settings.cloudSync;
    final github = sync.github;
    _serverUrlController = TextEditingController(text: github.serverUrl);
    _appClientIdController = TextEditingController(text: github.appClientId);
    _tokenController = TextEditingController(text: github.token);
    _ownerController = TextEditingController(text: github.owner);
    _repoController = TextEditingController(text: github.repo);
    _branchController = TextEditingController(text: github.branch);
    _pathController = TextEditingController(text: github.path);
    _encryptionKeyController = TextEditingController(text: sync.encryptionKey);
  }

  @override
  void didUpdateWidget(covariant _GitHubSyncSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sync = widget.settings.cloudSync;
    final oldSync = oldWidget.settings.cloudSync;
    final github = sync.github;
    final oldGithub = oldSync.github;
    void follow(TextEditingController controller, String before, String now) {
      if (before != now) _setControllerText(controller, now);
    }

    follow(_serverUrlController, oldGithub.serverUrl, github.serverUrl);
    follow(_appClientIdController, oldGithub.appClientId, github.appClientId);
    follow(_tokenController, oldGithub.token, github.token);
    follow(_ownerController, oldGithub.owner, github.owner);
    follow(_repoController, oldGithub.repo, github.repo);
    follow(_branchController, oldGithub.branch, github.branch);
    follow(_pathController, oldGithub.path, github.path);
    follow(_encryptionKeyController, oldSync.encryptionKey, sync.encryptionKey);
    if (oldGithub.targetKey != github.targetKey ||
        oldGithub.token != github.token) {
      _connectionOk = false;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _appClientIdController.dispose();
    _tokenController.dispose();
    _ownerController.dispose();
    _repoController.dispose();
    _branchController.dispose();
    _pathController.dispose();
    _encryptionKeyController.dispose();
    super.dispose();
  }

  void _setControllerText(TextEditingController controller, String text) {
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  GitHubSyncSettings _effectiveGitHubSettings() =>
      widget.settings.cloudSync.github.copyWith(
        serverUrl: widget.settings.cloudSync.github.isGitHubDotCom
            ? GitHubSyncSettings.githubComServerUrl
            : _serverUrlController.text.trim(),
        appClientId: widget.settings.cloudSync.github.isGitHubDotCom
            ? ''
            : _appClientIdController.text.trim(),
        token: _tokenController.text,
        owner: _ownerController.text.trim(),
        repo: _repoController.text.trim(),
        branch: _branchController.text.trim(),
        path: _pathController.text.trim(),
      );

  GitHubTokenRefresher get _refresher => GitHubTokenRefresher(
    service: ref.read(gitHubSyncServiceProvider),
    save: ref.read(appSettingsProvider.notifier).setGitHubSyncAuthorization,
  );

  void _showStatus(String message, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusOk = ok;
    });
  }

  Future<void> _checkConnection() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _checkingConnection = true;
      _deviceCode = null;
      _status = null;
    });
    try {
      final settings = await _refresher.fresh(_effectiveGitHubSettings());
      await ref.read(gitHubSyncServiceProvider).validateToken(settings);
      if (!mounted) return;
      setState(() => _connectionOk = true);
      _showStatus('저장소에 연결했습니다. 읽기·쓰기 권한이 있습니다.', ok: true);
    } catch (e) {
      if (mounted) setState(() => _connectionOk = false);
      _showStatus(e.toString(), ok: false);
    } finally {
      if (mounted) setState(() => _checkingConnection = false);
    }
  }

  Future<void> _authorizeGitHubApp() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _authorizing = true;
      _deviceCode = null;
      _status = null;
    });
    try {
      final service = ref.read(gitHubSyncServiceProvider);
      final settings = _effectiveGitHubSettings();
      final code = await service.requestDeviceCode(settings: settings);
      unawaited(
        Clipboard.setData(
          ClipboardData(text: code.userCode),
        ).catchError((_) {}),
      );
      final launched = await ref
          .read(externalUrlLauncherProvider)
          .call(code.verificationUri);
      if (!mounted) return;
      setState(() => _deviceCode = code);
      _showStatus(
        launched
            ? '브라우저에서 아래 인증 코드를 입력하세요. 코드는 클립보드에 복사했습니다.'
            : '브라우저를 열지 못했습니다. 아래 주소에서 인증 코드를 입력하세요.',
        ok: launched,
      );

      final authorization = await service.waitForDeviceAuthorization(
        settings: settings,
        deviceCode: code,
      );
      ref
          .read(appSettingsProvider.notifier)
          .setGitHubSyncAuthorization(authorization);
      if (!mounted) return;
      setState(() => _deviceCode = null);
      _showStatus('GitHub에 로그인했습니다. 다음 단계에서 앱을 저장소에 설치하세요.', ok: true);
    } catch (e) {
      _showStatus(e.toString(), ok: false);
    } finally {
      if (mounted) setState(() => _authorizing = false);
    }
  }

  Future<void> _openInstallPage() async {
    final launched = await ref
        .read(externalUrlLauncherProvider)
        .call(Uri.parse(GitHubSyncSettings.githubComAppInstallUrl));
    if (!launched) {
      _showStatus(
        '브라우저를 열지 못했습니다: ${GitHubSyncSettings.githubComAppInstallUrl}',
        ok: false,
      );
    }
  }

  Future<void> _syncNow({bool confirmed = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await ref
        .read(syncCoordinatorProvider.notifier)
        .syncNow(confirmed: confirmed);
  }

  Future<void> _confirmFirstMerge(
    SyncNeedsConfirmationException pending,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('데이터 합치기'),
        content: Text(
          '원격 저장소의 ${pending.remoteCount}개 항목과 이 기기의 '
          '${pending.localCount}개 항목을 합칩니다.\n\n'
          '양쪽 항목은 지워지지 않습니다. 같은 항목은 더 최근에 고친 쪽이 남습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('합치기'),
          ),
        ],
      ),
    );
    if (ok == true) await _syncNow(confirmed: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(appSettingsProvider.notifier);
    final status = ref.watch(syncCoordinatorProvider);
    final sync = widget.settings.cloudSync;
    final github = sync.github;
    final githubDotCom = github.isGitHubDotCom;
    final effective = _effectiveGitHubSettings();
    final signedIn = effective.isSignedIn;
    final connected = _connectionOk || (!sync.isFirstSync && signedIn);
    final keyReady =
        _encryptionKeyController.text.trim().length >=
        CloudSyncSettings.minEncryptionKeyLength;
    final canAuthorize = effective.effectiveAppClientId.isNotEmpty;

    return _SettingsTabScroll(
      children: [
        _SyncStatusCard(
          sync: sync,
          status: status,
          onSyncNow: sync.canSync && !status.running ? _syncNow : null,
          onConfirm: status.confirmation == null
              ? null
              : () => _confirmFirstMerge(status.confirmation!),
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          title: 'GitHub 동기화',
          description:
              '여러 기기가 GitHub 저장소의 암호화된 파일 하나로 호스트·스니펫·메모·'
              '키체인과 터미널 표시·알림·AI 설정을 주고받습니다. 로컬 셸, 패널 배치, '
              '단축키, 폰트는 기기마다 따로 둡니다.',
          children: [
            _SyncStep(
              number: 1,
              title: 'GitHub 로그인',
              done: signedIn,
              children: [
                DropdownButtonFormField<GitHubSyncHostType>(
                  initialValue: github.hostType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'GitHub 종류',
                    prefixIcon: Icon(Icons.public_outlined),
                  ),
                  items: [
                    for (final hostType in GitHubSyncHostType.values)
                      DropdownMenuItem(
                        value: hostType,
                        child: Text(hostType.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.setGitHubSyncHostType(value);
                  },
                ),
                if (!githubDotCom) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('github-sync-server-url-field'),
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      labelText: 'GitHub Enterprise URL',
                      hintText: 'https://github.example.com',
                      prefixIcon: Icon(Icons.public_outlined),
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: controller.setGitHubSyncServerUrl,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('github-app-client-id-field'),
                    controller: _appClientIdController,
                    decoration: const InputDecoration(
                      labelText: 'GitHub App Client ID',
                      hintText: 'Iv1.xxxxxxxxxxxxxxxx',
                      prefixIcon: Icon(Icons.app_registration_outlined),
                    ),
                    onChanged: controller.setGitHubSyncAppClientId,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: canAuthorize && !_authorizing
                      ? _authorizeGitHubApp
                      : null,
                  icon: _authorizing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_outlined),
                  label: Text(signedIn ? 'GitHub 다시 로그인' : 'GitHub App으로 로그인'),
                ),
                if (_deviceCode != null) ...[
                  const SizedBox(height: 12),
                  _GitHubDeviceCodeCard(code: _deviceCode!),
                ],
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Access token 직접 입력(고급)',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      TextFormField(
                        key: const ValueKey('github-sync-token-field'),
                        controller: _tokenController,
                        decoration: const InputDecoration(
                          labelText: 'Access token',
                          hintText: '로그인하면 자동으로 채워집니다',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        onChanged: controller.setGitHubSyncToken,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _SyncStep(
              number: 2,
              title: '앱을 저장소에 설치',
              done: connected,
              children: [
                if (githubDotCom) ...[
                  const _SyncHelpText(
                    'GitHub에서 private 저장소를 하나 새로 만들고, vibe-terminal 앱을 그 '
                    '저장소에만 설치하세요. 앱은 설치한 저장소에만 접근할 수 있으며, '
                    '설치하지 않으면 로그인해도 동기화할 수 없습니다.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openInstallPage,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('앱 설치 페이지 열기'),
                  ),
                ] else
                  const _SyncHelpText(
                    'GitHub Enterprise에서는 직접 만든 GitHub App을 동기화할 저장소에 '
                    '설치하세요. 저장소 권한은 Contents 읽기·쓰기가 필요합니다.',
                  ),
              ],
            ),
            _SyncStep(
              number: 3,
              title: '동기화할 저장소',
              done: connected,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('github-sync-owner-field'),
                        controller: _ownerController,
                        decoration: const InputDecoration(
                          labelText: 'Owner',
                          hintText: '사용자 또는 조직',
                          prefixIcon: Icon(Icons.account_tree_outlined),
                        ),
                        onChanged: controller.setGitHubSyncOwner,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('github-sync-repo-field'),
                        controller: _repoController,
                        decoration: const InputDecoration(
                          labelText: 'Repository',
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                        onChanged: controller.setGitHubSyncRepo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: TextFormField(
                        key: const ValueKey('github-sync-branch-field'),
                        controller: _branchController,
                        decoration: const InputDecoration(
                          labelText: 'Branch',
                          prefixIcon: Icon(Icons.call_split_outlined),
                        ),
                        onChanged: controller.setGitHubSyncBranch,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('github-sync-path-field'),
                        controller: _pathController,
                        decoration: const InputDecoration(
                          labelText: '동기화 파일 경로',
                          prefixIcon: Icon(Icons.insert_drive_file_outlined),
                        ),
                        onChanged: controller.setGitHubSyncPath,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: !_checkingConnection && effective.isConfigured
                      ? _checkConnection
                      : null,
                  icon: _checkingConnection
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: const Text('연결 확인'),
                ),
              ],
            ),
            _SyncStep(
              number: 4,
              title: '암호화 키',
              done: keyReady,
              children: [
                const _SyncHelpText(
                  '저장소에는 이 키로 암호화한 파일만 올라갑니다. 모든 기기에서 같은 키를 '
                  '입력하세요. 키는 이 기기의 보안 저장소에만 있고 GitHub로 보내지 '
                  '않으므로, 잃어버리면 원격 데이터를 복구할 수 없습니다.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('cloud-sync-encryption-key-field'),
                  controller: _encryptionKeyController,
                  decoration: const InputDecoration(
                    labelText: '암호화 키',
                    hintText: '${CloudSyncSettings.minEncryptionKeyLength}자 이상',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (value) {
                    controller.setCloudSyncEncryptionKey(value);
                    setState(() {});
                  },
                ),
              ],
            ),
            _SyncStep(
              number: 5,
              title: '자동 동기화',
              done: sync.enabled,
              last: true,
              children: [
                _SwitchSetting(
                  title: '자동 동기화',
                  subtitle:
                      '앱을 열 때, 데이터를 바꾸고 10초 뒤, 열려 있는 동안 5분마다, '
                      '앱을 내릴 때 동기화합니다.',
                  value: sync.enabled,
                  onChanged: controller.setCloudSyncEnabled,
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 10),
              _AsyncStatusText(message: _status!, success: _statusOk),
            ],
          ],
        ),
      ],
    );
  }
}

/// 마지막 동기화 결과와 다음 예정, 오류를 한눈에 보여 준다.
class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.sync,
    required this.status,
    required this.onSyncNow,
    required this.onConfirm,
  });

  final CloudSyncSettings sync;
  final SyncStatus status;
  final VoidCallback? onSyncNow;
  final VoidCallback? onConfirm;

  String get _headline => switch (status.phase) {
    SyncPhase.running => '동기화 중…',
    SyncPhase.needsConfirmation => '처음 동기화: 확인이 필요합니다',
    SyncPhase.blocked => '동기화가 멈췄습니다',
    SyncPhase.retrying => '동기화 실패: 잠시 뒤 다시 시도합니다',
    SyncPhase.idle when !sync.canSync => '아직 설정되지 않았습니다',
    SyncPhase.idle when sync.enabled => '자동 동기화 켜짐',
    SyncPhase.idle => '자동 동기화 꺼짐',
  };

  IconData get _icon => switch (status.phase) {
    SyncPhase.running => Icons.sync,
    SyncPhase.needsConfirmation => Icons.merge_type,
    SyncPhase.blocked => Icons.sync_problem,
    SyncPhase.retrying => Icons.sync_problem,
    SyncPhase.idle when sync.canSync => Icons.cloud_done_outlined,
    SyncPhase.idle => Icons.cloud_off_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final error = status.phase == SyncPhase.needsConfirmation
        ? status.confirmation?.toString()
        : status.error;
    final warn =
        status.phase == SyncPhase.blocked ||
        status.phase == SyncPhase.retrying ||
        status.phase == SyncPhase.needsConfirmation;
    final details = <String>[
      '마지막 동기화: ${_formatSyncTime(sync.lastSyncedAt)}',
      if (status.lastPulled != null && status.lastPushed != null)
        '가져옴 ${status.lastPulled}개 · 보냄 ${status.lastPushed}개',
      if (status.nextRunAt != null)
        '다음 예정: ${_formatSyncTime(status.nextRunAt)}',
    ];
    return Container(
      key: const ValueKey('github-sync-status-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warn ? null : VibeColors.accentSoft,
        border: Border.all(
          color: warn ? Theme.of(context).colorScheme.error : VibeColors.accent,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _icon,
                color: warn
                    ? Theme.of(context).colorScheme.error
                    : VibeColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _headline,
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in details)
            Text(
              line,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            _AsyncStatusText(message: error, success: false),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onConfirm != null)
                FilledButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.merge_type),
                  label: const Text('합치기'),
                ),
              OutlinedButton.icon(
                onPressed: onSyncNow,
                icon: status.running
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('지금 동기화'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatSyncTime(DateTime? value) {
  if (value == null) return '없음';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// 번호와 완료 표시가 붙은 설정 단계.
class _SyncStep extends StatelessWidget {
  const _SyncStep({
    required this.number,
    required this.title,
    required this.done,
    required this.children,
    this.last = false,
  });

  final int number;
  final String title;
  final bool done;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: done
                    ? VibeColors.accent
                    : VibeColors.borderSoft,
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '$number',
                        style: const TextStyle(
                          fontSize: 12,
                          color: VibeColors.onSurface,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$number. $title',
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SyncHelpText extends StatelessWidget {
  const _SyncHelpText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: VibeColors.onSurfaceDim, fontSize: 13),
  );
}

class _GitHubDeviceCodeCard extends StatelessWidget {
  const _GitHubDeviceCodeCard({required this.code});

  final GitHubDeviceCode code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VibeColors.accentSoft,
        border: Border.all(color: VibeColors.accent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: VibeColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
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
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: code.userCode)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('복사'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            code.verificationUri.toString(),
            style: const TextStyle(
              color: VibeColors.onSurfaceDim,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
