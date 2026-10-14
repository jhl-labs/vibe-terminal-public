import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/result.dart';
import '../../session/session.dart';
import '../../session/server_work_tabs.dart';
import '../../session/session_manager.dart';
import '../../ssh/remote_session_catalog.dart';
import '../../ssh/remote_server_info.dart';
import '../../state/providers.dart';
import '../security/keyboard_interactive_prompt.dart';

class RemoteSessionManagerPanel extends ConsumerStatefulWidget {
  const RemoteSessionManagerPanel({
    super.key,
    required this.connection,
    required this.onClose,
    required this.onActivated,
    required this.onBusyChanged,
  });

  final SessionInfo connection;
  final VoidCallback onClose;
  final VoidCallback onActivated;
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<RemoteSessionManagerPanel> createState() =>
      _RemoteSessionManagerPanelState();
}

class _RemoteSessionManagerPanelState
    extends ConsumerState<RemoteSessionManagerPanel> {
  var _loading = true;
  String? _error;
  String? _ownerId;
  String? _currentSessionName;
  List<RemotePersistentSession> _sessions = const [];
  final Set<String> _opening = {};
  final Set<String> _terminating = {};
  final Set<String> _selected = {};
  RemoteServerInfo? _serverInfo;
  var _serverInfoLoading = true;
  var _batchOpening = false;
  int _loadEpoch = 0;
  int _serverInfoEpoch = 0;

  bool get _connected => ServerWorkTab.supports(widget.connection);

  bool get _busy =>
      _batchOpening || _opening.isNotEmpty || _terminating.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_loadServerInfo());
  }

  @override
  void didUpdateWidget(covariant RemoteSessionManagerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection.id != widget.connection.id ||
        ServerWorkTab.supports(oldWidget.connection) != _connected) {
      _serverInfo = null;
      _serverInfoLoading = true;
      unawaited(_load());
      unawaited(_loadServerInfo());
    }
  }

  Future<void> _loadServerInfo() async {
    final epoch = ++_serverInfoEpoch;
    if (!_connected) {
      _serverInfoLoading = false;
      return;
    }
    final info = await ref
        .read(sessionManagerProvider.notifier)
        .remoteServerInfo(widget.connection.id);
    if (!mounted || epoch != _serverInfoEpoch) return;
    setState(() {
      _serverInfo = info;
      _serverInfoLoading = false;
    });
  }

  bool _canSelect(RemotePersistentSession session) =>
      _connected &&
      session.name != _currentSessionName &&
      ref
              .read(sessionManagerProvider.notifier)
              .localSessionForRemoteSession(
                widget.connection.host.id,
                session.remoteSessionId,
              ) ==
          null;

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    if (!_connected) {
      setState(() => _loading = false);
      return;
    }
    final connectionId = widget.connection.id;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final manager = ref.read(sessionManagerProvider.notifier);
    final ownerId = await manager.currentRemoteSessionOwnerId();
    final currentName = manager.currentPersistentSessionName(connectionId);
    final result = await manager.listRemotePersistentSessions(connectionId);
    if (!mounted || epoch != _loadEpoch) return;
    switch (result) {
      case Ok(:final value):
        setState(() {
          _ownerId = ownerId;
          _currentSessionName = currentName;
          _sessions = value;
          _selected.retainAll(
            value.where(_canSelect).map((session) => session.name),
          );
          _loading = false;
        });
      case Err(:final failure):
        setState(() {
          _ownerId = ownerId;
          _currentSessionName = currentName;
          _error = failure.message;
          _loading = false;
        });
    }
  }

  Future<void> _terminate(RemotePersistentSession session) async {
    final attached = session.isAttached;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('서버 작업을 종료할까요?'),
        content: Text(
          attached
              ? '이 작업에 연결된 터미널이 있습니다. 종료하면 그 터미널과 서버에서 실행 중인 프로세스가 함께 끝납니다.'
              : '분리된 터미널과 그 안에서 실행 중인 서버 프로세스가 함께 끝납니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VibeColors.statusError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('작업 종료'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _terminating.add(session.name));
    widget.onBusyChanged(true);
    final outcome = await ref
        .read(sessionManagerProvider.notifier)
        .terminateListedRemoteSession(widget.connection.id, session);
    if (!mounted) return;
    setState(() => _terminating.remove(session.name));
    widget.onBusyChanged(_busy);
    final notice = switch (outcome) {
      RemoteSessionTerminationOutcome.terminated ||
      RemoteSessionTerminationOutcome.alreadyAbsent => null,
      RemoteSessionTerminationOutcome.attachedElsewhere =>
        '다른 기기에서 이 작업을 보고 있어 종료하지 않았습니다. 그 기기에서 탭을 닫은 뒤 다시 시도하세요.',
      RemoteSessionTerminationOutcome.notManaged ||
      RemoteSessionTerminationOutcome.identityMismatch ||
      RemoteSessionTerminationOutcome.failed =>
        '소유권을 확인하지 못했거나 연결이 끊겨 작업을 종료하지 않았습니다.',
    };
    if (notice == null) {
      await _load();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _activate(RemotePersistentSession session) async {
    setState(() => _opening.add(session.name));
    widget.onBusyChanged(true);
    final result = await ref
        .read(sessionManagerProvider.notifier)
        .activateListedRemoteSession(
          widget.connection.id,
          session,
          onKeyboardInteractive: (hostAlias, request) {
            if (!mounted) return Future.value(null);
            return showKeyboardInteractivePrompt(
              context,
              hostAlias: hostAlias,
              request: request,
            );
          },
        );
    if (!mounted) return;
    setState(() => _opening.remove(session.name));
    widget.onBusyChanged(_busy);

    switch (result) {
      case Ok(:final value):
        widget.onActivated();
        final message = switch (value.kind) {
          RemoteSessionActivationKind.switchedToExistingTab =>
            '기존 터미널 탭으로 이동했습니다.',
          RemoteSessionActivationKind.openedNewTab => '서버 작업을 새 터미널 탭으로 열었습니다.',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case Err(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _activateSelected() async {
    if (_busy || _selected.isEmpty) return;
    final selected = _sessions
        .where((session) => _selected.contains(session.name))
        .toList();
    final failures = <String>[];
    var opened = 0;
    setState(() => _batchOpening = true);
    widget.onBusyChanged(true);
    for (final session in selected) {
      if (!mounted) return;
      setState(() => _opening.add(session.name));
      final result = await ref
          .read(sessionManagerProvider.notifier)
          .activateListedRemoteSession(
            widget.connection.id,
            session,
            onKeyboardInteractive: (hostAlias, request) => mounted
                ? showKeyboardInteractivePrompt(
                    context,
                    hostAlias: hostAlias,
                    request: request,
                  )
                : Future.value(null),
          );
      if (!mounted) return;
      setState(() {
        _opening.remove(session.name);
        switch (result) {
          case Ok():
            opened++;
            _selected.remove(session.name);
          case Err(:final failure):
            failures.add('${session.displayName}: ${failure.message}');
        }
      });
    }
    if (!mounted) return;
    setState(() => _batchOpening = false);
    widget.onBusyChanged(_busy);
    final messenger = ScaffoldMessenger.of(context);
    if (failures.isEmpty) widget.onActivated();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        content: Text(
          failures.isEmpty
              ? '선택한 작업 $opened개를 열었습니다.'
              : '$opened개 열림 · ${failures.join('\n')}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 700 || constraints.maxHeight < 450;
        return Material(
          color: VibeColors.surface,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: VibeColors.accent,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '서버 작업 보관함',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '원하는 작업을 선택한 뒤 한 번에 여세요.',
                            style: TextStyle(
                              fontSize: 11,
                              color: VibeColors.onSurfaceDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '새로고침',
                      onPressed: _loading || _busy || !_connected
                          ? null
                          : () {
                              unawaited(_load());
                              unawaited(_loadServerInfo());
                            },
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: '보관함 탭 닫기',
                      onPressed: _busy ? null : widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    [
                      '${widget.connection.host.alias} · ${widget.connection.host.endpointLabel}',
                      if (_serverInfo != null)
                        [
                          if (_serverInfo?.hostname case final hostname?)
                            'hostname: $hostname',
                          if (_serverInfo?.ipAddress case final ip?) 'IP: $ip',
                        ].join(' · '),
                      if (_serverInfo?.operatingSystem case final os?)
                        'OS: $os',
                      if (_serverInfoLoading) '서버 정보 확인 중…',
                      if (!_serverInfoLoading && _serverInfo == null)
                        '서버 상세 정보 조회 불가',
                    ].join('\n'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: VibeColors.onSurfaceDim,
                    ),
                    maxLines: compact ? 3 : 5,
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed:
                          _loading ||
                              _busy ||
                              _sessions.where(_canSelect).isEmpty
                          ? null
                          : () => setState(
                              () => _selected.addAll(
                                _sessions
                                    .where(_canSelect)
                                    .map((session) => session.name),
                              ),
                            ),
                      child: const Text('전체 선택'),
                    ),
                    TextButton(
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : () => setState(_selected.clear),
                      child: const Text('선택 해제'),
                    ),
                    Text(
                      '${_selected.length}개 선택',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),

                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: _buildContent(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const ValueKey('open-selected-remote-sessions'),
                    onPressed:
                        _loading || _busy || _selected.isEmpty || !_connected
                        ? null
                        : _activateSelected,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(
                      _batchOpening
                          ? '작업 여는 중…'
                          : '선택한 작업 열기 (${_selected.length})',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    if (!_connected) {
      return const _RemoteSessionMessage(
        key: ValueKey('disconnected'),
        icon: Icons.cloud_off_outlined,
        title: '서버 연결을 기다리고 있습니다.',
        detail: '연결된 터미널에서 재접속하면 보관함을 다시 불러옵니다.',
      );
    }
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error case final error?) {
      return _RemoteSessionMessage(
        key: const ValueKey('error'),
        icon: Icons.cloud_off_outlined,
        title: '작업 목록을 불러오지 못했습니다.',
        detail: error,
        actionLabel: '다시 시도',
        onAction: _load,
      );
    }
    if (_sessions.isEmpty) {
      return const _RemoteSessionMessage(
        key: ValueKey('empty'),
        icon: Icons.all_inbox_outlined,
        title: '보관 중인 서버 작업이 없습니다.',
        detail: '작업 이어가기로 연결하면 이 서버에 생성된 작업이 여기에 표시됩니다.',
      );
    }

    return LayoutBuilder(
      key: const ValueKey('list'),
      builder: (context, constraints) => _buildList(
        stacked: constraints.maxWidth < _RemoteSessionCard.stackedBelow,
      ),
    );
  }

  Widget _buildList({required bool stacked}) {
    return ListView.separated(
      key: const ValueKey('remote-session-list'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final current = session.name == _currentSessionName;
        final localSession = ref
            .read(sessionManagerProvider.notifier)
            .localSessionForRemoteSession(
              widget.connection.host.id,
              session.remoteSessionId,
            );
        return _RemoteSessionCard(
          session: session,
          current: current,
          locallyOpen: localSession != null,
          localDisplayName:
              session.title ?? localSession?.displayName ?? session.displayName,
          ownedByThisInstallation: session.ownerId == _ownerId,
          opening: _opening.contains(session.name),
          terminating: _terminating.contains(session.name),
          onActivate: current || _busy ? null : () => _activate(session),
          onTerminate: current || _busy ? null : () => _terminate(session),
          selected: _selected.contains(session.name),
          onSelected: _busy || !_canSelect(session)
              ? null
              : (selected) => setState(() {
                  if (selected == true) {
                    _selected.add(session.name);
                  } else {
                    _selected.remove(session.name);
                  }
                }),
          stacked: stacked,
        );
      },
    );
  }
}

class _RemoteSessionCard extends StatelessWidget {
  const _RemoteSessionCard({
    required this.session,
    required this.current,
    required this.locallyOpen,
    required this.localDisplayName,
    required this.ownedByThisInstallation,
    required this.opening,
    required this.terminating,
    required this.onActivate,
    required this.onTerminate,
    required this.stacked,
    required this.selected,
    required this.onSelected,
  });

  final RemotePersistentSession session;

  /// 좁은 화면 배치(버튼을 아래 줄로). 카드의 상태 띠가 IntrinsicHeight를
  /// 쓰므로 카드 안에서 LayoutBuilder로 폭을 잴 수 없어 목록에서 정해 준다.
  final bool stacked;
  final bool selected;
  final ValueChanged<bool?>? onSelected;
  final bool current;
  final bool locallyOpen;
  final String? localDisplayName;
  final bool ownedByThisInstallation;
  final bool opening;
  final bool terminating;
  final VoidCallback? onActivate;
  final VoidCallback? onTerminate;

  /// 목록이 이보다 좁으면 카드의 버튼을 정보 아래 줄로 내린다. 버튼 묶음
  /// (약 160)과 배지·날짜가 한 줄에 들어갈 최소 폭이다.
  static const stackedBelow = 480.0;

  @override
  Widget build(BuildContext context) {
    final statusColor = session.isAttached
        ? VibeColors.statusConnected
        : VibeColors.statusDisconnected;
    return Container(
      decoration: BoxDecoration(
        color: current ? VibeColors.accentSoft : VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: current ? VibeColors.accent : VibeColors.borderSoft,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Checkbox(
                key: ValueKey('select-${session.name}'),
                value: selected,
                onChanged: onSelected,
              ),
            ),
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(10),
                ),
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final info = _buildInfo(statusColor, stacked: stacked);
                  final actions = _buildActions();
                  if (stacked) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 6, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          info,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(child: info),
                        const SizedBox(width: 8),
                        actions,
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(Color statusColor, {required bool stacked}) {
    final shortId = session.remoteSessionId.length > 10
        ? session.remoteSessionId.substring(session.remoteSessionId.length - 10)
        : session.remoteSessionId;
    const detailStyle = TextStyle(color: VibeColors.onSurfaceDim, fontSize: 11);
    final created = '생성 시각 · ${_formatDateTime(session.createdAt)}';
    final lastActive = '최근 활동 ${_formatDateTime(session.lastActivityAt)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 좁으면 배지가 다음 줄로 넘어가도록 Wrap으로 둔다.
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              current ? '현재 작업' : '보관된 작업',
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            _SessionBadge(
              label: session.isAttached ? '연결됨' : '분리됨',
              color: statusColor,
            ),
            _SessionBadge(
              label: _ownerLabel(),
              color: ownedByThisInstallation
                  ? VibeColors.accent
                  : VibeColors.secondary,
            ),
          ],
        ),
        if (localDisplayName case final displayName?) ...[
          const SizedBox(height: 7),
          Text(
            displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VibeColors.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (session.title == null) ...[
          const SizedBox(height: 3),
          const Text('서버에 저장된 세션명 없음', style: detailStyle),
        ],
        const SizedBox(height: 4),
        Text(
          '만든 PC · ${session.creatorDevice?.displayName ?? '알 수 없음'}',
          style: detailStyle,
        ),
        const SizedBox(height: 4),
        if (!session.isAttached)
          const Text('사용 중인 PC · 없음', style: detailStyle)
        else ...[
          for (final client in session.clients)
            Text(
              '사용 중인 PC · ${client.device?.displayName ?? '기기 정보 없음'}'
              '\n접속 시각 · ${_formatDateTime(client.connectedAt)}',
              style: detailStyle,
            ),
          if (session.attachedClients > session.clients.length)
            Text(
              '사용 중인 PC · 기기 정보 없음 '
              '(${session.attachedClients - session.clients.length}개 연결)',
              style: detailStyle,
            ),
        ],
        const SizedBox(height: 7),
        Text(
          '작업 ID · $shortId',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: VibeColors.onSurfaceMuted,
            fontFamily: kMonoFontFamily,
            fontFamilyFallback: kMonoFontFallback,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        if (stacked) ...[
          Text(created, style: detailStyle),
          const SizedBox(height: 2),
          Text(lastActive, style: detailStyle),
        ] else
          Text('$created  ·  $lastActive', style: detailStyle),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 112,
          child: OutlinedButton.icon(
            key: ValueKey('activate-${session.name}'),
            onPressed: opening ? null : onActivate,
            icon: opening
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    current
                        ? Icons.check_circle_outline
                        : locallyOpen
                        ? Icons.arrow_forward
                        : Icons.open_in_new,
                    size: 16,
                  ),
            label: Text(
              current
                  ? '현재 탭'
                  : locallyOpen
                  ? '전환'
                  : '새 탭 열기',
              maxLines: 1,
            ),
          ),
        ),
        const SizedBox(width: 2),
        if (terminating)
          const SizedBox.square(
            dimension: 40,
            child: Padding(
              padding: EdgeInsets.all(11),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            tooltip: current ? '현재 작업은 탭에서 닫아 주세요' : '서버 작업 종료',
            onPressed: opening ? null : onTerminate,
            icon: Icon(
              Icons.delete_outline,
              color: onTerminate == null
                  ? VibeColors.onSurfaceDim
                  : VibeColors.statusError,
            ),
          ),
      ],
    );
  }

  String _ownerLabel() {
    if (ownedByThisInstallation) return '이 기기';
    if (session.ownerId == 'legacy') return '이전 버전';
    return '다른 Vibe';
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) return '알 수 없음';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}.${two(value.month)}.${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)} (이 기기 시간)';
  }
}

class _SessionBadge extends StatelessWidget {
  const _SessionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RemoteSessionMessage extends StatelessWidget {
  const _RemoteSessionMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: VibeColors.onSurfaceDim),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VibeColors.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 14),
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
