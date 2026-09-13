import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/result.dart';
import '../../session/session.dart';
import '../../session/session_manager.dart';
import '../../ssh/remote_session_catalog.dart';
import '../../state/providers.dart';
import '../security/keyboard_interactive_prompt.dart';

Future<void> showRemoteSessionManagerDialog(
  BuildContext context,
  SessionInfo connection,
) => showDialog<void>(
  context: context,
  builder: (_) => _RemoteSessionManagerDialog(connection: connection),
);

class _RemoteSessionManagerDialog extends ConsumerStatefulWidget {
  const _RemoteSessionManagerDialog({required this.connection});

  final SessionInfo connection;

  @override
  ConsumerState<_RemoteSessionManagerDialog> createState() =>
      _RemoteSessionManagerDialogState();
}

class _RemoteSessionManagerDialogState
    extends ConsumerState<_RemoteSessionManagerDialog> {
  var _loading = true;
  String? _error;
  String? _ownerId;
  String? _currentSessionName;
  List<RemotePersistentSession> _sessions = const [];
  final Set<String> _opening = {};
  final Set<String> _terminating = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final manager = ref.read(sessionManagerProvider.notifier);
    final ownerId = await manager.currentRemoteSessionOwnerId();
    final currentName = manager.currentPersistentSessionName(
      widget.connection.id,
    );
    final result = await manager.listRemotePersistentSessions(
      widget.connection.id,
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() {
          _ownerId = ownerId;
          _currentSessionName = currentName;
          _sessions = value;
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
    final completed = await ref
        .read(sessionManagerProvider.notifier)
        .terminateListedRemoteSession(widget.connection.id, session);
    if (!mounted) return;
    setState(() => _terminating.remove(session.name));
    if (completed) {
      await _load();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('소유권을 확인하지 못했거나 연결이 끊겨 작업을 종료하지 않았습니다.')),
    );
  }

  Future<void> _activate(RemotePersistentSession session) async {
    setState(() => _opening.add(session.name));
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

    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 14, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: VibeColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: VibeColors.accent.withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: VibeColors.accent,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('서버 작업 보관함'),
                SizedBox(height: 2),
                Text(
                  'Vibe Terminal이 만든 작업만 표시합니다.',
                  style: TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 440,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _buildContent(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _buildContent() {
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

    return ListView.separated(
      key: const ValueKey('list'),
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
        final busy = _opening.isNotEmpty || _terminating.isNotEmpty;
        return _RemoteSessionCard(
          session: session,
          current: current,
          locallyOpen: localSession != null,
          localDisplayName: localSession?.displayName,
          ownedByThisInstallation: session.ownerId == _ownerId,
          opening: _opening.contains(session.name),
          terminating: _terminating.contains(session.name),
          onActivate: current || busy ? null : () => _activate(session),
          onTerminate: current || busy ? null : () => _terminate(session),
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
  });

  final RemotePersistentSession session;
  final bool current;
  final bool locallyOpen;
  final String? localDisplayName;
  final bool ownedByThisInstallation;
  final bool opening;
  final bool terminating;
  final VoidCallback? onActivate;
  final VoidCallback? onTerminate;

  @override
  Widget build(BuildContext context) {
    final statusColor = session.isAttached
        ? VibeColors.statusConnected
        : VibeColors.statusDisconnected;
    final shortId = session.remoteSessionId.length > 10
        ? session.remoteSessionId.substring(session.remoteSessionId.length - 10)
        : session.remoteSessionId;
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
          children: [
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            current ? '현재 작업' : '보관된 작업',
                            style: const TextStyle(
                              color: VibeColors.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _SessionBadge(
                          label: session.isAttached ? '연결됨' : '분리됨',
                          color: statusColor,
                        ),
                        const SizedBox(width: 6),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VibeColors.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      '작업 ID · $shortId',
                      style: const TextStyle(
                        color: VibeColors.onSurfaceMuted,
                        fontFamily: kMonoFontFamily,
                        fontFamilyFallback: kMonoFontFallback,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '생성 ${_formatDateTime(session.createdAt)}  ·  '
                      '최근 활동 ${_formatDateTime(session.lastActivityAt)}',
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
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
              ),
            ),
          ],
        ),
      ),
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
        '${two(value.hour)}:${two(value.minute)}';
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
    );
  }
}
