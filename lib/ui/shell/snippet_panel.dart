import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../data/models/snippet.dart';
import '../../session/session.dart';
import '../../snippets/placeholder_parser.dart';
import '../../state/providers.dart';
import '../snippets/placeholder_form.dart';
import '../snippets/snippet_edit_page.dart';

/// 우측 패널. 스니펫 탭은 목록/검색/실행/편집/정렬, 정보 탭은 활성 세션의
/// 호스트·인증·연결 상태와 최근 연결 이벤트를 보여준다.
class SnippetPanel extends ConsumerStatefulWidget {
  const SnippetPanel({super.key});

  @override
  ConsumerState<SnippetPanel> createState() => _SnippetPanelState();
}

class _SnippetPanelState extends ConsumerState<SnippetPanel>
    with SingleTickerProviderStateMixin {
  static const _infoTabIndex = 1;

  String _query = '';
  Timer? _uptimeTimer;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    // 탭이 바뀌면 uptime 타이머를 켜거나 끄기 위해 다시 build한다.
    _tab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _tab
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// 정보 탭의 연결 지속 시간(uptime)은 매초 갱신해야 하지만, 정보 탭이
  /// 보이고 세션이 연결돼 있을 때만 타이머를 돌린다. 그 외에는 매초 rebuild할
  /// 이유가 없다.
  void _syncUptimeTimer(SessionInfo? active) {
    final shouldRun =
        _tab.index == _infoTabIndex &&
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

  SessionInfo? _activeSession() {
    final sessions = ref.read(sessionManagerProvider);
    final activeId = ref.read(activeSessionIdProvider);
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  Future<void> _run(Snippet s, SnippetRunMode mode) async {
    final active = _activeSession();
    if (active == null || active.status != SessionStatus.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결된 활성 세션이 없습니다')));
      return;
    }
    var body = s.body;
    final names = PlaceholderParser.extract(body);
    if (names.isNotEmpty) {
      final values = await showPlaceholderForm(context, names);
      if (values == null) return; // 취소
      body = PlaceholderParser.substitute(body, values);
    }
    active.engine.terminal.textInput(
      mode == SnippetRunMode.run ? '$body\n' : body,
    );
  }

  Future<void> _edit(Snippet? existing) async {
    final hostId = _activeSession()?.host.id;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SnippetEditPage(existing: existing, currentHostId: hostId),
      ),
    );
    ref.invalidate(snippetListProvider);
  }

  void _showError(String prefix, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$prefix: $error')));
  }

  Future<void> _delete(Snippet s) async {
    try {
      await ref.read(snippetRepositoryProvider).delete(s.id);
    } catch (e) {
      _showError('삭제 실패', e);
      return;
    }
    ref.invalidate(snippetListProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('스니펫을 삭제했습니다'),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () => unawaited(_restoreDeleted(s)),
          ),
        ),
      );
  }

  Future<void> _restoreDeleted(Snippet s) async {
    try {
      await ref.read(snippetRepositoryProvider).upsert(s);
    } catch (e) {
      _showError('복원 실패', e);
      return;
    }
    ref.invalidate(snippetListProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('스니펫을 복원했습니다')));
  }

  /// [s]와 [neighbour]의 sortOrder를 맞바꿔 목록에서 한 칸 이동한다.
  Future<void> _swapWith(Snippet s, Snippet neighbour) async {
    try {
      await ref
          .read(snippetRepositoryProvider)
          .swapSortOrder(s.id, neighbour.id);
    } catch (e) {
      _showError('순서 변경 실패', e);
      return;
    }
    ref.invalidate(snippetListProvider);
  }

  Widget _snippetTab() {
    final asyncSnippets = ref.watch(snippetListProvider);
    final hostId = _activeSession()?.host.id;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '스니펫 검색',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: asyncSnippets.when(
            data: (all) {
              final inScope = all
                  .where(
                    (s) =>
                        s.scope == SnippetScope.global ||
                        (hostId != null && s.hostId == hostId),
                  )
                  .toList();
              final query = _query.trim().toLowerCase();
              // 이름뿐 아니라 본문(명령어)도 검색 대상이다.
              final visible = query.isEmpty
                  ? inScope
                  : inScope
                        .where(
                          (s) =>
                              s.name.toLowerCase().contains(query) ||
                              s.body.toLowerCase().contains(query),
                        )
                        .toList();
              if (visible.isEmpty) {
                return Center(
                  child: Text(
                    inScope.isEmpty ? '스니펫이 없습니다' : '검색 결과가 없습니다',
                    style: const TextStyle(color: VibeColors.onSurfaceDim),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final s = visible[index];
                  return _SnippetTile(
                    snippet: s,
                    onTap: () => _run(s, s.defaultRunMode),
                    onLongPress: () => _showActions(
                      s,
                      above: index > 0 ? visible[index - 1] : null,
                      below: index < visible.length - 1
                          ? visible[index + 1]
                          : null,
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('오류: $e')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('스니펫 추가'),
            ),
          ),
        ),
      ],
    );
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

  /// 세션 상태 변화에 반응하도록 watch로 활성 세션을 찾는다.
  SessionInfo? _watchActiveSession() {
    final sessions = ref.watch(sessionManagerProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  Widget _infoTab() {
    final active = _watchActiveSession();

    if (active == null) {
      return const _EmptyState(
        icon: Icons.info_outline,
        title: '세션 정보',
        message: '활성 세션이 없습니다.\n세션을 선택하면 호스트·인증 방식·연결 상태를 표시합니다.',
      );
    }

    final session = active;
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

  /// 최근 연결 이벤트를 최신순으로 최대 30건 표시한다.
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
    return [
      for (final e in events.reversed.take(30))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatTime(e.at),
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
                  e.detail == null
                      ? e.type.label
                      : '${e.type.label} (${e.detail})',
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

  /// 길게 눌렀을 때의 동작 시트. [above]/[below]는 현재 목록에서의 이웃으로,
  /// 없으면(맨 위/맨 아래) 해당 이동 항목을 숨긴다.
  void _showActions(Snippet s, {Snippet? above, Snippet? below}) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('실행'),
              onTap: () {
                Navigator.pop(ctx);
                _run(s, SnippetRunMode.run);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('붙여넣기'),
              onTap: () {
                Navigator.pop(ctx);
                _run(s, SnippetRunMode.paste);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('편집'),
              onTap: () {
                Navigator.pop(ctx);
                _edit(s);
              },
            ),
            if (above != null)
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('위로 이동'),
                onTap: () {
                  Navigator.pop(ctx);
                  _swapWith(s, above);
                },
              ),
            if (below != null)
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('아래로 이동'),
                onTap: () {
                  Navigator.pop(ctx);
                  _swapWith(s, below);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('삭제'),
              onTap: () {
                Navigator.pop(ctx);
                _delete(s);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 세션 상태 변화에 따라 uptime 타이머를 켜고 끈다.
    _syncUptimeTimer(_watchActiveSession());
    return Container(
      color: VibeColors.surface,
      child: Column(
        children: [
          const _PanelHeader(),
          TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: '스니펫'),
              Tab(text: '정보'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_snippetTab(), _infoTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Icon(Icons.code, color: VibeColors.accent, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Command shelf',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'runbooks and snippets',
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

class _SnippetTile extends StatelessWidget {
  const _SnippetTile({
    required this.snippet,
    required this.onTap,
    required this.onLongPress,
  });

  final Snippet snippet;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final hostScoped = snippet.scope == SnippetScope.host;
    return Material(
      color: VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VibeColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hostScoped ? Icons.dns : Icons.public,
                    size: 16,
                    color: hostScoped
                        ? VibeColors.secondary
                        : VibeColors.onSurfaceDim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      snippet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.play_arrow,
                    size: 17,
                    color: VibeColors.accent,
                  ),
                ],
              ),
              if (snippet.body != snippet.name) ...[
                const SizedBox(height: 8),
                Text(
                  snippet.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
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

/// 탭에 보여줄 내용이 없을 때의 빈 상태(아이콘 + 제목 + 안내문).
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
