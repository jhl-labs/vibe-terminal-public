import 'package:flutter/material.dart';
import '../../session/session.dart';
import '../../session/session_pane_layout.dart';
import 'panes/pane_activity_frame.dart';
import 'panes/pane_geometry.dart';
import 'panes/pane_divider_handle.dart';
import 'panes/pane_preset_icon.dart';

class SessionPaneDeck extends StatefulWidget {
  const SessionPaneDeck({
    super.key,
    required this.sessions,
    required this.groupId,
    required this.activeId,
    required this.layout,
    required this.onLayout,
    required this.onActivate,
    required this.terminalBuilder,
    this.onNewSession,
    this.onControl,
    this.onBulk,
    this.onBackground,
    this.onWorkspace,
    this.storageError,
    this.onRetrySave,
    this.controlEnabled = false,
    this.onCloseSession,
    this.onUndo,
    this.canUndo = false,
    this.onPreviousSession,
    this.onNextSession,
    this.minimumPaneSize = const Size(320, 224),
    this.activity = const {},
  });

  /// All groups stay mounted; only the current group's rectangles are visible.
  final List<SessionInfo> sessions;
  final String groupId;
  final String? activeId;
  final SessionPaneLayout layout;
  final ValueChanged<SessionPaneLayout> onLayout;
  final ValueChanged<String?> onActivate;
  final Widget Function(SessionInfo, Widget Function(Map<String, VoidCallback>))
  terminalBuilder;
  final Future<void> Function(String paneId, SessionInfo? duplicate)?
  onNewSession;
  final VoidCallback? onControl,
      onBulk,
      onBackground,
      onWorkspace,
      onRetrySave,
      onUndo;
  final ValueChanged<SessionInfo>? onCloseSession;

  /// 목록 순서로 이전/다음 세션을 활성화한다(그룹 조작이라 칸 메뉴가 아닌 상단
  /// 툴바에 둔다). 대상 세션이 이미 칸에 있으면 그 칸으로 포커스가 가고, 없으면
  /// 포커스된 칸의 세션이 바뀐다. null이면 버튼을 비활성화한다.
  final VoidCallback? onPreviousSession, onNextSession;
  final String? storageError;
  final bool controlEnabled, canUndo;
  final Size minimumPaneSize;

  /// 세션별 활동 상태. 칸 테두리가 레일의 스피너·Agent 상태와 같이 움직인다.
  final Map<String, PaneActivity> activity;
  @override
  State<SessionPaneDeck> createState() => SessionPaneDeckState();
}

class SessionPaneDeckState extends State<SessionPaneDeck> {
  final _zoomed = <String>{};
  final _lastBounds = <String, Rect>{};
  SessionPaneLayout? _preview;
  final _resizeRatios = <String, double>{};
  Size _size = Size.zero;
  final _canvasKey = GlobalKey();
  bool _autoCompact = false;
  String? _dropPane;
  String? _dropSide;
  PaneSessionDrag? _drag;
  SessionPaneLayout get _layout => _preview ?? widget.layout;
  List<SessionInfo> get _groupSessions =>
      widget.sessions.where((s) => s.groupId == widget.groupId).toList();
  List<String> get _ids => _groupSessions.map((s) => s.id).toList();
  PaneGeometryResolver get _resolver =>
      PaneGeometryResolver(minimum: widget.minimumPaneSize);
  bool get _isZoomed => _zoomed.contains(widget.groupId);

  @override
  void didUpdateWidget(SessionPaneDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId ||
        oldWidget.layout != widget.layout) {
      _preview = null;
      _resizeRatios.clear();
      _dropPane = null;
      _drag = null;
      _dropSide = null;
    }
    _lastBounds.removeWhere((id, _) => !widget.sessions.any((s) => s.id == id));
  }

  void _commit(SessionPaneLayout next, {bool exitZoom = false}) {
    setState(() {
      _preview = null;
      _dropPane = null;
      _drag = null;
      _dropSide = null;
      if (exitZoom) _zoomed.remove(widget.groupId);
    });
    widget.onLayout(next);
    final id = next.focused.sessionId;
    widget.onActivate(_ids.contains(id) ? id : null);
  }

  void _focus(String paneId) {
    final next = widget.layout.focus(paneId);
    // Focus is not an undoable layout edit.
    if (_ids.contains(next.focused.sessionId)) {
      widget.onActivate(next.focused.sessionId);
    } else {
      widget.onLayout(next);
      widget.onActivate(null);
    }
  }

  bool _fits(SessionPaneLayout layout) {
    final min = _resolver.minimumFor(layout.root);
    return layout.count == 1 ||
        (_size.width >= min.width && _size.height >= min.height);
  }

  void _notice(String message) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
  void applyPreset(PanePreset preset) {
    final next = widget.layout.preset(preset, _ids);
    if (!_fits(next)) {
      _notice('공간이 부족합니다. 패널을 접거나 창을 넓혀 주세요.');
      return;
    }
    final hidden = widget.layout.slots
        .where((id) => !next.slots.contains(id))
        .length;
    _commit(next, exitZoom: true);
    if (hidden > 0) _notice('$hidden개 세션은 목록에 보관했습니다. 배치 메뉴에서 되돌릴 수 있습니다.');
  }

  Future<void> splitFocused(PaneAxis axis) =>
      _split(widget.layout.focused.id, axis);
  Future<void> _split(String paneId, PaneAxis axis) async {
    final source = _session(widget.layout.pane(paneId)?.sessionId);
    final next = widget.layout.split(paneId, axis);
    if (identical(next, widget.layout)) {
      _notice('최대 4칸까지 나눌 수 있습니다.');
      return;
    }
    if (!_fits(next)) {
      _notice('새 칸을 표시할 공간이 부족합니다. 패널을 접거나 창을 넓혀 주세요.');
      return;
    }
    _commit(next, exitZoom: true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && widget.layout.pane(next.focused.id) != null) {
      await _pickSession(next.focused.id, duplicateSource: source);
    }
  }

  void toggleZoom() {
    setState(() {
      if (!_zoomed.remove(widget.groupId)) _zoomed.add(widget.groupId);
    });
  }

  void removeFocused() =>
      _commit(widget.layout.remove(widget.layout.focused.id));
  void undo() {
    setState(() {
      _preview = null;
    });
    widget.onUndo?.call();
  }

  void focusNeighbor(TraversalDirection direction) {
    final geometry = _resolver.resolve(widget.layout, _size);
    final origin = geometry.panes[widget.layout.focused.id];
    if (origin == null) return;
    final candidates =
        geometry.panes.entries.where((e) {
          if (e.key == widget.layout.focused.id) return false;
          return switch (direction) {
            TraversalDirection.left => e.value.center.dx < origin.center.dx,
            TraversalDirection.right => e.value.center.dx > origin.center.dx,
            TraversalDirection.up => e.value.center.dy < origin.center.dy,
            TraversalDirection.down => e.value.center.dy > origin.center.dy,
          };
        }).toList()..sort(
          (a, b) => (a.value.center - origin.center).distanceSquared.compareTo(
            (b.value.center - origin.center).distanceSquared,
          ),
        );
    if (candidates.isNotEmpty) _focus(candidates.first.key);
  }

  Future<void> showPresets() async {
    final selected = await showDialog<PanePreset>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('터미널 배치'),
        children: [
          for (final preset in PanePreset.values)
            Builder(
              builder: (context) {
                final preview = widget.layout.preset(preset, _ids);
                final fits = _fits(preview);
                final names = preview.panes
                    .map((p) => _session(p.sessionId)?.displayName ?? '빈 칸')
                    .join(' · ');
                return ListTile(
                  key: ValueKey('preset-${preset.name}'),
                  enabled: fits,
                  leading: PanePresetIcon(preset),
                  title: Text(panePresetLabel(preset)),
                  subtitle: Text(
                    fits ? names : '공간 부족 · 패널을 접거나 창을 넓혀 주세요',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: fits ? () => Navigator.pop(context, preset) : null,
                );
              },
            ),
          const Divider(),
          ListTile(
            enabled: widget.canUndo,
            leading: const Icon(Icons.undo),
            title: const Text('배치 되돌리기'),
            onTap: widget.canUndo
                ? () {
                    Navigator.pop(context);
                    undo();
                  }
                : null,
          ),
        ],
      ),
    );
    if (selected != null && mounted) applyPreset(selected);
  }

  SessionInfo? _session(String? id) {
    for (final s in widget.sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _pickSession(
    String paneId, {
    SessionInfo? duplicateSource,
  }) async {
    final group = widget.groupId;
    final before = widget.layout;
    final duplicate = duplicateSource ?? _session(before.focused.sessionId);
    final options = [..._groupSessions]
      ..sort(
        (a, b) => (before.slots.contains(a.id) ? 1 : 0).compareTo(
          before.slots.contains(b.id) ? 1 : 0,
        ),
      );
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('이 칸에 표시할 세션'),
        children: [
          for (final session in options)
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(session.displayName),
              subtitle: Text(
                before.paneForSession(session.id) == null
                    ? '열린 세션 · 이 칸에 표시'
                    : '이미 표시 중 · 해당 칸으로 이동',
              ),
              onTap: () => Navigator.pop(context, session.id),
            ),
          if (widget.onNewSession != null) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('새 연결 / 로컬 터미널'),
              onTap: () => Navigator.pop(context, ':new:'),
            ),
            if (duplicate != null)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('같은 호스트에 새 연결'),
                onTap: () => Navigator.pop(context, ':duplicate:'),
              ),
          ],
        ],
      ),
    );
    if (!mounted ||
        selected == null ||
        group != widget.groupId ||
        !identical(widget.layout, before) ||
        widget.layout.pane(paneId) == null) {
      return;
    }
    if (selected == ':new:' || selected == ':duplicate:') {
      await widget.onNewSession?.call(
        paneId,
        selected == ':duplicate:' ? duplicate : null,
      );
    } else if (_ids.contains(selected)) {
      final existing = widget.layout.paneForSession(selected);
      if (existing != null) {
        _focus(existing.id);
      } else {
        _commit(widget.layout.assign(paneId, selected));
      }
    }
  }

  Future<void> _paneMenu(
    String paneId,
    Map<String, VoidCallback> terminalActions,
  ) async {
    final group = widget.groupId;
    final pane = widget.layout.pane(paneId);
    if (pane == null) return;
    final command = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('칸 조작'),
        children: [
          ListTile(
            leading: const Icon(Icons.vertical_split),
            title: const Text('오른쪽에 나누기'),
            enabled: widget.layout.count < 4,
            onTap: widget.layout.count < 4
                ? () => Navigator.pop(context, 'right')
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.horizontal_split),
            title: const Text('아래에 나누기'),
            enabled: widget.layout.count < 4,
            onTap: widget.layout.count < 4
                ? () => Navigator.pop(context, 'down')
                : null,
          ),
          for (final other in widget.layout.panes.where((p) => p.id != paneId))
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(
                '${_session(other.sessionId)?.displayName ?? '빈 칸'}과 교환',
              ),
              onTap: () => Navigator.pop(context, 'swap:${other.id}'),
            ),
          const Divider(),
          for (final action in terminalActions.entries)
            ListTile(
              title: Text(action.key),
              onTap: () => Navigator.pop(context, 'terminal:${action.key}'),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: const Text('이 칸 없애기'),
            subtitle: const Text('세션 연결은 목록에 유지됩니다'),
            onTap: () => Navigator.pop(context, 'remove'),
          ),
          if (pane.sessionId != null && widget.onCloseSession != null)
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('세션 닫기'),
              subtitle: const Text('연결 종료 · 칸 제거와 별개'),
              onTap: () => Navigator.pop(context, 'close-session'),
            ),
        ],
      ),
    );
    if (!mounted ||
        command == null ||
        group != widget.groupId ||
        widget.layout.pane(paneId) == null) {
      return;
    }
    if (command == 'right' || command == 'down') {
      await _split(
        paneId,
        command == 'right' ? PaneAxis.leftRight : PaneAxis.topBottom,
      );
    } else if (command == 'remove') {
      _commit(widget.layout.remove(paneId));
    } else if (command == 'close-session') {
      final session = _session(pane.sessionId);
      if (session != null) widget.onCloseSession?.call(session);
    } else if (command.startsWith('swap:')) {
      _commit(widget.layout.swap(paneId, command.substring(5)));
    } else if (command.startsWith('terminal:')) {
      terminalActions[command.substring(9)]?.call();
    }
  }

  Widget _header(
    PaneLeaf pane,
    SessionInfo? session,
    Map<String, VoidCallback> actions,
  ) {
    final active = pane.id == widget.layout.focused.id;
    final number = widget.layout.panes.indexWhere((p) => p.id == pane.id) + 1;
    final status = switch (session?.status) {
      SessionStatus.connected => '연결됨',
      SessionStatus.connecting => '연결 중',
      SessionStatus.error => '연결 오류',
      SessionStatus.disconnected => '연결 끊김',
      null => '빈 칸',
    };
    final title = session?.displayName ?? '세션 선택';
    final label =
        '$number/${widget.layout.count} $title · $status${active ? ' · 입력 대상' : ''}';
    final name = GestureDetector(
      onDoubleTap: () {
        _focus(pane.id);
        toggleZoom();
      },
      child: TextButton(
        onPressed: () => _pickSession(pane.id),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$number  $title',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: label,
      child: Material(
        color: active ? const Color(0xff183b3a) : const Color(0xff182332),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: status,
                  child: Icon(
                    Icons.circle,
                    size: 8,
                    color: session?.status == SessionStatus.connected
                        ? Colors.tealAccent
                        : Colors.orangeAccent,
                  ),
                ),
              ),
              Expanded(
                child: session == null
                    ? name
                    : Draggable<PaneSessionDrag>(
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        data: PaneSessionDrag(session.id, widget.groupId),
                        onDragStarted: () => setState(
                          () => _drag = PaneSessionDrag(
                            session.id,
                            widget.groupId,
                          ),
                        ),
                        onDragEnd: (_) => setState(() {
                          _drag = null;
                          _dropPane = null;
                          _dropSide = null;
                        }),
                        feedback: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(title),
                          ),
                        ),
                        child: name,
                      ),
              ),
              IconButton(
                key: ValueKey('pane-zoom-${pane.id}'),
                tooltip: _isZoomed ? '분할로 돌아가기' : '이 칸 확대',
                icon: Icon(
                  _isZoomed ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                onPressed: () {
                  _focus(pane.id);
                  toggleZoom();
                },
              ),
              IconButton(
                key: ValueKey('pane-menu-${pane.id}'),
                tooltip: '칸 조작',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _paneMenu(pane.id, actions),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('pane-layout-picker'),
                  onPressed: showPresets,
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('배치'),
                ),
                PopupMenuButton<PaneAxis>(
                  tooltip: '현재 칸 분할',
                  onSelected: splitFocused,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: PaneAxis.leftRight,
                      enabled: widget.layout.count < 4,
                      child: const Text('오른쪽에 나누기'),
                    ),
                    PopupMenuItem(
                      value: PaneAxis.topBottom,
                      enabled: widget.layout.count < 4,
                      child: const Text('아래에 나누기'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('분할 ▾'),
                  ),
                ),
                if (_isZoomed)
                  TextButton.icon(
                    onPressed: toggleZoom,
                    icon: const Icon(Icons.fullscreen_exit),
                    label: const Text('분할로 돌아가기'),
                  ),
                IconButton(
                  key: const ValueKey('pane-session-prev'),
                  tooltip: '이전 세션',
                  onPressed: widget.onPreviousSession,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  key: const ValueKey('pane-session-next'),
                  tooltip: '다음 세션',
                  onPressed: widget.onNextSession,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                PopupMenuButton<String>(
                  tooltip: '다른 칸',
                  onSelected: _focus,
                  itemBuilder: (_) => [
                    for (final p in widget.layout.panes)
                      PopupMenuItem(
                        value: p.id,
                        child: Text(
                          _session(p.sessionId)?.displayName ?? '빈 칸',
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.tab),
                ),
                IconButton(
                  tooltip: '배치 되돌리기',
                  onPressed: widget.canUndo ? undo : null,
                  icon: const Icon(Icons.undo),
                ),
                if (widget.storageError != null)
                  IconButton(
                    tooltip: '${widget.storageError} · 재시도',
                    onPressed: widget.onRetrySave,
                    icon: const Icon(Icons.warning_amber, color: Colors.orange),
                  ),
                if (widget.onWorkspace != null)
                  IconButton(
                    tooltip: '작업공간 패널 표시',
                    onPressed: widget.onWorkspace,
                    icon: const Icon(Icons.folder_open),
                  ),
                if (widget.onBulk != null)
                  IconButton(
                    tooltip: '여러 세션 조작',
                    onPressed: widget.onBulk,
                    icon: const Icon(Icons.checklist),
                  ),
                if (widget.onControl != null)
                  IconButton(
                    tooltip: widget.controlEnabled ? '외부 제어 실행 중' : '외부 제어',
                    onPressed: widget.onControl,
                    icon: const Icon(Icons.lan_outlined),
                  ),
                if (widget.onBackground != null)
                  IconButton(
                    tooltip: '로컬 백그라운드 작업',
                    onPressed: widget.onBackground,
                    icon: const Icon(Icons.settings_backup_restore),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              _size = bounds.biggest;
              final geometry = _resolver.resolve(_layout, _size);
              _autoCompact = !geometry.fits && _layout.count > 1;
              final shown = _isZoomed
                  ? {_layout.focused.id: Offset.zero & _size}
                  : geometry.panes;
              return Stack(
                key: _canvasKey,
                children: [
                  for (final session in widget.sessions)
                    _terminal(session, shown),
                  for (final pane in _layout.panes)
                    if (shown.containsKey(pane.id) &&
                        !_groupSessions.any((s) => s.id == pane.sessionId))
                      Positioned.fromRect(
                        key: ValueKey('empty-${pane.id}'),
                        rect: shown[pane.id]!,
                        child: Column(
                          children: [
                            _header(pane, null, {}),
                            Expanded(
                              child: Center(
                                child: TextButton.icon(
                                  key: ValueKey('pane-empty-${pane.id}'),
                                  onPressed: () => _pickSession(pane.id),
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    pane.sessionId == null
                                        ? '세션 선택'
                                        : '세션을 복원하지 못했습니다 · 선택',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  if (!_isZoomed && !_autoCompact)
                    for (final divider in geometry.dividers) _divider(divider),
                  for (final pane in _layout.panes)
                    if (shown.containsKey(pane.id))
                      _dropTarget(pane, shown[pane.id]!),
                  if (_autoCompact && !_isZoomed)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: IgnorePointer(
                        child: Material(
                          color: const Color(0xe6182332),
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Text(
                              '공간이 좁아 한 칸으로 표시 중 · 상단에서 다른 칸 선택',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _terminal(SessionInfo session, Map<String, Rect> shown) {
    final pane = session.groupId == widget.groupId
        ? _layout.paneForSession(session.id)
        : null;
    final rect = pane == null ? null : shown[pane.id];
    if (rect != null) _lastBounds[session.id] = rect;
    final last =
        rect ?? _lastBounds[session.id] ?? const Rect.fromLTWH(0, 0, 800, 500);
    return Positioned.fromRect(
      key: ValueKey('terminal-${session.id}'),
      rect: last,
      child: Offstage(
        offstage: rect == null,
        child: TickerMode(
          enabled: rect != null,
          child: ExcludeFocus(
            excluding: rect == null,
            child: ExcludeSemantics(
              excluding: rect == null,
              child: IgnorePointer(
                ignoring: rect == null,
                child: Listener(
                  onPointerDown: (_) {
                    if (pane != null && rect != null) _focus(pane.id);
                  },
                  child: PaneActivityFrame(
                    focused:
                        pane?.id == widget.layout.focused.id && rect != null,
                    activity: widget.activity[session.id] ?? PaneActivity.idle,
                    child: widget.terminalBuilder(
                      session,
                      (actions) => _header(
                        pane ?? PaneLeaf('hidden', session.id),
                        session,
                        actions,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(PaneDivider divider) {
    final horizontal = divider.split.axis == PaneAxis.leftRight;
    void resize(double delta) {
      final extent =
          (horizontal ? divider.parent.width : divider.parent.height) -
          _resolver.gap;
      final start = (_resizeRatios[divider.split.id] ?? divider.split.ratio)
          .clamp(divider.minRatio, divider.maxRatio);
      _resizeRatios[divider.split.id] = (start + delta / extent).clamp(
        divider.minRatio,
        divider.maxRatio,
      );
      setState(
        () => _preview = _layout.resize(
          divider.split.id,
          (start + delta / extent).clamp(divider.minRatio, divider.maxRatio),
        ),
      );
    }

    void finish() {
      _resizeRatios.clear();
      final next = _preview;
      if (next != null) _commit(next);
    }

    final touch =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final rect = touch
        ? (horizontal
              ? Rect.fromCenter(
                  center: divider.rect.center,
                  width: 24,
                  height: divider.rect.height,
                )
              : Rect.fromCenter(
                  center: divider.rect.center,
                  width: divider.rect.width,
                  height: 24,
                ))
        : divider.rect;
    return Positioned.fromRect(
      key: ValueKey('divider-${divider.split.id}'),
      rect: rect,
      child: PaneDividerHandle(
        divider: divider,
        onDelta: resize,
        onFinish: finish,
        onCancel: () => setState(() {
          _preview = null;
          _resizeRatios.clear();
        }),
        onEqualize: () => _commit(widget.layout.resize(divider.split.id, .5)),
        onUnlink: () => _commit(
          widget.layout.resize(
            divider.split.id,
            divider.split.ratio,
            unlink: true,
          ),
        ),
      ),
    );
  }

  Widget _dropTarget(PaneLeaf pane, Rect rect) {
    return Positioned.fromRect(
      rect: rect,
      child: DragTarget<PaneSessionDrag>(
        onWillAcceptWithDetails: (details) =>
            details.data.groupId == widget.groupId &&
            details.data.sessionId != pane.sessionId,
        onMove: (details) {
          final box =
              _canvasKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || details.data.groupId != widget.groupId) return;
          final point = box.globalToLocal(details.offset) - rect.topLeft;
          final xEdge = (rect.width * .25).clamp(0.0, 64.0),
              yEdge = (rect.height * .25).clamp(0.0, 64.0);
          final side = point.dx < xEdge
              ? 'left'
              : point.dx > rect.width - xEdge
              ? 'right'
              : point.dy < yEdge
              ? 'top'
              : point.dy > rect.height - yEdge
              ? 'bottom'
              : 'center';
          setState(() {
            _dropPane = pane.id;
            _dropSide = side;
            _drag = details.data;
          });
        },
        onLeave: (_) => setState(() {
          _dropPane = null;
          _dropSide = null;
        }),
        onAcceptWithDetails: (details) {
          final side = _dropSide;
          if (details.data.groupId != widget.groupId ||
              !_ids.contains(details.data.sessionId) ||
              _dropPane != pane.id ||
              side == null) {
            return;
          }
          final next = _dropLayout(details.data.sessionId, pane.id, side);
          if (next != null) {
            _commit(next, exitZoom: true);
          } else {
            setState(() {
              _dropPane = null;
              _dropSide = null;
            });
            _notice('이 위치에는 배치할 수 없습니다. 최대 4칸과 최소 크기를 확인해 주세요.');
          }
        },
        builder: (_, candidates, rejected) {
          final show =
              candidates.isNotEmpty && _dropPane == pane.id && _drag != null;
          final valid =
              show &&
              _dropLayout(_drag!.sessionId, pane.id, _dropSide ?? 'center') !=
                  null;
          return IgnorePointer(
            child: show
                ? Align(
                    alignment: switch (_dropSide) {
                      'left' => Alignment.centerLeft,
                      'right' => Alignment.centerRight,
                      'top' => Alignment.topCenter,
                      'bottom' => Alignment.bottomCenter,
                      _ => Alignment.center,
                    },
                    child: FractionallySizedBox(
                      widthFactor: _dropSide == 'left' || _dropSide == 'right'
                          ? .5
                          : 1,
                      heightFactor: _dropSide == 'top' || _dropSide == 'bottom'
                          ? .5
                          : 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: (valid ? Colors.teal : Colors.orange)
                              .withValues(alpha: .22),
                          border: Border.all(
                            color: valid ? Colors.tealAccent : Colors.orange,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Material(
                            color: const Color(0xee182332),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                !valid
                                    ? '배치할 공간이 부족합니다'
                                    : switch (_dropSide) {
                                        'left' => '왼쪽에 배치',
                                        'right' => '오른쪽에 배치',
                                        'top' => '위에 배치',
                                        'bottom' => '아래에 배치',
                                        _ =>
                                          widget.layout.paneForSession(
                                                    _drag!.sessionId,
                                                  ) ==
                                                  null
                                              ? '이 칸의 세션 교체'
                                              : '두 칸 교환',
                                      },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.expand(),
          );
        },
      ),
    );
  }

  SessionPaneLayout? _dropLayout(String session, String target, String side) {
    final edge = side == 'center'
        ? null
        : side == 'left' || side == 'right'
        ? PaneAxis.leftRight
        : PaneAxis.topBottom;
    final next = widget.layout.moveSession(
      session,
      target,
      edge: edge,
      before: side == 'left' || side == 'top',
    );
    return identical(next, widget.layout) || !_fits(next) ? null : next;
  }
}
