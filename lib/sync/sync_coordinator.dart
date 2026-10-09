import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../settings/app_settings.dart';
import '../state/providers.dart';
import 'github_sync_remote.dart';
import 'github_sync_service.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';
import 'sync_local_store.dart';
import 'sync_remote.dart';
import 'sync_sections.dart';
import 'sync_snapshot.dart';
import 'synced_settings.dart';

enum SyncPhase {
  idle,
  running,

  /// 처음 합치기 전 사용자 확인을 기다린다.
  needsConfirmation,

  /// 사용자가 고쳐야 하는 오류(키, 권한 등). 자동으로 다시 시도하지 않는다.
  blocked,

  /// 잠시 뒤 자동으로 다시 시도하는 오류(네트워크 등).
  retrying,
}

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastPulled,
    this.lastPushed,
    this.lastRunAt,
    this.nextRunAt,
    this.error,
    this.confirmation,
  });

  final SyncPhase phase;

  /// 마지막으로 성공한 동기화에서 가져오고 보낸 항목 수.
  final int? lastPulled;
  final int? lastPushed;

  /// 이번 앱 실행에서 마지막으로 동기화를 끝낸 시각.
  final DateTime? lastRunAt;

  /// 예정된 다음 자동 실행 시각.
  final DateTime? nextRunAt;
  final String? error;
  final SyncNeedsConfirmationException? confirmation;

  bool get running => phase == SyncPhase.running;

  SyncStatus copyWith({
    SyncPhase? phase,
    int? lastPulled,
    int? lastPushed,
    DateTime? lastRunAt,
    Object? nextRunAt = _keep,
    Object? error = _keep,
    Object? confirmation = _keep,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastPulled: lastPulled ?? this.lastPulled,
    lastPushed: lastPushed ?? this.lastPushed,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    nextRunAt: identical(nextRunAt, _keep)
        ? this.nextRunAt
        : nextRunAt as DateTime?,
    error: identical(error, _keep) ? this.error : error as String?,
    confirmation: identical(confirmation, _keep)
        ? this.confirmation
        : confirmation as SyncNeedsConfirmationException?,
  );
}

const _keep = Object();

/// 키 유도 결과를 캐시하므로 앱 전체에서 하나만 쓴다.
final syncCryptoProvider = Provider<SyncCryptoService>(
  (ref) => SyncCryptoService(),
);

final syncLocalStoreProvider = Provider<SyncLocalStore>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final secureStore = ref.watch(secureStoreProvider);
  return AppSyncLocalStore(
    database: db,
    secureStore: secureStore,
    sections: buildSyncSections(db, secureStore),
    readSettings: () {
      final settings = ref.read(appSettingsProvider);
      return SyncSettingsBlock(
        updatedAt: settings.cloudSync.settingsUpdatedAt,
        values: SyncedSettings.extract(settings),
      );
    },
    applySettings: ref.read(appSettingsProvider.notifier).applySyncedSettings,
  );
});

final syncRemoteProvider = Provider<SyncRemote>((ref) {
  final service = ref.watch(gitHubSyncServiceProvider);
  final refresher = GitHubTokenRefresher(
    service: service,
    save: ref.read(appSettingsProvider.notifier).setGitHubSyncAuthorization,
  );
  return GitHubSyncRemote(
    service: service,
    settings: () =>
        refresher.fresh(ref.read(appSettingsProvider).cloudSync.github),
  );
});

final syncCoordinatorProvider = NotifierProvider<SyncCoordinator, SyncStatus>(
  SyncCoordinator.new,
);

/// 동기화를 언제 실행할지 정하고 한 번에 하나만 실행한다.
class SyncCoordinator extends Notifier<SyncStatus> {
  /// 로컬 변경을 모아 올리기까지 기다리는 시간.
  static const changeDebounce = Duration(seconds: 10);

  /// 다른 기기의 변경을 확인하는 간격.
  static const pollInterval = Duration(minutes: 5);
  static const initialBackoff = Duration(seconds: 30);
  static const maxBackoff = Duration(minutes: 30);

  Timer? _scheduled;
  Timer? _poll;
  StreamSubscription<Set<TableUpdate>>? _tableUpdates;
  Future<void>? _running;
  bool _rerun = false;
  bool _started = false;
  int _failures = 0;
  SyncCheckpoint? _checkpoint;

  @override
  SyncStatus build() {
    ref.onDispose(_stop);
    ref.listen(appSettingsProvider, _onSettingsChanged);
    return const SyncStatus();
  }

  CloudSyncSettings get _sync => ref.read(appSettingsProvider).cloudSync;

  bool get _autoReady =>
      _sync.isConfigured &&
      state.phase != SyncPhase.blocked &&
      state.phase != SyncPhase.needsConfirmation;

  /// 설정을 다 읽은 뒤 한 번 호출한다. 자동 동기화가 켜져 있으면 바로 실행한다.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await ref.read(appSettingsProvider.notifier).loaded;
    if (!ref.mounted) return;
    final local = ref.read(syncLocalStoreProvider);
    if (local is AppSyncLocalStore) {
      unawaited(local.pruneTombstones(DateTime.now()).catchError((_) {}));
    }
    _tableUpdates = ref
        .read(appDatabaseProvider)
        .tableUpdates(const TableUpdateQuery.any())
        .listen(_onTableUpdates);
    _poll = Timer.periodic(pollInterval, (_) {
      if (_autoReady) unawaited(syncNow());
    });
    if (_autoReady) unawaited(syncNow());
  }

  /// 앱이 백그라운드로 갈 때 기다리던 변경을 바로 올린다.
  void flushPending() {
    if (_scheduled == null || !_autoReady) return;
    _schedule(Duration.zero);
  }

  /// 지금 동기화한다. 실행 중이면 끝난 뒤 한 번 더 실행한다.
  /// [confirmed]는 첫 동기화에서 양쪽 데이터를 합치기로 확인했다는 뜻이다.
  Future<void> syncNow({bool confirmed = false}) {
    final running = _running;
    if (running != null) {
      _rerun = true;
      return running;
    }
    _scheduled?.cancel();
    _scheduled = null;
    final run = _run(confirmed: confirmed).whenComplete(() {
      _running = null;
      if (_rerun && ref.mounted) {
        _rerun = false;
        _schedule(Duration.zero);
      }
    });
    _running = run;
    return run;
  }

  Future<void> _run({required bool confirmed}) async {
    final sync = _sync;
    if (!sync.canSync) {
      state = state.copyWith(
        phase: SyncPhase.blocked,
        error: 'GitHub 로그인, 저장소, 암호화 키를 먼저 설정하세요.',
        nextRunAt: null,
      );
      return;
    }
    state = state.copyWith(
      phase: SyncPhase.running,
      error: null,
      confirmation: null,
      nextRunAt: null,
    );
    final target = sync.github.targetKey;
    try {
      final engine = SyncEngine(
        local: ref.read(syncLocalStoreProvider),
        remote: ref.read(syncRemoteProvider),
        crypto: ref.read(syncCryptoProvider),
      );
      final initial = sync.isFirstSync;
      final result = await engine.run(
        encryptionKey: sync.encryptionKey,
        initial: initial,
        confirmed: confirmed,
        checkpoint: initial ? null : _checkpoint,
      );
      if (!ref.mounted) return;
      _checkpoint = result.checkpoint;
      _failures = 0;
      final now = DateTime.now();
      ref
          .read(appSettingsProvider.notifier)
          .recordSyncCompleted(target: target, at: now);
      if (result.pulled > 0) _refreshSyncedData();
      state = state.copyWith(
        phase: SyncPhase.idle,
        lastPulled: result.pulled,
        lastPushed: result.pushed,
        lastRunAt: now,
        nextRunAt: _sync.isConfigured ? now.add(pollInterval) : null,
      );
    } on SyncNeedsConfirmationException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: SyncPhase.needsConfirmation,
        confirmation: e,
        error: null,
      );
    } catch (e) {
      if (!ref.mounted) return;
      _onFailure(e);
    }
  }

  void _onFailure(Object error) {
    if (!_isRetryable(error)) {
      state = state.copyWith(
        phase: SyncPhase.blocked,
        error: error.toString(),
        nextRunAt: null,
      );
      return;
    }
    _failures++;
    final factor = pow(2, min(_failures - 1, 10)).toInt();
    final delay = initialBackoff * factor;
    final wait = delay > maxBackoff ? maxBackoff : delay;
    state = state.copyWith(
      phase: SyncPhase.retrying,
      error: error.toString(),
      nextRunAt: _sync.isConfigured ? DateTime.now().add(wait) : null,
    );
    if (_sync.isConfigured) _schedule(wait);
  }

  /// 네트워크·서버 오류와 겹침만 자동으로 다시 시도한다. 키·권한·설정 문제는
  /// 사용자가 고칠 때까지 같은 결과이므로 멈춘다.
  bool _isRetryable(Object error) {
    if (error is SyncWrongKeyException ||
        error is SyncRemoteFormatException ||
        error is FormatException) {
      return false;
    }
    if (error is GitHubSyncException) {
      final status = error.statusCode;
      return status == null || status >= 500 || status == 429;
    }
    return true;
  }

  void _schedule(Duration delay) {
    _scheduled?.cancel();
    _scheduled = Timer(delay, () {
      _scheduled = null;
      if (ref.mounted) unawaited(syncNow());
    });
    if (delay > Duration.zero) {
      state = state.copyWith(nextRunAt: DateTime.now().add(delay));
    }
  }

  void _onTableUpdates(Set<TableUpdate> updates) {
    if (!_autoReady) return;
    final tracked = updates.any(
      (u) => AppDatabase.syncTrackedTables.containsKey(u.table),
    );
    if (tracked) _onLocalChange();
  }

  /// 실행 중에 생긴 변경은 버리지 않고 끝난 뒤 한 번 더 실행한다. 이 실행이
  /// 적용하며 만든 알림이면 다음 실행은 체크포인트로 바로 끝난다.
  void _onLocalChange() {
    if (_running != null) {
      _rerun = true;
    } else {
      _schedule(changeDebounce);
    }
  }

  void _onSettingsChanged(AppSettings? previous, AppSettings next) {
    if (previous == null) return;
    final before = previous.cloudSync;
    final after = next.cloudSync;
    final setupChanged =
        before.enabled != after.enabled ||
        before.encryptionKey != after.encryptionKey ||
        before.github.targetKey != after.github.targetKey ||
        before.github.token != after.github.token;
    if (setupChanged) {
      // 설정을 고쳤으니 멈춰 있던 오류와 기억한 원격 상태를 버린다.
      _checkpoint = null;
      _failures = 0;
      if (state.phase == SyncPhase.blocked ||
          state.phase == SyncPhase.retrying) {
        state = state.copyWith(phase: SyncPhase.idle, error: null);
      }
      if (!after.isConfigured) {
        _scheduled?.cancel();
        _scheduled = null;
        state = state.copyWith(nextRunAt: null);
        return;
      }
    }
    if (!_started || !_autoReady) return;
    if (setupChanged) {
      if (_running != null) {
        _rerun = true;
      } else {
        _schedule(const Duration(seconds: 1));
      }
    } else if (before.settingsUpdatedAt != after.settingsUpdatedAt) {
      _onLocalChange();
    }
  }

  /// 동기화로 바뀐 데이터를 화면 목록에 다시 읽힌다.
  void _refreshSyncedData() {
    ref
      ..invalidate(hostListProvider)
      ..invalidate(snippetListProvider)
      ..invalidate(knownHostListProvider)
      ..invalidate(sshKeyListProvider)
      ..invalidate(identityListProvider);
  }

  void _stop() {
    _scheduled?.cancel();
    _poll?.cancel();
    unawaited(_tableUpdates?.cancel());
  }
}
