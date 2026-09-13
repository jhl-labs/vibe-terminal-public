import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_chat_service.dart';
import '../app/background_keep_alive.dart';
import '../app/build_features.dart';
import '../app/keepalive_pulse.dart';
import '../app/update_checker.dart';
import '../community/github_community_service.dart';
import '../data/db/app_database.dart';
import '../data/models/host.dart';
import '../data/models/session_log.dart';
import '../data/models/snippet.dart';
import '../data/repositories/host_repository.dart';
import '../data/repositories/memo_repository.dart';
import '../data/repositories/session_log_repository.dart';
import '../data/repositories/snippet_repository.dart';
import '../local/local_terminal_service.dart';
import '../kubernetes/kubernetes_port_forward_service.dart';
import '../notifications/notification_service.dart';
import '../security/host_key_store.dart';
import '../security/secure_store.dart';
import '../session/session.dart';
import '../session/session_diagnostics.dart';
import '../session/session_group.dart';
import '../session/remote_session_identity_store.dart';
import '../session/remote_session_cleanup_store.dart';
import '../session/session_manager.dart';
import '../session/session_restore_store.dart';
import '../ai/custom_headers.dart';
import '../agent/agent_worktree_store.dart';
import '../settings/app_settings.dart';
import '../settings/app_settings_store.dart';
import '../ssh/ssh_service.dart';
import '../ssh/remote_session_catalog.dart';
import '../sync/cloud_sync_snapshot.dart';
import '../sync/github_sync_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final secureStoreProvider = Provider<SecureStore>(
  (ref) => FlutterSecureStoreImpl(),
);

final remoteSessionIdentityStoreProvider = Provider<RemoteSessionIdentityStore>(
  (ref) => RemoteSessionIdentityStore(),
);

final remoteSessionCleanupStoreProvider = Provider<RemoteSessionCleanupStore>(
  (ref) => RemoteSessionCleanupStore(),
);

final agentWorktreeStoreProvider = Provider<AgentWorktreeStore>(
  (ref) => AgentWorktreeStore(),
);

final remoteSessionCatalogProvider = Provider<RemoteSessionCatalog>(
  (ref) => const TmuxRemoteSessionCatalog(),
);

final hostKeyStoreProvider = Provider<HostKeyStore>(
  (ref) => HostKeyStore(ref.watch(appDatabaseProvider)),
);

final hostRepositoryProvider = Provider<HostRepository>(
  (ref) => HostRepository(ref.watch(appDatabaseProvider)),
);

final sshServiceProvider = Provider<SshService>(
  (ref) => SshService(
    secureStore: ref.watch(secureStoreProvider),
    hostKeyStore: ref.watch(hostKeyStoreProvider),
  ),
);

final localTerminalServiceProvider = Provider<LocalTerminalService>(
  (ref) => LocalTerminalService(),
);

final kubernetesPortForwardServiceProvider =
    Provider<KubernetesPortForwardService>(
      (ref) => ProcessKubernetesPortForwardService(),
    );

final aiChatServiceProvider = Provider<AiChatService>((ref) => AiChatService());

final buildFeaturesProvider = Provider<BuildFeatures>(
  (ref) => BuildFeatures.current,
);

final gitHubSyncServiceProvider = Provider<GitHubSyncService>(
  (ref) => GitHubSyncService(),
);

final gitHubCommunityServiceProvider = Provider<GitHubCommunityService>(
  (ref) => GitHubCommunityService(),
);

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

final cloudSyncSnapshotServiceProvider = Provider<CloudSyncSnapshotService>(
  (ref) => CloudSyncSnapshotService(
    database: ref.watch(appDatabaseProvider),
    secureStore: ref.watch(secureStoreProvider),
  ),
);

/// AI 채팅 대화 히스토리. 세션별로 분리하되 패널(우측 drawer/스트립) 위젯의
/// 수명과는 분리해 보관하므로, 패널을 닫았다 다시 열어도 해당 세션의 대화
/// 맥락이 유지된다.
class AiChatNotifier extends Notifier<List<AiChatMessage>> {
  AiChatNotifier(String sessionId);

  @override
  List<AiChatMessage> build() => const [];

  void add(AiChatMessage message) => state = [...state, message];

  void clear() => state = const [];
}

final aiChatMessagesProvider =
    NotifierProvider.family<AiChatNotifier, List<AiChatMessage>, String>(
      AiChatNotifier.new,
    );

final hostListProvider = FutureProvider<List<Host>>(
  (ref) => ref.watch(hostRepositoryProvider).getAll(),
);

final backgroundKeepAliveProvider = Provider<BackgroundKeepAlive>(
  (ref) => PlatformBackgroundKeepAlive(),
);

/// keepalive 박자 공급원(플랫폼별). 테스트에서 Fake로 치환한다.
final keepalivePulseProvider = Provider<KeepalivePulse>(
  (ref) => createPlatformKeepalivePulse(),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => const UpdateChecker(),
);

/// 앱이 포그라운드에 보이는지 여부. 작업 완료 알림 조건에 쓰인다(앱이
/// 백그라운드면 활성 세션이라도 알림을 보낸다).
class AppForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool foreground) => state = foreground;
}

final appForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(
  AppForegroundNotifier.new,
);

final sessionManagerProvider =
    NotifierProvider<SessionManager, List<SessionInfo>>(SessionManager.new);

/// 세션별 연결 진단 이벤트(keepalive/끊김/재연결) 로그.
final sessionDiagnosticsProvider =
    NotifierProvider<SessionDiagnostics, Map<String, List<SessionEvent>>>(
      SessionDiagnostics.new,
    );

final sessionRestoreStoreProvider = Provider<SessionRestoreStore>(
  (ref) => SessionRestoreStore(),
);

class SessionGroupController extends Notifier<SessionGroupState> {
  int _counter = 1;

  @override
  SessionGroupState build() => SessionGroupState.initial;

  String createGroup(String name) {
    final fallbackName = '그룹 ${state.groups.length}';
    final id = _nextGroupId();
    state = state.copyWith(
      groups: [
        ...state.groups,
        SessionGroup(id: id, name: SessionGroup.cleanName(name, fallbackName)),
      ],
      activeGroupId: id,
    );
    _persist();
    return id;
  }

  void setActive(String groupId) {
    if (!state.contains(groupId)) return;
    if (state.activeGroupId == groupId) return;
    state = state.copyWith(activeGroupId: groupId);
    _persist();
  }

  void ensureGroup(String groupId, {String? name}) {
    final id = groupId.trim();
    if (id.isEmpty) return;
    if (state.contains(id)) return;
    state = state.copyWith(
      groups: [
        ...state.groups,
        SessionGroup(
          id: id,
          name: SessionGroup.cleanName(name, '그룹 ${state.groups.length}'),
        ),
      ],
    );
    _reserveCounterFor(id);
    _persist();
  }

  void restoreFromSnapshot(SessionRestoreSnapshot snapshot) {
    final groups = normalizeSessionGroups(
      snapshot.groups,
      requiredIds: snapshot.sessions.map((session) => session.groupId),
    );
    for (final group in groups) {
      _reserveCounterFor(group.id);
    }
    state = SessionGroupState(
      groups: groups,
      activeGroupId: groups.any((group) => group.id == snapshot.activeGroupId)
          ? snapshot.activeGroupId
          : defaultSessionGroupId,
    );
  }

  String _nextGroupId() {
    while (state.contains('g$_counter')) {
      _counter++;
    }
    return 'g${_counter++}';
  }

  static final _generatedIdPattern = RegExp(r'^g(\d+)$');

  void _reserveCounterFor(String id) {
    final match = _generatedIdPattern.firstMatch(id);
    if (match == null) return;
    final index = int.tryParse(match.group(1)!);
    if (index == null) return;
    if (_counter <= index) _counter = index + 1;
  }

  void _persist() {
    unawaited(
      ref
          .read(sessionRestoreStoreProvider)
          .saveGroupState(state.groups, state.activeGroupId),
    );
  }
}

final sessionGroupProvider =
    NotifierProvider<SessionGroupController, SessionGroupState>(
      SessionGroupController.new,
    );

class _ActiveSessionIdNotifier extends Notifier<String?> {
  String? _previousId;

  @override
  String? build() => null;

  void set(String? id) {
    if (id != state) {
      _previousId = state;
    }
    state = id;
    unawaited(ref.read(sessionRestoreStoreProvider).saveActiveId(id));
  }

  void switchToPrevious(List<SessionInfo> sessions) {
    if (sessions.length < 2) return;

    final currentId = state;
    final previousId = _previousId;
    if (previousId != null &&
        previousId != currentId &&
        sessions.any((session) => session.id == previousId)) {
      set(previousId);
      return;
    }

    final current = sessions.indexWhere((session) => session.id == currentId);
    final base = current < 0 ? 0 : current;
    final next = (base - 1) % sessions.length;
    final wrapped = next < 0 ? next + sessions.length : next;
    set(sessions[wrapped].id);
  }
}

final activeSessionIdProvider =
    NotifierProvider<_ActiveSessionIdNotifier, String?>(
      _ActiveSessionIdNotifier.new,
    );

/// 활성 세션을 [delta]칸 순환 이동한다. 세션이 2개 미만이면 무시하고,
/// 양 끝에서는 순환한다. 상단 헤더·스와이프 등 여러 진입점이 공유한다.
void cycleActiveSession(WidgetRef ref, int delta) {
  final activeGroupId = ref.read(sessionGroupProvider).activeGroupId;
  final sessions = [
    for (final session in ref.read(sessionManagerProvider))
      if (session.groupId == activeGroupId) session,
  ];
  if (sessions.length < 2) return;
  final activeId = ref.read(activeSessionIdProvider);
  final current = sessions.indexWhere((s) => s.id == activeId);
  final base = current < 0 ? 0 : current;
  final next = (base + delta) % sessions.length;
  final wrapped = next < 0 ? next + sessions.length : next;
  ref.read(activeSessionIdProvider.notifier).set(sessions[wrapped].id);
}

/// 직전에 활성화했던 세션으로 전환한다. 직전 세션이 없거나 닫혔으면
/// 좌측 목록 기준 이전 세션으로 폴백한다.
void switchToPreviousActiveSession(WidgetRef ref) {
  final activeGroupId = ref.read(sessionGroupProvider).activeGroupId;
  final sessions = [
    for (final session in ref.read(sessionManagerProvider))
      if (session.groupId == activeGroupId) session,
  ];
  if (sessions.length < 2) return;
  ref.read(activeSessionIdProvider.notifier).switchToPrevious(sessions);
}

/// 보조 키바 등 터미널 외부에서 활성 터미널에 소프트키보드 포커스를 요청하는
/// 신호. 값이 증가할 때마다 활성 SessionTerminalView가 포커스를 다시 요청한다.
class KeyboardFocusRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void request() => state = state + 1;
}

final keyboardFocusRequestProvider =
    NotifierProvider<KeyboardFocusRequestNotifier, int>(
      KeyboardFocusRequestNotifier.new,
    );

/// 터미널 폰트 크기(줌). 전역 단일 값. 범위 [8, 32], 기본 14, 단계 2.
class FontSizeController extends Notifier<double> {
  static const double minSize = 8.0;
  static const double maxSize = 32.0;
  static const double defaultSize = 14.0;
  static const double step = 2.0;

  @override
  double build() => defaultSize;

  void setSize(double v) => state = v.clamp(minSize, maxSize);
  void zoomIn() => setSize(state + step);
  void zoomOut() => setSize(state - step);
  void reset() => state = defaultSize;
}

final fontSizeProvider = NotifierProvider<FontSizeController, double>(
  FontSizeController.new,
);

/// 모바일 보조 키바(ExtraKeysBar)의 Ctrl sticky 모디파이어.
/// 바의 토글/표시와 터미널 IME 입력 경로(시스템 키보드로 친 문자에 Ctrl 적용)가
/// 같은 상태를 공유하도록 전역으로 둔다. 한 문자에 적용되면 자동 해제된다.
class CtrlStickyController extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void clear() => state = false;
}

final ctrlStickyProvider = NotifierProvider<CtrlStickyController, bool>(
  CtrlStickyController.new,
);

final appSettingsStoreProvider = Provider<AppSettingsStore>(
  (ref) => AppSettingsStore(),
);

class AppSettingsController extends Notifier<AppSettings> {
  bool _loadStarted = false;

  @override
  AppSettings build() {
    if (!_loadStarted) {
      _loadStarted = true;
      unawaited(_load());
    }
    return AppSettings.defaultSettings;
  }

  Future<void> _load() async {
    var loaded = await ref.read(appSettingsStoreProvider).load();
    try {
      final store = ref.read(secureStoreProvider);
      final token = await store.readSecret(AiSettings.apiTokenSecretRef);
      final customHeaders = await store.readSecret(
        AiSettings.customHeadersSecretRef,
      );
      final githubToken = await store.readSecret(
        CloudSyncSettings.githubTokenSecretRef,
      );
      final githubRefreshToken = await store.readSecret(
        CloudSyncSettings.githubRefreshTokenSecretRef,
      );
      final syncEncryptionKey = await store.readSecret(
        CloudSyncSettings.encryptionKeySecretRef,
      );
      if ((token != null && token.isNotEmpty) ||
          (customHeaders != null && customHeaders.isNotEmpty) ||
          (githubToken != null && githubToken.isNotEmpty) ||
          (githubRefreshToken != null && githubRefreshToken.isNotEmpty) ||
          (syncEncryptionKey != null && syncEncryptionKey.isNotEmpty)) {
        final base = loaded ?? AppSettings.defaultSettings;
        loaded = base.copyWith(
          ai: base.ai.copyWith(
            apiToken: token != null && token.isNotEmpty
                ? token
                : base.ai.apiToken,
            customHeaders: customHeaders != null && customHeaders.isNotEmpty
                ? customHeaders
                : base.ai.customHeaders,
          ),
          cloudSync: base.cloudSync.copyWith(
            encryptionKey:
                syncEncryptionKey != null && syncEncryptionKey.isNotEmpty
                ? syncEncryptionKey
                : base.cloudSync.encryptionKey,
            github: base.cloudSync.github.copyWith(
              token: githubToken != null && githubToken.isNotEmpty
                  ? githubToken
                  : base.cloudSync.github.token,
              refreshToken:
                  githubRefreshToken != null && githubRefreshToken.isNotEmpty
                  ? githubRefreshToken
                  : base.cloudSync.github.refreshToken,
            ),
          ),
        );
      }
    } catch (_) {
      // Settings must remain usable even when secure storage is unavailable.
    }
    if (loaded != null) state = loaded;
  }

  void update(AppSettings settings) {
    final previousToken = state.ai.apiToken;
    final previousCustomHeaders = state.ai.customHeaders;
    final previousGithubToken = state.cloudSync.github.token;
    final previousGithubRefreshToken = state.cloudSync.github.refreshToken;
    final previousSyncEncryptionKey = state.cloudSync.encryptionKey;
    state = settings;
    unawaited(ref.read(appSettingsStoreProvider).save(settings));
    if (settings.ai.apiToken != previousToken) {
      unawaited(
        _saveSecret(AiSettings.apiTokenSecretRef, settings.ai.apiToken),
      );
    }
    if (settings.ai.customHeaders != previousCustomHeaders) {
      unawaited(
        _saveSecret(
          AiSettings.customHeadersSecretRef,
          settings.ai.customHeaders,
        ),
      );
    }
    if (settings.cloudSync.github.token != previousGithubToken) {
      unawaited(
        _saveSecret(
          CloudSyncSettings.githubTokenSecretRef,
          settings.cloudSync.github.token,
        ),
      );
    }
    if (settings.cloudSync.github.refreshToken != previousGithubRefreshToken) {
      unawaited(
        _saveSecret(
          CloudSyncSettings.githubRefreshTokenSecretRef,
          settings.cloudSync.github.refreshToken,
        ),
      );
    }
    if (settings.cloudSync.encryptionKey != previousSyncEncryptionKey) {
      unawaited(
        _saveSecret(
          CloudSyncSettings.encryptionKeySecretRef,
          settings.cloudSync.encryptionKey,
        ),
      );
    }
  }

  Future<void> _saveSecret(String secretRef, String value) async {
    try {
      final store = ref.read(secureStoreProvider);
      if (value.trim().isEmpty) {
        await store.deleteSecret(secretRef);
      } else {
        await store.writeSecret(secretRef, value);
      }
    } catch (_) {
      // Secret persistence is best-effort. Runtime settings still apply.
    }
  }

  void reset() => update(AppSettings.defaultSettings);

  void setTerminalTheme(TerminalThemePreset theme) {
    update(state.copyWith(terminalTheme: theme));
  }

  void setTerminalFontFamily(String fontFamily) {
    update(state.copyWith(terminalFontFamily: fontFamily));
  }

  void setTerminalFontSize(double fontSize) {
    update(state.copyWith(terminalFontSize: fontSize));
  }

  void setTerminalLineHeight(double lineHeight) {
    update(state.copyWith(terminalLineHeight: lineHeight));
  }

  void setTerminalScrollbackLines(int lines) {
    update(state.copyWith(terminalScrollbackLines: lines));
  }

  void setCopyOnSelection(bool enabled) {
    update(state.copyWith(copyOnSelection: enabled));
  }

  void setRightClickPaste(bool enabled) {
    update(state.copyWith(rightClickPaste: enabled));
  }

  void setConfirmMultilinePaste(bool enabled) {
    update(state.copyWith(confirmMultilinePaste: enabled));
  }

  void setCtrlCBehavior(CtrlCBehavior behavior) {
    update(state.copyWith(ctrlCBehavior: behavior));
  }

  void setExtraKeysBarItems(List<String> items) {
    update(state.copyWith(extraKeysBarItems: List.unmodifiable(items)));
  }

  void setTerminalHeaderItems(List<String> items) {
    update(state.copyWith(terminalHeaderItems: List.unmodifiable(items)));
  }

  void setShortcutBinding(String action, List<String> bindings) {
    final next = {
      ...state.shortcutBindings,
      action: List.unmodifiable(bindings),
    };
    update(state.copyWith(shortcutBindings: Map.unmodifiable(next)));
  }

  void setNotificationsEnabled(bool enabled) {
    update(
      state.copyWith(
        notifications: state.notifications.copyWith(enabled: enabled),
      ),
    );
  }

  void setTaskCompleteNotificationsEnabled(bool enabled) {
    update(
      state.copyWith(
        notifications: state.notifications.copyWith(
          taskCompleteEnabled: enabled,
        ),
      ),
    );
  }

  void setAgentAttentionNotificationsEnabled(bool enabled) {
    update(
      state.copyWith(
        notifications: state.notifications.copyWith(
          agentAttentionEnabled: enabled,
        ),
      ),
    );
  }

  void setLeftPanelWidth(double width) {
    update(state.copyWith(leftPanelWidth: width));
  }

  void setRightPanelWidth(double width) {
    update(state.copyWith(rightPanelWidth: width));
  }

  void rememberAgentLaunch({
    required String cliName,
    required List<String> arguments,
    required bool isolateByDefault,
  }) {
    update(
      state.copyWith(
        agentLaunch: state.agentLaunch
            .withArguments(cliName, arguments)
            .copyWith(isolateByDefault: isolateByDefault),
      ),
    );
  }

  void saveAgentLaunchProfile(AgentLaunchProfile profile) {
    update(state.copyWith(agentLaunch: state.agentLaunch.withProfile(profile)));
  }

  void removeAgentLaunchProfile(String id) {
    update(state.copyWith(agentLaunch: state.agentLaunch.withoutProfile(id)));
  }

  void saveAgentRunProfile(AgentRunProfile profile) {
    update(
      state.copyWith(agentLaunch: state.agentLaunch.withRunProfile(profile)),
    );
  }

  void removeAgentRunProfile(String id) {
    update(
      state.copyWith(agentLaunch: state.agentLaunch.withoutRunProfile(id)),
    );
  }

  void setXServerAutoStart(bool enabled) {
    update(state.copyWith(xServer: state.xServer.copyWith(autoStart: enabled)));
  }

  void setXServerExecutablePath(String path) {
    update(
      state.copyWith(xServer: state.xServer.copyWith(executablePath: path)),
    );
  }

  void setXServerDisplayNumber(int displayNumber) {
    update(
      state.copyWith(
        xServer: state.xServer.copyWith(displayNumber: displayNumber),
      ),
    );
  }

  void setXServerExtraArgs(String args) {
    update(state.copyWith(xServer: state.xServer.copyWith(extraArgs: args)));
  }

  void setCloudSyncProvider(CloudSyncProviderType provider) {
    update(
      state.copyWith(cloudSync: state.cloudSync.copyWith(provider: provider)),
    );
  }

  void setCloudSyncEnabled(bool enabled) {
    update(
      state.copyWith(cloudSync: state.cloudSync.copyWith(enabled: enabled)),
    );
  }

  void setCloudSyncEncryptionKey(String key) {
    update(
      state.copyWith(cloudSync: state.cloudSync.copyWith(encryptionKey: key)),
    );
  }

  void setGitHubSyncServerUrl(String serverUrl) {
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(serverUrl: serverUrl),
        ),
      ),
    );
  }

  void setGitHubSyncHostType(GitHubSyncHostType hostType) {
    final current = state.cloudSync.github;
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: current.copyWith(
            hostType: hostType,
            serverUrl: hostType == GitHubSyncHostType.githubDotCom
                ? GitHubSyncSettings.githubComServerUrl
                : current.serverUrl == GitHubSyncSettings.githubComServerUrl
                ? ''
                : current.serverUrl,
            appClientId: hostType == GitHubSyncHostType.githubDotCom
                ? ''
                : current.appClientId,
          ),
        ),
      ),
    );
  }

  void setGitHubSyncAppClientId(String appClientId) {
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(appClientId: appClientId),
        ),
      ),
    );
  }

  void setGitHubSyncOwner(String owner) {
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(owner: owner),
        ),
      ),
    );
  }

  void setGitHubSyncRepo(String repo) {
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(repo: repo),
        ),
      ),
    );
  }

  void setGitHubSyncBranch(String branch) {
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(branch: branch),
        ),
      ),
    );
  }

  void setGitHubSyncPath(String path) {
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(path: path),
        ),
      ),
    );
  }

  void setGitHubSyncToken(String token) {
    final clearToken = token.trim().isEmpty;
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(
            token: token,
            refreshToken: clearToken ? '' : null,
            tokenExpiresAt: clearToken
                ? null
                : state.cloudSync.github.tokenExpiresAt,
            refreshTokenExpiresAt: clearToken
                ? null
                : state.cloudSync.github.refreshTokenExpiresAt,
          ),
        ),
      ),
    );
  }

  void setGitHubSyncAuthorization(GitHubAppAuthorization authorization) {
    update(
      state.copyWith(
        cloudSync: state.cloudSync.copyWith(
          github: state.cloudSync.github.copyWith(
            token: authorization.accessToken,
            refreshToken: authorization.refreshToken ?? '',
            tokenExpiresAt: authorization.expiresAt,
            refreshTokenExpiresAt: authorization.refreshTokenExpiresAt,
          ),
        ),
      ),
    );
  }

  void setAiProvider(AiProviderType provider) {
    update(state.copyWith(ai: state.ai.withProviderDefaults(provider)));
  }

  void setAiBaseUrl(String baseUrl) {
    update(state.copyWith(ai: state.ai.copyWith(baseUrl: baseUrl)));
  }

  void setAiModel(String model) {
    update(state.copyWith(ai: state.ai.copyWith(model: model)));
  }

  void setAiApiToken(String token) {
    update(state.copyWith(ai: state.ai.copyWith(apiToken: token)));
  }

  void setAiCustomHeaders(String headers) {
    update(
      state.copyWith(
        ai: state.ai.copyWith(
          customHeaders: normalizeCustomHeadersInput(headers),
        ),
      ),
    );
  }

  void setAiHttpProxy(String proxy) {
    update(state.copyWith(ai: state.ai.copyWith(httpProxy: proxy)));
  }

  void setAiHttpsProxy(String proxy) {
    update(state.copyWith(ai: state.ai.copyWith(httpsProxy: proxy)));
  }

  void setAiCustomPrompt(String prompt) {
    update(state.copyWith(ai: state.ai.copyWith(customPrompt: prompt)));
  }

  void setAiMaxContextLines(int lines) {
    update(state.copyWith(ai: state.ai.copyWith(maxContextLines: lines)));
  }

  void setAiChatFontFamily(String fontFamily) {
    update(state.copyWith(ai: state.ai.copyWith(chatFontFamily: fontFamily)));
  }

  void setAiChatFontSize(double fontSize) {
    update(state.copyWith(ai: state.ai.copyWith(chatFontSize: fontSize)));
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

enum RightPanelTool {
  snippets,
  aiChat,
  memo,
  claudeSettings,
  codexSettings,
  opencodeSettings,
  community,
  logs,
}

class RightPanelState {
  const RightPanelState({required this.open, required this.tool});

  final bool open;
  final RightPanelTool tool;

  static const closed = RightPanelState(
    open: false,
    tool: RightPanelTool.aiChat,
  );

  RightPanelState copyWith({bool? open, RightPanelTool? tool}) =>
      RightPanelState(open: open ?? this.open, tool: tool ?? this.tool);
}

/// 우측 패널 열림 상태. 데스크톱은 도구 스트립, 모바일은 endDrawer에서 같은 모드를 쓴다.
class RightPanelController extends Notifier<RightPanelState> {
  @override
  RightPanelState build() => RightPanelState.closed;

  void toggle(RightPanelTool tool) {
    if (state.open && state.tool == tool) {
      state = state.copyWith(open: false);
      return;
    }
    state = RightPanelState(open: true, tool: tool);
  }

  void open(RightPanelTool tool) {
    state = RightPanelState(open: true, tool: tool);
  }

  void close() => state = state.copyWith(open: false);
}

final rightPanelProvider =
    NotifierProvider<RightPanelController, RightPanelState>(
      RightPanelController.new,
    );

class LeftPanelController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void expand() => state = false;
  void collapse() => state = true;
}

final leftPanelCollapsedProvider = NotifierProvider<LeftPanelController, bool>(
  LeftPanelController.new,
);

final snippetRepositoryProvider = Provider<SnippetRepository>(
  (ref) => SnippetRepository(ref.watch(appDatabaseProvider)),
);

final memoRepositoryProvider = Provider<MemoRepository>(
  (ref) => MemoRepository(ref.watch(appDatabaseProvider)),
);

final sessionLogRepositoryProvider = Provider<SessionLogRepository>(
  (ref) => SessionLogRepository(ref.watch(appDatabaseProvider)),
);

final sessionLogListProvider = FutureProvider<List<SessionLog>>(
  (ref) => ref.watch(sessionLogRepositoryProvider).getAll(),
);

final snippetListProvider = FutureProvider<List<Snippet>>(
  (ref) => ref.watch(snippetRepositoryProvider).getAll(),
);
