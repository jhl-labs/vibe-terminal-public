import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../agent/agent_launcher.dart';
import '../agent/agent_semantic_event.dart';
import '../agent/agent_conflict.dart';
import '../agent/agent_delivery.dart';
import '../agent/agent_delivery_runtime.dart';
import '../agent/agent_source_control.dart';
import '../agent/agent_workspace_test.dart';
import '../agent/agent_workspace_test_runtime.dart';
import '../agent/agent_workspace_test_store.dart';
import '../agent/agent_workspace_run.dart';
import '../agent/agent_workspace_run_runtime.dart';
import '../agent/agent_workspace_run_store.dart';
import '../agent/agent_worktree.dart';
import '../agent/agent_worktree_runtime.dart';
import '../core/result.dart';
import '../data/models/host.dart';
import '../data/repositories/session_log_repository.dart';
import '../local/local_shell_paths.dart';
import '../kubernetes/kubernetes_port_forward_service.dart';
import '../security/host_key_store.dart';
import '../ssh/jump_chain.dart';
import '../ssh/ssh_service.dart';
import '../ssh/remote_session_identity.dart';
import '../ssh/remote_session_catalog.dart';
import '../ssh/remote_terminal_launcher.dart';
import '../state/providers.dart';
import '../terminal/logging_terminal_session_handle.dart';
import '../terminal/terminal_engine.dart';
import '../terminal/terminal_session_handle.dart';
import 'local_session_state_tracker.dart';
import 'remote_session_cleanup_store.dart';
import 'session.dart';
import 'session_activity.dart';
import 'session_attention.dart';
import 'session_diagnostics.dart';
import 'session_group.dart';
import 'session_restore_store.dart';

enum RemoteSessionActivationKind { switchedToExistingTab, openedNewTab }

class RemoteSessionActivation {
  const RemoteSessionActivation({required this.sessionId, required this.kind});

  final String sessionId;
  final RemoteSessionActivationKind kind;
}

/// 다중 SSH 세션 풀을 관리하는 Notifier.
class SessionManager extends Notifier<List<SessionInfo>> {
  @override
  List<SessionInfo> build() {
    _agentWorktreeInitialization = ref
        .read(agentWorktreeStoreProvider)
        .markPreviousRunStranded();
    ref.onDispose(() {
      _persistTimer?.cancel();
      for (final timer in _reconnectTimers.values) {
        timer.cancel();
      }
      for (final engine in _engines.values) {
        engine.dispose();
      }
      for (final forward in _kubernetesForwards.values) {
        unawaited(forward.close());
      }
      for (final run in _runningWorkspaceRuns.values) {
        run.stopRequested = true;
        run.persistTimer?.cancel();
        unawaited(run.handle.stop());
      }
      _runningWorkspaceRuns.clear();
      _kubernetesForwards.clear();
      _engines.clear();
    });
    return const [];
  }

  int _counter = 0;
  String _genId() => 's${_counter++}';
  final Random _secureRandom = Random.secure();
  final Map<String, TerminalEngine> _engines = {};
  final Set<String> _runningWorkspaceTests = {};
  final Set<String> _runningWorkspaceDeliveries = {};
  final Map<String, _ManagedAgentWorkspaceRun> _runningWorkspaceRuns = {};

  String _randomHex(int byteCount) => List.generate(
    byteCount,
    (_) => _secureRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<String> _newRemoteSessionId() async {
    final ownerId = await ref
        .read(remoteSessionIdentityStoreProvider)
        .readOrCreate();
    return RemoteSessionIdentity.compose(
      ownerId: ownerId,
      sessionId: _randomHex(16),
    );
  }

  bool _restoreStarted = false;
  Future<void>? _agentWorktreeInitialization;

  /// pingActiveSessions 재진입 방지 플래그.
  bool _pinging = false;

  /// 자동 재연결 백오프(초). 인덱스 = 시도 횟수. 마지막 값을 상한으로 사용.
  static const _reconnectBackoff = [1, 2, 4, 8, 16, 30];

  /// 자동 재연결 시도 상한. 이 횟수를 넘으면 포기하고, 사용자가 직접
  /// 재연결하도록 둔다. 상한이 없으면 살아나지 않는 호스트에 30초마다 영원히
  /// 접속을 시도해 모바일에서 배터리와 라디오를 계속 깨운다.
  static const _maxReconnectAttempts = 12;

  /// 세션별 예약된 재연결 타이머.
  final Map<String, Timer> _reconnectTimers = {};

  Timer? _persistTimer;

  /// 세션별 연속 재연결 시도 횟수(성공 시 0으로 리셋).
  final Map<String, int> _reconnectAttempts = {};

  /// 사용자가 명시적으로 닫은 세션 id(자동 재연결 금지).
  final Set<String> _userClosed = {};

  /// 세션별 SSH 핸들. SFTP 등 같은 연결 위의 추가 채널에 클라이언트를 제공한다.
  final Map<String, SshSessionHandle> _sshHandles = {};

  /// Kubernetes 경유 SSH 세션과 수명을 같이하는 kubectl port-forward.
  final Map<String, KubernetesPortForwardHandle> _kubernetesForwards = {};

  /// 세션별 복원 메타데이터 추적기.
  final Map<String, LocalSessionStateTracker> _sessionStates = {};

  /// 세션별 현재 로그 id.
  final Map<String, String> _sessionLogIds = {};

  /// 활성 SFTP 등에서 쓸 수 있도록 세션의 SSHClient를 노출한다.
  /// 연결되어 있지 않거나 로컬 셸이면 null.
  SSHClient? sshClientFor(String id) => _sshHandles[id]?.client;

  TerminalEngine _newEngine(String id) {
    // 스크롤백은 터미널 생성 시점에 정해진다. 설정을 바꾸면 이후에 여는
    // 세션부터 적용된다(설정 화면에 그렇게 안내한다).
    final engine = TerminalEngine(
      maxLines: ref.read(appSettingsProvider).terminalScrollbackLines,
    );
    _engines[id] = engine;
    // 서버 출력 활동을 busy/idle 추적기로 전달한다.
    engine.onOutputActivity = () {
      ref
          .read(sessionActivityProvider.notifier)
          .markActivity(id, screen: engine.recentPlainText(maxLines: 80));
      _schedulePersistOpenSessions();
    };
    engine.onSidebandMessage = (message) {
      if (message.channel != AgentSemanticEvent.sidebandChannel) return;
      final event = AgentSemanticEvent.tryParseSideband(message.payload);
      if (event == null) return;
      final session = _sessionById(id);
      final expectedProvider = session?.agentWorkspace?.cli.name;
      // 일반 셸과 다른 Agent 종류가 만든 marker는 상태 신호로 받아들이지 않는다.
      if (expectedProvider == null || event.provider != expectedProvider) {
        return;
      }
      final userIsWatching =
          ref.read(appForegroundProvider) &&
          ref.read(activeSessionIdProvider) == id;
      ref
          .read(sessionAttentionProvider.notifier)
          .applySemanticEvent(id, event, userIsWatching: userIsWatching);
    };
    return engine;
  }

  SessionInfo _newSessionInfo(
    String id,
    Host host, {
    String? title,
    RestoredSessionContext? restoredContext,
    String groupId = defaultSessionGroupId,
    String? remoteSessionId,
    AgentWorkspaceContext? agentWorkspace,
  }) => SessionInfo(
    id: id,
    host: host,
    engine: _newEngine(id),
    title: _cleanTitle(title),
    restoredContext: restoredContext,
    groupId: groupId,
    remoteSessionId: host.keepsRemoteSession ? remoteSessionId : null,
    agentWorkspace: agentWorkspace,
  );

  /// 새 세션을 열고 연결을 시도한다. 생성한 sessionId를 반환한다.
  Future<String> openSession(
    Host host, {
    required Future<bool> Function(String, String, String, HostKeyVerdict)
    onHostKey,
    KeyboardInteractivePrompt? onKeyboardInteractive,
    String? title,
    String groupId = defaultSessionGroupId,
    String? remoteSessionId,
    AgentWorkspaceContext? agentWorkspace,
  }) async {
    final resolvedRemoteSessionId = host.keepsRemoteSession
        ? (remoteSessionId?.trim().isNotEmpty == true
              ? remoteSessionId!.trim()
              : await _newRemoteSessionId())
        : null;
    final id = _genId();
    final session = _newSessionInfo(
      id,
      host,
      title: title,
      groupId: groupId,
      remoteSessionId: resolvedRemoteSessionId,
      agentWorkspace: agentWorkspace,
    );
    final engine = session.engine;
    _configureSessionTracking(id, host, engine);
    state = [...state, session];
    if (session.remoteSessionId != null) _persistOpenSessions();

    if (host.isLocalShell) {
      await _connectLocalSession(id, host, engine);
      return id;
    }

    final routeResult = await _openSshRoute(host);
    final _SshRoute route;
    switch (routeResult) {
      case Ok(:final value):
        route = value;
      case Err(:final failure):
        _markError(id, failure);
        _persistOpenSessions();
        return id;
    }
    if (_userClosed.contains(id) || !state.any((session) => session.id == id)) {
      await route.kubernetesForward?.close();
      return id;
    }
    if (route.kubernetesForward case final forward?) {
      _kubernetesForwards[id] = forward;
    }

    final ssh = ref.read(sshServiceProvider);
    final result = await ssh.connect(
      host: host,
      // 연결 준비 중 UI가 이미 레이아웃됐다면 실제 뷰 크기로 PTY를 시작한다.
      // 특히 실행 중인 tmux TUI 재접속에서 80x24로 축소했다가 즉시 다시 늘리는
      // 불필요한 중간 프레임과 화면 손상을 피한다.
      cols: engine.terminal.viewWidth,
      rows: engine.terminal.viewHeight,
      onHostKey: onHostKey,
      onKeyboardInteractive: onKeyboardInteractive,
      jumpHosts: route.jumpHosts,

      remoteSessionId: session.remoteSessionId,
    );

    // 연결을 준비하는 사이 사용자가 탭을 닫거나 manager가 해제될 수 있다.
    // 명시적 닫기라면 그 사이 만들어진 tmux 작업도 끝내고, 앱 수명 종료라면
    // 전송만 닫아 다음 실행에서 이어갈 수 있게 둔다.
    if (_userClosed.contains(id) || !state.any((item) => item.id == id)) {
      if (result case Ok(:final value)) {
        if (_userClosed.contains(id)) {
          await value.terminatePersistentSession();
        }
        await value.close();
      }
      await _closeKubernetesForward(id);
      return id;
    }

    switch (result) {
      case Ok(:final value):
        _sshHandles[id] = value;
        final handle = await _withSessionLogging(id, host, value);
        engine.attach(
          handle,
          onClosed: () => _handleSshSessionClosed(id, value),
        );
        _markStatus(
          id,
          SessionStatus.connected,
          fellBackToDirectSsh: value.fellBackToDirectSsh,
        );
        _recordRemoteSessionLaunch(id, value);
        unawaited(_markAgentWorktreeActiveIfResumed(session, value));
        _persistOpenSessions();
        unawaited(
          _reconcilePendingRemoteSessionTerminations(
            id,
            host,
            value,
            currentRemoteSessionId: session.remoteSessionId,
          ),
        );
        if (!value.resumedPersistentSession) _runStartupScript(host, engine);
      case Err(:final failure):
        await _closeKubernetesForward(id);
        _markError(id, failure);
        _persistOpenSessions();
    }
    return id;
  }

  Future<Result<_SshRoute>> _openSshRoute(Host host) async {
    if (!host.isKubernetesSsh) {
      if (host.jumpHostId == null) return const Ok(_SshRoute());
      final chain = await resolveJumpChain(
        host,
        ref.read(hostRepositoryProvider).getById,
      );
      return switch (chain) {
        Ok(:final value) => Ok(_SshRoute(jumpHosts: value)),
        Err(:final failure) => Err(failure),
      };
    }

    final namespace = host.kubernetesNamespace?.trim() ?? '';
    final resource = host.kubernetesResource?.trim() ?? '';
    final gatewayUsername = host.kubernetesUsername?.trim() ?? '';
    if (namespace.isEmpty || resource.isEmpty || gatewayUsername.isEmpty) {
      return const Err(
        KubernetesFailure('Kubernetes namespace, 리소스, Pod SSH 사용자명을 확인하세요.'),
      );
    }

    final result = await ref
        .read(kubernetesPortForwardServiceProvider)
        .start(
          KubernetesPortForwardSpec(
            context: host.kubernetesContext,
            namespace: namespace,
            resource: resource,
            remotePort: host.kubernetesSshPort,
          ),
        );
    return switch (result) {
      Ok(:final value) => Ok(
        _SshRoute(
          jumpHosts: [
            Host(
              id: '${host.id}:kubernetes-gateway',
              alias: '${host.alias} · $resource',
              hostname: _kubernetesHostKeyIdentity(host, namespace, resource),
              port: host.kubernetesSshPort,
              username: gatewayUsername,
              authType: host.kubernetesAuthType,
              credentialRef: host.kubernetesCredentialRef,
              transportHostname: value.localHost,
              transportPort: value.localPort,
              createdAt: host.createdAt,
              updatedAt: host.updatedAt,
            ),
          ],
          kubernetesForward: value,
        ),
      ),
      Err(:final failure) => Err(failure),
    };
  }

  String _kubernetesHostKeyIdentity(
    Host host,
    String namespace,
    String resource,
  ) {
    final context = host.kubernetesContext?.trim();
    final cluster = context == null || context.isEmpty
        ? 'current-context'
        : context;
    return 'kubernetes:$cluster:$namespace:$resource';
  }

  Future<void> _closeKubernetesForward(String id) async {
    await _kubernetesForwards.remove(id)?.close();
  }

  /// 실행 중인 세션의 현재 상태를 기준으로 새 세션을 만든다.
  ///
  /// 로컬 셸은 추적 중인 셸 종류와 작업 디렉터리를 시작 옵션으로 넘기고,
  /// SSH는 연결과 시작 스크립트 실행이 끝난 뒤 현재 원격 디렉터리로 이동한다.
  Future<String> duplicateSession(
    String id, {
    required Future<bool> Function(String, String, String, HostKeyVerdict)
    onHostKey,
    KeyboardInteractivePrompt? onKeyboardInteractive,
    AgentWorkspaceContext? agentWorkspace,
  }) async {
    SessionInfo? source;
    for (final session in state) {
      if (session.id == id) source = session;
    }
    if (source == null) return id;

    final tracker = _sessionStates[id];
    final workingDirectory = _cleanWorkingDirectory(
      tracker?.workingDirectory ?? source.restoredContext?.workingDirectory,
    );
    final storedHost =
        await ref.read(hostRepositoryProvider).getById(source.host.id) ??
        source.host;
    final host = source.host.isLocalShell
        ? source.host.copyWith(
            localShellType: tracker?.shellType ?? source.host.localShellType,
            workingDirectory: workingDirectory ?? source.host.workingDirectory,
          )
        : storedHost;

    final duplicateId = await openSession(
      host,
      onHostKey: onHostKey,
      onKeyboardInteractive: onKeyboardInteractive,
      title: source.title,
      groupId: source.groupId,
      agentWorkspace: agentWorkspace,
    );

    if (!host.isLocalShell && workingDirectory != null) {
      final duplicate = _sessionById(duplicateId);
      if (duplicate?.status == SessionStatus.connected) {
        _changeRemoteWorkingDirectory(duplicate!.engine, workingDirectory);
      }
    }
    return duplicateId;
  }

  /// 현재 세션의 연결·작업 위치를 복제하고 선택한 CLI Agent를 실행한다.
  ///
  /// worktree 생성은 사용자가 실행 대화상자에서 명시적으로 선택한 경우에만
  /// 수행한다. 명령 생성은 [AgentLaunchCommandBuilder]에 위임해 세션 관리자가
  /// 셸 문법과 Git 정책을 직접 알지 않도록 한다.
  Future<String> launchAgentSession(
    String id,
    AgentLaunchSpec spec, {
    required Future<bool> Function(String, String, String, HostKeyVerdict)
    onHostKey,
  }) async {
    final source = _sessionById(id);
    if (source == null) return id;

    final shell = _agentShellFlavor(source.host);
    final command = const AgentLaunchCommandBuilder().build(spec, shell);
    AgentWorktreeRecord? worktree;
    var workspace = spec.toWorkspaceContext();
    if (spec.isolatedWorktree) {
      await _agentWorktreeInitialization;
      final workingDirectory = _cleanWorkingDirectory(
        _sessionStates[source.id]?.workingDirectory ??
            source.restoredContext?.workingDirectory ??
            source.host.workingDirectory,
      );
      final location = await _worktreeRuntime.resolveLocation(
        host: source.host,
        preferredSessionId: source.id,
        workingDirectory: workingDirectory,
        spec: spec,
      );
      worktree = AgentWorktreeRecord(
        id: 'aw-${DateTime.now().microsecondsSinceEpoch}-${_randomHex(4)}',
        hostId: source.host.id,
        hostAlias: source.host.alias,
        groupId: source.groupId,
        cli: spec.cli,
        arguments: List.unmodifiable(spec.arguments),
        branchName: spec.branchName!.trim(),
        baseRef: location.baseRef,
        repositoryRoot: location.repositoryRoot,
        worktreePath: location.worktreePath,
        createdAt: DateTime.now(),
        lifecycle: AgentWorktreeLifecycle.provisioning,
      );
      workspace = worktree.toWorkspaceContext();
      await ref.read(agentWorktreeStoreProvider).upsert(worktree);
    }
    final launchedId = await duplicateSession(
      id,
      onHostKey: onHostKey,
      agentWorkspace: workspace,
    );
    final launched = _sessionById(launchedId);
    if (launched?.status != SessionStatus.connected) {
      if (worktree != null) {
        await ref
            .read(agentWorktreeStoreProvider)
            .upsert(
              worktree.copyWith(
                lifecycle: AgentWorktreeLifecycle.stranded,
                lastError: launched?.error ?? 'Agent 세션 연결에 실패했습니다.',
              ),
            );
      }
      return launchedId;
    }

    renameSession(launchedId, '${spec.cli.label} · ${source.displayName}');
    if (worktree != null) {
      final activeWorktree = worktree.copyWith(
        lifecycle: AgentWorktreeLifecycle.active,
        sessionId: launchedId,
        lastError: null,
      );
      await ref.read(agentWorktreeStoreProvider).upsert(activeWorktree);
      unawaited(_inspectAgentWorktreeAfterLaunch(activeWorktree));
    }
    launched!.engine.terminal.textInput(command);
    launched.engine.terminal.keyInput(TerminalKey.enter);
    return launchedId;
  }

  /// Agent의 TUI 입력 상태를 건드리지 않고 같은 작업 디렉터리에서 읽기 전용
  /// Git 상태·diff를 보여주는 별도 셸 세션을 연다.
  Future<String> openAgentReviewSession(
    String id, {
    required Future<bool> Function(String, String, String, HostKeyVerdict)
    onHostKey,
  }) async {
    final source = _sessionById(id);
    if (source == null) return id;
    final shell = _agentShellFlavor(source.host);
    final command = const AgentLaunchCommandBuilder().reviewCommand(shell);
    final reviewId = await duplicateSession(id, onHostKey: onHostKey);
    final review = _sessionById(reviewId);
    if (review?.status != SessionStatus.connected) return reviewId;

    renameSession(reviewId, '변경 검토 · ${source.displayName}');
    review!.engine.terminal.textInput(command);
    review.engine.terminal.keyInput(TerminalKey.enter);
    return reviewId;
  }

  Future<List<AgentWorktreeRecord>> agentWorktrees() async {
    await _agentWorktreeInitialization;
    return ref.read(agentWorktreeStoreProvider).all();
  }

  Future<Host> agentWorkspaceHost(String workspaceId) async {
    await _agentWorktreeInitialization;
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    return _hostForWorktree(entry);
  }

  Future<AgentSourceControlSnapshot> agentSourceControl(
    String workspaceId,
  ) async {
    await _agentWorktreeInitialization;
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    if (entry.lifecycle == AgentWorktreeLifecycle.missing) {
      throw StateError('worktree 경로가 더 이상 존재하지 않습니다.');
    }
    final host = await _hostForWorktree(entry);
    final snapshot = await _worktreeRuntime.sourceControlSnapshot(
      entry: entry,
      host: host,
    );
    _syncWorkspaceConflictAttention(
      entry,
      source: 'git-unresolved:${entry.id}',
      paths: snapshot.files
          .where((file) => file.isConflicted)
          .map((file) => file.path)
          .toList(),
      label: '해결되지 않은 Git 충돌',
    );
    return snapshot;
  }

  Future<AgentConflictSnapshot> agentConflictSnapshot(
    String workspaceId,
  ) async {
    await _agentWorktreeInitialization;
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    if (entry.lifecycle == AgentWorktreeLifecycle.missing) {
      throw StateError('worktree 경로가 더 이상 존재하지 않습니다.');
    }
    final host = await _hostForWorktree(entry);
    final results = await Future.wait<Object>([
      _worktreeRuntime.unresolvedConflicts(entry: entry, host: host),
      _deliveryRuntime.predictedConflictPaths(entry: entry, host: host),
    ]);
    final unresolved = results[0] as List<AgentConflictFile>;
    final predicted = results[1] as List<String>;
    _syncWorkspaceConflictAttention(
      entry,
      source: 'git-unresolved:${entry.id}',
      paths: unresolved.map((file) => file.path).toList(),
      label: '해결되지 않은 Git 충돌',
    );
    _syncWorkspaceConflictAttention(
      entry,
      source: 'git-predicted:${entry.id}',
      paths: predicted,
      label: '병합 시 예상되는 Git 충돌',
    );
    return AgentConflictSnapshot(
      unresolvedFiles: List.unmodifiable(unresolved),
      predictedPaths: List.unmodifiable(predicted),
    );
  }

  Future<AgentFileDiff> agentFileDiff(
    String workspaceId,
    AgentFileChange change,
  ) async {
    await _agentWorktreeInitialization;
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    final host = await _hostForWorktree(entry);
    return _worktreeRuntime.fileDiff(entry: entry, host: host, change: change);
  }

  Future<AgentCommitResult> commitAgentChanges(
    String workspaceId, {
    required Set<String> selectedPaths,
    required String message,
  }) async {
    await _agentWorktreeInitialization;
    if (_runningWorkspaceTests.contains(workspaceId)) {
      throw StateError('테스트가 끝난 뒤 커밋해 주세요.');
    }
    if (_runningWorkspaceDeliveries.contains(workspaceId)) {
      throw StateError('전달 작업이 끝난 뒤 커밋해 주세요.');
    }
    final store = ref.read(agentWorktreeStoreProvider);
    final entry = await store.find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    final host = await _hostForWorktree(entry);
    final result = await _worktreeRuntime.commitSelected(
      entry: entry,
      host: host,
      selectedPaths: selectedPaths,
      message: message,
    );
    await inspectAgentWorktree(workspaceId);
    return result;
  }

  Future<AgentWorkspaceTestState> agentWorkspaceTestState(
    String workspaceId,
  ) async {
    await _agentWorktreeInitialization;
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    final host = await _hostForWorktree(entry);
    final context = await _worktreeRuntime.workspaceTestContext(
      entry: entry,
      host: host,
    );
    final lastResult = await ref
        .read(agentWorkspaceTestStoreProvider)
        .latest(workspaceId);
    return AgentWorkspaceTestState(
      suggestedCommand: lastResult?.command ?? context.suggestedCommand,
      currentFingerprint: context.workspaceFingerprint,
      lastResult: lastResult,
      running: _runningWorkspaceTests.contains(workspaceId),
    );
  }

  Future<AgentWorkspaceTestResult> runAgentWorkspaceTest(
    String workspaceId,
    String command,
  ) async {
    await _agentWorktreeInitialization;
    final normalizedCommand = command.trim();
    if (normalizedCommand.isEmpty) {
      throw StateError('테스트 명령을 입력해 주세요.');
    }
    if (normalizedCommand.contains('\u0000')) {
      throw StateError('테스트 명령에 NUL 문자를 사용할 수 없습니다.');
    }
    if (normalizedCommand.length > 4000) {
      throw StateError('테스트 명령은 4,000자 이하여야 합니다.');
    }
    if (_runningWorkspaceDeliveries.contains(workspaceId)) {
      throw StateError('전달 작업이 끝난 뒤 테스트해 주세요.');
    }
    if (!_runningWorkspaceTests.add(workspaceId)) {
      throw StateError('이 작업공간에서 테스트가 이미 실행 중입니다.');
    }

    AgentWorktreeRecord? entry;
    AgentWorkspaceTestContext? testContext;
    final startedAt = DateTime.now();
    try {
      entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
      if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
      final host = await _hostForWorktree(entry);
      testContext = await _worktreeRuntime.workspaceTestContext(
        entry: entry,
        host: host,
      );
      final process = await AgentWorkspaceTestRuntime(_runRemoteAgentTest).run(
        host: host,
        preferredSessionId: entry.sessionId,
        command: normalizedCommand,
        workingDirectory: entry.worktreePath,
      );
      final outcome = process.timedOut
          ? AgentWorkspaceTestOutcome.timedOut
          : process.exitCode == 0
          ? AgentWorkspaceTestOutcome.passed
          : AgentWorkspaceTestOutcome.failed;
      final output = _formatAgentTestOutput(process);
      final result = AgentWorkspaceTestResult(
        workspaceId: workspaceId,
        command: normalizedCommand,
        outcome: outcome,
        exitCode: process.exitCode,
        output: output,
        outputTruncated: process.outputTruncated,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        headSha: testContext.headSha,
        workspaceFingerprint: testContext.workspaceFingerprint,
      );
      await ref.read(agentWorkspaceTestStoreProvider).save(result);
      return result;
    } catch (error) {
      final context = testContext;
      if (entry != null && context != null) {
        final result = AgentWorkspaceTestResult(
          workspaceId: workspaceId,
          command: normalizedCommand,
          outcome: AgentWorkspaceTestOutcome.error,
          exitCode: null,
          output: '$error'.replaceFirst('Bad state: ', ''),
          outputTruncated: false,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          headSha: context.headSha,
          workspaceFingerprint: context.workspaceFingerprint,
        );
        try {
          await ref.read(agentWorkspaceTestStoreProvider).save(result);
        } catch (_) {
          // 원래 실행 오류를 저장소 오류로 가리지 않는다.
        }
      }
      rethrow;
    } finally {
      _runningWorkspaceTests.remove(workspaceId);
    }
  }

  Future<AgentWorkspaceRunState> agentWorkspaceRunState(
    String workspaceId,
  ) async {
    await _agentWorktreeInitialization;
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    final active = _runningWorkspaceRuns[workspaceId];
    if (active != null) {
      return AgentWorkspaceRunState(
        suggestedCommand: active.record.command,
        currentFingerprint: active.record.workspaceFingerprint,
        lastRun: active.record,
      );
    }
    final host = await _hostForWorktree(entry);
    final context = await _worktreeRuntime.workspaceRunContext(
      entry: entry,
      host: host,
    );
    var latest = await ref
        .read(agentWorkspaceRunStoreProvider)
        .latest(workspaceId);
    if (latest?.running == true) {
      latest = latest!.copyWith(
        outcome: AgentWorkspaceRunOutcome.stopped,
        output: '${latest.output.trimRight()}\n\n[앱 종료로 실행 연결이 끝났습니다.]',
        finishedAt: DateTime.now(),
      );
      await ref.read(agentWorkspaceRunStoreProvider).save(latest);
    }
    return AgentWorkspaceRunState(
      suggestedCommand: latest?.command ?? context.suggestedCommand,
      currentFingerprint: context.workspaceFingerprint,
      lastRun: latest,
    );
  }

  Future<AgentWorkspaceRunRecord> startAgentWorkspaceRun(
    String workspaceId,
    String command,
  ) async {
    await _agentWorktreeInitialization;
    final normalizedCommand = command.trim();
    if (normalizedCommand.isEmpty) {
      throw StateError('실행 명령을 입력해 주세요.');
    }
    if (normalizedCommand.contains('\u0000')) {
      throw StateError('실행 명령에 NUL 문자를 사용할 수 없습니다.');
    }
    if (normalizedCommand.length > 4000) {
      throw StateError('실행 명령은 4,000자 이하여야 합니다.');
    }
    if (_runningWorkspaceDeliveries.contains(workspaceId)) {
      throw StateError('전달 작업이 끝난 뒤 실행해 주세요.');
    }
    if (_runningWorkspaceRuns.containsKey(workspaceId)) {
      throw StateError('이 작업공간의 개발 서버가 이미 실행 중입니다.');
    }
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    final host = await _hostForWorktree(entry);
    final context = await _worktreeRuntime.workspaceRunContext(
      entry: entry,
      host: host,
    );
    final startedAt = DateTime.now();
    AgentWorkspaceRunHandle? handle;
    try {
      handle = await AgentWorkspaceRunRuntime(_startRemoteAgentWorkspaceRun)
          .start(
            host: host,
            preferredSessionId: entry.sessionId,
            command: normalizedCommand,
            workingDirectory: entry.worktreePath,
          );
      final record = AgentWorkspaceRunRecord(
        workspaceId: workspaceId,
        command: normalizedCommand,
        outcome: AgentWorkspaceRunOutcome.running,
        output: '',
        outputTruncated: false,
        urls: const [],
        startedAt: startedAt,
        headSha: context.headSha,
        workspaceFingerprint: context.workspaceFingerprint,
      );
      final runStore = ref.read(agentWorkspaceRunStoreProvider);
      final managed = _ManagedAgentWorkspaceRun(
        handle: handle,
        record: record,
        store: runStore,
      );
      _runningWorkspaceRuns[workspaceId] = managed;
      managed.stdoutSubscription = const Utf8Decoder(allowMalformed: true)
          .bind(handle.stdout)
          .listen((chunk) => _appendAgentRunOutput(workspaceId, chunk));
      managed.stdoutDone = managed.stdoutSubscription!.asFuture<void>();
      managed.stderrSubscription = const Utf8Decoder(allowMalformed: true)
          .bind(handle.stderr)
          .listen((chunk) => _appendAgentRunOutput(workspaceId, chunk));
      managed.stderrDone = managed.stderrSubscription!.asFuture<void>();
      await runStore.save(record);
      unawaited(_watchAgentWorkspaceRun(workspaceId, managed));
      return record;
    } catch (error) {
      await handle?.stop();
      final failed = AgentWorkspaceRunRecord(
        workspaceId: workspaceId,
        command: normalizedCommand,
        outcome: AgentWorkspaceRunOutcome.failed,
        output: '$error'.replaceFirst('Bad state: ', ''),
        outputTruncated: false,
        urls: const [],
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        headSha: context.headSha,
        workspaceFingerprint: context.workspaceFingerprint,
      );
      await ref.read(agentWorkspaceRunStoreProvider).save(failed);
      rethrow;
    }
  }

  Future<AgentWorkspaceRunRecord> restartAgentWorkspaceRun(
    String workspaceId,
    String command,
  ) async {
    if (_runningWorkspaceRuns.containsKey(workspaceId)) {
      await stopAgentWorkspaceRun(workspaceId);
    }
    return startAgentWorkspaceRun(workspaceId, command);
  }

  Future<void> stopAgentWorkspaceRun(String workspaceId) async {
    final managed = _runningWorkspaceRuns[workspaceId];
    if (managed == null) return;
    managed.stopRequested = true;
    await managed.handle.stop();
    await managed.completed.future;
  }

  void _appendAgentRunOutput(String workspaceId, String chunk) {
    final managed = _runningWorkspaceRuns[workspaceId];
    if (managed == null || chunk.isEmpty) return;
    final clean = chunk.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    var output = '${managed.record.output}$clean';
    var truncated = managed.record.outputTruncated;
    if (output.length > _ManagedAgentWorkspaceRun.maximumOutputCharacters) {
      output = output.substring(
        output.length - _ManagedAgentWorkspaceRun.maximumOutputCharacters,
      );
      truncated = true;
    }
    final urls = <Uri>{
      ...managed.record.urls,
      ...extractAgentWorkspaceRunUrls('${managed.urlTail}$clean'),
    }.toList();
    managed.urlTail = '${managed.urlTail}$clean';
    if (managed.urlTail.length > 2048) {
      managed.urlTail = managed.urlTail.substring(
        managed.urlTail.length - 2048,
      );
    }
    managed.record = managed.record.copyWith(
      output: output,
      outputTruncated: truncated,
      urls: urls,
    );
    managed.persistTimer?.cancel();
    managed.persistTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(managed.store.save(managed.record));
    });
  }

  Future<void> _watchAgentWorkspaceRun(
    String workspaceId,
    _ManagedAgentWorkspaceRun managed,
  ) async {
    int? exitCode;
    try {
      exitCode = await managed.handle.done;
      await Future.wait([
        if (managed.stdoutDone != null) managed.stdoutDone!,
        if (managed.stderrDone != null) managed.stderrDone!,
      ]).timeout(const Duration(seconds: 2));
    } catch (error) {
      _appendAgentRunOutput(workspaceId, '\n[실행 스트림 오류: $error]\n');
    } finally {
      managed.persistTimer?.cancel();
      managed.record = managed.record.copyWith(
        outcome: managed.stopRequested
            ? AgentWorkspaceRunOutcome.stopped
            : exitCode == 0
            ? AgentWorkspaceRunOutcome.exited
            : AgentWorkspaceRunOutcome.failed,
        finishedAt: DateTime.now(),
        exitCode: exitCode,
      );
      await managed.store.save(managed.record);
      if (identical(_runningWorkspaceRuns[workspaceId], managed)) {
        _runningWorkspaceRuns.remove(workspaceId);
      }
      if (!managed.completed.isCompleted) managed.completed.complete();
    }
  }

  Future<AgentDeliveryPreview> agentDeliveryPreview(String workspaceId) async {
    await _agentWorktreeInitialization;
    final entry = await ref.read(agentWorktreeStoreProvider).find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
    if (entry.lifecycle == AgentWorktreeLifecycle.missing) {
      throw StateError('worktree 경로가 더 이상 존재하지 않습니다.');
    }
    final host = await _hostForWorktree(entry);
    final preview = await _deliveryRuntime.preview(entry: entry, host: host);
    _syncWorkspaceConflictAttention(
      entry,
      source: 'git-predicted:${entry.id}',
      paths: preview.conflictPaths,
      label: '병합 시 예상되는 Git 충돌',
    );
    return preview;
  }

  void _syncWorkspaceConflictAttention(
    AgentWorktreeRecord entry, {
    required String source,
    required List<String> paths,
    required String label,
  }) {
    final tracker = ref.read(sessionAttentionProvider.notifier);
    for (final session in state.where(
      (candidate) =>
          candidate.status == SessionStatus.connected &&
          candidate.agentWorkspace?.workspaceId == entry.id,
    )) {
      if (paths.isEmpty) {
        tracker.clearExternalBlock(session.id, source);
      } else {
        tracker.markExternalBlocked(
          session.id,
          source: source,
          message: '$label ${paths.length}개 · Agent 입력 필요',
          agentHint: entry.cli.name,
        );
      }
    }
  }

  Future<AgentDeliveryResult> mergeAgentWorkspace(String workspaceId) =>
      _runAgentDelivery(
        workspaceId,
        (entry, host) =>
            _deliveryRuntime.mergeFastForward(entry: entry, host: host),
        inspectAfter: true,
      );

  Future<AgentDeliveryResult> pushAgentWorkspace(String workspaceId) =>
      _runAgentDelivery(
        workspaceId,
        (entry, host) => _deliveryRuntime.pushBranch(entry: entry, host: host),
      );

  Future<AgentDeliveryResult> createAgentPullRequest(
    String workspaceId,
    AgentPullRequestDraft draft,
  ) => _runAgentDelivery(
    workspaceId,
    (entry, host) => _deliveryRuntime.createPullRequest(
      entry: entry,
      host: host,
      draft: draft,
    ),
  );

  Future<T> _runAgentDelivery<T>(
    String workspaceId,
    Future<T> Function(AgentWorktreeRecord entry, Host host) action, {
    bool inspectAfter = false,
  }) async {
    await _agentWorktreeInitialization;
    if (_runningWorkspaceTests.contains(workspaceId)) {
      throw StateError('테스트가 끝난 뒤 전달해 주세요.');
    }
    if (!_runningWorkspaceDeliveries.add(workspaceId)) {
      throw StateError('이 작업공간에서 전달 작업이 이미 실행 중입니다.');
    }
    try {
      final testState = await agentWorkspaceTestState(workspaceId);
      final test = testState.lastResult;
      if (test == null) {
        throw StateError('전달 전에 workspace 검증을 실행해 주세요.');
      }
      if (testState.isStale) {
        throw StateError('변경된 workspace를 다시 검증한 뒤 전달해 주세요.');
      }
      if (!test.passed) {
        throw StateError('통과한 workspace 검증이 필요합니다.');
      }
      final entry = await ref
          .read(agentWorktreeStoreProvider)
          .find(workspaceId);
      if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');
      final host = await _hostForWorktree(entry);
      final result = await action(entry, host);
      if (inspectAfter) await inspectAgentWorktree(workspaceId);
      return result;
    } finally {
      _runningWorkspaceDeliveries.remove(workspaceId);
    }
  }

  /// 저장된 worktree의 실제 Git 상태를 로컬 프로세스 또는 현재 SSH 연결로
  /// 확인한다. 화면 텍스트가 아니라 Git exit code를 사용한다.
  Future<AgentWorktreeRecord> inspectAgentWorktree(String workspaceId) async {
    await _agentWorktreeInitialization;
    final store = ref.read(agentWorktreeStoreProvider);
    final entry = await store.find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');

    try {
      final host = await _hostForWorktree(entry);
      final result = await _worktreeRuntime.inspect(entry: entry, host: host);
      if (!result.exists) {
        final missing = entry.copyWith(
          lifecycle: AgentWorktreeLifecycle.missing,
          gitState: AgentWorktreeGitState.unknown,
          sessionId: null,
          lastInspectedAt: DateTime.now(),
          lastError: null,
        );
        await store.upsert(missing);
        return missing;
      }

      final activeSession = state.any(
        (session) =>
            entry.sessionId != null &&
            session.id == entry.sessionId &&
            session.status == SessionStatus.connected &&
            session.agentWorkspace?.workspaceId == entry.id,
      );
      final inspected = entry.copyWith(
        lifecycle: activeSession
            ? AgentWorktreeLifecycle.active
            : AgentWorktreeLifecycle.stranded,
        gitState: result.gitState,
        sessionId: activeSession ? entry.sessionId : null,
        lastInspectedAt: DateTime.now(),
        lastError: null,
      );
      await store.upsert(inspected);
      return inspected;
    } catch (error) {
      final failed = entry.copyWith(
        lastInspectedAt: DateTime.now(),
        lastError: '$error'.replaceFirst('Bad state: ', ''),
      );
      await store.upsert(failed);
      rethrow;
    }
  }

  /// 중단된 worktree에서 원래 Agent CLI를 다시 실행한다. 기존 브랜치나
  /// worktree를 새로 만들지 않는다.
  Future<String> resumeAgentWorktree(
    String workspaceId, {
    required Future<bool> Function(String, String, String, HostKeyVerdict)
    onHostKey,
  }) async {
    await _agentWorktreeInitialization;
    final store = ref.read(agentWorktreeStoreProvider);
    var entry = await store.find(workspaceId);
    if (entry == null) throw StateError('Agent 작업공간 기록을 찾을 수 없습니다.');

    SessionInfo? reusableShell;
    for (final session in state) {
      if (entry.sessionId != null &&
          session.id == entry.sessionId &&
          session.status == SessionStatus.connected &&
          session.agentWorkspace?.workspaceId == workspaceId) {
        return session.id;
      }
      if (session.status == SessionStatus.connected &&
          session.agentWorkspace?.workspaceId == workspaceId) {
        reusableShell ??= session;
      }
    }

    final host = await _hostForWorktree(entry);
    ref
        .read(sessionGroupProvider.notifier)
        .ensureGroup(entry.groupId, name: 'Agent 작업');
    final launchHost = host.isLocalShell
        ? host.copyWith(workingDirectory: entry.worktreePath)
        : host;
    final String sessionId;
    final SessionInfo session;
    if (reusableShell != null) {
      sessionId = reusableShell.id;
      session = reusableShell;
      renameSession(sessionId, '${entry.cli.label} · ${entry.branchName}');
    } else {
      sessionId = await openSession(
        launchHost,
        onHostKey: onHostKey,
        title: '${entry.cli.label} · ${entry.branchName}',
        groupId: entry.groupId,
        agentWorkspace: entry.toWorkspaceContext(),
      );
      final opened = _sessionById(sessionId);
      if (opened?.status != SessionStatus.connected) {
        throw StateError(opened?.error ?? 'Agent 작업공간에 연결하지 못했습니다.');
      }
      session = opened!;
    }

    entry = entry.copyWith(
      lifecycle: AgentWorktreeLifecycle.active,
      sessionId: sessionId,
      lastError: null,
    );
    await store.upsert(entry);
    try {
      entry = await inspectAgentWorktree(workspaceId);
    } catch (_) {
      closeSession(sessionId);
      rethrow;
    }
    if (entry.lifecycle == AgentWorktreeLifecycle.missing) {
      closeSession(sessionId);
      throw StateError('worktree 경로가 더 이상 존재하지 않습니다.');
    }

    // tmux가 복원한 원격 세션에는 기존 Agent 프로세스가 이미 살아 있다.
    // 같은 CLI를 중복 실행하지 않고 해당 탭을 활성화하는 것으로 재개한다.
    if (!session.host.isLocalShell &&
        _sshHandles[sessionId]?.resumedPersistentSession == true) {
      return sessionId;
    }

    final shell = _agentShellFlavor(session.host);
    final invocation = const AgentLaunchCommandBuilder().invocation(
      AgentLaunchSpec(cli: entry.cli, arguments: entry.arguments),
      shell,
    );
    if (!session.host.isLocalShell) {
      session.engine.terminal.textInput(
        'cd ${_posixWorkingDirectoryArgument(entry.worktreePath)} && $invocation',
      );
    } else {
      session.engine.terminal.textInput(invocation);
    }
    session.engine.terminal.keyInput(TerminalKey.enter);
    return sessionId;
  }

  /// clean + merged인 중단 worktree만 제거한다. 브랜치는 보존한다.
  Future<void> cleanupAgentWorktree(String workspaceId) async {
    if (_runningWorkspaceTests.contains(workspaceId)) {
      throw StateError('테스트가 끝난 뒤 worktree를 정리해 주세요.');
    }
    if (_runningWorkspaceDeliveries.contains(workspaceId)) {
      throw StateError('전달 작업이 끝난 뒤 worktree를 정리해 주세요.');
    }
    if (_runningWorkspaceRuns.containsKey(workspaceId)) {
      throw StateError('개발 서버를 중지한 뒤 worktree를 정리해 주세요.');
    }
    final store = ref.read(agentWorktreeStoreProvider);
    final attachedSession = state.any(
      (session) =>
          session.status == SessionStatus.connected &&
          session.agentWorkspace?.workspaceId == workspaceId,
    );
    if (attachedSession) {
      throw StateError('이 worktree를 사용하는 세션을 먼저 닫아 주세요.');
    }
    final inspected = await inspectAgentWorktree(workspaceId);
    if (inspected.lifecycle == AgentWorktreeLifecycle.active) {
      throw StateError('실행 중인 Agent 세션을 먼저 닫아 주세요.');
    }
    if (inspected.lifecycle == AgentWorktreeLifecycle.missing) {
      await store.remove(workspaceId);
      await ref.read(agentWorkspaceTestStoreProvider).remove(workspaceId);
      await ref.read(agentWorkspaceRunStoreProvider).remove(workspaceId);
      return;
    }
    if (inspected.gitState == AgentWorktreeGitState.dirty) {
      throw StateError('커밋하지 않은 변경이 있어 worktree를 정리할 수 없습니다.');
    }
    if (inspected.gitState != AgentWorktreeGitState.merged) {
      throw StateError('기준 브랜치에 병합되지 않은 commit이 있어 정리할 수 없습니다.');
    }

    final host = await _hostForWorktree(inspected);
    await _worktreeRuntime.remove(entry: inspected, host: host);
    await store.remove(workspaceId);
    await ref.read(agentWorkspaceTestStoreProvider).remove(workspaceId);
    await ref.read(agentWorkspaceRunStoreProvider).remove(workspaceId);
  }

  AgentWorktreeRuntime get _worktreeRuntime =>
      AgentWorktreeRuntime(_runRemoteGit);

  AgentDeliveryRuntime get _deliveryRuntime =>
      AgentDeliveryRuntime(_runRemoteAgentDelivery);

  Future<AgentTestProcessResult> _runRemoteAgentTest({
    required Host host,
    required String? preferredSessionId,
    required String command,
    required String workingDirectory,
    required Duration timeout,
  }) async {
    SshSessionHandle? handle;
    if (preferredSessionId != null) handle = _sshHandles[preferredSessionId];
    if (handle == null) {
      for (final session in state) {
        if (session.host.id == host.id &&
            session.status == SessionStatus.connected &&
            _sshHandles[session.id] != null) {
          handle = _sshHandles[session.id];
          break;
        }
      }
    }
    if (handle == null) {
      throw StateError('${host.alias}에 연결된 세션이 필요합니다.');
    }

    final remoteCommand =
        'cd ${_posixWorkingDirectoryArgument(workingDirectory)} && '
        '(\n$command\n)';
    final remoteSession = await handle.client.execute(remoteCommand);
    final stdout = AgentBoundedOutputCollector(
      AgentWorkspaceTestRuntime.maximumOutputCharacters ~/ 2,
    )..listen(remoteSession.stdout);
    final stderr = AgentBoundedOutputCollector(
      AgentWorkspaceTestRuntime.maximumOutputCharacters ~/ 2,
    )..listen(remoteSession.stderr);
    var timedOut = false;
    try {
      await remoteSession.done.timeout(timeout);
      await Future.wait([stdout.done, stderr.done]);
    } on TimeoutException {
      timedOut = true;
      remoteSession.kill(SSHSignal.TERM);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      remoteSession.close();
      await stdout.cancel();
      await stderr.cancel();
    }
    return AgentTestProcessResult(
      exitCode: remoteSession.exitCode,
      stdout: stdout.text,
      stderr: stderr.text,
      timedOut: timedOut,
      outputTruncated: stdout.truncated || stderr.truncated,
    );
  }

  Future<AgentWorkspaceRunHandle> _startRemoteAgentWorkspaceRun({
    required Host host,
    required String? preferredSessionId,
    required String command,
    required String workingDirectory,
  }) async {
    SshSessionHandle? handle;
    if (preferredSessionId != null) handle = _sshHandles[preferredSessionId];
    if (handle == null) {
      for (final session in state) {
        if (session.host.id == host.id &&
            session.status == SessionStatus.connected &&
            _sshHandles[session.id] != null) {
          handle = _sshHandles[session.id];
          break;
        }
      }
    }
    if (handle == null) {
      throw StateError('${host.alias}에 연결된 세션이 필요합니다.');
    }
    final remoteCommand =
        'cd ${_posixWorkingDirectoryArgument(workingDirectory)} && '
        '(\n$command\n)';
    final session = await handle.client.execute(remoteCommand);
    return _RemoteAgentWorkspaceRunHandle(session);
  }

  String _formatAgentTestOutput(AgentTestProcessResult process) {
    final parts = <String>[];
    if (process.timedOut) {
      parts.add('[15분 제한을 넘어 테스트를 종료했습니다.]');
    }
    if (process.stdout.trim().isNotEmpty) parts.add(process.stdout.trimRight());
    if (process.stderr.trim().isNotEmpty) {
      parts.add('[stderr]\n${process.stderr.trimRight()}');
    }
    if (parts.isEmpty) return '(출력 없음)';
    final output = parts.join('\n\n');
    return process.outputTruncated
        ? '[출력이 커서 마지막 일부만 보존했습니다.]\n\n$output'
        : output;
  }

  Future<AgentGitResult> _runRemoteGit({
    required Host host,
    required String? preferredSessionId,
    required List<String> arguments,
    required String? workingDirectory,
  }) async {
    final directory = workingDirectory?.trim();
    SshSessionHandle? handle;
    if (preferredSessionId != null) handle = _sshHandles[preferredSessionId];
    if (handle == null) {
      for (final session in state) {
        if (session.host.id == host.id &&
            session.status == SessionStatus.connected &&
            _sshHandles[session.id] != null) {
          handle = _sshHandles[session.id];
          break;
        }
      }
    }
    if (handle == null) {
      throw StateError('${host.alias}에 연결된 세션이 필요합니다.');
    }
    final command = [
      'git',
      if (directory != null && directory.isNotEmpty) ...[
        '-C',
        _posixWorkingDirectoryArgument(directory),
      ],
      for (final argument in arguments) _quotePosixShellWord(argument),
    ].join(' ');
    final result = await handle.client
        .runWithResult(command)
        .timeout(const Duration(seconds: 45));
    return AgentGitResult(
      exitCode: result.exitCode ?? -1,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  }

  Future<AgentDeliveryProcessResult> _runRemoteAgentDelivery({
    required Host host,
    required String? preferredSessionId,
    required String executable,
    required List<String> arguments,
    required String? workingDirectory,
    required Duration timeout,
  }) async {
    SshSessionHandle? handle;
    if (preferredSessionId != null) handle = _sshHandles[preferredSessionId];
    if (handle == null) {
      for (final session in state) {
        if (session.host.id == host.id &&
            session.status == SessionStatus.connected &&
            _sshHandles[session.id] != null) {
          handle = _sshHandles[session.id];
          break;
        }
      }
    }
    if (handle == null) {
      throw StateError('${host.alias}에 연결된 세션이 필요합니다.');
    }
    final directory = workingDirectory?.trim();
    final invocation = [
      executable,
      for (final argument in arguments) _quotePosixShellWord(argument),
    ].join(' ');
    final command = directory == null || directory.isEmpty
        ? invocation
        : 'cd ${_posixWorkingDirectoryArgument(directory)} && $invocation';
    final result = await handle.client.runWithResult(command).timeout(timeout);
    return AgentDeliveryProcessResult(
      exitCode: result.exitCode ?? -1,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  }

  Future<Host> _hostForWorktree(AgentWorktreeRecord entry) async {
    for (final session in state) {
      if (session.host.id == entry.hostId) return session.host;
    }
    final host = await ref.read(hostRepositoryProvider).getById(entry.hostId);
    if (host == null) throw StateError('${entry.hostAlias} 호스트 설정을 찾을 수 없습니다.');
    return host;
  }

  Future<void> _inspectAgentWorktreeAfterLaunch(
    AgentWorktreeRecord entry,
  ) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      try {
        final inspected = await inspectAgentWorktree(entry.id);
        if (inspected.lifecycle != AgentWorktreeLifecycle.missing) return;
      } catch (_) {
        // 생성 명령과 경합할 수 있으므로 짧게 재시도한다.
      }
    }
  }

  Future<void> _markAgentWorktreeActiveIfResumed(
    SessionInfo session,
    SshSessionHandle handle,
  ) async {
    final workspaceId = session.agentWorkspace?.workspaceId;
    if (workspaceId == null || !handle.resumedPersistentSession) return;
    final store = ref.read(agentWorktreeStoreProvider);
    final entry = await store.find(workspaceId);
    if (entry == null) return;
    await store.upsert(
      entry.copyWith(
        lifecycle: AgentWorktreeLifecycle.active,
        sessionId: session.id,
        lastError: null,
      ),
    );
  }

  Future<void> _markAgentWorktreeStranded(
    String workspaceId,
    String closingSessionId,
  ) async {
    await _agentWorktreeInitialization;
    final stillActive = state.any(
      (session) =>
          session.id != closingSessionId &&
          session.status == SessionStatus.connected &&
          session.agentWorkspace?.workspaceId == workspaceId,
    );
    if (stillActive) return;
    final store = ref.read(agentWorktreeStoreProvider);
    final entry = await store.find(workspaceId);
    if (entry == null) return;
    await store.upsert(
      entry.copyWith(
        lifecycle: AgentWorktreeLifecycle.stranded,
        sessionId: null,
      ),
    );
  }

  AgentShellFlavor _agentShellFlavor(Host host) {
    if (!host.isLocalShell || !Platform.isWindows) {
      return AgentShellFlavor.posix;
    }
    return switch (host.localShellType) {
      LocalShellType.powershell => AgentShellFlavor.powershell,
      LocalShellType.cmd => AgentShellFlavor.cmd,
      LocalShellType.wsl => AgentShellFlavor.posix,
    };
  }

  SessionInfo? _sessionById(String id) {
    for (final session in state) {
      if (session.id == id) return session;
    }
    return null;
  }

  void _changeRemoteWorkingDirectory(
    TerminalEngine engine,
    String workingDirectory,
  ) {
    engine.terminal.textInput(
      'cd ${_posixWorkingDirectoryArgument(workingDirectory)}',
    );
    engine.terminal.keyInput(TerminalKey.enter);
  }

  String _posixWorkingDirectoryArgument(String workingDirectory) {
    if (workingDirectory == '~') return '~';
    if (workingDirectory.startsWith('~/')) {
      return '~/${_quotePosixShellWord(workingDirectory.substring(2))}';
    }
    return _quotePosixShellWord(workingDirectory);
  }

  String _quotePosixShellWord(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  String? _cleanWorkingDirectory(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  /// Android가 Activity/Flutter 상태를 재생성하면 인메모리 세션 목록과 SSH
  /// 소켓은 사라진다. 마지막으로 연결됐던 원격 세션 탭을 복원하고, 이미 핀된
  /// 호스트키가 일치하는 경우에만 자동 재연결한다.
  Future<void> restoreSavedSessions() async {
    if (_restoreStarted || state.isNotEmpty) return;
    _restoreStarted = true;
    await _agentWorktreeInitialization;

    final snapshot = await ref.read(sessionRestoreStoreProvider).load();
    if (snapshot == null || state.isNotEmpty) return;
    ref.read(sessionGroupProvider.notifier).restoreFromSnapshot(snapshot);
    if (snapshot.sessions.isEmpty) return;

    final restored = <SessionInfo>[];
    final usedIds = <String>{};
    for (final entry in snapshot.sessions) {
      final host = await ref.read(hostRepositoryProvider).getById(entry.hostId);
      if (host == null) continue;
      var id = entry.id;
      if (usedIds.contains(id)) id = _genId();
      usedIds.add(id);
      _reserveCounterFor(id);
      final restoredHost = host.isLocalShell
          ? _hostForRestoredLocalSession(host, entry)
          : host;
      // 호스트 설정을 나중에 켰다는 이유만으로 기존 복원 탭 전체를 tmux
      // 세션으로 소급 전환하지 않는다. 저장 당시 이미 원격 세션 ID가 있던
      // 탭만 이어가고, 새 설정은 이후 새 연결/명시적 재시도부터 적용한다.
      final sessionHost =
          !restoredHost.isLocalShell &&
              restoredHost.keepsRemoteSession &&
              entry.remoteSessionId == null
          ? restoredHost.copyWith(
              remoteSessionPersistence: RemoteSessionPersistence.none,
            )
          : restoredHost;
      if (!sessionHost.keepsRemoteSession && entry.remoteSessionId != null) {
        await _queueRemoteSessionTermination(
          sessionHost.id,
          entry.remoteSessionId!,
        );
      }
      final restoredContext = _restoredContextFor(entry, sessionHost);
      final session = _newSessionInfo(
        id,
        sessionHost,
        title: entry.title,
        restoredContext: restoredContext,
        groupId: entry.groupId,
        remoteSessionId: sessionHost.keepsRemoteSession
            ? entry.remoteSessionId
            : null,
        agentWorkspace: entry.agentWorkspace,
      );
      if (!sessionHost.keepsRemoteSession) {
        session.engine.restorePlainText(entry.terminalText);
      }
      _configureSessionTracking(
        id,
        sessionHost,
        session.engine,
        restoredEntry: entry,
      );
      restored.add(session);
    }
    if (restored.isEmpty || state.isNotEmpty) return;

    state = restored;
    final activeId = snapshot.activeId;
    ref
        .read(activeSessionIdProvider.notifier)
        .set(
          restored.any((s) => s.id == activeId)
              ? activeId
              : _firstSessionIdInGroup(restored, snapshot.activeGroupId) ??
                    restored.first.id,
        );
    _persistOpenSessions();

    for (final session in restored) {
      if (session.host.isLocalShell) {
        unawaited(
          _connectLocalSession(
            session.id,
            session.host,
            session.engine,
            runStartupScript: false,
          ),
        );
      } else {
        unawaited(_reconnect(session.id));
      }
    }
  }

  /// 실패한 세션을 닫고 같은 호스트로 다시 연결한다. 연결 실패 후 사용자가
  /// 호스트 정보를 수정했을 수 있으므로, 세션 생성 시점에 캡처한 스냅샷이
  /// 아니라 DB에서 최신 호스트를 다시 읽어 연결한다. 호스트가 삭제됐으면
  /// 기존 세션의 호스트로 폴백한다. 생성한 새 sessionId를 반환한다.
  Future<String> retrySession(
    String id, {
    required Future<bool> Function(String, String, String, HostKeyVerdict)
    onHostKey,
    KeyboardInteractivePrompt? onKeyboardInteractive,
  }) async {
    SessionInfo? session;
    for (final s in state) {
      if (s.id == id) session = s;
    }
    if (session == null) return id;

    final latest = await ref
        .read(hostRepositoryProvider)
        .getById(session.host.id);
    final host = latest ?? session.host;
    final title = session.title;
    final remoteSessionId = session.remoteSessionId;

    closeSession(id);
    return openSession(
      host,
      onHostKey: onHostKey,
      onKeyboardInteractive: onKeyboardInteractive,
      title: title,
      groupId: session.groupId,
      remoteSessionId: remoteSessionId,
    );
  }

  /// 호스트에 등록된 시작 스크립트가 있으면 세션 연결 직후 한 번 실행한다.
  /// 자동 재연결 시에는 다시 실행하지 않는다("세션 시작" 시점에만). 여러 줄은
  /// 각 줄을 입력 후 Enter로 순차 실행한다.
  void _runStartupScript(Host host, TerminalEngine engine) {
    final script = host.startupScript?.trim();
    if (script == null || script.isEmpty) return;
    for (final line in script.split(RegExp(r'\r\n|\r|\n'))) {
      engine.terminal.textInput(line);
      engine.terminal.keyInput(TerminalKey.enter);
    }
  }

  void _configureSessionTracking(
    String id,
    Host host,
    TerminalEngine engine, {
    RestoredSessionEntry? restoredEntry,
  }) {
    final tracker = LocalSessionStateTracker(
      host,
      restoredShellType: restoredEntry?.localShellType,
      restoredWorkingDirectory: restoredEntry?.currentWorkingDirectory,
    );
    _sessionStates[id] = tracker;
    engine.onInput = (data) {
      if (data.contains('\r') || data.contains('\n')) {
        ref.read(sessionActivityProvider.notifier).markTaskSubmitted(id);
      }
      final current = _sessionStates[id];
      if (current == null) return;
      if (current.handleInput(data)) {
        _schedulePersistOpenSessions();
      }
    };
  }

  Future<void> _connectLocalSession(
    String id,
    Host host,
    TerminalEngine engine, {
    bool runStartupScript = true,
  }) async {
    final local = ref.read(localTerminalServiceProvider);
    final result = await local.start(
      host: host,
      cols: engine.terminal.viewWidth,
      rows: engine.terminal.viewHeight,
    );
    switch (result) {
      case Ok(:final value):
        final handle = await _withSessionLogging(id, host, value);
        engine.attach(
          handle,
          onClosed: () {
            _markStatus(id, SessionStatus.disconnected);
            _persistOpenSessions();
          },
        );
        _markStatus(id, SessionStatus.connected);
        _persistOpenSessions();
        if (runStartupScript) _runStartupScript(host, engine);
      case Err(:final failure):
        _markError(id, failure);
        _persistOpenSessions();
    }
  }

  Future<TerminalSessionHandle> _withSessionLogging(
    String sessionId,
    Host host,
    TerminalSessionHandle handle,
  ) async {
    SessionLogWriter? writer;
    try {
      writer = await ref
          .read(sessionLogRepositoryProvider)
          .start(sessionId: sessionId, host: host);
      _sessionLogIds[sessionId] = writer.id;
      _schedulePersistOpenSessions();
      return LoggingTerminalSessionHandle(inner: handle, writer: writer);
    } catch (e) {
      if (writer != null) {
        unawaited(writer.finish('error'));
      }
      debugPrint('[session-log] 로그 기록을 시작하지 못했습니다: $e');
      return handle;
    }
  }

  /// SSH 출력 스트림이 끊겼을 때 호출. 사용자가 닫은 세션이 아니면
  /// 끊김 상태로 표시하고 자동 재연결을 예약한다.
  ///
  /// 실제 소켓 종료(onDone)로만 도달하는 경로라 테스트에서 이 이벤트를
  /// 시뮬레이션할 수 있도록 노출한다.
  @visibleForTesting
  void handleSessionDropped(String id) {
    if (_userClosed.contains(id)) return;
    SessionInfo? session;
    for (final s in state) {
      if (s.id == id) session = s;
    }
    if (session == null) return;
    // onClosed 콜백과 ping 실패가 레이스할 수 있다. 이미 끊김/재연결
    // 처리 중인 세션이면 중복 drop(타이머 취소, 백오프 재시도 횟수 이중
    // 증가, 이벤트 중복 기록)을 막기 위해 조용히 무시한다.
    if (session.status == SessionStatus.disconnected ||
        session.status == SessionStatus.connecting) {
      return;
    }
    ref
        .read(sessionDiagnosticsProvider.notifier)
        .record(id, SessionEventType.dropped);
    final staleHandle = _sshHandles.remove(id);
    if (staleHandle != null) unawaited(staleHandle.close());
    unawaited(_closeKubernetesForward(id));
    _markStatus(id, SessionStatus.disconnected);
    _scheduleReconnect(id);
  }

  void _handleSshSessionClosed(String id, SshSessionHandle handle) {
    if (_userClosed.contains(id)) return;
    if (handle.remoteProcessExited) {
      closeSession(id);
      return;
    }
    handleSessionDropped(id);
  }

  void _recordRemoteSessionLaunch(String id, SshSessionHandle handle) {
    if (!handle.isPersistent) return;
    ref
        .read(sessionDiagnosticsProvider.notifier)
        .record(
          id,
          handle.resumedPersistentSession
              ? SessionEventType.remoteSessionResumed
              : SessionEventType.remoteSessionCreated,
        );
  }

  /// 앱이 포그라운드로 복귀했을 때 호출. 백그라운드 동안 끊긴 원격 세션은
  /// 백오프 타이머가 Doze로 지연·병합돼 복귀 후에도 한참 끊긴 채로 보일 수
  /// 있다. 그래서 대기 중인 예약을 무시하고 즉시 재연결을 시도한다.
  ///
  /// 이미 연결됐거나 재연결 중인 세션, 사용자가 닫은 세션, 재연결 대상이
  /// 아닌 로컬 셸은 건드리지 않는다. 인증에 한 번 성공했던(=끊김 상태) 세션만
  /// 대상으로 삼아, 초기 인증 실패(error)를 복귀마다 재시도해 계정이 잠기는
  /// 상황을 피한다.
  void reconnectDisconnectedNow() {
    for (final session in state) {
      final id = session.id;
      if (_userClosed.contains(id)) continue;
      if (session.host.isLocalShell) continue;
      if (session.status != SessionStatus.disconnected) continue;
      _reconnectTimers.remove(id)?.cancel();
      _reconnectAttempts[id] = 0;
      unawaited(_reconnect(id));
    }
  }

  /// keepalive 박자([KeepalivePulse])가 울릴 때 호출. 연결된 원격 세션마다
  /// SSH keepalive ping을 보내 NAT/서버 유휴 타임아웃을 막는다.
  ///
  /// ping이 5초 안에 완료되지 않거나 예외가 나면 죽은 연결로 간주하고
  /// 즉시 끊김 처리한다(감지가 빨라지는 부수효과). dartssh2 내장 keepalive
  /// (15초)는 별도로 도는데, 백그라운드에서 Dart 타이머가 굶겨질 수 있어
  /// 이 박자가 보증 레이어 역할을 한다.
  Future<void> pingActiveSessions() async {
    // 죽은 세션이 여럿이면 순차 5초 타임아웃 합이 20초 박자 간격을 넘어설 수
    // 있다. 재진입을 막아 이전 호출이 끝나기 전에 다음 박자가 겹쳐 같은
    // 세션을 두 번 drop 처리하는 것을 방지한다.
    if (_pinging) return;
    _pinging = true;
    try {
      final diag = ref.read(sessionDiagnosticsProvider.notifier);
      for (final session in state) {
        final id = session.id;
        if (_userClosed.contains(id)) continue;
        if (session.host.isLocalShell) continue;
        if (session.status != SessionStatus.connected) continue;
        final client = _sshHandles[id]?.client;
        if (client == null) continue;
        try {
          await client.ping().timeout(const Duration(seconds: 5));
          diag.record(id, SessionEventType.pingSent);
        } catch (e) {
          diag.record(id, SessionEventType.pingFailed, detail: '$e');
          handleSessionDropped(id);
        }
      }
    } finally {
      _pinging = false;
    }
  }

  /// 지수 백오프로 다음 재연결을 예약한다. [_maxReconnectAttempts]를 넘기면
  /// 더 예약하지 않고 멈춘다.
  void _scheduleReconnect(String id) {
    if (_userClosed.contains(id)) return;
    final attempt = _reconnectAttempts[id] ?? 0;
    if (attempt >= _maxReconnectAttempts) {
      _reconnectTimers.remove(id)?.cancel();
      ref
          .read(sessionDiagnosticsProvider.notifier)
          .record(
            id,
            SessionEventType.reconnectGaveUp,
            detail: '$_maxReconnectAttempts회 실패 후 자동 재연결 중단',
          );
      return;
    }
    final seconds =
        _reconnectBackoff[attempt.clamp(0, _reconnectBackoff.length - 1)];
    _reconnectAttempts[id] = attempt + 1;
    _reconnectTimers[id]?.cancel();
    _reconnectTimers[id] = Timer(
      Duration(seconds: seconds),
      () => unawaited(_reconnect(id)),
    );
    ref
        .read(sessionDiagnosticsProvider.notifier)
        .record(id, SessionEventType.reconnectScheduled, detail: '${seconds}s');
  }

  /// 끊긴 SSH 세션을 같은 호스트로 다시 연결한다. 호스트키는 이미 핀된
  /// 키(trustedKnown)와 일치할 때만 자동 승인하고, 그 외엔 거부한다.
  Future<void> _reconnect(String id) async {
    _reconnectTimers.remove(id);
    if (_userClosed.contains(id)) return;

    SessionInfo? session;
    for (final s in state) {
      if (s.id == id) session = s;
    }
    if (session == null) return;

    if (session.host.authType == HostAuthType.keyboardInteractive ||
        (session.host.isKubernetesSsh &&
            session.host.kubernetesAuthType ==
                HostAuthType.keyboardInteractive)) {
      _markError(id, const AuthFailure('추가 인증 응답이 필요합니다. 수동으로 재시도하세요.'));
      _persistOpenSessions();
      return;
    }

    _markStatus(id, SessionStatus.connecting);
    ref
        .read(sessionDiagnosticsProvider.notifier)
        .record(id, SessionEventType.reconnectAttempt);

    await _closeKubernetesForward(id);
    final routeResult = await _openSshRoute(session.host);
    final _SshRoute route;
    switch (routeResult) {
      case Ok(:final value):
        route = value;
      case Err(:final failure):
        debugPrint('[reconnect] $id SSH 경로 준비 실패: ${failure.message}');
        _markStatus(id, SessionStatus.disconnected);
        _scheduleReconnect(id);
        return;
    }
    if (_userClosed.contains(id) || !state.any((item) => item.id == id)) {
      await route.kubernetesForward?.close();
      return;
    }
    if (route.kubernetesForward case final forward?) {
      _kubernetesForwards[id] = forward;
    }

    final ssh = ref.read(sshServiceProvider);
    final result = await ssh.connect(
      host: session.host,
      cols: session.engine.terminal.viewWidth,
      rows: session.engine.terminal.viewHeight,
      // 자동 재연결은 사용자 개입 없이 일어나므로 이미 핀된 키만 신뢰한다.
      // 콜백은 미지의 키일 때만(trustedNew) 호출되므로 항상 false → 새 키 거부.
      onHostKey: (_, _, _, verdict) async =>
          verdict == HostKeyVerdict.trustedKnown,
      jumpHosts: route.jumpHosts,

      remoteSessionId: session.remoteSessionId,
    );

    // 재연결 도중 사용자가 닫았거나 세션이 사라졌으면 정리하고 중단.
    if (_userClosed.contains(id) || !state.any((s) => s.id == id)) {
      if (result case Ok(:final value)) {
        await value.close();
      }
      await _closeKubernetesForward(id);
      return;
    }

    switch (result) {
      case Ok(:final value):
        _sshHandles[id] = value;
        final handle = await _withSessionLogging(id, session.host, value);
        session.engine.attach(
          handle,
          onClosed: () => _handleSshSessionClosed(id, value),
        );
        _markStatus(
          id,
          SessionStatus.connected,
          fellBackToDirectSsh: value.fellBackToDirectSsh,
        );
        _reconnectAttempts[id] = 0;
        _recordRemoteSessionLaunch(id, value);
        unawaited(_markAgentWorktreeActiveIfResumed(session, value));
        ref
            .read(sessionDiagnosticsProvider.notifier)
            .record(id, SessionEventType.reconnected);
        _persistOpenSessions();
        unawaited(
          _reconcilePendingRemoteSessionTerminations(
            id,
            session.host,
            value,
            currentRemoteSessionId: session.remoteSessionId,
          ),
        );
        if (value.isPersistent && !value.resumedPersistentSession) {
          _runStartupScript(session.host, session.engine);
        }
      case Err():
        await _closeKubernetesForward(id);
        // 다시 끊김 상태로 두고 백오프 재시도.
        _markStatus(id, SessionStatus.disconnected);
        _scheduleReconnect(id);
    }
  }

  String? _cleanTitle(String? title) {
    final cleaned = title?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  void _markStatus(
    String id,
    SessionStatus status, {
    bool? fellBackToDirectSsh,
  }) {
    // connected 진입 시 연결 시각을 기록(재연결마다 갱신), 그 외엔 비운다.
    final connectedAt = status == SessionStatus.connected
        ? DateTime.now()
        : null;
    state = [
      for (final s in state)
        if (s.id == id)
          s.copyWith(
            status: status,
            connectedAt: connectedAt,
            fellBackToDirectSsh: fellBackToDirectSsh,
          )
        else
          s,
    ];
  }

  void _markError(String id, Failure failure) {
    state = [
      for (final s in state)
        if (s.id == id)
          s.copyWith(
            status: SessionStatus.error,
            error: failure.message,
            failure: failure,
          )
        else
          s,
    ];
  }

  void renameSession(String id, String title) {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(title: _cleanTitle(title)) else s,
    ];
    _persistOpenSessions();
  }

  void reorderSession(int oldIndex, int newIndex) {
    final adjustedIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    moveSession(oldIndex, adjustedIndex);
  }

  void moveSession(int oldIndex, int targetIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;

    final next = [...state];
    final session = next.removeAt(oldIndex);
    final boundedIndex = targetIndex.clamp(0, next.length).toInt();
    next.insert(boundedIndex, session);
    state = next;
    _persistOpenSessions();
  }

  void moveSessionInGroup(String groupId, int oldIndex, int targetIndex) {
    final groupSessions = [
      for (final session in state)
        if (session.groupId == groupId) session,
    ];
    if (oldIndex < 0 || oldIndex >= groupSessions.length) return;
    if (groupSessions.length < 2) return;

    final reordered = [...groupSessions];
    final session = reordered.removeAt(oldIndex);
    final boundedIndex = targetIndex.clamp(0, reordered.length).toInt();
    reordered.insert(boundedIndex, session);

    var nextGroupIndex = 0;
    state = [
      for (final session in state)
        if (session.groupId == groupId)
          reordered[nextGroupIndex++]
        else
          session,
    ];
    _persistOpenSessions();
  }

  void moveSessionToGroup(String id, String groupId) {
    if (!ref.read(sessionGroupProvider).contains(groupId)) return;
    final next = <SessionInfo>[];
    var moved = false;
    for (final session in state) {
      if (session.id != id) {
        next.add(session);
        continue;
      }
      if (session.groupId == groupId) return;
      next.add(session.copyWith(groupId: groupId));
      moved = true;
    }
    if (!moved) return;
    state = next;

    final activeGroupId = ref.read(sessionGroupProvider).activeGroupId;
    if (ref.read(activeSessionIdProvider) == id && groupId != activeGroupId) {
      ref
          .read(activeSessionIdProvider.notifier)
          .set(_firstSessionIdInGroup(state, activeGroupId));
    }
    _persistOpenSessions();
  }

  /// 세션을 닫고 자원을 정리한다. active 세션이 닫히면 active-id를 수정한다.
  /// 작업 이어가기가 켜진 세션의 원격 작업을 끝내려면 먼저
  /// [terminatePersistentSession]을 호출해야 한다.
  void closeSession(String id) {
    final closing = _sessionById(id);
    final workspaceId = closing?.agentWorkspace?.workspaceId;
    if (workspaceId != null) {
      unawaited(_markAgentWorktreeStranded(workspaceId, id));
    }
    // 자동 재연결 중단: 사용자가 명시적으로 닫은 세션이다.
    _userClosed.add(id);
    _reconnectTimers.remove(id)?.cancel();
    _reconnectAttempts.remove(id);
    _sshHandles.remove(id);
    unawaited(_closeKubernetesForward(id));
    _sessionStates.remove(id);
    _sessionLogIds.remove(id);
    ref.read(sessionActivityProvider.notifier).remove(id);
    ref.read(sessionDiagnosticsProvider.notifier).remove(id);
    _engines.remove(id)?.dispose();
    state = [
      for (final s in state)
        if (s.id != id) s,
    ];
    final activeId = ref.read(activeSessionIdProvider);
    if (activeId == id) {
      final activeGroupId = ref.read(sessionGroupProvider).activeGroupId;
      ref
          .read(activeSessionIdProvider.notifier)
          .set(
            _firstSessionIdInGroup(state, activeGroupId) ??
                (state.isEmpty ? null : state.first.id),
          );
    }
    _persistOpenSessions();
  }

  /// 현재 SSH 연결을 사용해 앱 전용 원격 작업을 종료한다.
  ///
  /// 연결이 끊긴 상태에서는 서버에 종료 명령을 보낼 수 없으므로 false를
  /// 반환한다. 호출자는 사용자에게 원격 작업이 남을 수 있음을 알려야 한다.
  Future<bool> terminatePersistentSession(String id) async {
    final session = _sessionById(id);
    if (session == null || !session.host.keepsRemoteSession) return true;

    _userClosed.add(id);
    _reconnectTimers.remove(id)?.cancel();
    _reconnectAttempts.remove(id);
    final remoteSessionId = session.remoteSessionId;
    if (remoteSessionId == null) return false;
    final handle = _sshHandles[id];
    if (handle == null || session.status != SessionStatus.connected) {
      await _queueRemoteSessionTermination(session.host.id, remoteSessionId);
      return false;
    }
    final terminated = await handle.terminatePersistentSession();
    if (terminated) {
      await _removeQueuedRemoteSessionTermination(
        session.host.id,
        remoteSessionId,
      );
    } else {
      await _queueRemoteSessionTermination(session.host.id, remoteSessionId);
    }
    return terminated;
  }

  Future<Result<List<RemotePersistentSession>>> listRemotePersistentSessions(
    String id,
  ) async {
    final session = _sessionById(id);
    final handle = _sshHandles[id];
    if (session == null ||
        !session.host.keepsRemoteSession ||
        handle == null ||
        session.status != SessionStatus.connected) {
      return const Err(RemoteSessionFailure('연결된 작업 이어가기 세션에서만 볼 수 있습니다.'));
    }
    return ref.read(remoteSessionCatalogProvider).list(handle.client);
  }

  String? currentPersistentSessionName(String id) =>
      _sshHandles[id]?.persistentSessionName;

  Future<String> currentRemoteSessionOwnerId() =>
      ref.read(remoteSessionIdentityStoreProvider).readOrCreate();

  Future<bool> terminateListedRemoteSession(
    String connectionSessionId,
    RemotePersistentSession remoteSession,
  ) async {
    final connection = _sessionById(connectionSessionId);
    final handle = _sshHandles[connectionSessionId];
    if (connection == null ||
        handle == null ||
        connection.status != SessionStatus.connected ||
        handle.persistentSessionName == remoteSession.name) {
      return false;
    }

    final outcome = await ref
        .read(remoteSessionCatalogProvider)
        .terminate(handle.client, persistentSessionName: remoteSession.name);
    final completed =
        outcome == RemoteSessionTerminationOutcome.terminated ||
        outcome == RemoteSessionTerminationOutcome.alreadyAbsent;
    if (completed) {
      await _removeQueuedRemoteSessionTermination(
        connection.host.id,
        remoteSession.remoteSessionId,
      );
    }
    return completed;
  }

  /// 보관함의 원격 작업을 앱의 터미널 탭으로 활성화한다.
  ///
  /// 같은 호스트와 원격 작업 ID를 가진 탭이 이미 있으면 해당 그룹과 탭으로
  /// 이동하고, 없을 때만 정확히 그 tmux 작업을 가리키는 새 탭을 연다.
  Future<Result<RemoteSessionActivation>> activateListedRemoteSession(
    String connectionSessionId,
    RemotePersistentSession remoteSession, {
    KeyboardInteractivePrompt? onKeyboardInteractive,
  }) async {
    final connection = _sessionById(connectionSessionId);
    if (connection == null ||
        !connection.host.keepsRemoteSession ||
        connection.status != SessionStatus.connected) {
      return const Err(RemoteSessionFailure('연결된 작업 이어가기 세션이 필요합니다.'));
    }

    final existing = localSessionForRemoteSession(
      connection.host.id,
      remoteSession.remoteSessionId,
    );
    if (existing != null) {
      _activateSession(existing);
      return Ok(
        RemoteSessionActivation(
          sessionId: existing.id,
          kind: RemoteSessionActivationKind.switchedToExistingTab,
        ),
      );
    }

    final sessionId = await openSession(
      connection.host,
      groupId: connection.groupId,
      remoteSessionId: remoteSession.remoteSessionId,
      title: _remoteSessionTitle(connection.host.alias, remoteSession),
      // 보관함을 불러온 연결과 같은 호스트이므로 키가 이미 핀되어 있어야 한다.
      // 그 사이 키가 사라지거나 바뀌었다면 모달 밖에서 암묵적으로 승인하지
      // 않고 새 탭의 연결 오류로 안전하게 노출한다.
      onHostKey: (_, _, _, _) async => false,
      onKeyboardInteractive: onKeyboardInteractive,
    );
    final opened = _sessionById(sessionId);
    if (opened == null) {
      return const Err(RemoteSessionFailure('서버 작업 탭을 만들지 못했습니다.'));
    }
    _activateSession(opened);
    if (opened.status != SessionStatus.connected) {
      return Err(
        opened.failure ??
            RemoteSessionFailure(opened.error ?? '서버 작업에 연결하지 못했습니다.'),
      );
    }
    return Ok(
      RemoteSessionActivation(
        sessionId: sessionId,
        kind: RemoteSessionActivationKind.openedNewTab,
      ),
    );
  }

  SessionInfo? localSessionForRemoteSession(
    String hostId,
    String remoteSessionId,
  ) {
    for (final session in state) {
      if (session.host.id == hostId &&
          session.remoteSessionId == remoteSessionId) {
        return session;
      }
    }
    return null;
  }

  void _activateSession(SessionInfo session) {
    ref.read(sessionGroupProvider.notifier).setActive(session.groupId);
    ref.read(activeSessionIdProvider.notifier).set(session.id);
  }

  static String _remoteSessionTitle(
    String hostAlias,
    RemotePersistentSession remoteSession,
  ) {
    final id = remoteSession.remoteSessionId;
    final shortId = id.length > 10 ? id.substring(id.length - 10) : id;
    return '$hostAlias · $shortId';
  }

  Future<void> _queueRemoteSessionTermination(
    String hostId,
    String remoteSessionId,
  ) async {
    try {
      await ref
          .read(remoteSessionCleanupStoreProvider)
          .enqueue(
            PendingRemoteSessionTermination(
              hostId: hostId,
              remoteSessionId: remoteSessionId,
              queuedAt: DateTime.now(),
            ),
          );
    } catch (error) {
      // 보조 정리 큐를 기록하지 못해도 사용자가 탭을 닫는 흐름은 막지 않는다.
      debugPrint('[remote-session-cleanup] 종료 요청 저장 실패: $error');
    }
  }

  Future<void> _removeQueuedRemoteSessionTermination(
    String hostId,
    String remoteSessionId,
  ) async {
    try {
      await ref
          .read(remoteSessionCleanupStoreProvider)
          .remove(hostId: hostId, remoteSessionId: remoteSessionId);
    } catch (error) {
      debugPrint('[remote-session-cleanup] 종료 요청 삭제 실패: $error');
    }
  }

  Future<void> _reconcilePendingRemoteSessionTerminations(
    String connectionSessionId,
    Host host,
    SshSessionHandle handle, {
    required String? currentRemoteSessionId,
  }) async {
    final store = ref.read(remoteSessionCleanupStoreProvider);
    final catalog = ref.read(remoteSessionCatalogProvider);
    for (final entry in await store.forHost(host.id)) {
      if (entry.remoteSessionId == currentRemoteSessionId) continue;
      String persistentSessionName;
      try {
        persistentSessionName = TmuxRemoteTerminalLauncher.sessionNameFor(
          entry.remoteSessionId,
        );
      } on ArgumentError {
        await store.remove(
          hostId: entry.hostId,
          remoteSessionId: entry.remoteSessionId,
        );
        continue;
      }

      final outcome = await catalog.terminate(
        handle.client,
        persistentSessionName: persistentSessionName,
      );
      switch (outcome) {
        case RemoteSessionTerminationOutcome.terminated:
        case RemoteSessionTerminationOutcome.alreadyAbsent:
          await store.remove(
            hostId: entry.hostId,
            remoteSessionId: entry.remoteSessionId,
          );
        case RemoteSessionTerminationOutcome.notManaged:
        case RemoteSessionTerminationOutcome.identityMismatch:
          // 같은 이름의 비관리 세션으로 바뀌었다면 절대 종료하지 않고 대기
          // 항목만 버린다. 반복 시도보다 타인의 작업을 건드리지 않는 것이 우선이다.
          debugPrint(
            '[remote-session-cleanup] $connectionSessionId 소유권 확인 실패: '
            '${entry.remoteSessionId}',
          );
          await store.remove(
            hostId: entry.hostId,
            remoteSessionId: entry.remoteSessionId,
          );
        case RemoteSessionTerminationOutcome.failed:
          // 일시 실패는 다음 연결에서 다시 시도한다.
          break;
      }
    }
  }

  static final _generatedIdPattern = RegExp(r'^s(\d+)$');

  void _reserveCounterFor(String id) {
    final match = _generatedIdPattern.firstMatch(id);
    if (match == null) return;
    final index = int.tryParse(match.group(1)!);
    if (index == null) return;
    if (_counter <= index) _counter = index + 1;
  }

  Future<void> persistOpenSessionsForRestore() {
    _persistTimer?.cancel();
    _persistTimer = null;
    return _saveOpenSessionsSnapshot();
  }

  void _schedulePersistOpenSessions() {
    _persistTimer?.cancel();
    _persistTimer = Timer(
      const Duration(milliseconds: 500),
      _persistOpenSessions,
    );
  }

  void _persistOpenSessions() {
    _persistTimer?.cancel();
    _persistTimer = null;
    unawaited(_saveOpenSessionsSnapshot());
  }

  Future<void> _saveOpenSessionsSnapshot() {
    final snapshot = SessionRestoreSnapshot(
      activeId: ref.read(activeSessionIdProvider),
      groups: ref.read(sessionGroupProvider).groups,
      activeGroupId: ref.read(sessionGroupProvider).activeGroupId,
      sessions: [
        for (final session in state)
          if (!_userClosed.contains(session.id) &&
              session.status != SessionStatus.error)
            RestoredSessionEntry(
              id: session.id,
              hostId: session.host.id,
              title: session.title,
              groupId: session.groupId,
              remoteSessionId: session.remoteSessionId,
              agentWorkspace: session.agentWorkspace,
              terminalText: _terminalTextForRestore(session),
              currentWorkingDirectory:
                  _sessionStates[session.id]?.workingDirectory ??
                  session.restoredContext?.workingDirectory,
              localShellType: session.host.isLocalShell
                  ? _sessionStates[session.id]?.shellType
                  : null,
              sessionLogId: _logIdForRestore(session),
              historyPromptDismissed: _historyPromptDismissedForRestore(
                session,
              ),
              historyPromptCompleted: _historyPromptCompletedForRestore(
                session,
              ),
              pathPromptDismissed: _pathPromptDismissedForRestore(session),
              pathPromptCompleted: _pathPromptCompletedForRestore(session),
            ),
      ],
    );
    return ref.read(sessionRestoreStoreProvider).save(snapshot);
  }

  String? _firstSessionIdInGroup(List<SessionInfo> sessions, String groupId) {
    for (final session in sessions) {
      if (session.groupId == groupId) return session.id;
    }
    return null;
  }

  String? _logIdForRestore(SessionInfo session) {
    final context = session.restoredContext;
    if (context != null &&
        (context.shouldOfferSummary || context.shouldOfferPathRestore)) {
      return context.logId;
    }
    return _sessionLogIds[session.id] ?? session.restoredContext?.logId;
  }

  bool _historyPromptDismissedForRestore(SessionInfo session) {
    final context = session.restoredContext;
    if (context == null || !context.summaryPromptDismissed) return false;
    return _logIdForRestore(session) == context.logId;
  }

  bool _historyPromptCompletedForRestore(SessionInfo session) {
    final context = session.restoredContext;
    if (context == null || !context.summaryPromptCompleted) return false;
    return _logIdForRestore(session) == context.logId;
  }

  bool _pathPromptDismissedForRestore(SessionInfo session) {
    final context = session.restoredContext;
    if (context == null || !context.pathPromptDismissed) return false;
    return _logIdForRestore(session) == context.logId;
  }

  bool _pathPromptCompletedForRestore(SessionInfo session) {
    final context = session.restoredContext;
    if (context == null || !context.pathPromptCompleted) return false;
    return _logIdForRestore(session) == context.logId;
  }

  RestoredSessionContext? _restoredContextFor(
    RestoredSessionEntry entry,
    Host restoredHost,
  ) {
    // tmux가 실제 화면과 작업 디렉터리를 복원하므로 과거 평문 화면이나 AI
    // 복원 제안을 겹쳐 보여 주지 않는다.
    if (restoredHost.keepsRemoteSession) return null;
    final logId = entry.sessionLogId?.trim();
    final workingDirectory = restoredHost.isLocalShell
        ? _validRestoredWorkingDirectory(
            restoredHost.localShellType,
            entry.currentWorkingDirectory,
          )
        : entry.currentWorkingDirectory?.trim();
    if ((logId == null || logId.isEmpty) &&
        (workingDirectory == null || workingDirectory.isEmpty)) {
      return null;
    }
    return RestoredSessionContext(
      logId: logId == null || logId.isEmpty ? null : logId,
      workingDirectory: workingDirectory == null || workingDirectory.isEmpty
          ? null
          : workingDirectory,
      summaryPromptDismissed: entry.historyPromptDismissed,
      summaryPromptCompleted: entry.historyPromptCompleted,
      pathPromptDismissed: entry.pathPromptDismissed,
      pathPromptCompleted: entry.pathPromptCompleted,
    );
  }

  void markRestoreSummaryDismissed(String id) {
    final currentLogId = _sessionLogIds[id];
    _updateRestoredContext(
      id,
      (context) => context.copyWith(
        logId: currentLogId ?? context.logId,
        summaryPromptDismissed: true,
      ),
    );
  }

  void markRestoreSummaryCompleted(String id) {
    _updateRestoredContext(id, (context) {
      final next = context.copyWith(summaryPromptCompleted: true);
      return next.hasWorkingDirectory ? next : null;
    });
  }

  void markRestorePathDismissed(String id) {
    _updateRestoredContext(id, (_) => null);
  }

  void markRestorePathCompleted(String id) {
    _updateRestoredContext(id, (_) => null);
  }

  void _updateRestoredContext(
    String id,
    RestoredSessionContext? Function(RestoredSessionContext context) update,
  ) {
    state = [
      for (final s in state)
        if (s.id == id && s.restoredContext != null)
          s.copyWith(restoredContext: update(s.restoredContext!))
        else
          s,
    ];
    _persistOpenSessions();
  }

  String? _terminalTextForRestore(SessionInfo session) {
    if (session.host.keepsRemoteSession) return null;
    const maxLines = 300;
    const maxChars = 20000;
    final text = session.engine.recentPlainText(maxLines: maxLines).trimRight();
    if (text.isEmpty) return null;
    if (text.length <= maxChars) return text;
    final start = text.length - maxChars;
    final lineStart = text.indexOf('\n', start);
    if (lineStart < 0 || lineStart + 1 >= text.length) {
      return text.substring(start);
    }
    return text.substring(lineStart + 1);
  }

  Host _hostForRestoredLocalSession(Host host, RestoredSessionEntry entry) {
    final shellType = entry.localShellType ?? host.localShellType;
    final workingDirectory =
        _validRestoredWorkingDirectory(
          shellType,
          entry.currentWorkingDirectory,
        ) ??
        _validRestoredWorkingDirectory(shellType, host.workingDirectory);
    return host.copyWith(
      localShellType: shellType,
      workingDirectory: workingDirectory,
    );
  }

  String? _validRestoredWorkingDirectory(
    LocalShellType shellType,
    String? value,
  ) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    if (Platform.isWindows && shellType == LocalShellType.wsl) {
      return LocalShellPaths.wslWorkingDirectoryForState(cleaned);
    }
    return Directory(cleaned).existsSync() ? cleaned : null;
  }
}

class _ManagedAgentWorkspaceRun {
  _ManagedAgentWorkspaceRun({
    required this.handle,
    required this.record,
    required this.store,
  });

  static const int maximumOutputCharacters = 240000;

  final AgentWorkspaceRunHandle handle;
  final AgentWorkspaceRunStore store;
  AgentWorkspaceRunRecord record;
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  Future<void>? stdoutDone;
  Future<void>? stderrDone;
  Timer? persistTimer;
  String urlTail = '';
  bool stopRequested = false;
  final Completer<void> completed = Completer<void>();
}

class _RemoteAgentWorkspaceRunHandle implements AgentWorkspaceRunHandle {
  _RemoteAgentWorkspaceRunHandle(this._session);

  final SSHSession _session;
  bool _stopping = false;

  @override
  Stream<List<int>> get stdout => _session.stdout;

  @override
  Stream<List<int>> get stderr => _session.stderr;

  @override
  Future<int?> get done async {
    await _session.done;
    return _session.exitCode;
  }

  @override
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    _session.kill(SSHSignal.TERM);
    try {
      await _session.done.timeout(const Duration(seconds: 3));
    } catch (_) {
      _session.close();
    }
  }
}

class _SshRoute {
  const _SshRoute({this.jumpHosts = const [], this.kubernetesForward});

  final List<Host> jumpHosts;
  final KubernetesPortForwardHandle? kubernetesForward;
}
