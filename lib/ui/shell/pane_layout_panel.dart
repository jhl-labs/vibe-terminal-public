import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../session/session.dart';
import '../../session/session_pane_layout.dart';
import 'panes/pane_preset_icon.dart';
import 'session_pane_deck.dart';

/// 우측 "화면 분할 관리" 앱. 예전 분할 상단 툴바에 흩어져 있던 배치·분할·
/// 되돌리기·칸 선택과 도구 버튼을 한곳에 모은다.
///
/// 배치 편집은 [deck]([SessionPaneDeckState])에 위임한다 — 명령 팔레트와 같은
/// 경로라 공간 검사·세션 선택 다이얼로그·되돌리기 이력이 한 군데서만 돈다.
/// [layout]·[sessions]는 앱 셸이 provider에서 읽어 넘기므로 배치가 바뀌면
/// 패널도 다시 그려진다. 확대 상태와 캔버스 크기(프리셋 가능 여부)는 deck 안에
/// 있어 [SessionPaneDeckState.revision]을 따로 듣는다.
class PaneLayoutPanel extends StatefulWidget {
  const PaneLayoutPanel({
    super.key,
    required this.deck,
    required this.sessions,
    required this.layout,
    this.canUndo = false,
    this.storageError,
    this.onRetrySave,
    this.onWorkspace,
    this.onControl,
    this.controlEnabled = false,
    this.onBackground,
    this.onAfterAction,
  });

  final GlobalKey<SessionPaneDeckState> deck;

  /// 배치·칸·도구 조작 직후 호출된다. 모바일은 이 패널이 화면 전체를 덮는
  /// endDrawer라 여기서 drawer를 닫아 결과가 바로 보이게 한다.
  final VoidCallback? onAfterAction;

  /// 현재 그룹의 세션. 빈 목록이면 안내만 보여준다.
  final List<SessionInfo> sessions;
  final SessionPaneLayout layout;
  final bool canUndo;

  /// 배치 저장 실패 메시지. null이면 배너를 그리지 않는다.
  final String? storageError;
  final VoidCallback? onRetrySave;

  /// 도구 버튼. null이면 해당 항목을 그리지 않는다(빌드 피처·상태에 따라 결정).
  final VoidCallback? onWorkspace, onControl, onBackground;
  final bool controlEnabled;

  @override
  State<PaneLayoutPanel> createState() => _PaneLayoutPanelState();
}

class _PaneLayoutPanelState extends State<PaneLayoutPanel> {
  ValueNotifier<int>? _revision;

  SessionPaneDeckState? get _deck => widget.deck.currentState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenDeck();
  }

  @override
  void didUpdateWidget(PaneLayoutPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listenDeck();
  }

  /// deck은 세션이 생기고 나서야 마운트되므로 빌드 때마다 다시 붙는다.
  void _listenDeck() {
    final next = _deck?.revision;
    if (identical(next, _revision)) return;
    _revision?.removeListener(_onDeckChanged);
    _revision = next?..addListener(_onDeckChanged);
  }

  void _onDeckChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _revision?.removeListener(_onDeckChanged);
    super.dispose();
  }

  SessionInfo? _session(String? id) {
    for (final s in widget.sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  String _name(String? sessionId) => _session(sessionId)?.displayName ?? '빈 칸';

  /// [action]을 실행하고 [PaneLayoutPanel.onAfterAction]을 부른다.
  VoidCallback? _act(VoidCallback? action) => action == null
      ? null
      : () {
          action();
          widget.onAfterAction?.call();
        };

  @override
  Widget build(BuildContext context) {
    final deck = _deck;
    final layout = widget.layout;
    final ids = widget.sessions.map((s) => s.id).toList();
    final current = _shape(layout.root);
    final zoomed = deck?.isZoomed ?? false;
    final canSplit = layout.count < 4 && deck != null;
    return Material(
      color: VibeColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeader(),
          if (widget.storageError != null)
            _StorageErrorBanner(
              message: widget.storageError!,
              onRetry: widget.onRetrySave,
            ),
          Expanded(
            child: widget.sessions.isEmpty || deck == null
                ? const _Empty()
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      const _Section('배치'),
                      for (final preset in PanePreset.values)
                        _PresetTile(
                          preset: preset,
                          selected:
                              _shape(layout.preset(preset, ids).root) ==
                              current,
                          fits: deck.fitsPreset(preset),
                          names: layout
                              .preset(preset, ids)
                              .panes
                              .map((p) => _name(p.sessionId))
                              .join(' · '),
                          onTap: _act(() => deck.applyPreset(preset))!,
                        ),
                      const _Section('현재 칸'),
                      _ActionTile(
                        key: const ValueKey('layout-split-right'),
                        icon: Icons.vertical_split,
                        label: '오른쪽에 나누기',
                        onTap: _act(
                          canSplit
                              ? () => deck.splitFocused(PaneAxis.leftRight)
                              : null,
                        ),
                      ),
                      _ActionTile(
                        key: const ValueKey('layout-split-down'),
                        icon: Icons.horizontal_split,
                        label: '아래에 나누기',
                        onTap: _act(
                          canSplit
                              ? () => deck.splitFocused(PaneAxis.topBottom)
                              : null,
                        ),
                      ),
                      _ActionTile(
                        key: const ValueKey('layout-zoom'),
                        icon: zoomed ? Icons.fullscreen_exit : Icons.fullscreen,
                        label: zoomed ? '분할로 돌아가기' : '이 칸 확대',
                        onTap: _act(layout.count > 1 ? deck.toggleZoom : null),
                      ),
                      _ActionTile(
                        key: const ValueKey('layout-remove'),
                        icon: Icons.remove_circle_outline,
                        label: '이 칸 없애기',
                        subtitle: '세션 연결은 목록에 유지됩니다',
                        onTap: _act(
                          layout.count > 1 ? deck.removeFocused : null,
                        ),
                      ),
                      _ActionTile(
                        key: const ValueKey('layout-undo'),
                        icon: Icons.undo,
                        label: '배치 되돌리기',
                        onTap: _act(widget.canUndo ? deck.undo : null),
                      ),
                      const _Section('칸 목록'),
                      for (final (index, pane) in layout.panes.indexed)
                        ListTile(
                          key: ValueKey('layout-pane-${pane.id}'),
                          dense: true,
                          selected: pane.id == layout.focused.id,
                          leading: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontFamily: kMonoFontFamily,
                              fontFamilyFallback: kMonoFontFallback,
                            ),
                          ),
                          title: Text(
                            _name(pane.sessionId),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: pane.id == layout.focused.id
                              ? const Icon(Icons.keyboard, size: 16)
                              : null,
                          onTap: _act(() => deck.focusPane(pane.id)),
                        ),
                      if (widget.onWorkspace != null ||
                          widget.onControl != null ||
                          widget.onBackground != null) ...[
                        const _Section('도구'),
                        if (widget.onWorkspace != null)
                          _ActionTile(
                            key: const ValueKey('layout-tool-workspace'),
                            icon: Icons.folder_open,
                            label: '작업공간 패널 표시',
                            onTap: _act(widget.onWorkspace),
                          ),
                        if (widget.onControl != null)
                          _ActionTile(
                            key: const ValueKey('layout-tool-control'),
                            icon: Icons.lan_outlined,
                            label: widget.controlEnabled
                                ? '외부 제어 실행 중'
                                : '외부 제어',
                            onTap: _act(widget.onControl),
                          ),
                        if (widget.onBackground != null)
                          _ActionTile(
                            key: const ValueKey('layout-tool-background'),
                            icon: Icons.settings_backup_restore,
                            label: '로컬 백그라운드 작업',
                            onTap: _act(widget.onBackground),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 칸 id·세션·비율을 뺀 모양만 남긴 서명. 현재 배치가 어느 프리셋인지 고를 때 쓴다.
String _shape(PaneNode node) => switch (node) {
  PaneLeaf() => '.',
  PaneSplit(:final axis, :final first, :final second) =>
    '(${axis.name} ${_shape(first)} ${_shape(second)})',
};

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Row(
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            color: VibeColors.accent,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '화면 분할 관리',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'layout · panes · tools',
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

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      title,
      style: const TextStyle(
        color: VibeColors.onSurfaceDim,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .4,
      ),
    ),
  );
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.fits,
    required this.names,
    required this.onTap,
  });
  final PanePreset preset;
  final bool selected, fits;
  final String names;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('layout-preset-${preset.name}'),
    dense: true,
    enabled: fits,
    selected: selected,
    leading: PanePresetIcon(preset),
    title: Text(panePresetLabel(preset)),
    subtitle: Text(
      fits ? names : '공간 부족 · 패널을 접거나 창을 넓혀 주세요',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: selected ? const Icon(Icons.check, size: 16) : null,
    onTap: fits && !selected ? onTap : null,
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    enabled: onTap != null,
    leading: Icon(icon, size: 20),
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle!),
    onTap: onTap,
  );
}

class _StorageErrorBanner extends StatelessWidget {
  const _StorageErrorBanner({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('layout-storage-error'),
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.orange.withValues(alpha: .5)),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        TextButton(
          key: const ValueKey('layout-storage-retry'),
          onPressed: onRetry,
          child: const Text('재시도'),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(18),
    child: Text(
      '열린 세션이 없습니다. 세션을 열면 배치와 분할을 관리할 수 있습니다.',
      style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 13),
    ),
  );
}
