import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../app/theme.dart';
import '../../clipboard/clipboard_image.dart';
import '../../clipboard/image_paste.dart';
import '../../core/result.dart';
import '../../session/session.dart';
import '../../settings/app_settings.dart';
import '../../settings/shortcut_bindings.dart';
import '../../state/providers.dart';
import '../adaptive/breakpoints.dart';
import 'action_bar_catalog.dart';
import 'terminal_selection_overlay.dart';

/// 세션 하나의 터미널 화면. 줌(핀치/단축키)과 keep-alive를 담당한다.
class SessionTerminalView extends ConsumerStatefulWidget {
  const SessionTerminalView({
    super.key,
    required this.session,
    this.onRetry,
    this.onEditHost,
    this.onFallbackToCmd,
    this.isPowershellFallbackAvailable = false,
  });

  final SessionInfo session;
  final VoidCallback? onRetry;
  final VoidCallback? onEditHost;
  final VoidCallback? onFallbackToCmd;
  final bool isPowershellFallbackAvailable;

  @override
  ConsumerState<SessionTerminalView> createState() =>
      _SessionTerminalViewState();
}

class _SessionTerminalViewState extends ConsumerState<SessionTerminalView>
    with AutomaticKeepAliveClientMixin {
  // Android/iOS IME 중 일부는 연결된 편집값을 완전히 비우면 한글 조합 세션까지
  // 초기화해 영문 자판으로 돌아간다. 터미널의 논리 입력 버퍼가 비어 있을 때도
  // 플랫폼 편집값은 보이지 않는 anchor 한 글자를 유지한다. 아래의
  // [_logicalInputValue]가 이 글자를 제거하므로 터미널로 전송되지는 않는다.
  static const _imeBufferAnchor = '\u200B';
  static const _emptyImeEditingValue = TextEditingValue(
    text: _imeBufferAnchor,
    selection: TextSelection.collapsed(offset: 1),
  );

  final _inputFocusNode = FocusNode(
    debugLabel: 'terminal-ime-input',
    skipTraversal: true,
  );
  final _inputController = TextEditingController.fromValue(
    _emptyImeEditingValue,
  );
  final _editableTextKey = GlobalKey<EditableTextState>();
  final _terminalController = TerminalController();
  final _terminalScrollController = ScrollController();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  late final _TerminalShortcutManager _terminalShortcutManager;
  bool _clearingInput = false;
  // 조합(composing) 중이라 아직 서버로 보내지 않은 한글 꼬리.
  // xterm처럼 터미널 커서 위치에 로컬로 표시해 "입력이 안 보이는" 문제를 없앤다.
  String? _composingText;
  String _recentHardwareText = '';
  DateTime? _recentHardwareTextAt;
  String _recentCommittedText = '';
  DateTime? _recentCommittedTextAt;
  String _lastCommittedText = '';
  DateTime? _lastCommittedTextAt;
  String _lastClearedImeText = '';
  DateTime? _lastClearedImeTextAt;
  String _sentTextInputPrefix = '';
  bool _controlModifierActive = false;
  bool _altModifierActive = false;
  bool _metaModifierActive = false;
  bool _shiftModifierActive = false;
  Timer? _imeIdleCommitTimer;
  Timer? _imeBufferClearTimer;
  Timer? _selectionCopyTimer;
  // xterm Terminal 은 Flutter Listenable 이 아니므로 출력·reflow 갱신을 선택
  // 오버레이의 ListenableBuilder 에 전달하는 브리지. 선택이 있을 때만 알린다.
  final _terminalChangeBridge = _ChangeBridge();
  Timer? _pasteLongPressTimer;
  Offset? _pointerDownGlobal;
  static const _pasteLongPressDelay = Duration(milliseconds: 500);
  static const _pasteLongPressSlop = 18.0;
  final Map<int, Offset> _activePointers = {};
  double _pinchBaseDistance = 0;
  double _pinchBaseFontSize = 14;

  // 테스트 전용: 선택 상태 검증용 컨트롤러 노출.
  @visibleForTesting
  TerminalController get terminalControllerForTest => _terminalController;

  void _requestTerminalRepaint() {
    _terminalViewKey.currentState?.requestRepaint();
    _requestFocus();
  }

  // 핸들 드래그 동안 고정할 반대쪽 끝의 anchor(버퍼 셀). 제스처 시작 시 한 번만
  // 잡고 종료 시 해제한다. 매 업데이트마다 live 선택에서 다시 읽으면, 끝 핸들을
  // 시작점보다 반대로 끌 때 selectCharacters가 begin/end를 재정렬해 anchor가
  // 드래그 지점으로 따라가고 양끝이 같이 움직이는 버그가 생긴다. 픽셀이 아니라
  // 셀로 들어야 드래그 중 스크롤(자동/휠)돼도 anchor가 따라 밀리지 않는다.
  CellOffset? _selectionDragAnchor;
  bool _draggingBeginHandle = false;

  // 드래그 선택(핸들·선택 모드) 중 포인터가 뷰포트 밖으로 나가면 그쪽으로
  // 스크롤하고, 스크롤될 때마다 마지막 포인터 위치로 선택을 다시 계산한다.
  // 마우스 드래그 선택은 xterm TerminalGestureHandler가 같은 헬퍼로 처리한다.
  late final _selectionAutoScroller = SelectionAutoScroller(
    getScrollController: () => _terminalScrollController,
    onScrolled: _reapplyDragSelection,
  );
  Offset? _lastSelectionDragGlobal;

  void _beginSelectionDrag() {
    _selectionDragAnchor = null;
    _selectionAutoScroller.begin();
  }

  void _endSelectionDrag() {
    _selectionAutoScroller.end();
    _selectionDragAnchor = null;
    _lastSelectionDragGlobal = null;
  }

  void _reapplyDragSelection() {
    final global = _lastSelectionDragGlobal;
    if (global == null) return;
    // 스크롤로 인한 재계산은 선택만 갱신한다. 여기서 자동 스크롤까지 다시
    // 갱신하면 jumpTo → 리스너 → 재계산이 같은 프레임 안에서 되돌아온다.
    if (_selectionMode && _selectionModeAnchor != null) {
      _selectionModePanUpdate(global, fromScroll: true);
    } else if (_selectionDragAnchor != null) {
      _dragSelectionEnd(
        global,
        draggingBegin: _draggingBeginHandle,
        fromScroll: true,
      );
    }
  }

  void _updateSelectionAutoScroll({
    required Offset local,
    required Size viewport,
    required double lineHeight,
  }) {
    _selectionAutoScroller.update(
      localY: local.dy,
      viewportHeight: viewport.height,
      lineHeight: lineHeight,
    );
  }

  /// 선택 모드: codex/claude 같은 TUI는 마우스 리포팅을 켜서 일반 드래그가
  /// 앱으로 전달돼 로컬 선택이 안 된다. 이 모드를 켜면 터미널 위에 드래그를
  /// 가로채는 레이어를 올려, 마우스 모드와 무관하게 로컬로 텍스트를 선택한다.
  bool _selectionMode = false;
  CellOffset? _selectionModeAnchor;

  void _enableSelectionMode() {
    if (_selectionMode) return;
    setState(() {
      _selectionMode = true;
      _selectionModeAnchor = null;
    });
  }

  void _disableSelectionMode({bool clearSelection = false}) {
    if (!_selectionMode && !clearSelection) return;
    setState(() {
      _selectionMode = false;
      _selectionModeAnchor = null;
      if (clearSelection) _terminalController.clearSelection();
    });
  }

  void _selectionModePanStart(Offset globalPos) {
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (render == null) return;
    final local = render.globalToLocal(globalPos);
    _selectionModeAnchor = render.getCellOffset(local);
    _lastSelectionDragGlobal = globalPos;
    _selectionAutoScroller.begin();
    render.selectCharacters(local);
  }

  void _selectionModePanUpdate(Offset globalPos, {bool fromScroll = false}) {
    final render = _terminalViewKey.currentState?.renderTerminal;
    final anchor = _selectionModeAnchor;
    if (render == null || anchor == null) return;
    _lastSelectionDragGlobal = globalPos;
    final current = render.globalToLocal(globalPos);
    render.selectCharactersFromCell(anchor, current);
    if (fromScroll) return;
    _updateSelectionAutoScroll(
      local: current,
      viewport: render.size,
      lineHeight: render.lineHeight,
    );
  }

  void _selectionModePanEnd() {
    _selectionAutoScroller.end();
    _lastSelectionDragGlobal = null;
    if (!_selectionMode) return;
    _disableSelectionMode();
  }

  /// 화면 텍스트 스냅샷을 시트로 띄워 표준 [SelectableText]로 선택·복사한다.
  /// codex 같은 라이브 TUI는 화면을 계속 다시 그려 인라인 선택이 불안정하므로,
  /// 제스처와 무관한 정적 스냅샷에서 안정적으로 복사할 수 있게 한다.
  void _openCopySheet() {
    final text = widget.session.engine.terminal.buffer.getText().trimRight();
    final settings = ref.read(appSettingsProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VibeColors.surface,
      showDragHandle: true,
      builder: (ctx) => _CopySheet(
        text: text.isEmpty ? '(빈 화면)' : text,
        fontFamily: settings.terminalFontFamily,
        fontFallback: settings.fontFallback,
      ),
    );
  }

  /// 핸들 드래그: 반대쪽 끝을 anchor로 고정하고 드래그 지점까지 문자 단위 선택.
  void _dragSelectionEnd(
    Offset globalPos, {
    required bool draggingBegin,
    bool fromScroll = false,
  }) {
    final selection = _terminalController.selection;
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (selection == null || render == null) return;

    final cell = render.cellSize;
    // 고정 anchor = 드래그하지 않는 반대쪽 끝의 셀. 제스처 첫 업데이트에서만
    // 캡처하고 이후엔 그대로 재사용한다. (셀 중심 픽셀을 셀로 되돌려 열 범위
    // 클램프까지 기존 동작과 같게 맞춘다.)
    _selectionDragAnchor ??= render.getCellOffset(
      render.getOffset(draggingBegin ? selection.end : selection.begin) +
          Offset(cell.width / 2, cell.height / 2),
    );
    _draggingBeginHandle = draggingBegin;
    _lastSelectionDragGlobal = globalPos;
    final anchor = _selectionDragAnchor!;
    final dragLocal = render.globalToLocal(globalPos);
    // selectCharactersFromCell은 anchor 셀과 드래그 지점을 읽기 순서로 정렬해
    // 고정한 anchor 쪽 끝은 그대로 두고 드래그하는 핸들만 움직인다.
    render.selectCharactersFromCell(anchor, dragLocal);
    if (fromScroll) return;
    _updateSelectionAutoScroll(
      local: dragLocal,
      viewport: render.size,
      lineHeight: render.lineHeight,
    );
  }

  void _selectAll() {
    final buffer = widget.session.engine.terminal.buffer;
    final lastLine = buffer.height - 1;
    final lastCol = buffer.viewWidth - 1;
    if (lastLine < 0 || lastCol < 0) return;
    _terminalController.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(lastCol, lastLine),
      mode: SelectionMode.line,
    );
    _scrollTerminalToBottomOnInput();
  }

  SelectionGeometry? _selectionGeometry() {
    final selection = _terminalController.selection;
    if (selection == null) return null;
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (render == null) return null;
    return SelectionGeometry(
      begin: render.getOffset(selection.begin),
      end: render.getOffset(selection.end),
      cellSize: render.cellSize,
    );
  }

  // 하드웨어 키 채널과 IME 텍스트 채널이 같은 물리 키를 둘 다 전달할 때, 한 번만
  // 보내려고 최근 전송 텍스트를 기억해 두는 창(cross-channel echo 창).
  //
  // 이 창이 너무 길면(과거엔 2초) IME로만 확정된 글자('a')가 남긴 잔여가, 잠시 뒤
  // 같은 글자를 **일부러 다시 친** 하드웨어 입력까지 "중복"으로 오판해 드롭한다.
  // 실제 에코는 하드웨어 폴백 지연(24ms) 안에 도착하므로, 같은 keypress의 에코는
  // 확실히 잡되 사용자의 빠른 반복 입력('dd', 'aa' 등)은 살리도록 짧게 잡는다.
  // (증상: 빠르게 치면 몇몇 글자 누락, 천천히 치면 정상 — 이슈 #2)
  static const _hardwareTextDedupWindow = Duration(milliseconds: 200);
  static const _hardwareTextFallbackDelay = Duration(milliseconds: 24);
  static const _imeIdleCommitDelay = Duration(milliseconds: 450);
  static const _selectionCopyDelay = Duration(milliseconds: 120);
  static const _staleImePrefixWindow = Duration(seconds: 5);
  static const _inputTracePath = String.fromEnvironment(
    'VIBE_TERMINAL_INPUT_TRACE',
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _terminalShortcutManager = _TerminalShortcutManager(
      onTerminalKey: (context, event) =>
          _handleTerminalKeyEvent(context, _inputFocusNode, event),
    );
    _inputFocusNode.onKeyEvent = _handleInputFocusKeyEvent;
    _terminalController.addListener(_handleTerminalSelectionChanged);
    widget.session.engine.terminal.addListener(_handleTerminalChanged);
    _inputController.addListener(_handleCommittedTextInput);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
  }

  @override
  void dispose() {
    _imeIdleCommitTimer?.cancel();
    _imeBufferClearTimer?.cancel();
    _selectionCopyTimer?.cancel();
    _pasteLongPressTimer?.cancel();
    _terminalController.removeListener(_handleTerminalSelectionChanged);
    widget.session.engine.terminal.removeListener(_handleTerminalChanged);
    _terminalChangeBridge.dispose();
    _terminalController.dispose();
    _terminalScrollController.dispose();
    _terminalShortcutManager.dispose();
    _selectionAutoScroller.dispose();
    _inputFocusNode.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _handleTerminalChanged() {
    if (_terminalController.selection == null) return;
    _terminalChangeBridge.bump();
  }

  void _handleTerminalSelectionChanged() {
    if (!ref.read(appSettingsProvider).copyOnSelection) return;
    final selection = _terminalController.selection;
    if (selection == null) {
      _selectionCopyTimer?.cancel();
      _selectionCopyTimer = null;
      return;
    }

    _selectionCopyTimer?.cancel();
    _selectionCopyTimer = Timer(
      _selectionCopyDelay,
      () => unawaited(_copySelectionToClipboard()),
    );
  }

  String? _selectedText() {
    final selection = _terminalController.selection;
    if (selection == null) return null;
    final text = widget.session.engine.terminal.buffer.getText(selection);
    if (text.trim().isEmpty) return null;
    return text;
  }

  Future<bool> _copySelectionToClipboard() async {
    final text = _selectedText();
    if (text == null) return false;
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  /// 이미지 업로드 경로를 터미널에 입력하고, 텍스트 붙여넣기와 동일하게 후처리한다.
  void _sendImagePathToTerminal(String text) {
    _flushTextInputBuffer();
    widget.session.engine.terminal.textInput(text);
    _terminalController.clearSelection();
    _requestFocus();
    _scrollTerminalToBottomOnInput();
  }

  void _showTerminalSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleContentInserted(KeyboardInsertedContent content) {
    final image = keyboardContentToImage(content);
    if (image == null) return;
    unawaited(
      handleImagePaste(
        context: context,
        ref: ref,
        session: widget.session,
        image: image,
        sendText: _sendImagePathToTerminal,
        showSnack: _showTerminalSnack,
      ),
    );
  }

  Future<bool> _pasteClipboardText(BuildContext context) async {
    // 클립보드에 이미지가 있으면 텍스트 대신 업로드 흐름으로 전환한다.
    ClipboardImage? image;
    try {
      image = await readClipboardImage();
    } catch (_) {
      image = null;
    }
    if (!mounted || !context.mounted) return false;
    if (image != null) {
      await handleImagePaste(
        context: context,
        ref: ref,
        session: widget.session,
        image: image,
        sendText: _sendImagePathToTerminal,
        showSnack: _showTerminalSnack,
      );
      return true;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || !context.mounted) return false;
    final text = data?.text;
    if (text == null || text.isEmpty) return false;
    final settings = ref.read(appSettingsProvider);
    if (settings.confirmMultilinePaste && _isMultilineText(text)) {
      final confirmed = await _confirmMultilinePaste(context, text);
      if (!confirmed) return false;
    }

    _flushTextInputBuffer();
    widget.session.engine.terminal.paste(text);
    _terminalController.clearSelection();
    _requestFocus();
    _scrollTerminalToBottomOnInput();
    return true;
  }

  bool _isMultilineText(String text) {
    return text.contains('\n') || text.contains('\r');
  }

  Future<bool> _confirmMultilinePaste(BuildContext context, String text) async {
    final lineCount = text.split(RegExp(r'\r\n|\r|\n')).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('여러 줄 붙여넣기'),
        content: Text('$lineCount줄 텍스트를 터미널에 붙여넣습니다. 계속할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('붙여넣기'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 스크롤백을 위로 올려 과거 출력을 보던 중 키를 입력하면, 현재
  /// 프롬프트(맨 아래)로 자동 복귀시킨다. 입력 결과가 반영되며 스크롤
  /// 범위가 바뀌므로 다음 프레임에 맨 아래로 점프한다.
  void _scrollTerminalToBottomOnInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_terminalScrollController.hasClients) return;
      final position = _terminalScrollController.position;
      if (position.pixels < position.maxScrollExtent) {
        _terminalScrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  /// xterm와 동일한 방식('mmmmmmmmmm' 측정)으로 단일 셀 크기를 계산한다.
  /// composing 오버레이를 터미널 커서 셀에 맞춰 배치하는 데 쓴다.
  Size _terminalCellSize(AppSettings settings, double fontSize) {
    const probe = 'mmmmmmmmmm';
    final painter = TextPainter(
      text: TextSpan(
        text: probe,
        style: TextStyle(
          fontSize: fontSize,
          height: settings.terminalLineHeight,
          fontFamily: settings.terminalFontFamily,
          fontFamilyFallback: settings.fontFallback,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final size = Size(painter.maxIntrinsicWidth / probe.length, painter.height);
    painter.dispose();
    return size;
  }

  /// 조합 중인 한글을 터미널 커서 위치에 밑줄과 함께 표시한다(전송 전 로컬 echo).
  Widget _buildComposingOverlay(AppSettings settings, double fontSize) {
    final composing = _composingText;
    if (composing == null) return const SizedBox.shrink();
    final buffer = widget.session.engine.terminal.buffer;
    final cell = _terminalCellSize(settings, fontSize);
    // 아래 TerminalView의 padding(EdgeInsets.fromLTRB(14, 10, 14, 12))과 일치.
    final left = 14 + buffer.cursorX * cell.width;
    final top = 10 + buffer.cursorY * cell.height;
    return Positioned(
      key: const ValueKey('composing-overlay'),
      left: left,
      top: top,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: VibeColors.terminal,
            border: Border(
              bottom: BorderSide(color: VibeColors.accent, width: 2),
            ),
          ),
          child: Text(
            composing,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: VibeColors.onSurface,
              fontSize: fontSize,
              height: settings.terminalLineHeight,
              fontFamily: settings.terminalFontFamily,
              fontFamilyFallback: settings.fontFallback,
            ),
          ),
        ),
      ),
    );
  }

  /// 활성 포인터가 정확히 2개일 때만 핀치 기준을 잡고, 그 외에는 비활성화한다.
  /// 손가락 수가 바뀔 때마다 호출해 3→2 복귀 시 점프를 막는다.
  void _syncPinchBase() {
    if (_activePointers.length == 2) {
      _pinchBaseDistance = _currentPointerDistance();
      _pinchBaseFontSize = ref.read(appSettingsProvider).terminalFontSize;
    } else {
      _pinchBaseDistance = 0;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.session.status == SessionStatus.connected &&
        _activePointers.isEmpty) {
      _requestFocus();
    }
    _activePointers[event.pointer] = event.position;
    _syncPinchBase();
    if (_activePointers.length >= 2) {
      _pasteLongPressTimer?.cancel();
      return;
    }
    _pointerDownGlobal = event.position;
    _pasteLongPressTimer?.cancel();
    _pasteLongPressTimer = Timer(_pasteLongPressDelay, () {
      final down = _pointerDownGlobal;
      if (down != null) _maybeShowPasteMenu(down);
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.position;
    final start = _pointerDownGlobal;
    if (start != null &&
        (event.position - start).distance > _pasteLongPressSlop) {
      _pasteLongPressTimer?.cancel();
    }
    if (_activePointers.length == 2 && _pinchBaseDistance > 0) {
      final scale = _currentPointerDistance() / _pinchBaseDistance;
      ref
          .read(appSettingsProvider.notifier)
          .setTerminalFontSize(_pinchBaseFontSize * scale);
    }
  }

  void _handlePointerUp(PointerEvent event) {
    _pasteLongPressTimer?.cancel();
    _activePointers.remove(event.pointer);
    _syncPinchBase();
  }

  /// 빈 셀(공백) 롱프레스에서는 터미널 액션 메뉴를 띄운다.
  /// 글자 셀의 롱프레스는 xterm 내부 단어 선택에 양보한다.
  Future<void> _maybeShowPasteMenu(Offset globalPos) async {
    if (!mounted) return;
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (render == null) return;

    final cell = render.getCellOffset(render.globalToLocal(globalPos));
    final text = widget.session.engine.terminal.buffer.getText(
      BufferRangeLine(cell, cell),
    );
    final hasSelection = _terminalController.selection != null;
    final compact = context.isCompact;
    final isBlankCell = text.trim().isEmpty;
    if (!hasSelection && !_selectionMode && !isBlankCell) {
      return;
    }

    final overlay = Overlay.of(context);
    final renderObject = overlay.context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final overlayBox = renderObject;
    final overlayPos = overlayBox.globalToLocal(globalPos);
    final position = RelativeRect.fromSize(
      Rect.fromLTWH(overlayPos.dx, overlayPos.dy, 0, 0),
      overlayBox.size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        if (hasSelection) ...const [
          PopupMenuItem(value: 'copySelection', child: Text('복사')),
          PopupMenuItem(value: 'selectAll', child: Text('전체 선택')),
        ],
        if (!hasSelection) ...[
          const PopupMenuItem(value: 'paste', child: Text('붙여넣기')),
          if (compact)
            PopupMenuItem(
              value: _selectionMode ? 'selectionModeOff' : 'selectionModeOn',
              child: Text(_selectionMode ? '선택 종료' : '선택'),
            ),
          // 화면(스크롤백 포함) 전체 텍스트를 정적 스냅샷 시트로 보고 선택·복사한다.
          // claude/codex처럼 라이브로 재그리는 세션은 인라인 드래그 선택이
          // 불안정하고, 스크롤백으로 밀려난 긴 응답을 마우스 스크롤로 되짚기
          // 어렵다. 데스크톱·모바일 모두에서 안정적인 읽기·복사 경로를 제공한다.
          const PopupMenuItem(value: 'copyScreen', child: Text('화면 복사')),
        ],
      ],
    );
    if (!mounted || !context.mounted) return;
    switch (selected) {
      case 'paste':
        await _pasteClipboardText(context);
        break;
      case 'selectionModeOn':
        _enableSelectionMode();
        break;
      case 'selectionModeOff':
        _disableSelectionMode();
        break;
      case 'copyScreen':
        _openCopySheet();
        break;
      case 'copySelection':
        await _copySelectionToClipboard();
        break;
      case 'selectAll':
        _selectAll();
        break;
    }
  }

  double _currentPointerDistance() {
    final points = _activePointers.values.toList(growable: false);
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  void _requestFocus() {
    if (mounted && widget.session.status == SessionStatus.connected) {
      _traceInput('requestFocus hasFocus=${_inputFocusNode.hasFocus}');
      _inputFocusNode.requestFocus();
      _editableTextKey.currentState?.requestKeyboard();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.session.status == SessionStatus.connected) {
          _traceInput(
            'requestFocus.postFrame hasFocus=${_inputFocusNode.hasFocus}',
          );
          _inputFocusNode.requestFocus();
          _editableTextKey.currentState?.requestKeyboard();
        }
      });
    }
  }

  /// 소프트키보드의 엔터(제출) 처리: 조합 중인 텍스트를 먼저 전송한 뒤
  /// 개행(Enter)을 터미널로 보낸다. onEditingComplete가 포커스를 유지하므로
  /// 키보드를 다시 띄울 필요가 없다(깜빡임 방지).
  void _handleImeSubmit([String _ = '']) {
    if (widget.session.status != SessionStatus.connected) return;
    _flushTextInputBuffer();
    widget.session.engine.terminal.keyInput(TerminalKey.enter);
    _releaseTextInputBuffer();
    _scrollTerminalToBottomOnInput();
  }

  void _handleCommittedTextInput() {
    if (_clearingInput) return;
    _imeIdleCommitTimer?.cancel();
    _imeBufferClearTimer?.cancel();
    final value = _logicalInputValue();
    final text = value.text;
    _traceInput('textCommit candidate ${_describeEditingValue(value)}');
    if (text.isEmpty) {
      // Windows는 clear를 미루므로 버퍼에 남은 텍스트가 전부 서버로 보낸
      // 것일 수 있다. 사용자가 그것을 끝까지 지웠다면 서버에서도 지워야 한다.
      // (백스페이스 방식 IME의 중간 '' 상태는 prefix가 비어 있어 영향 없음.)
      if (_defersTextInputBufferClear && _sentTextInputPrefix.isNotEmpty) {
        _sendNewCommittedPrefix('', 0);
      }
      _sentTextInputPrefix = '';
      _updateComposingText(null);
      // IME가 Backspace 등으로 anchor까지 지웠다면 즉시 복구한다. 빈
      // setEditingState가 다음 조합의 한글 모드를 해제하지 않게 하기 위함이다.
      if (_inputController.value.text.isEmpty) {
        _clearTextInputBuffer();
      }
      return;
    }
    _scrollTerminalToBottomOnInput();
    _restoreStaleImePrefixIfNeeded(text);

    if (_shouldBufferImeText(value)) {
      final committedEnd = _committedPrefixEndForImeText(value);
      if (committedEnd > 0) {
        _sendNewCommittedPrefix(text, committedEnd);
      }
      if (_hasActiveComposing(value)) {
        // 조합 중인 꼬리(예: Android Gboard의 마지막 음절)는 서버로 보내지
        // 않고 커서 위치에 로컬로 표시한다. 다음 입력에서 확정 prefix로
        // 전송되거나 Enter/다음 키 시 flush된다. (xterm의 onComposing 패턴)
        _updateComposingText(text.substring(committedEnd));
        // 조합한 채로 입력을 멈추면 마지막 음절이 영영 전송되지 않으므로,
        // 일정 시간 변화가 없으면 꼬리까지 확정 전송한다(이슈 #2).
        _scheduleComposingIdleCommit(value);
      } else {
        // composing 없이 음절이 진화하는 IME(예: Windows)는 기존 idle 경로.
        // 이 경우에도 아직 서버로 보내지 않은 꼬리를 보여 줘야
        // 사용자가 idle commit을 기다리는 동안 입력이 누락된 것처럼 보이지 않는다.
        _updateComposingText(text.substring(committedEnd));
        // 공백 등 한글 조합 경계를 넘어 확정된 텍스트는 더 이상 백스페이스로
        // 분해될 수 없다. 이 시점에 버퍼를 비워, 우리 shadow(_sentTextInputPrefix)가
        // 문장 전체로 누적돼 서버 표시와 desync되는 것을 막는다. desync는 "엔터로
        // 버퍼를 비워야만 복구"되는 입력 꼬임의 원인이므로, 경계마다 자동
        // 리셋해 desync 범위를 단어 단위로 가둔다(이슈 #3).
        if (_endsAtImeCommitBoundary(text)) {
          _flushTextInputBuffer();
        } else {
          _scheduleImeIdleCommit(value);
        }
      }
      return;
    }

    _updateComposingText(null);
    if (_sendNewCommittedPrefix(text, text.length)) {
      _releaseTextInputBuffer();
    }
  }

  /// 조합 중인 한글 꼬리를 로컬 표시 상태로 갱신한다. 빈 값은 null로 정규화.
  void _updateComposingText(String? text) {
    final normalized = (text == null || text.isEmpty) ? null : text;
    if (_composingText == normalized) return;
    setState(() => _composingText = normalized);
  }

  bool _shouldBufferImeText(TextEditingValue value) {
    final text = value.text;
    if (!_containsNonAscii(text)) return false;
    if (_hasActiveComposing(value)) return true;
    if (_containsHangulJamo(text)) return true;
    return true;
  }

  int _committedPrefixEndForImeText(TextEditingValue value) {
    final text = value.text;
    if (_hasActiveComposing(value)) {
      return value.composing.start.clamp(0, text.length);
    }

    final firstJamo = _firstHangulJamoIndex(text);
    if (firstJamo >= 0) return firstJamo;

    return _sentTextInputPrefix.length.clamp(0, text.length);
  }

  bool _hasActiveComposing(TextEditingValue value) {
    return value.composing.isValid && !value.composing.isCollapsed;
  }

  bool _sendNewCommittedPrefix(String text, int committedEnd) {
    final committedText = text.substring(0, committedEnd);
    // 이미 서버로 보낸 prefix와 새 확정 텍스트의 공통 부분을 구한다. 전진 입력은
    // 공통 길이 = 보낸 prefix 길이라 백스페이스 없이 뒤만 추가된다. 한글 백스페이스로
    // 확정 음절이 분해/수정되면(예: '이'→'ㅇ') 공통 부분 이후가 줄어든 만큼
    // 백스페이스를 보내 서버 상태를 맞춘 뒤 새 글자를 보낸다. 이렇게 하지 않으면
    // 갈라진 prefix가 통째로 재전송되어 한글이 중복·깨져 들어간다.
    final common = _commonPrefixLength(_sentTextInputPrefix, committedText);
    final deleteCount = _sentTextInputPrefix.length - common;
    final nextText = committedText.substring(common);
    if (deleteCount == 0 && nextText.isEmpty) return false;

    if (deleteCount > 0) {
      _traceInput(
        'textCommit backspace x$deleteCount old="$_sentTextInputPrefix" '
        'new="$committedText"',
      );
      for (var i = 0; i < deleteCount; i++) {
        widget.session.engine.terminal.keyInput(TerminalKey.backspace);
      }
    }
    if (nextText.isNotEmpty) {
      _sendCommittedText(nextText);
    }
    _sentTextInputPrefix = committedText;
    return true;
  }

  /// 두 문자열의 공통 prefix 길이(코드 유닛 기준). 완성형 한글·자모는 모두 BMP
  /// 단일 코드 유닛이라 음절 단위 비교가 정확하다.
  int _commonPrefixLength(String a, String b) {
    final max = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < max && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  void _sendCommittedText(String text) {
    if (_terminalController.selection != null) {
      _terminalController.clearSelection();
    }
    if (text.isEmpty) return;
    // 보조 키바의 Ctrl sticky가 켜져 있으면 시스템 키보드로 친 첫 문자에도
    // Ctrl을 적용한다(예: Ctrl 토글 후 'c' → Ctrl+C). 적용 후 자동 해제.
    final outgoing = _applyStickyCtrl(text);
    if (!_consumeRecentHardwareText(text)) {
      _traceInput('textCommit send "$outgoing"');
      widget.session.engine.terminal.textInput(outgoing);
      _rememberCommittedText(text);
      _rememberLastCommittedText(text);
    } else {
      _traceInput('textCommit dedupe "$text"');
    }
  }

  /// Ctrl sticky가 활성이면 [text]의 첫 문자를 제어바이트로 변환하고 모디파이어를
  /// 소비한다. a~z는 0x01~0x1A로, 그 외 문자는 그대로 둔다.
  String _applyStickyCtrl(String text) {
    if (text.isEmpty) return text;
    if (!ref.read(ctrlStickyProvider)) return text;
    ref.read(ctrlStickyProvider.notifier).clear();
    final code = text[0].toLowerCase().codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7a) {
      return String.fromCharCode(code - 0x60) + text.substring(1);
    }
    return text;
  }

  void _scheduleImeIdleCommit(TextEditingValue expectedValue) {
    if (!_isIdleCommittableImeText(expectedValue)) return;
    final expectedText = expectedValue.text;
    _imeIdleCommitTimer = Timer(_imeIdleCommitDelay, () {
      if (!mounted || widget.session.status != SessionStatus.connected) return;
      final value = _logicalInputValue();
      if (value.text != expectedText || value.text.isEmpty) return;
      _traceInput('imeIdleCommit "${value.text}"');
      // Windows IME는 조합 중에도 composing 범위를 비워서 보낼 수 있다. 여기서
      // 컨트롤러를 비우면 TSF가 아직 들고 있는 조합을 selection 0에 되밀어 넣어
      // 다음 음절이 앞에 삽입되고 입력 순서가 뒤집힐 수 있다. 서버 전송 상태만
      // 갱신하고 편집값은 공백·Enter 같은 실제 확정 경계까지 유지한다.
      _commitImeTextWithoutClearing();
    });
  }

  /// 조합(composing)이 멈춘 채 일정 시간이 지나면 조합 꼬리까지 확정 전송한다.
  /// 안드로이드 한글처럼 마지막 음절을 계속 조합 상태로 들고 있는 IME에서
  /// "마지막 글자가 바로 안 들어가는" 문제(이슈 #2)를 해결한다. 다음 입력이 오면
  /// _handleCommittedTextInput 진입부에서 타이머가 취소되어 조기 전송을 막는다.
  /// flush 후 같은 음절 조합이 이어지면 _restoreStaleImePrefixIfNeeded가 이미
  /// 보낸 prefix를 복원해 중복 전송을 막는다.
  void _scheduleComposingIdleCommit(TextEditingValue expectedValue) {
    final expectedText = expectedValue.text;
    final expectedComposing = expectedValue.composing;
    _imeIdleCommitTimer = Timer(_imeIdleCommitDelay, () {
      if (!mounted || widget.session.status != SessionStatus.connected) return;
      final value = _logicalInputValue();
      // 값이 그대로 멈춰 있을 때만 확정한다(조합이 더 진행되면 취소됨).
      if (value.text != expectedText ||
          value.composing != expectedComposing ||
          value.text.isEmpty) {
        return;
      }
      _traceInput('composingIdleCommit "${value.text}"');
      _commitImeTextWithoutClearing();
    });
  }

  /// IME 편집값이 유휴 상태가 됐을 때 전체 텍스트를 서버로 보내되 입력 버퍼는
  /// **비우지 않는다**. composing 범위가 활성인 IME와, 조합 중에도 그 범위를
  /// 비워 보내는 Windows IME가 같은 안전한 상태 전이를 사용한다.
  ///
  /// 여기서 컨트롤러를 비우면(= setEditingState empty) 플랫폼 IME는 아직 자기
  /// 조합 상태를 들고 있기 때문에, 비워진 필드에 그 상태를 그대로 다시 밀어
  /// 넣는다. 그 결과 사라지지 않는 자모가 버퍼 끝에 남고, 이후 조합이 그 앞에
  /// 삽입되면서(selection이 0으로 돌아간다) 결국 `ㄴㄴ`, `나나나` 같은 쓰레기
  /// 문자가 터미널로 전송된다. Windows TSF는 setEditingState로 조합이 끊기지
  /// 않아 특히 잘 재현된다.
  ///
  /// 비우지 않으면 [_sendNewCommittedPrefix]의 공통 prefix 비교가 계속 유효해서,
  /// 조합이 이어져도 백스페이스 + 새 글자로 정확히 동기화된다.
  void _commitImeTextWithoutClearing() {
    final text = _logicalInputValue().text;
    if (text.isEmpty) return;
    _imeIdleCommitTimer?.cancel();
    _sendNewCommittedPrefix(text, text.length);
    _updateComposingText(null);
  }

  bool _flushTextInputBuffer() {
    final text = _logicalInputValue().text;
    if (text.isEmpty) return false;
    _imeIdleCommitTimer?.cancel();
    _sendNewCommittedPrefix(text, text.length);
    _rememberLastClearedImeText(text);
    _releaseTextInputBuffer();
    return true;
  }

  /// Windows에서는 편집 버퍼 비우기(setEditingState)를 입력이 멈춘 뒤로 미룬다.
  ///
  /// Windows 엔진은 WM_KEYDOWN/WM_CHAR를 키마다 Dart 응답을 기다리는 큐에 넣지만
  /// WM_IME_COMPOSITION(조합 갱신)은 큐를 거치지 않고 즉시 플랫폼 텍스트 모델에
  /// 반영한다. 빠르게 치면 우리가 공백 등 경계에서 보낸 clear가 플랫폼에 닿기
  /// 전에 다음 음절 조합이 이미 시작돼 있고, 그 상태에서 clear가 적용되면 엔진
  /// 모델이 composing 플래그를 잃어 다음 조합 갱신을 커서 위치에 한 번 더
  /// 삽입한다(`하하`, `한하하`). 그 어긋난 편집값을 prefix diff가 그대로 반영해
  /// 백스페이스와 재전송이 서버로 나가 한글이 깨진다.
  ///
  /// 그래서 Windows는 서버 전송(shadow 갱신)만 즉시 하고, 실제 clear는
  /// [_scheduleDeferredBufferClear]로 미룬다. 입력이 이어지는 동안 플랫폼
  /// 버퍼를 건드리지 않으므로 조합 상태가 깨질 틈이 없다. 모바일 IME는 기존
  /// 동작(즉시 clear)을 유지한다.
  bool get _defersTextInputBufferClear =>
      defaultTargetPlatform == TargetPlatform.windows;

  /// 버퍼 내용이 전부 서버로 전송돼 미룬 clear만 남은 상태인지.
  bool get _textInputBufferReleased => _imeBufferClearTimer?.isActive ?? false;

  /// 현재 버퍼를 "다 썼다"고 표시한다. 즉시 비우거나(기본), Windows에서는 미룬다.
  void _releaseTextInputBuffer() {
    if (!_defersTextInputBufferClear) {
      _clearTextInputBuffer();
      return;
    }
    _updateComposingText(null);
    _scheduleDeferredBufferClear();
  }

  /// 편집값이 [_imeIdleCommitDelay] 동안 그대로이고 조합 범위가 없을 때만
  /// 버퍼를 비운다. 그 사이 새 입력이 오면 [_handleCommittedTextInput]가
  /// 타이머를 취소하고, 남은 텍스트는 이미 보낸 prefix로서 diff 기준이 된다.
  void _scheduleDeferredBufferClear() {
    _imeBufferClearTimer?.cancel();
    final expected = _logicalInputValue();
    if (expected.text.isEmpty) {
      _clearTextInputBuffer();
      return;
    }
    _imeBufferClearTimer = Timer(_imeIdleCommitDelay, () {
      if (!mounted) return;
      final value = _logicalInputValue();
      if (value.text != expected.text || _hasActiveComposing(value)) return;
      _traceInput('deferredClear "${value.text}"');
      _clearTextInputBuffer();
    });
  }

  void _clearTextInputBuffer() {
    _clearingInput = true;
    _inputController.value = _emptyImeEditingValue;
    _sentTextInputPrefix = '';
    _clearingInput = false;
    _updateComposingText(null);
  }

  /// 플랫폼 편집값에만 존재하는 IME anchor를 제거하고 selection/composing 범위를
  /// 터미널 입력 기준으로 이동한다. 테스트 입력이나 일부 IME가 anchor 없이 값을
  /// 교체하는 경우에는 원본을 그대로 받아 여러 플랫폼의 입력 방식을 함께 지원한다.
  TextEditingValue _logicalInputValue() {
    final value = _inputController.value;
    if (!value.text.startsWith(_imeBufferAnchor)) return value;

    final text = value.text.substring(_imeBufferAnchor.length);
    int shiftOffset(int offset) {
      if (offset < 0) return offset;
      return (offset - _imeBufferAnchor.length).clamp(0, text.length);
    }

    final selection = value.selection;
    final composing = value.composing;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: shiftOffset(selection.baseOffset),
        extentOffset: shiftOffset(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
      composing: composing.isValid
          ? TextRange(
              start: shiftOffset(composing.start),
              end: shiftOffset(composing.end),
            )
          : TextRange.empty,
    );
  }

  void _scheduleHardwareTextInput(String text) {
    Timer(_hardwareTextFallbackDelay, () {
      if (!mounted || widget.session.status != SessionStatus.connected) return;
      final value = _logicalInputValue();
      if (value.text.isNotEmpty || !value.composing.isCollapsed) {
        if (_flushPendingAsciiTextInput(value)) {
          _traceInput('hardwareText flush pending ascii before "$text"');
          return;
        }
        _traceInput(
          'hardwareText skip "$text" text="${value.text}" '
          'composing=${value.composing}',
        );
        return;
      }
      if (_consumeRecentCommittedText(text)) {
        _traceInput('hardwareText skip committed "$text"');
        return;
      }
      if (_wasRecentlyCommittedText(text)) {
        _traceInput('hardwareText skip recent committed "$text"');
        return;
      }
      _sendHardwareTextInput(text);
    });
  }

  void _sendHardwareTextInput(String text) {
    if (_terminalController.selection != null) {
      _terminalController.clearSelection();
    }
    _traceInput('hardwareText send "$text"');
    widget.session.engine.terminal.textInput(text);
    _rememberHardwareText(text);
  }

  bool _flushPendingAsciiTextInput(TextEditingValue value) {
    if (value.text.isEmpty) return false;
    if (!_isAsciiPrintableText(value.text)) return false;
    _traceInput('hardwareText pending ascii ${_describeEditingValue(value)}');
    return _flushTextInputBuffer();
  }

  void _rememberHardwareText(String text) {
    _clearStaleTextBuffers();
    _recentHardwareText += text;
    if (_recentHardwareText.length > 256) {
      _recentHardwareText = _recentHardwareText.substring(
        _recentHardwareText.length - 256,
      );
    }
    _recentHardwareTextAt = DateTime.now();
  }

  bool _consumeRecentHardwareText(String text) {
    _clearStaleTextBuffers();
    if (_recentHardwareText.isEmpty || text.isEmpty) return false;
    if (!_recentHardwareText.startsWith(text)) return false;
    _recentHardwareText = _recentHardwareText.substring(text.length);
    if (_recentHardwareText.isEmpty) {
      _recentHardwareTextAt = null;
    }
    return true;
  }

  void _rememberCommittedText(String text) {
    _clearStaleTextBuffers();
    _recentCommittedText += text;
    if (_recentCommittedText.length > 256) {
      _recentCommittedText = _recentCommittedText.substring(
        _recentCommittedText.length - 256,
      );
    }
    _recentCommittedTextAt = DateTime.now();
  }

  void _rememberLastCommittedText(String text) {
    _lastCommittedText = text;
    _lastCommittedTextAt = DateTime.now();
  }

  bool _wasRecentlyCommittedText(String text) {
    final lastAt = _lastCommittedTextAt;
    if (lastAt == null || _lastCommittedText != text) return false;
    if (DateTime.now().difference(lastAt) > _hardwareTextDedupWindow) {
      return false;
    }
    // 한 번의 커밋당 하드웨어 에코 하나만 억제한다(one-shot). 남겨 두면 같은
    // 글자를 다시 친 다음 하드웨어 입력까지 계속 중복으로 오판해 드롭한다.
    _lastCommittedText = '';
    _lastCommittedTextAt = null;
    return true;
  }

  bool _consumeRecentCommittedText(String text) {
    _clearStaleTextBuffers();
    if (_recentCommittedText.isEmpty || text.isEmpty) return false;
    if (!_recentCommittedText.startsWith(text)) return false;
    _recentCommittedText = _recentCommittedText.substring(text.length);
    if (_recentCommittedText.isEmpty) {
      _recentCommittedTextAt = null;
    }
    return true;
  }

  void _clearStaleTextBuffers() {
    final now = DateTime.now();
    final lastHardware = _recentHardwareTextAt;
    if (lastHardware != null &&
        now.difference(lastHardware) > _hardwareTextDedupWindow) {
      _recentHardwareText = '';
      _recentHardwareTextAt = null;
    }
    final lastCommitted = _recentCommittedTextAt;
    if (lastCommitted != null &&
        now.difference(lastCommitted) > _hardwareTextDedupWindow) {
      _recentCommittedText = '';
      _recentCommittedTextAt = null;
    }
    final lastExactCommit = _lastCommittedTextAt;
    if (lastExactCommit != null &&
        now.difference(lastExactCommit) > _hardwareTextDedupWindow) {
      _lastCommittedText = '';
      _lastCommittedTextAt = null;
    }
    final lastClearedIme = _lastClearedImeTextAt;
    if (lastClearedIme != null &&
        now.difference(lastClearedIme) > _staleImePrefixWindow) {
      _lastClearedImeText = '';
      _lastClearedImeTextAt = null;
    }
  }

  void _rememberLastClearedImeText(String text) {
    if (!_containsNonAscii(text)) return;
    _lastClearedImeText = text;
    _lastClearedImeTextAt = DateTime.now();
  }

  void _restoreStaleImePrefixIfNeeded(String text) {
    _clearStaleTextBuffers();
    if (_sentTextInputPrefix.isNotEmpty || _lastClearedImeText.isEmpty) {
      return;
    }
    final staleText = _lastClearedImeText;
    if (!text.startsWith(staleText) &&
        !_looksLikeStaleHangulEdit(staleText, text)) {
      return;
    }
    _sentTextInputPrefix = staleText;
    _traceInput('textCommit restore stale prefix "$_sentTextInputPrefix"');
  }

  bool _looksLikeStaleHangulEdit(String staleText, String text) {
    if (text.isEmpty || staleText.isEmpty) return false;
    if (!_isHangulSyllableOrJamo(staleText.runes.last)) return false;

    final common = _commonPrefixLength(staleText, text);
    if (common <= 0) return false;
    if (common >= staleText.length - 1) return true;

    // idle flush 이후 백스페이스로 여러 글자를 줄인 경우. 예: '한글이' -> '한'.
    return text.length < staleText.length && common == text.length;
  }

  Map<ShortcutActivator, VoidCallback> _terminalShortcutCallbacks({
    required AppSettings settings,
    required VoidCallback zoomIn,
    required VoidCallback zoomOut,
    required VoidCallback zoomReset,
  }) {
    final bindings = <ShortcutActivator, VoidCallback>{};
    void add(String action, VoidCallback callback) {
      for (final activator in shortcutActivatorsForAction(settings, action)) {
        bindings[activator] = callback;
      }
    }

    add('zoomIn', zoomIn);
    add('zoomOut', zoomOut);
    add('zoomReset', zoomReset);
    add('sessionPrevious', () => switchToPreviousActiveSession(ref));
    return bindings;
  }

  KeyEventResult _handleTerminalKeyEvent(
    BuildContext context,
    FocusNode _,
    KeyEvent event,
  ) {
    _trackModifierKey(event);
    _traceInput(
      'key ${event.runtimeType} logical=${event.logicalKey.debugName} '
      'character="${event.character}"',
    );
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _scrollTerminalToBottomOnInput();
    final key = _terminalKeyFor(event.logicalKey);
    final ctrl =
        HardwareKeyboard.instance.isControlPressed && _controlModifierActive;
    final alt = HardwareKeyboard.instance.isAltPressed && _altModifierActive;
    final meta = HardwareKeyboard.instance.isMetaPressed && _metaModifierActive;
    final shift =
        HardwareKeyboard.instance.isShiftPressed && _shiftModifierActive;
    if (_shouldDeferEditingKeyToIme(
      event.logicalKey,
      ctrl: ctrl,
      alt: alt,
      meta: meta,
    )) {
      // Microsoft IME는 한글 자모를 완성형 음절로 교체할 때 raw
      // Backspace를 먼저 보낸다. 이 키를 터미널이 소비하면 EditableText가
      // 기존 자모를 지우지 못해 조합 문자와 DEL 바이트가 누적된다.
      // 방향키와 Home/End/Page 키는 미전송 텍스트를 먼저 확정한 뒤
      // 터미널 커서를 움직여야 하므로 여기서 가로채지 않는다.
      _traceInput('key defer to IME logical=${event.logicalKey.debugName}');
      return KeyEventResult.ignored;
    }
    final settings = ref.read(appSettingsProvider);
    if (_matchesShortcut(
      'sessionPrevious',
      event.logicalKey,
      settings: settings,
      ctrl: ctrl,
      alt: alt,
      meta: meta,
      shift: shift,
    )) {
      switchToPreviousActiveSession(ref);
      return KeyEventResult.handled;
    }
    if (_matchesShortcut(
          'zoomIn',
          event.logicalKey,
          settings: settings,
          ctrl: ctrl,
          alt: alt,
          meta: meta,
          shift: shift,
        ) ||
        _matchesShortcut(
          'zoomOut',
          event.logicalKey,
          settings: settings,
          ctrl: ctrl,
          alt: alt,
          meta: meta,
          shift: shift,
        ) ||
        _matchesShortcut(
          'zoomReset',
          event.logicalKey,
          settings: settings,
          ctrl: ctrl,
          alt: alt,
          meta: meta,
          shift: shift,
        )) {
      return KeyEventResult.ignored;
    }
    if (_isCopyShortcut(
      event.logicalKey,
      settings: settings,
      ctrl: ctrl,
      alt: alt,
      meta: meta,
      shift: shift,
    )) {
      unawaited(_copySelectionToClipboard());
      return KeyEventResult.handled;
    }
    if (_isPasteShortcut(
      event.logicalKey,
      ctrl: ctrl,
      alt: alt,
      meta: meta,
      shift: shift,
    )) {
      unawaited(_pasteClipboardText(context));
      return KeyEventResult.handled;
    }
    if (ctrl && !alt && !meta && !shift && _isEnterKey(event.logicalKey)) {
      _sendLineFeedInput();
      return KeyEventResult.handled;
    }
    if (key != null &&
        (ctrl || alt || meta || _isNonPrintableKey(event.logicalKey))) {
      if (!ctrl &&
          !alt &&
          !meta &&
          _shouldFlushBeforeTerminalKey(event.logicalKey)) {
        _flushTextInputBuffer();
      }
      widget.session.engine.terminal.keyInput(
        key,
        ctrl: ctrl,
        alt: alt,
        shift: shift,
      );
      _discardStaleImeBufferAfterServerEdit(event.logicalKey);
      // Enter, Tab, 커서 이동, Ctrl 조합 등 여기로 오는 모든 키는 커서 위치나
      // 줄 맥락을 바꾼다. 그 뒤로는 "이미 보낸 prefix가 커서 바로 앞에 있다"는
      // 전제가 깨지므로 shadow와 복원 후보를 버린다.
      _forgetSentPrefixAfterTerminalKey();
      return KeyEventResult.handled;
    }

    if (!ctrl && !alt && !meta) {
      final character = _printableInputFor(event, shift: shift);
      if (character != null && _isAsciiPrintableText(character)) {
        // IME가 한글 등을 조합 중이면(_inputController에 미확정 텍스트 존재)
        // 이 문자를 하드웨어 경로로 가로채지 않는다. 여기서 버퍼를 비우면
        // 버퍼를 empty editing state로 초기화하면 블루투스 키보드의 한글 IME가
        // 영문 모드로 리셋되는 문제(이슈 #4)가 있다. IME가 직접 처리해
        // '안녕/'처럼 텍스트 채널로 들어오게 둔다.
        if (_logicalInputValue().text.isNotEmpty) {
          return KeyEventResult.ignored;
        }
        if (!_inputFocusNode.hasFocus) {
          _requestFocus();
        }
        _scheduleHardwareTextInput(character);
      }
    }

    return KeyEventResult.ignored;
  }

  void _sendLineFeedInput() {
    _flushTextInputBuffer();
    if (_terminalController.selection != null) {
      _terminalController.clearSelection();
    }
    _traceInput('key send line feed');
    widget.session.engine.terminal.textInput('\n');
    _releaseTextInputBuffer();
    _scrollTerminalToBottomOnInput();
  }

  KeyEventResult _handleInputFocusKeyEvent(FocusNode node, KeyEvent event) {
    _trackModifierKey(event);
    final shouldForward =
        event.logicalKey == LogicalKeyboardKey.tab ||
        (_isEnterKey(event.logicalKey) &&
            HardwareKeyboard.instance.isControlPressed);
    if (!shouldForward) {
      return KeyEventResult.ignored;
    }
    return _handleTerminalKeyEvent(context, node, event);
  }

  void _trackModifierKey(KeyEvent event) {
    final pressed = event is KeyDownEvent || event is KeyRepeatEvent;
    final released = event is KeyUpEvent;
    if (!pressed && !released) return;

    final active = pressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.controlLeft:
      case LogicalKeyboardKey.controlRight:
        _controlModifierActive = active;
        break;
      case LogicalKeyboardKey.altLeft:
      case LogicalKeyboardKey.altRight:
        _altModifierActive = active;
        break;
      case LogicalKeyboardKey.metaLeft:
      case LogicalKeyboardKey.metaRight:
        _metaModifierActive = active;
        break;
      case LogicalKeyboardKey.shiftLeft:
      case LogicalKeyboardKey.shiftRight:
        _shiftModifierActive = active;
        break;
    }
  }

  void _syncModifierKeyState() {
    final keyboard = HardwareKeyboard.instance;
    _controlModifierActive = keyboard.isControlPressed;
    _altModifierActive = keyboard.isAltPressed;
    _metaModifierActive = keyboard.isMetaPressed;
    _shiftModifierActive = keyboard.isShiftPressed;
  }

  void _traceInput(String message) {
    if (_inputTracePath.isEmpty) return;
    // `--dart-define=VIBE_TERMINAL_INPUT_TRACE=console`이면 콘솔로 출력해
    // 실기기에서 `flutter run` 로그만으로 IME/조합 흐름을 진단할 수 있다.
    if (_inputTracePath == 'console') {
      debugPrint('[input] ${DateTime.now().toIso8601String()} $message');
      return;
    }
    try {
      File(_inputTracePath).writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Trace logging is diagnostic-only and must not affect terminal input.
    }
  }

  bool _isCopyShortcut(
    LogicalKeyboardKey key, {
    required AppSettings settings,
    required bool ctrl,
    required bool alt,
    required bool meta,
    required bool shift,
  }) {
    if (_matchesShortcut(
      'copy',
      key,
      settings: settings,
      ctrl: ctrl,
      alt: alt,
      meta: meta,
      shift: shift,
    )) {
      return true;
    }
    return ctrl &&
        key == LogicalKeyboardKey.keyC &&
        !shift &&
        !meta &&
        settings.ctrlCBehavior == CtrlCBehavior.copySelection &&
        _selectedText() != null;
  }

  bool _isPasteShortcut(
    LogicalKeyboardKey key, {
    required bool ctrl,
    required bool alt,
    required bool meta,
    required bool shift,
  }) {
    return _matchesShortcut(
      'paste',
      key,
      settings: ref.read(appSettingsProvider),
      ctrl: ctrl,
      alt: alt,
      meta: meta,
      shift: shift,
    );
  }

  bool _matchesShortcut(
    String action,
    LogicalKeyboardKey key, {
    required AppSettings settings,
    required bool ctrl,
    required bool alt,
    required bool meta,
    required bool shift,
  }) {
    final bindings =
        settings.shortcutBindings[action] ?? kDefaultShortcutBindings[action];
    if (bindings == null) return false;
    return bindings.any(
      (binding) => _shortcutMatches(
        binding,
        key,
        ctrl: ctrl,
        alt: alt,
        meta: meta,
        shift: shift,
      ),
    );
  }

  bool _shortcutMatches(
    String binding,
    LogicalKeyboardKey key, {
    required bool ctrl,
    required bool alt,
    required bool meta,
    required bool shift,
  }) {
    final parts = binding
        .toLowerCase()
        .split('+')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toSet();
    final wantsCtrl = parts.remove('ctrl') || parts.remove('control');
    final wantsAlt = parts.remove('alt') || parts.remove('option');
    final wantsMeta =
        parts.remove('cmd') || parts.remove('command') || parts.remove('meta');
    final wantsShift = parts.remove('shift');
    if (ctrl != wantsCtrl ||
        alt != wantsAlt ||
        meta != wantsMeta ||
        shift != wantsShift ||
        parts.length != 1) {
      return false;
    }
    return _logicalKeyToken(key) == parts.single;
  }

  String? _logicalKeyToken(LogicalKeyboardKey key) {
    if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
        key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
      final offset = key.keyId - LogicalKeyboardKey.keyA.keyId;
      return String.fromCharCode('a'.codeUnitAt(0) + offset);
    }
    if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
        key.keyId <= LogicalKeyboardKey.digit9.keyId) {
      final offset = key.keyId - LogicalKeyboardKey.digit0.keyId;
      return String.fromCharCode('0'.codeUnitAt(0) + offset);
    }
    return switch (key) {
      LogicalKeyboardKey.equal => '=',
      LogicalKeyboardKey.minus => '-',
      LogicalKeyboardKey.tab => 'tab',
      LogicalKeyboardKey.insert => 'insert',
      _ => null,
    };
  }

  bool _shouldFlushBeforeTerminalKey(LogicalKeyboardKey key) {
    return _isEnterKey(key) ||
        key == LogicalKeyboardKey.tab ||
        _movesServerCursor(key);
  }

  /// 서버의 커서 위치를 바꾸는 키.
  ///
  /// 이런 키를 누르기 전에 미전송 입력을 확정해야 사용자가 보고 있던 위치에
  /// 글자가 들어간다. 확정하지 않으면 유휴 커밋이 나중에 발동해 **이동한
  /// 커서 위치에** 남은 음절이 삽입된다.
  bool _movesServerCursor(LogicalKeyboardKey key) {
    return switch (key) {
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.arrowUp ||
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.home ||
      LogicalKeyboardKey.end ||
      LogicalKeyboardKey.pageUp ||
      LogicalKeyboardKey.pageDown => true,
      _ => false,
    };
  }

  /// 터미널 키를 보낸 뒤 shadow 상태를 버린다.
  ///
  /// [_sentTextInputPrefix]는 "커서 바로 앞에 우리가 넣어 둔 글자"라는 전제로
  /// 쓰인다. Enter로 명령이 실행되거나 커서가 이동하면 그 전제가 깨지므로,
  /// 이후 diff에서 나가는 백스페이스는 사용자가 손대지 않은 글자를 지운다.
  ///
  /// 복원 후보([_lastClearedImeText])도 반드시 함께 버려야 한다. 남겨 두면
  /// [_restoreStaleImePrefixIfNeeded]가 죽은 prefix를 되살린다. 실제로
  /// `괜찮은` + Enter 뒤 새 줄에서 `괜`을 치면 이전 줄 기준으로 백스페이스
  /// 두 개가 새 줄로 나갔다.
  void _forgetSentPrefixAfterTerminalKey() {
    if (_sentTextInputPrefix.isEmpty && _lastClearedImeText.isEmpty) return;
    _traceInput(
      'terminal key drops shadow sent="$_sentTextInputPrefix" '
      'lastCleared="$_lastClearedImeText"',
    );
    // clear를 미룬 버퍼(Windows)는 전부 전송된 텍스트가 아직 편집값에 남아
    // 있다. shadow를 비우면 다음 갱신에서 그 텍스트가 새 입력으로 재전송되므로,
    // 버퍼 텍스트 전체를 "이미 보낸 것"으로 유지해 diff가 꼬리만 보게 한다.
    _sentTextInputPrefix = _textInputBufferReleased
        ? _logicalInputValue().text
        : '';
    _lastClearedImeText = '';
    _lastClearedImeTextAt = null;
  }

  /// 백스페이스/Delete를 서버로 그대로 보냈다면, IME 버퍼에 남아 있던 텍스트는
  /// 더 이상 서버 화면과 대응하지 않는다.
  ///
  /// 조합 중이 아닌데 버퍼에 글자가 남아 있는 상황은 이전 조합의 잔여물이다.
  /// 그대로 두면 다음 조합이 그 잔여물 앞에 삽입되고(커서가 0으로 돌아간다),
  /// shadow(_sentTextInputPrefix)도 실제 서버 상태와 어긋난 채로 계속 diff를
  /// 계산해 엉뚱한 문자가 전송된다. 조합 중일 때는 IME가 백스페이스를 직접
  /// 소비하므로 여기로 오지 않는다 — 그 경우는 건드리지 않는다.
  void _discardStaleImeBufferAfterServerEdit(LogicalKeyboardKey key) {
    if (key != LogicalKeyboardKey.backspace &&
        key != LogicalKeyboardKey.delete) {
      return;
    }
    final value = _logicalInputValue();
    if (value.text.isEmpty) return;
    if (_hasActiveComposing(value)) return;
    _traceInput('key backspace discards stale ime buffer "${value.text}"');
    _clearTextInputBuffer();
  }

  bool _shouldDeferEditingKeyToIme(
    LogicalKeyboardKey key, {
    required bool ctrl,
    required bool alt,
    required bool meta,
  }) {
    final value = _logicalInputValue();
    if (value.text.isEmpty || ctrl || alt || meta) return false;
    return switch (key) {
      LogicalKeyboardKey.backspace || LogicalKeyboardKey.delete => true,
      // Escape는 조합을 취소할 수 있을 때만 IME에 넘긴다. clear를 미룬 버퍼
      // (Windows)가 공백·ASCII로 끝나 있으면 조합이 없으므로 터미널로 보낸다.
      // 그렇지 않으면 vim 사용자가 입력 직후 누른 Esc가 삼켜진다.
      LogicalKeyboardKey.escape => _mayHaveLiveHangulComposition(value),
      _ => false,
    };
  }

  bool _mayHaveLiveHangulComposition(TextEditingValue value) {
    if (_hasActiveComposing(value)) return true;
    final text = value.text;
    return text.isNotEmpty && _isHangulSyllableOrJamo(text.runes.last);
  }

  bool _isEnterKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
  }

  bool _isAsciiPrintableText(String value) {
    return value.codeUnits.every((unit) => unit >= 0x20 && unit <= 0x7E);
  }

  bool _containsNonAscii(String value) {
    return value.runes.any((rune) => rune > 0x7F);
  }

  /// IME 텍스트가 한글 조합 경계로 끝나는지. 마지막 글자가 한글 음절/자모가
  /// 아니면(공백·`/`·`.`·`-`·숫자 등) 직전 한글은 백스페이스로 분해해도 그 글자를
  /// 넘어갈 수 없으므로, 여기서 버퍼를 비워 shadow 누적을 끊어도 분해 처리가
  /// 깨지지 않는다. 터미널에서 흔한 경로/플래그(`cd /usr`, `ls -la`)마다 자동
  /// 재동기화돼 desync 전파 범위가 크게 줄어든다(이슈 #3).
  bool _endsAtImeCommitBoundary(String text) {
    if (text.isEmpty) return false;
    final last = text.runes.last;
    return !_isHangulSyllableOrJamo(last);
  }

  bool _isHangulSyllableOrJamo(int rune) {
    // 완성형 한글 음절(가–힣)은 백스페이스로 직전 음절이 분해될 수 있다.
    if (rune >= 0xAC00 && rune <= 0xD7A3) return true;
    return _isHangulJamo(rune);
  }

  bool _isIdleCommittableImeText(TextEditingValue value) {
    if (_hasActiveComposing(value)) return false;
    final runes = value.text.runes.toList(growable: false);
    var hasNonAscii = false;
    for (final rune in runes) {
      if (rune > 0x7F) hasNonAscii = true;
      if (_isHangulJamo(rune)) return false;
    }
    return hasNonAscii;
  }

  bool _isHangulJamo(int rune) {
    return (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F) ||
        (rune >= 0xA960 && rune <= 0xA97F) ||
        (rune >= 0xD7B0 && rune <= 0xD7FF);
  }

  bool _containsHangulJamo(String value) {
    return _firstHangulJamoIndex(value) >= 0;
  }

  int _firstHangulJamoIndex(String value) {
    for (var i = 0; i < value.length; i++) {
      if (_isHangulJamo(value.codeUnitAt(i))) return i;
    }
    return -1;
  }

  String _describeEditingValue(TextEditingValue value) {
    final selection = value.selection;
    final composing = value.composing;
    return 'text="${value.text}" '
        'selection=${selection.start}:${selection.end} '
        'composing=${composing.start}:${composing.end}';
  }

  String? _printableInputFor(KeyEvent event, {required bool shift}) {
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        !character.codeUnits.any((unit) => unit < 0x20 || unit == 0x7F)) {
      return character;
    }

    final key = event.logicalKey;
    if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
        key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
      final codeUnit =
          'a'.codeUnitAt(0) + key.keyId - LogicalKeyboardKey.keyA.keyId;
      final letter = String.fromCharCode(codeUnit);
      return shift ? letter.toUpperCase() : letter;
    }

    final digits = {
      LogicalKeyboardKey.digit0: ['0', ')'],
      LogicalKeyboardKey.digit1: ['1', '!'],
      LogicalKeyboardKey.digit2: ['2', '@'],
      LogicalKeyboardKey.digit3: ['3', '#'],
      LogicalKeyboardKey.digit4: ['4', r'$'],
      LogicalKeyboardKey.digit5: ['5', '%'],
      LogicalKeyboardKey.digit6: ['6', '^'],
      LogicalKeyboardKey.digit7: ['7', '&'],
      LogicalKeyboardKey.digit8: ['8', '*'],
      LogicalKeyboardKey.digit9: ['9', '('],
    };
    final digit = digits[key];
    if (digit != null) return shift ? digit[1] : digit[0];

    final punctuation = {
      LogicalKeyboardKey.space: [' ', ' '],
      LogicalKeyboardKey.minus: ['-', '_'],
      LogicalKeyboardKey.equal: ['=', '+'],
      LogicalKeyboardKey.bracketLeft: ['[', '{'],
      LogicalKeyboardKey.bracketRight: [']', '}'],
      LogicalKeyboardKey.backslash: [r'\', '|'],
      LogicalKeyboardKey.semicolon: [';', ':'],
      LogicalKeyboardKey.quote: ["'", '"'],
      LogicalKeyboardKey.comma: [',', '<'],
      LogicalKeyboardKey.period: ['.', '>'],
      LogicalKeyboardKey.slash: ['/', '?'],
      LogicalKeyboardKey.backquote: ['`', '~'],
      LogicalKeyboardKey.numpad0: ['0', '0'],
      LogicalKeyboardKey.numpad1: ['1', '1'],
      LogicalKeyboardKey.numpad2: ['2', '2'],
      LogicalKeyboardKey.numpad3: ['3', '3'],
      LogicalKeyboardKey.numpad4: ['4', '4'],
      LogicalKeyboardKey.numpad5: ['5', '5'],
      LogicalKeyboardKey.numpad6: ['6', '6'],
      LogicalKeyboardKey.numpad7: ['7', '7'],
      LogicalKeyboardKey.numpad8: ['8', '8'],
      LogicalKeyboardKey.numpad9: ['9', '9'],
      LogicalKeyboardKey.numpadDecimal: ['.', '.'],
      LogicalKeyboardKey.numpadAdd: ['+', '+'],
      LogicalKeyboardKey.numpadSubtract: ['-', '-'],
      LogicalKeyboardKey.numpadMultiply: ['*', '*'],
      LogicalKeyboardKey.numpadDivide: ['/', '/'],
    };
    final value = punctuation[key];
    if (value == null) return null;
    return shift ? value[1] : value[0];
  }

  bool _isNonPrintableKey(LogicalKeyboardKey key) {
    return switch (key) {
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter ||
      LogicalKeyboardKey.backspace ||
      LogicalKeyboardKey.tab ||
      LogicalKeyboardKey.escape ||
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.arrowUp ||
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.home ||
      LogicalKeyboardKey.end ||
      LogicalKeyboardKey.pageUp ||
      LogicalKeyboardKey.pageDown ||
      LogicalKeyboardKey.insert ||
      LogicalKeyboardKey.delete ||
      LogicalKeyboardKey.f1 ||
      LogicalKeyboardKey.f2 ||
      LogicalKeyboardKey.f3 ||
      LogicalKeyboardKey.f4 ||
      LogicalKeyboardKey.f5 ||
      LogicalKeyboardKey.f6 ||
      LogicalKeyboardKey.f7 ||
      LogicalKeyboardKey.f8 ||
      LogicalKeyboardKey.f9 ||
      LogicalKeyboardKey.f10 ||
      LogicalKeyboardKey.f11 ||
      LogicalKeyboardKey.f12 => true,
      _ => false,
    };
  }

  TerminalKey? _terminalKeyFor(LogicalKeyboardKey key) {
    if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
        key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
      final offset = key.keyId - LogicalKeyboardKey.keyA.keyId;
      return TerminalKey.values[TerminalKey.keyA.index + offset];
    }

    return switch (key) {
      LogicalKeyboardKey.digit0 => TerminalKey.digit0,
      LogicalKeyboardKey.digit1 => TerminalKey.digit1,
      LogicalKeyboardKey.digit2 => TerminalKey.digit2,
      LogicalKeyboardKey.digit3 => TerminalKey.digit3,
      LogicalKeyboardKey.digit4 => TerminalKey.digit4,
      LogicalKeyboardKey.digit5 => TerminalKey.digit5,
      LogicalKeyboardKey.digit6 => TerminalKey.digit6,
      LogicalKeyboardKey.digit7 => TerminalKey.digit7,
      LogicalKeyboardKey.digit8 => TerminalKey.digit8,
      LogicalKeyboardKey.digit9 => TerminalKey.digit9,
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter => TerminalKey.enter,
      LogicalKeyboardKey.backspace => TerminalKey.backspace,
      LogicalKeyboardKey.tab => TerminalKey.tab,
      LogicalKeyboardKey.escape => TerminalKey.escape,
      LogicalKeyboardKey.space => TerminalKey.space,
      LogicalKeyboardKey.minus => TerminalKey.minus,
      LogicalKeyboardKey.equal => TerminalKey.equal,
      LogicalKeyboardKey.bracketLeft => TerminalKey.bracketLeft,
      LogicalKeyboardKey.bracketRight => TerminalKey.bracketRight,
      LogicalKeyboardKey.backslash => TerminalKey.backslash,
      LogicalKeyboardKey.semicolon => TerminalKey.semicolon,
      LogicalKeyboardKey.quote => TerminalKey.quote,
      LogicalKeyboardKey.comma => TerminalKey.comma,
      LogicalKeyboardKey.period => TerminalKey.period,
      LogicalKeyboardKey.slash => TerminalKey.slash,
      LogicalKeyboardKey.backquote => TerminalKey.backquote,
      LogicalKeyboardKey.arrowLeft => TerminalKey.arrowLeft,
      LogicalKeyboardKey.arrowRight => TerminalKey.arrowRight,
      LogicalKeyboardKey.arrowUp => TerminalKey.arrowUp,
      LogicalKeyboardKey.arrowDown => TerminalKey.arrowDown,
      LogicalKeyboardKey.home => TerminalKey.home,
      LogicalKeyboardKey.end => TerminalKey.end,
      LogicalKeyboardKey.pageUp => TerminalKey.pageUp,
      LogicalKeyboardKey.pageDown => TerminalKey.pageDown,
      LogicalKeyboardKey.insert => TerminalKey.insert,
      LogicalKeyboardKey.delete => TerminalKey.delete,
      LogicalKeyboardKey.f1 => TerminalKey.f1,
      LogicalKeyboardKey.f2 => TerminalKey.f2,
      LogicalKeyboardKey.f3 => TerminalKey.f3,
      LogicalKeyboardKey.f4 => TerminalKey.f4,
      LogicalKeyboardKey.f5 => TerminalKey.f5,
      LogicalKeyboardKey.f6 => TerminalKey.f6,
      LogicalKeyboardKey.f7 => TerminalKey.f7,
      LogicalKeyboardKey.f8 => TerminalKey.f8,
      LogicalKeyboardKey.f9 => TerminalKey.f9,
      LogicalKeyboardKey.f10 => TerminalKey.f10,
      LogicalKeyboardKey.f11 => TerminalKey.f11,
      LogicalKeyboardKey.f12 => TerminalKey.f12,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive 필수 호출
    // 보조 키바의 키보드 토글 등 외부에서 포커스를 요청하면, 활성 세션의
    // 터미널만 반응해 소프트키보드를 띄운다.
    ref.listen(keyboardFocusRequestProvider, (_, _) {
      if (widget.session.id == ref.read(activeSessionIdProvider)) {
        _requestFocus();
      }
    });
    ref.listen(activeSessionIdProvider, (_, activeId) {
      if (activeId == widget.session.id) {
        _syncModifierKeyState();
        _requestFocus();
      }
    });
    final settings = ref.watch(appSettingsProvider);
    final settingsController = ref.read(appSettingsProvider.notifier);
    final fontSize = settings.terminalFontSize;

    switch (widget.session.status) {
      case SessionStatus.connecting:
        return const Center(child: CircularProgressIndicator());
      case SessionStatus.error:
        return _SessionErrorView(
          failure: widget.session.failure,
          detail: widget.session.error,
          onRetry: widget.onRetry,
          onEditHost: widget.onEditHost,
          onFallbackToCmd: widget.onFallbackToCmd,
          isPowershellFallbackAvailable: widget.isPowershellFallbackAvailable,
        );
      case SessionStatus.disconnected:
        return Column(
          children: [
            _TerminalHeader(
              session: widget.session,
              onRetry: widget.onRetry,
              onZoomIn: () => settingsController.setTerminalFontSize(
                fontSize + AppSettings.fontSizeStep,
              ),
              onZoomOut: () => settingsController.setTerminalFontSize(
                fontSize - AppSettings.fontSizeStep,
              ),
              onZoomReset: () => settingsController.setTerminalFontSize(
                AppSettings.defaultSettings.terminalFontSize,
              ),
              onRepaint: _requestTerminalRepaint,
            ),
            if (widget.session.fellBackToDirectSsh)
              _DirectSshFallbackNotice(onEditHost: widget.onEditHost),
            Expanded(
              child: Stack(
                children: [
                  TerminalView(
                    widget.session.engine.terminal,
                    key: _terminalViewKey,
                    controller: _terminalController,
                    scrollController: _terminalScrollController,
                    readOnly: true,
                    hardwareKeyboardOnly: true,
                    theme: settings.resolvedTerminalTheme,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    alwaysShowCursor: false,
                    textStyle: TerminalStyle(
                      fontSize: fontSize,
                      height: settings.terminalLineHeight,
                      fontFamily: settings.terminalFontFamily,
                      fontFamilyFallback: settings.fontFallback,
                    ),
                  ),
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: _DisconnectedBadge(),
                  ),
                ],
              ),
            ),
          ],
        );
      case SessionStatus.connected:
        return Column(
          children: [
            _TerminalHeader(
              session: widget.session,
              onRetry: widget.onRetry,
              onZoomIn: () => settingsController.setTerminalFontSize(
                fontSize + AppSettings.fontSizeStep,
              ),
              onZoomOut: () => settingsController.setTerminalFontSize(
                fontSize - AppSettings.fontSizeStep,
              ),
              onZoomReset: () => settingsController.setTerminalFontSize(
                AppSettings.defaultSettings.terminalFontSize,
              ),
              onRepaint: _requestTerminalRepaint,
            ),
            if (widget.session.fellBackToDirectSsh)
              _DirectSshFallbackNotice(onEditHost: widget.onEditHost),
            Expanded(
              child: CallbackShortcuts(
                bindings: _terminalShortcutCallbacks(
                  settings: settings,
                  zoomIn: () => settingsController.setTerminalFontSize(
                    fontSize + AppSettings.fontSizeStep,
                  ),
                  zoomOut: () => settingsController.setTerminalFontSize(
                    fontSize - AppSettings.fontSizeStep,
                  ),
                  zoomReset: () => settingsController.setTerminalFontSize(
                    AppSettings.defaultSettings.terminalFontSize,
                  ),
                ),
                child: Shortcuts.manager(
                  debugLabel: 'Terminal input shortcuts',
                  manager: _terminalShortcutManager,
                  child: Stack(
                    children: [
                      Listener(
                        onPointerDown: _handlePointerDown,
                        onPointerMove: _handlePointerMove,
                        onPointerUp: _handlePointerUp,
                        onPointerCancel: _handlePointerUp,
                        child: GestureDetector(
                          behavior: HitTestBehavior.deferToChild,
                          onTap: () {
                            _disableSelectionMode(clearSelection: true);
                            _requestFocus();
                          },
                          child: TerminalView(
                            widget.session.engine.terminal,
                            key: _terminalViewKey,
                            controller: _terminalController,
                            scrollController: _terminalScrollController,
                            readOnly: true,
                            hardwareKeyboardOnly: true,
                            theme: settings.resolvedTerminalTheme,
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                            alwaysShowCursor: true,
                            onSecondaryTapDown: settings.rightClickPaste
                                ? (_, _) =>
                                      unawaited(_pasteClipboardText(context))
                                : null,
                            textStyle: TerminalStyle(
                              fontSize: fontSize,
                              height: settings.terminalLineHeight,
                              fontFamily: settings.terminalFontFamily,
                              fontFamilyFallback: settings.fontFallback,
                            ),
                          ),
                        ),
                      ),
                      _TerminalImeInputLayer(
                        editableTextKey: _editableTextKey,
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        fontSize: fontSize,
                        fontFamily: settings.terminalFontFamily,
                        fontFallback: settings.fontFallback,
                        onSubmitted: _handleImeSubmit,
                        onContentInserted: _handleContentInserted,
                      ),
                      _buildComposingOverlay(settings, fontSize),
                      // 선택 모드: 드래그를 가로채 마우스 모드(TUI)와 무관하게
                      // 로컬 선택. 셀렉션 오버레이보다 아래에 둬 핸들 조작은 유지.
                      if (_selectionMode)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) =>
                                _selectionModePanStart(d.globalPosition),
                            onPanUpdate: (d) =>
                                _selectionModePanUpdate(d.globalPosition),
                            onPanEnd: (_) => _selectionModePanEnd(),
                            onPanCancel: _selectionModePanEnd,
                          ),
                        ),
                      // 선택 핸들·툴바는 셀 픽셀 좌표로 배치되므로 선택/스크롤
                      // 변화뿐 아니라 레이아웃 변화(패널·창 크기 조정)와 터미널
                      // 갱신(출력·reflow)에도 다시 계산해야 한다. xterm은 레이아웃
                      // 중 스크롤 오프셋을 correctBy로 조용히 바꾸기 때문에 스크롤
                      // 컨트롤러 알림만으로는 핸들이 옛 위치에 남아 하이라이트와
                      // 어긋난다. LayoutBuilder는 터미널(앞 형제) 레이아웃 뒤에
                      // 빌드되므로 보정된 오프셋을 읽는다.
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, _) => ListenableBuilder(
                            listenable: Listenable.merge([
                              _terminalController,
                              _terminalScrollController,
                              _terminalChangeBridge,
                            ]),
                            builder: (context, _) {
                              final geo = _selectionGeometry();
                              return TerminalSelectionOverlay(
                                geometry: geo,
                                onHandleDragStart: _beginSelectionDrag,
                                onHandleDragStop: _endSelectionDrag,
                                onHandleDragBegin: (g) =>
                                    _dragSelectionEnd(g, draggingBegin: true),
                                onHandleDragEnd: (g) =>
                                    _dragSelectionEnd(g, draggingBegin: false),
                                toolbar: geo == null
                                    ? const SizedBox.shrink()
                                    : SelectionToolbar(
                                        anchor: Offset(
                                          (geo.begin.dx + geo.end.dx) / 2 +
                                              geo.cellSize.width / 2,
                                          geo.begin.dy < geo.end.dy
                                              ? geo.begin.dy
                                              : geo.end.dy,
                                        ),
                                        onCopy: () => unawaited(
                                          _copySelectionToClipboard(),
                                        ),
                                        onSelectAll: _selectAll,
                                      ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _TerminalImeInputLayer extends StatelessWidget {
  const _TerminalImeInputLayer({
    required this.editableTextKey,
    required this.controller,
    required this.focusNode,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFallback,
    required this.onSubmitted,
    required this.onContentInserted,
  });

  final GlobalKey<EditableTextState> editableTextKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final double fontSize;
  final String fontFamily;
  final List<String> fontFallback;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<KeyboardInsertedContent> onContentInserted;

  @override
  Widget build(BuildContext context) {
    final height = (fontSize * 1.35).clamp(18.0, 40.0);

    return Positioned(
      left: 14,
      top: 10,
      width: 320,
      height: height,
      child: IgnorePointer(
        child: ClipRect(
          child: EditableText(
            key: editableTextKey,
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            style: TextStyle(
              color: const Color(0x01000000),
              fontSize: fontSize,
              height: 1.25,
              fontFamily: fontFamily,
              fontFamilyFallback: fontFallback,
            ),
            rendererIgnoresPointer: true,
            enableInteractiveSelection: false,
            selectionColor: Colors.transparent,
            showCursor: false,
            cursorWidth: 0,
            cursorColor: Colors.transparent,
            backgroundCursorColor: Colors.transparent,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            // onEditingComplete를 직접 제공하면 기본 동작(포커스 해제 → 키보드 닫힘)이
            // 일어나지 않아, 엔터 후에도 키보드가 유지된다(깜빡임 방지).
            onEditingComplete: () => onSubmitted(''),
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 1,
            scrollPadding: EdgeInsets.zero,
            contentInsertionConfiguration: ContentInsertionConfiguration(
              allowedMimeTypes: kImageInsertionMimeTypes,
              onContentInserted: onContentInserted,
            ),
          ),
        ),
      ),
    );
  }
}

class _DisconnectedBadge extends StatelessWidget {
  const _DisconnectedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VibeColors.surface.withValues(alpha: 0.92),
        border: Border.all(color: VibeColors.borderSoft),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_off,
              size: 16,
              color: VibeColors.statusDisconnected,
            ),
            SizedBox(width: 6),
            Text('연결이 종료되었습니다'),
          ],
        ),
      ),
    );
  }
}

class _TerminalShortcutManager extends ShortcutManager {
  _TerminalShortcutManager({required this.onTerminalKey})
    : super(shortcuts: const <ShortcutActivator, Intent>{});

  final KeyEventResult Function(BuildContext context, KeyEvent event)
  onTerminalKey;

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    final result = onTerminalKey(context, event);
    if (result != KeyEventResult.ignored) {
      return result;
    }
    return super.handleKeypress(context, event);
  }
}

/// 화면 텍스트 스냅샷 시트: 표준 [SelectableText]로 선택/복사하고 전체 복사도 제공.
class _CopySheet extends StatelessWidget {
  const _CopySheet({
    required this.text,
    required this.fontFamily,
    required this.fontFallback,
  });

  final String text;
  final String fontFamily;
  final List<String> fontFallback;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SizedBox(
      height: media.size.height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '화면 텍스트 — 길게 눌러 선택·복사',
                    style: TextStyle(
                      color: VibeColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('모두 복사'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: VibeColors.borderSoft),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  text,
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontSize: 13,
                    height: 1.3,
                    fontFamily: fontFamily,
                    fontFamilyFallback: fontFallback,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectSshFallbackNotice extends StatelessWidget {
  const _DirectSshFallbackNotice({this.onEditHost});

  final VoidCallback? onEditHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('direct-ssh-fallback-notice'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: VibeColors.warning.withValues(alpha: 0.12),
        border: const Border(bottom: BorderSide(color: VibeColors.warning)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: VibeColors.warning,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'tmux가 없어 일반 SSH로 연결했습니다. 연결이 끊기거나 앱을 '
              '다시 시작하면 이 작업은 복원되지 않습니다.',
              style: TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          if (onEditHost != null)
            IconButton(
              tooltip: '호스트 설정 열기',
              onPressed: onEditHost,
              icon: const Icon(Icons.settings_outlined, size: 18),
              color: VibeColors.warning,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _TerminalHeader extends ConsumerWidget {
  const _TerminalHeader({
    required this.session,
    required this.onRetry,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onRepaint,
  });

  final SessionInfo session;
  final VoidCallback? onRetry;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final VoidCallback onRepaint;

  Color get _statusColor => switch (session.status) {
    SessionStatus.connecting => VibeColors.statusConnecting,
    SessionStatus.connected => VibeColors.statusConnected,
    SessionStatus.disconnected => VibeColors.statusDisconnected,
    SessionStatus.error => VibeColors.statusError,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 세션이 2개 이상일 때만 세션 전환(위/아래) 버튼을 활성화한다.
    final canSwitchSession = ref.watch(sessionManagerProvider).length > 1;
    final items = ref.watch(
      appSettingsProvider.select((s) => s.terminalHeaderItems),
    );

    // 토큰 하나를 헤더 아이콘 버튼으로. 알 수 없는 토큰은 null로 건너뛴다.
    Widget? headerItem(String token) {
      final def = resolveHeaderToken(token);
      if (def == null) return null;
      final onTap = switch (token) {
        'sessionPrev' =>
          canSwitchSession ? () => cycleActiveSession(ref, -1) : null,
        'sessionNext' =>
          canSwitchSession ? () => cycleActiveSession(ref, 1) : null,
        'retry' => onRetry,
        'zoomIn' => onZoomIn,
        'zoomOut' => onZoomOut,
        'zoomReset' => onZoomReset,
        'repaint' => onRepaint,
        _ => null,
      };
      return IconButton(
        tooltip: def.label,
        onPressed: onTap,
        icon: Icon(def.icon ?? Icons.help_outline, size: 18),
      );
    }

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: VibeColors.surface,
        border: Border(bottom: BorderSide(color: VibeColors.borderSoft)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 데스크톱 좌측 묶음의 고정 폭(상태점 8 + 간격 10). 액션 상한에서 이만큼을
          // 남겨 두지 않으면 좌측 Row가 0에 가까운 폭을 받아 대신 넘친다.
          const leadingMinWidth = 18.0;
          final actionsMaxWidth =
              (constraints.maxWidth -
                      (context.isCompact ? 0.0 : leadingMinWidth))
                  .clamp(0.0, double.infinity);
          return Row(
            children: [
              // 모바일은 AppBar가 이미 세션명을 보여주므로, 여기서는 세션명·상태점
              // 대신 연결 지속 시간(상태는 글자 색)으로 대체한다.
              // 데스크톱은 AppBar가 없으므로 상태점 + 세션명을 유지한다.
              //
              // 좌측 묶음을 Expanded 하나로 모아 두면 Row의 비-flex 자식이 우측
              // 액션뿐이라, 아래 상한만으로 넘침을 막을 수 있다.
              Expanded(
                child: context.isCompact
                    ? _SessionStatusLine(session: session)
                    : Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _statusColor,
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
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              // 우측 액션이 헤더 폭을 넘으면 가로 스크롤되도록 감싼다(모바일 대응).
              //
              // Row의 비-flex 자식은 주축 제약이 무한이어서 스크롤 뷰가 내용 폭을
              // 그대로 가져간다. 액션이 늘어나면 Expanded가 0이 되고도 헤더를
              // 넘치므로, 헤더 안쪽 폭을 상한으로 걸어 넘침 대신 스크롤로 흐르게 한다.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: actionsMaxWidth),
                child: _HeaderActions(
                  children: [for (final token in items) ?headerItem(token)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 헤더 우측 액션들을 묶고, 폭이 부족하면 가로 스크롤되게 한다.
class _HeaderActions extends StatelessWidget {
  const _HeaderActions({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// 헤더 좌측에 연결 지속 시간(uptime)을 라이브로 표시한다.
/// connected가 아니면 상태 텍스트를 보여주며, 글자 색으로 상태를 나타낸다.
class _SessionStatusLine extends StatefulWidget {
  const _SessionStatusLine({required this.session});

  final SessionInfo session;

  @override
  State<_SessionStatusLine> createState() => _SessionStatusLineState();
}

class _SessionStatusLineState extends State<_SessionStatusLine> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_SessionStatusLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  /// connected일 때만 주기적으로 uptime을 갱신한다.
  void _syncTicker() {
    final shouldRun = widget.session.status == SessionStatus.connected;
    if (shouldRun && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) setState(() {});
      });
    } else if (!shouldRun && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Color get _color => switch (widget.session.status) {
    SessionStatus.connecting => VibeColors.statusConnecting,
    SessionStatus.connected => VibeColors.statusConnected,
    SessionStatus.disconnected => VibeColors.statusDisconnected,
    SessionStatus.error => VibeColors.statusError,
  };

  String _label() {
    switch (widget.session.status) {
      case SessionStatus.connecting:
        return '연결 중…';
      case SessionStatus.disconnected:
        return '연결 종료됨';
      case SessionStatus.error:
        return '연결 오류';
      case SessionStatus.connected:
        final since = widget.session.connectedAt;
        if (since == null) return '연결됨';
        return _formatUptime(DateTime.now().difference(since));
    }
  }

  static String _formatUptime(Duration d) {
    if (d.inSeconds < 60) return '방금 연결됨';
    if (d.inMinutes < 60) return '${d.inMinutes}분 연결됨';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (minutes == 0) return '$hours시간 연결됨';
    return '$hours시간 $minutes분 연결됨';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _color,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }
}

class _SessionErrorView extends StatelessWidget {
  const _SessionErrorView({
    required this.failure,
    required this.detail,
    required this.onRetry,
    required this.onEditHost,
    required this.onFallbackToCmd,
    required this.isPowershellFallbackAvailable,
  });

  final Failure? failure;
  final String? detail;
  final VoidCallback? onRetry;
  final VoidCallback? onEditHost;
  final VoidCallback? onFallbackToCmd;
  final bool isPowershellFallbackAvailable;

  String get _title => switch (failure) {
    LocalShellMissingExecutableFailure() => '로컬 셸 실행 파일 누락',
    AuthFailure() => '인증에 실패했습니다',
    HostKeyMismatchFailure() => '호스트 키가 변경되었습니다',
    NetworkFailure() => '네트워크 연결에 실패했습니다',
    KubernetesFailure() => 'Kubernetes 연결 준비에 실패했습니다',
    RemoteSessionFailure() => '작업 이어가기를 시작하지 못했습니다',
    StorageFailure() => '자격증명 저장소를 읽지 못했습니다',
    JumpChainFailure() => 'Jump 호스트 체인 오류',
    UnknownFailure() || null => '연결에 실패했습니다',
  };

  String get _message => switch (failure) {
    LocalShellMissingExecutableFailure(
      shellLabel: final missingShellLabel,
      executable: final executable,
      guidance: final guidance,
    ) =>
      '로컬 셸 [$missingShellLabel]를 시작할 실행 파일을 찾지 못했습니다.\n'
          '$executable\n'
          '$guidance',
    AuthFailure() => '사용자명, 비밀번호 또는 인증 방식을 확인하세요.',
    HostKeyMismatchFailure() =>
      '서버 신원이 저장된 호스트 키와 다릅니다. 서버 변경 여부를 확인한 뒤 다시 시도하세요.',
    NetworkFailure() => '주소, 포트, 네트워크 상태와 SSH 서버 실행 여부를 확인하세요.',
    KubernetesFailure() =>
      'kubectl 설치·PATH, context, namespace, 리소스와 Pod SSH 설정을 확인하세요.',
    RemoteSessionFailure() => '서버에 tmux를 설치하거나 호스트 설정에서 작업 이어가기를 꺼 주세요.',
    StorageFailure() => '저장된 자격증명을 읽을 수 없습니다. 비밀번호를 다시 저장하세요.',
    JumpChainFailure() => 'Jump 호스트 설정을 확인한 뒤 다시 연결하세요.',
    UnknownFailure() || null => '설정을 확인한 뒤 다시 연결하세요.',
  };

  @override
  Widget build(BuildContext context) {
    final errorDetail = detail;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                failure is HostKeyMismatchFailure
                    ? Icons.security
                    : Icons.error_outline,
                size: 36,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(_title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_message),
              if (errorDetail != null && errorDetail.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  errorDetail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (failure is LocalShellMissingExecutableFailure &&
                      isPowershellFallbackAvailable &&
                      onFallbackToCmd != null)
                    FilledButton.icon(
                      onPressed: onFallbackToCmd,
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('CMD로 전환 후 다시 시도'),
                    ),
                  if (failure is LocalShellMissingExecutableFailure)
                    OutlinedButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text: (failure as LocalShellMissingExecutableFailure)
                              .executable,
                        ),
                      ),
                      icon: const Icon(Icons.content_copy),
                      label: const Text('실행 파일 경로 복사'),
                    ),
                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('다시 시도'),
                    ),
                  if (onEditHost != null)
                    OutlinedButton.icon(
                      onPressed: onEditHost,
                      icon: const Icon(Icons.tune),
                      label: const Text('호스트 수정'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeBridge extends ChangeNotifier {
  void bump() => notifyListeners();
}
