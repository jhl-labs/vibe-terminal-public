import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../session/session_diagnostics.dart';
import '../../session/session.dart';
import '../../state/providers.dart';

/// 우측 패널. 활성 세션의 호스트·인증·연결 상태와 최근 연결 이벤트를 보여준다.
class SessionInfoPanel extends ConsumerStatefulWidget {
  const SessionInfoPanel({super.key});

  @override
  ConsumerState<SessionInfoPanel> createState() => _SessionInfoPanelState();
}

class _SessionInfoPanelState extends ConsumerState<SessionInfoPanel> {
  Timer? _uptimeTimer;

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  /// 연결 지속 시간(uptime)은 매초 갱신해야 하지만, 세션이 연결돼 있을 때만
  /// 타이머를 돌린다. 그 외에는 매초 rebuild할 이유가 없다.
  void _syncUptimeTimer(SessionInfo? active) {
    final shouldRun =
        active?.status == SessionStatus.connected &&
        active?.connectedAt != null;
    if (shouldRun && _uptimeTimer == null) {
      _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!shouldRun && _uptimeTimer != null) {
      _uptimeTimer!.cancel();
      _uptimeTimer = null;
    }
  }

  Color _statusColor(SessionStatus s) => switch (s) {
    SessionStatus.connecting => VibeColors.statusConnecting,
    SessionStatus.connected => VibeColors.statusConnected,
    SessionStatus.disconnected => VibeColors.statusDisconnected,
    SessionStatus.error => VibeColors.statusError,
  };

  /// connectedAt 기준 경과 시간을 "1h 02m 03s" 형태로 포맷.
  String _formatUptime(DateTime since) {
    var seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${_two(m)}m ${_two(s)}s';
    if (m > 0) return '${m}m ${_two(s)}s';
    return '${s}s';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatTime(DateTime t) {
    return '${t.year}-${_two(t.month)}-${_two(t.day)} '
        '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  }

  SessionInfo? _watchActiveSession() {
    final sessions = ref.watch(sessionManagerProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  /// 최근 연결 이벤트를 최신순으로 표시한다. 같은 이벤트가 연속되면 횟수로
  /// 묶어 keepalive 기록이 목록을 채우지 않도록 한다.
  List<Widget> _eventRows(String sessionId) {
    final events = ref.watch(sessionDiagnosticsProvider)[sessionId] ?? const [];
    if (events.isEmpty) {
      return const [
        Text(
          '아직 기록된 이벤트가 없습니다.',
          style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
        ),
      ];
    }
    final groups = <_SessionEventGroup>[];
    for (final event in events.reversed) {
      if (groups.isNotEmpty && groups.last.matches(event)) {
        groups.last.count++;
      } else {
        groups.add(_SessionEventGroup(event));
      }
    }
    return [
      for (final group in groups.take(30))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatTime(group.event.at),
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${group.event.type.label}'
                  '${group.count > 1 ? ' ×${group.count}' : ''}'
                  '${group.event.detail == null ? '' : ' (${group.event.detail})'}',
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final active = _watchActiveSession();
    _syncUptimeTimer(active);

    return Container(
      color: VibeColors.surface,
      child: Column(
        children: [
          const _PanelHeader(),
          Expanded(child: active == null ? _empty() : _details(active)),
        ],
      ),
    );
  }

  Widget _empty() {
    return const _EmptyState(
      icon: Icons.info_outline,
      title: '활성 세션 없음',
      message: '세션을 선택하면 호스트·인증 방식·연결 상태를 표시합니다.',
    );
  }

  Widget _details(SessionInfo session) {
    final host = session.host;
    final statusColor = _statusColor(session.status);
    final errorText = session.error ?? session.failure?.message;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                session.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VibeColors.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            Text(
              session.status.label,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _InfoRow(label: '호스트', value: host.alias),
        _InfoRow(label: '연결 방식', value: host.connectionType.label),
        _InfoRow(label: '엔드포인트', value: host.endpointLabel, mono: true),
        if (host.isLocalShell)
          _InfoRow(label: '셸', value: host.localShellLabel)
        else ...[
          _InfoRow(label: '사용자', value: host.username, mono: true),
          _InfoRow(label: '인증 방식', value: host.authType.label),
        ],
        if (session.connectedAt != null) ...[
          _InfoRow(
            label: '연결 시각',
            value: _formatTime(session.connectedAt!),
            mono: true,
          ),
          _InfoRow(
            label: '지속 시간',
            value: session.status == SessionStatus.connected
                ? _formatUptime(session.connectedAt!)
                : '-',
            mono: true,
          ),
        ],
        if (errorText != null && errorText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VibeColors.statusError.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: VibeColors.statusError.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: VibeColors.statusError,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorText,
                    style: const TextStyle(
                      color: VibeColors.statusError,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          '연결 이벤트',
          style: TextStyle(
            color: VibeColors.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        ..._eventRows(session.id),
      ],
    );
  }
}

class _SessionEventGroup {
  _SessionEventGroup(this.event);

  /// 이벤트는 최신순으로 탐색하므로 그룹의 시각은 가장 최근 이벤트 시각이다.
  final SessionEvent event;
  int count = 1;

  bool matches(SessionEvent other) =>
      event.type == other.type && event.detail == other.detail;
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: VibeColors.accent, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '세션 정보',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'host, auth, connection log',
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
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: VibeColors.onSurface,
                fontSize: 12.5,
                height: 1.3,
                fontFamily: mono ? kMonoFontFamily : null,
                fontFamilyFallback: mono ? kMonoFontFallback : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 보여줄 내용이 없을 때의 빈 상태(아이콘 + 제목 + 안내문).
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: VibeColors.onSurfaceDim, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
