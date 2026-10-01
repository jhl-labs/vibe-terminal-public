import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_chat_service.dart';
import '../app/background_keep_alive.dart';
import '../app/build_features.dart';
import '../app/error_reporter.dart';
import '../app/keepalive_pulse.dart';
import '../app/update_checker.dart';
import '../app/telemetry_notice.dart';
import '../app/update_preferences.dart';
import '../community/github_community_service.dart';
import '../data/db/app_database.dart';
import '../data/models/host.dart';
import '../data/models/identity.dart';
import '../data/models/session_log.dart';
import '../data/models/snippet.dart';
import '../data/models/ssh_key.dart';
import '../data/repositories/host_repository.dart';
import '../data/repositories/identity_repository.dart';
import '../data/repositories/memo_repository.dart';
import '../data/repositories/session_log_repository.dart';
import '../data/repositories/ssh_key_repository.dart';
import '../data/repositories/snippet_repository.dart';
import '../local/local_terminal_service.dart';
import '../local/default_local_hosts.dart';
import '../kubernetes/kubernetes_exec_relay.dart';
import '../notifications/notification_service.dart';
import '../security/host_key_store.dart';
import '../security/secure_store.dart';
import '../session/session.dart';
import '../snippets/gist_sync_service.dart';
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
import '../ssh/public_key_installer.dart';
import '../ssh/ssh_service.dart';
import '../ssh/remote_session_catalog.dart';
import '../sync/cloud_sync_snapshot.dart';
import '../sync/github_sync_service.dart';
import '../telemetry/telemetry.dart';
import '../telemetry/telemetry_factory.dart';

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

final knownHostListProvider = FutureProvider<List<HostKeyRow>>(
  (ref) => ref.watch(hostKeyStoreProvider).listAll(),
);

final sshKeyRepositoryProvider = Provider<SshKeyRepository>(
  (ref) => SshKeyRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(secureStoreProvider),
  ),
);

final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => IdentityRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(secureStoreProvider),
  ),
);

final hostRepositoryProvider = Provider<HostRepository>(
  (ref) => HostRepository(
    ref.watch(appDatabaseProvider),
    secureStore: ref.watch(secureStoreProvider),
  ),
);

final sshKeyListProvider = FutureProvider<List<SshKey>>(
  (ref) => ref.watch(sshKeyRepositoryProvider).getAll(),
);

final identityListProvider = FutureProvider<List<Identity>>(
  (ref) => ref.watch(identityRepositoryProvider).getAll(),
);

final sshServiceProvider = Provider<SshService>(
  (ref) => SshService(
    secureStore: ref.watch(secureStoreProvider),
    hostKeyStore: ref.watch(hostKeyStoreProvider),
  ),
);

/// 키체인 공개키를 서버 authorized_keys에 등록하는 ssh-copy-id 상당 흐름.
final publicKeyInstallerProvider = Provider<PublicKeyInstaller>(
  (ref) => PublicKeyInstaller(
    sshService: ref.watch(sshServiceProvider),
    hostRepository: ref.watch(hostRepositoryProvider),
    identityRepository: ref.watch(identityRepositoryProvider),
    sshKeyRepository: ref.watch(sshKeyRepositoryProvider),
  ),
);

final localTerminalServiceProvider = Provider<LocalTerminalService>(
  (ref) => LocalTerminalService(),
);

final kubernetesRelayServiceProvider = Provider<KubernetesRelayService>(
  (ref) => ProcessKubernetesRelayService(),
);

final aiChatServiceProvider = Provider<AiChatService>((ref) => AiChatService());

final buildFeaturesProvider = Provider<BuildFeatures>(
  (ref) => BuildFeatures.current,
);

final telemetryProvider = Provider<Telemetry>(
  (ref) => createTelemetry(ref.read(buildFeaturesProvider)),
);

final gitHubSyncServiceProvider = Provider<GitHubSyncService>(
  (ref) => GitHubSyncService(),
);

final gitHubCommunityServiceProvider = Provider<GitHubCommunityService>(
  (ref) => GitHubCommunityService(),
);

final gistSyncServiceProvider = Provider<GistSyncService>(
  (ref) => GistSyncService(),
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
  (ref) => PlatformBackgroundKeepAlive(
    // 포그라운드 서비스 상태를 오류 보고의 커스텀 키로 남긴다.
    onStateChanged: (active) =>
        ref.read(telemetryProvider).setKey('platform_keepalive', active),
  ),
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

/// 첫 실행에 플랫폼별 기본 로컬 셸 호스트(PowerShell/WSL/로컬 셸)를 만든다.
final defaultLocalHostSeederProvider = Provider<DefaultLocalHostSeeder>(
  (ref) => DefaultLocalHostSeeder(
    ref.watch(hostRepositoryProvider),
    candidates: defaultLocalHostCandidatesForThisDevice(),
  ),
);

/// 텔레메트리 첫 실행 안내를 이미 보여 줬는지 기억한다.
final telemetryNoticeFlagProvider = Provider<TelemetryNoticeFlag>(
  (ref) => TelemetryNoticeFlag(),
);

/// 건너뛴 버전과 마지막 조회 시각을 기억한다.
final updatePreferencesProvider = Provider<UpdatePreferences>(
  (ref) => UpdatePreferences(),
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

  /// [groupId] 그룹의 이름을 바꾼다. 고정 그룹(default/apps)과 없는 그룹은
  /// 무시한다. 빈 이름은 기존 이름을 유지한다.
  void renameGroup(String groupId, String name) {
    final index = state.groups.indexWhere((g) => g.id == groupId);
    if (index < 0) return;
    final group = state.groups[index];
    if (group.isFixed) return;
    final renamed = SessionGroup(
      id: group.id,
      name: SessionGroup.cleanName(name, group.name),
    );
    if (renamed == group) return;
    state = state.copyWith(groups: [...state.groups]..[index] = renamed);
    _persist();
  }

  /// [groupId] 그룹을 삭제한다. 고정 그룹(default/apps)은 삭제하지 않는다.
  /// 소속 세션은 모두 기본 그룹으로 옮긴 뒤 그룹 목록에서 제거한다.
  void deleteGroup(String groupId) {
    SessionGroup? group;
    for (final g in state.groups) {
      if (g.id == groupId) {
        group = g;
        break;
      }
    }
    if (group == null || group.isFixed) return;

    final sessions = ref.read(sessionManagerProvider);
    final sessionManager = ref.read(sessionManagerProvider.notifier);
    for (final session in sessions) {
      if (session.groupId == groupId) {
        sessionManager.moveSessionToGroup(session.id, defaultSessionGroupId);
      }
    }

    state = state.copyWith(
      groups: [
        for (final g in state.groups)
          if (g.id != groupId) g,
      ],
      activeGroupId: state.activeGroupId == groupId
          ? defaultSessionGroupId
          : state.activeGroupId,
    );
    _persist();
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

/// 결정되지 않은 텔레메트리 설정을 [locale] 기준 기본값으로 채우고 configured 로
/// 표시한다. 이미 결정된 설정은 그대로 돌려준다.
AppSettings applyTelemetryDefaults(AppSettings settings, Locale? locale) {
  if (settings.telemetry.configured) return settings;
  return settings.copyWith(
    telemetry: TelemetrySettings.defaultsFor(locale).copyWith(configured: true),
  );
}

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
    // 비동기 대기 사이에 컨테이너가 dispose될 수 있다(앱 종료, 테스트 정리).
    // 그 뒤 ref를 만지면 riverpod이 예외를 던지므로 각 대기 후 확인한다.
    final settingsStore = ref.read(appSettingsStoreProvider);
    final store = ref.read(secureStoreProvider);
    var loaded = await settingsStore.load();
    if (!ref.mounted) return;
    // 손상돼 읽지 못한 파일은 기본값으로 덮어쓰지 않는다(진단 증거 보존).
    final canPersistDefaults = loaded != null || !await settingsStore.exists();
    if (!ref.mounted) return;
    // 비밀값은 키마다 따로 읽는다. 한 키의 읽기 실패가 나머지(예: GitHub
    // 로그인 token)까지 버리게 하면 "매번 다시 로그인" 증상이 되고, 원인도
    // 남지 않는다.
    final token = await _readSecret(store, AiSettings.apiTokenSecretRef);
    final customHeaders = await _readSecret(
      store,
      AiSettings.customHeadersSecretRef,
    );
    final githubToken = await _readSecret(
      store,
      CloudSyncSettings.githubTokenSecretRef,
    );
    final githubRefreshToken = await _readSecret(
      store,
      CloudSyncSettings.githubRefreshTokenSecretRef,
    );
    final syncEncryptionKey = await _readSecret(
      store,
      CloudSyncSettings.encryptionKeySecretRef,
    );
    if (token != null ||
        customHeaders != null ||
        githubToken != null ||
        githubRefreshToken != null ||
        syncEncryptionKey != null) {
      final base = loaded ?? AppSettings.defaultSettings;
      loaded = base.copyWith(
        ai: base.ai.copyWith(
          apiToken: token ?? base.ai.apiToken,
          customHeaders: customHeaders ?? base.ai.customHeaders,
        ),
        cloudSync: base.cloudSync.copyWith(
          encryptionKey: syncEncryptionKey ?? base.cloudSync.encryptionKey,
          github: base.cloudSync.github.copyWith(
            token: githubToken ?? base.cloudSync.github.token,
            refreshToken:
                githubRefreshToken ?? base.cloudSync.github.refreshToken,
          ),
        ),
      );
    }
    if (!ref.mounted) return;
    // 텔레메트리 설정이 아직 결정되지 않았으면(첫 실행, 또는 이 키가 없던
    // 버전에서 올라온 설치) 기기 로케일 기준 기본값(EEA 는 사용 통계 끔)을
    // 한 번 정해 저장한다. 다음 실행부터 main.dart 의 부트스트랩이 같은 값을 읽는다.
    final base = loaded ?? state;
    if (!base.telemetry.configured) {
      loaded = applyTelemetryDefaults(base, PlatformDispatcher.instance.locale);
      if (canPersistDefaults) unawaited(settingsStore.save(loaded));
    }
    if (loaded != null) state = loaded;
  }

  /// 비밀값 하나를 읽는다. 없거나 비어 있으면 null. 보안 저장소 오류는
  /// 설정을 계속 쓸 수 있게 삼키되 crash.log에 남긴다.
  Future<String?> _readSecret(SecureStore store, String secretRef) async {
    try {
      final value = await store.readSecret(secretRef);
      return value == null || value.isEmpty ? null : value;
    } catch (error, stackTrace) {
      appErrorReporter.report(
        error,
        stackTrace,
        source: 'secure-store',
        context: '비밀값 읽기 실패: $secretRef',
      );
      return null;
    }
  }

  void update(AppSettings settings) {
    final previousToken = state.ai.apiToken;
    final previousCustomHeaders = state.ai.customHeaders;
    final previousGithubToken = state.cloudSync.github.token;
    final previousGithubRefreshToken = state.cloudSync.github.refreshToken;
    final previousSyncEncryptionKey = state.cloudSync.encryptionKey;
    final previousTelemetry = state.telemetry;
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
    if (settings.telemetry != previousTelemetry) {
      unawaited(ref.read(telemetryProvider).applySettings(settings.telemetry));
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
    } catch (error, stackTrace) {
      // 저장 실패는 런타임 설정에 영향이 없지만, 다음 실행에서 값이 사라지는
      // 원인이므로 기록은 남긴다.
      appErrorReporter.report(
        error,
        stackTrace,
        source: 'secure-store',
        context: '비밀값 저장 실패: $secretRef',
      );
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
    final next = <String, List<String>>{
      ...state.shortcutBindings,
      action: List<String>.unmodifiable(bindings),
    };
    update(
      state.copyWith(
        shortcutBindings: Map<String, List<String>>.unmodifiable(next),
      ),
    );
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

  void setRightPanelToolHidden(RightPanelTool tool, bool hidden) {
    final next = {...state.hiddenRightPanelTools};
    if (hidden) {
      next.add(tool.name);
    } else {
      next.remove(tool.name);
    }
    update(state.copyWith(hiddenRightPanelTools: next));
  }

  void setSnippetGistId(String gistId) {
    update(state.copyWith(snippetGistId: gistId));
  }

  void setRightPanelToolOrder(List<String> order) {
    update(state.copyWith(rightPanelToolOrder: List.unmodifiable(order)));
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

  void rememberAgentLaunchModel(String model) {
    update(
      state.copyWith(agentLaunch: state.agentLaunch.withRecentModel(model)),
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

  void setAiMaxLogContextLines(int lines) {
    update(state.copyWith(ai: state.ai.copyWith(maxLogContextLines: lines)));
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
  paneLayout,
  snippets,
  sessionInfo,
  aiChat,
  memo,
  claudeSettings,
  codexSettings,
  opencodeSettings,
  community,
  logs,
}

/// [RightPanelState.copyWith]에서 "값을 바꾸지 않음"과 "null로 지움"을
/// 구분하기 위한 센티널.
const Object _unchangedRightPanel = Object();

class RightPanelState {
  const RightPanelState({
    required this.open,
    required this.tool,
    this.customAppId,
    this.customAppEditing = false,
  });

  final bool open;
  final RightPanelTool tool;

  /// 우측 패널이 항목 하나를 지목할 때 쓰는 대상 id. null이면 도구의 기본
  /// 화면을 뜻한다.
  final String? customAppId;

  /// 대상 id를 편집 모드로 열었는지 여부.
  final bool customAppEditing;

  static const closed = RightPanelState(
    open: false,
    tool: RightPanelTool.aiChat,
  );

  RightPanelState copyWith({
    bool? open,
    RightPanelTool? tool,
    Object? customAppId = _unchangedRightPanel,
    bool? customAppEditing,
  }) => RightPanelState(
    open: open ?? this.open,
    tool: tool ?? this.tool,
    customAppId: identical(customAppId, _unchangedRightPanel)
        ? this.customAppId
        : customAppId as String?,
    customAppEditing: customAppEditing ?? this.customAppEditing,
  );
}

/// 우측 패널 열림 상태. 데스크톱은 도구 스트립, 모바일은 endDrawer에서 같은 모드를 쓴다.
class RightPanelController extends Notifier<RightPanelState> {
  @override
  RightPanelState build() => RightPanelState.closed;

  void toggle(RightPanelTool tool) {
    if (state.open &&
        state.tool == tool &&
        state.customAppId == null &&
        !state.customAppEditing) {
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
