import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection, SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme.dart';
import '../../../ai/ai_chat_service.dart';
import '../../../ai/terminal_recap.dart';
import '../../../ai/terminal_reply_suggestions.dart';
import '../../../settings/app_settings.dart';
import '../../../state/providers.dart';
import '../../../session/session.dart';
import '../../../terminal/gui/terminal_gui_controller.dart';
import '../../../terminal/gui/terminal_gui_document.dart';
import '../../../terminal/gui/terminal_interaction_controller.dart';
import '../../../terminal/gui/terminal_interaction.dart';
import '../../../terminal/gui/terminal_auto_reply.dart';
import '../../../terminal/gui/terminal_reply_suggestion_controller.dart';
import '../../shell/ai_data_consent.dart';
import 'terminal_interaction_card.dart';
import 'terminal_gui_mode.dart';
import '../terminal_native_text_input.dart';
import 'terminal_gui_links.dart';
import 'terminal_reply_suggestion_panel.dart';
import 'terminal_reply_overlay.dart';

class TerminalGuiSurface extends ConsumerStatefulWidget {
  const TerminalGuiSurface({
    super.key,
    required this.session,
    required this.theme,
    required this.fontSize,
    required this.terminal,
    this.terminalInputActivity,
    this.onReplyOverlayOpened,
    this.onReplyOverlayClosed,
  });
  final SessionInfo session;
  final TerminalTheme theme;
  final double fontSize;
  final Widget terminal;
  final Listenable? terminalInputActivity;
  final VoidCallback? onReplyOverlayOpened;
  final VoidCallback? onReplyOverlayClosed;

  @override
  ConsumerState<TerminalGuiSurface> createState() => _TerminalGuiSurfaceState();
}

class _TerminalGuiSurfaceState extends ConsumerState<TerminalGuiSurface> {
  var _visited = false;
  final _autoReplyHistory = TerminalAutoReplyHistory();

  /// 퍼피 ReCap에 보낼 사용자 입력. 새 키 기록기를 두지 않고 세션 로그의
  /// `[input]` 줄을 재사용해 비밀번호 프롬프트 가림 처리를 그대로 따른다.
  /// 로그가 없는 세션은 빈 목록을 돌려 화면 출력만 요약하게 한다.
  Future<List<String>> _recapInputs() async {
    final logId = ref
        .read(sessionManagerProvider.notifier)
        .logIdOf(widget.session.id);
    if (logId == null || logId.trim().isEmpty) return const [];
    final tail = await ref
        .read(sessionLogRepositoryProvider)
        .readPlainTextTailById(
          logId,
          maxLines: TerminalRecapService.inputLogLines,
        );
    return TerminalRecapService.inputsFromSessionLog(tail);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      terminalGuiModesProvider.select((ids) => ids.contains(widget.session.id)),
    );
    _visited |= enabled;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: enabled,
          child: ExcludeFocus(
            excluding: enabled,
            child: TerminalReplyOverlay(
              terminal: widget.session.engine.terminal,
              connected: widget.session.status == SessionStatus.connected,
              active: !enabled,
              agentTitle: () => widget.session.engine.title ?? '',
              aiSettings: ref.watch(appSettingsProvider.select((s) => s.ai)),
              aiService: ref.watch(aiChatServiceProvider),
              aiConsentStore: ref.watch(aiConsentStoreProvider),
              inputActivity: widget.terminalInputActivity,
              autoReplyHistory: _autoReplyHistory,
              recapInputs: _recapInputs,
              onOpened: widget.onReplyOverlayOpened,
              onClosed: widget.onReplyOverlayClosed,
              child: widget.terminal,
            ),
          ),
        ),
        if (_visited)
          Offstage(
            offstage: !enabled,
            child: ExcludeFocus(
              excluding: !enabled,
              child: TickerMode(
                enabled: enabled,
                child: TerminalGuiView(
                  autoReplyHistory: _autoReplyHistory,
                  active: enabled,
                  terminal: widget.session.engine.terminal,
                  connected: widget.session.status == SessionStatus.connected,
                  theme: widget.theme,
                  fontSize: widget.fontSize,
                  agentTitle: () => widget.session.engine.title ?? '',
                  aiSettings: ref.watch(
                    appSettingsProvider.select((s) => s.ai),
                  ),
                  aiService: ref.watch(aiChatServiceProvider),
                  aiConsentStore: ref.watch(aiConsentStoreProvider),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class TerminalGuiView extends StatefulWidget {
  const TerminalGuiView({
    super.key,
    required this.terminal,
    required this.connected,
    required this.theme,
    required this.fontSize,
    this.active = true,
    this.agentTitle,
    this.aiSettings,
    this.aiService,
    this.aiConsentStore,
    this.autoReplyHistory,
  });

  final Terminal terminal;
  final bool connected;
  final TerminalTheme theme;
  final double fontSize;
  final bool active;
  final String Function()? agentTitle;
  final AiSettings? aiSettings;
  final AiChatService? aiService;
  final AiConsentStore? aiConsentStore;
  final TerminalAutoReplyHistory? autoReplyHistory;

  @override
  State<TerminalGuiView> createState() => _TerminalGuiViewState();
}

class _TerminalGuiViewState extends State<TerminalGuiView>
    with WidgetsBindingObserver {
  late TerminalGuiController _document;
  late TerminalInteractionController _interaction;
  late TerminalReplySuggestionController _suggestions;
  late AiDataConsent _aiConsent;
  late TerminalAutoReply _automatic;
  late AiConsentStore _consentStore;
  late List<TerminalGuiBlock> _blocks;
  TerminalGuiDocument? _projected;
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _replyInput = TextEditingController();
  String? _replyIdentity;
  final _inputFocus = FocusNode();
  var _follow = true;
  var _manualPause = false;
  var _hasSelection = false;
  String _selectedText = "";
  Offset? _linkPosition;
  var _visible = true;
  var _appActive = true;
  var _resumeScheduled = false;
  var _selectionEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
    _input.addListener(_draftChanged);
    _replyInput.addListener(_draftChanged);
    _consentStore = widget.aiConsentStore ?? AiConsentStore();
    _aiConsent = AiDataConsent(store: _consentStore);
    _inputFocus.onKeyEvent = _handleInputKey;
    _scroll.addListener(_scrolled);
    _scrollToLatest();
  }

  void _attach() {
    _replyInput.clear();
    _replyIdentity = null;
    _interaction = TerminalInteractionController(
      widget.terminal,
      title: () => widget.agentTitle?.call() ?? '',
    )..addListener(_interactionChanged);
    _replyIdentity = _interaction.prompt?.identity;
    _interaction.setEnabled(
      _visible && _appActive && widget.active && widget.connected,
    );
    _document = TerminalGuiController(widget.terminal)..addListener(_changed);
    _projected = _document.document;
    _blocks = terminalGuiBlocks(_document.document);
    _document.setEnabled(_visible);
    _suggestions = TerminalReplySuggestionController(
      widget.terminal,
      _interaction,
      draft: () => _interaction.captureCurrent()?.editing == true
          ? _replyInput.text
          : _input.text,
    )..addListener(_suggestionsChanged);
    _automatic = TerminalAutoReply(
      widget.terminal,
      history: widget.autoReplyHistory,
      title: () => widget.agentTitle?.call() ?? '',
      canSuggest: () =>
          !_suggestions.hasContent &&
          _input.text.isEmpty &&
          _replyInput.text.isEmpty &&
          !_composing,
      onReady: (current) async {
        final settings = widget.aiSettings;
        if (settings == null ||
            !await _consentStore.isApproved(
              AiConsentStore.destinationKey(settings),
            ) ||
            !current()) {
          return;
        }
        await _suggestions.request(
          (settings) =>
              _consentStore.isApproved(AiConsentStore.destinationKey(settings)),
          isCurrent: current,
        );
      },
    );
    _configureSuggestions();
  }

  void _suggestionsChanged() {
    if (mounted) setState(() {});
  }

  void _draftChanged() {
    _automatic.userInput();
    _suggestions.checkCurrent();
  }

  void _dismissSuggestions() {
    _automatic.dismiss();
    _suggestions.clear();
  }

  void _configureSuggestions() {
    _suggestions.configure(
      widget.aiSettings,
      widget.aiService,
      enabled: _visible && _appActive && widget.active && widget.connected,
    );
    _automatic.setEnabled(
      _visible &&
          _appActive &&
          widget.active &&
          widget.connected &&
          _suggestions.configured &&
          widget.aiSettings?.autoReplySuggestions == true,
    );
  }

  Future<void> _requestSuggestions() async {
    if (_suggestions.busy) {
      _dismissSuggestions();
      return;
    }
    await _suggestions.request(
      (settings) => _aiConsent.request(context, settings),
    );
  }

  Future<void> _applySuggestion(TerminalReplySuggestion suggestion) async {
    bool canSend() =>
        mounted &&
        widget.active &&
        widget.connected &&
        _visible &&
        _appActive &&
        !_composing &&
        !(_replyInput.value.composing.isValid &&
            !_replyInput.value.composing.isCollapsed);
    await _suggestions.apply(
      suggestion,
      canSend: canSend,
      sendConversation: (text) {
        _input.text = text;
        _send();
      },
      sendEditing: (prompt, text) async {
        _replyInput.text = text;
        final sent = await _interaction.sendText(prompt, text);
        if (sent && mounted) _replyInput.clear();
        return sent;
      },
    );
  }

  @override
  void didUpdateWidget(covariant TerminalGuiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      _automatic.dispose();
      _suggestions.dispose();
      _document.dispose();
      _interaction.dispose();
      _attach();
    }
    if (oldWidget.aiConsentStore != widget.aiConsentStore) {
      _consentStore = widget.aiConsentStore ?? AiConsentStore();
      _aiConsent = AiDataConsent(store: _consentStore);
    }
    _configureSuggestions();
    _interaction.setEnabled(
      _visible && _appActive && widget.active && widget.connected,
    );
    if (oldWidget.terminal != widget.terminal ||
        (!oldWidget.active && widget.active) ||
        (!oldWidget.connected && widget.connected)) {
      _latest();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden session tabs retain their reader/draft without projecting every frame.
    _visible = TickerMode.valuesOf(context).enabled;
    _configureSuggestions();
    _document.setEnabled(_visible);
    _interaction.setEnabled(
      _visible && _appActive && widget.active && widget.connected,
    );
    _resumeAtLatest();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _configureSuggestions();
    if (state == AppLifecycleState.resumed && widget.active && _visible) {
      _interaction.setEnabled(widget.connected);
      if (_document.paused) {
        _resumeAtLatest();
      } else {
        _document.refresh();
      }
      _interaction.refresh();
    } else if (state != AppLifecycleState.resumed) {
      _interaction.setEnabled(false);
    }
  }

  void _interactionChanged() {
    final prompt = _interaction.prompt;
    if (prompt != null && _replyIdentity != prompt.identity) {
      _replyInput.clear();
      _replyIdentity = prompt.identity;
    }
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_projected != _document.document) {
        _projected = _document.document;
        _blocks = terminalGuiBlocks(_document.document);
      }
    });
    if (_follow && !_document.paused) _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _follow && _scroll.hasClients && !_document.paused) {
        _scroll.jumpTo(0);
      }
    });
  }

  void _scrolled() {
    if (_scroll.position.userScrollDirection != ScrollDirection.idle &&
        _scroll.position.pixels > 48) {
      _follow = false;
      _document.pause();
    } else {
      _resumeAtLatest();
    }
  }

  void _selectionChanged(SelectedContent? selection) {
    _selectedText = selection?.plainText ?? "";
    _hasSelection = _selectedText.isNotEmpty;
    if (_hasSelection) {
      _follow = false;
      _document.pause();
    } else {
      _resumeAtLatest();
    }
  }

  bool get _canResumeAtLatest =>
      widget.active &&
      _visible &&
      !_manualPause &&
      !_hasSelection &&
      _document.paused &&
      _scroll.hasClients &&
      _scroll.position.pixels <= 12;

  void _resumeAtLatest() {
    if (_resumeScheduled || !_canResumeAtLatest) return;
    _resumeScheduled = true;
    // Selection and scroll callbacks can run while descendants are laying out.
    // Reconcile the document after that frame, keeping selected text stable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeScheduled = false;
      if (mounted && _canResumeAtLatest) _latest();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _latest() {
    setState(() {
      _follow = true;
      _manualPause = false;
      _hasSelection = false;
      _selectedText = '';
      _selectionEpoch++;
    });
    _document.resume();
    _scrollToLatest();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('복사했습니다.'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _linkMenu(Uri uri, Offset? position) async {
    final paused = _document.paused;
    final follow = _follow;
    _follow = false;
    _document.pause();
    await showTerminalGuiLinkMenu(context, uri, position: position);
    if (mounted && !paused && !_manualPause && !_hasSelection) {
      _follow = follow;
      _document.resume();
    }
  }

  bool get _composing =>
      _input.value.composing.isValid && !_input.value.composing.isCollapsed;

  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    if ((event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        HardwareKeyboard.instance.isAltPressed) {
      // Keep unrelated keys and Alt combinations on the normal editor path.
      return KeyEventResult.ignored;
    }
    if (_composing) {
      // Consume the confirming hardware Enter, so Android cannot redispatch
      // that same key as an editor Send action. Keep all visible text local.
      if (event is KeyDownEvent) _input.clearComposing();
      return event is KeyUpEvent
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (widget.connected) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        final value = _input.value;
        final selection = value.selection;
        final start = selection.isValid ? selection.start : value.text.length;
        final end = selection.isValid ? selection.end : value.text.length;
        _input.value = TextEditingValue(
          text: value.text.replaceRange(start, end, '\n'),
          selection: TextSelection.collapsed(offset: start + 1),
        );
      } else {
        _send();
      }
    }
    return KeyEventResult.handled;
  }

  void _send({bool commitComposition = false}) {
    _interaction.refresh();
    final value = _input.value;
    if (!widget.active ||
        !_visible ||
        !_appActive ||
        !widget.connected ||
        _interaction.prompt != null ||
        value.text.trim().isEmpty ||
        (_composing && !commitComposition)) {
      return;
    }
    if (commitComposition && _composing) _input.clearComposing();
    widget.terminal.paste(value.text);
    widget.terminal.keyInput(TerminalKey.enter);
    _input.clear();
    _latest();
    _inputFocus.requestFocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _document.dispose();
    _automatic.dispose();
    _suggestions.dispose();
    _interaction.dispose();
    _scroll.dispose();
    _input.dispose();
    _replyInput.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('terminal-gui-view'),
      color: VibeColors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text(
                    'GUI',
                    style: TextStyle(
                      color: VibeColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _document.paused ? '갱신 일시정지' : '실시간',
                    style: const TextStyle(fontSize: 11),
                  ),
                  TextButton.icon(
                    key: const ValueKey('terminal-gui-pause'),
                    onPressed: _document.paused
                        ? _latest
                        : () {
                            _manualPause = true;
                            _follow = false;
                            _document.pause();
                          },
                    icon: Icon(
                      _document.paused
                          ? Icons.vertical_align_bottom
                          : Icons.pause,
                      size: 16,
                    ),
                    label: Text(
                      _document.paused
                          ? (_document.pending ? '새 출력 · 최신으로' : '최신으로')
                          : '읽기 일시정지',
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('terminal-gui-refresh'),
                    tooltip: '현재 터미널 화면으로 새로고침',
                    onPressed: _latest,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                  IconButton(
                    key: const ValueKey('terminal-gui-copy-all'),
                    tooltip: '전체 출력 복사',
                    onPressed: _document.document.text.isEmpty
                        ? null
                        : () => unawaited(_copy(_document.document.text)),
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                  ),
                ],
              ),
            ),
            if (_document.document.truncated)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '최근 출력 일부를 표시합니다. 앞선 기록은 터미널 모드에서 확인하세요.',
                  style: TextStyle(
                    fontSize: 11,
                    color: VibeColors.onSurfaceDim,
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: SelectionArea(
                key: ValueKey('terminal-gui-selection-$_selectionEpoch'),
                contextMenuBuilder: (context, state) =>
                    terminalGuiSelectionToolbar(
                      context,
                      state.contextMenuAnchors,
                      state.contextMenuButtonItems,
                      selectedText: _selectedText,
                      hideToolbar: state.hideToolbar,
                    ),
                onSelectionChanged: _selectionChanged,
                child: Scrollbar(
                  controller: _scroll,
                  child: ListView.builder(
                    key: const PageStorageKey('terminal-gui-document-scroll'),
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    itemCount: _blocks.isEmpty ? 1 : _blocks.length,
                    itemBuilder: (context, index) => _blocks.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('아직 출력이 없습니다.'),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _block(
                              _blocks[_blocks.length - 1 - index],
                              _blocks.length - 1 - index,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            if (_interaction.prompt != null || _suggestions.hasContent)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.48,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_interaction.prompt case final prompt?)
                      Flexible(
                        child: TerminalInteractionCard(
                          key: ValueKey(prompt.identity),
                          controller: _interaction,
                          prompt: prompt,
                          input: _replyInput,
                        ),
                      ),
                    if (_suggestions.hasContent)
                      Flexible(
                        child: TerminalReplySuggestionPanel(
                          controller: _suggestions,
                          onClose: _dismissSuggestions,
                          onSelected: (suggestion) =>
                              unawaited(_applySuggestion(suggestion)),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TerminalNativeTextInput(
                      controller: _input,
                      focusNode: _inputFocus,
                      enabled:
                          widget.connected &&
                          widget.active &&
                          _visible &&
                          _appActive &&
                          _interaction.prompt == null,
                      child: TextField(
                        key: const ValueKey('terminal-gui-command'),
                        controller: _input,
                        focusNode: _inputFocus,
                        enabled:
                            widget.connected && _interaction.prompt == null,
                        minLines: 1,
                        maxLines: 4,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.send,
                        // Explicit Send commits the visible preedit, while a
                        // hardware Enter confirming Hangul stays local.
                        onEditingComplete: () {},
                        onSubmitted: (_) => _send(commitComposition: true),
                        contextMenuBuilder: (context, state) =>
                            terminalGuiSelectionToolbar(
                              context,
                              state.contextMenuAnchors,
                              state.contextMenuButtonItems,
                              selectedText: state.widget.controller.selection
                                  .textInside(state.widget.controller.text),
                              hideToolbar: state.hideToolbar,
                            ),
                        decoration: InputDecoration(
                          hintText: widget.connected
                              ? (_interaction.prompt != null
                                    ? '위 질문에 답변해 주세요.'
                                    : 'Enter로 전송 · Shift+Enter로 줄바꿈')
                              : '연결이 끊겼습니다.',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const ValueKey('terminal-gui-ai-suggest'),
                    tooltip: _suggestions.busy
                        ? '자동 응답 제안 · 생성 취소'
                        : !_suggestions.configured
                        ? '자동 응답 제안 · AI Chat 연결 설정이 필요합니다.'
                        : _interaction.prompt?.kind ==
                              TerminalInteractionKind.collapsed
                        ? '자동 응답 제안 · 먼저 선택지를 열어 주세요.'
                        : '자동 응답 제안',
                    onPressed: _suggestions.busy || _suggestions.canRequest
                        ? () => unawaited(_requestSuggestions())
                        : null,
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
                  IconButton(
                    key: const ValueKey('terminal-gui-interrupt'),
                    tooltip: '실행 중단 (Ctrl+C 전송)',
                    onPressed: widget.connected
                        ? () => widget.terminal.keyInput(
                            TerminalKey.keyC,
                            ctrl: true,
                          )
                        : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (context, value, _) => IconButton(
                      key: const ValueKey('terminal-gui-send'),
                      tooltip: '보내기',
                      onPressed:
                          widget.connected &&
                              _interaction.prompt == null &&
                              value.text.trim().isNotEmpty
                          ? () => _send(commitComposition: true)
                          : null,
                      icon: const Icon(
                        Icons.send_outlined,
                        color: VibeColors.accent,
                      ),
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

  Widget _block(TerminalGuiBlock block, int index) {
    final bodyStyle = TextStyle(
      color: VibeColors.onSurface,
      fontSize: widget.fontSize,
      height: 1.5,
    );
    if (block.kind == TerminalGuiBlockKind.markdown) {
      return Listener(
        onPointerDown: (event) => _linkPosition = event.position,
        child: MarkdownBody(
          data: block.text,
          onTapLink: (_, href, _) {
            final uri = terminalGuiWebUri(href ?? "");
            if (uri != null) {
              unawaited(_linkMenu(uri, _linkPosition));
            }
          },
          selectable: false,
          // CLI text must never cause an implicit network image request.
          imageBuilder: (uri, title, alt) => Text(alt ?? title ?? '[이미지]'),
          styleSheet: MarkdownStyleSheet(
            p: bodyStyle,
            listBullet: bodyStyle,
            h1: bodyStyle.copyWith(
              fontSize: widget.fontSize + 6,
              fontWeight: FontWeight.w700,
            ),
            h2: bodyStyle.copyWith(
              fontSize: widget.fontSize + 4,
              fontWeight: FontWeight.w700,
            ),
            h3: bodyStyle.copyWith(
              fontSize: widget.fontSize + 2,
              fontWeight: FontWeight.w700,
            ),
            code: bodyStyle.copyWith(
              fontFamily: kMonoFontFamily,
              backgroundColor: VibeColors.surfaceHigh,
            ),
          ),
        ),
      );
    }
    final rich = TerminalGuiLinkText(
      onLink: _linkMenu,
      spans: [
        for (final run in block.runs)
          TextSpan(text: run.text, style: _runStyle(run)),
      ],
      style: bodyStyle.copyWith(
        fontFamily: kMonoFontFamily,
        fontFamilyFallback: kMonoFontFallback,
      ),
    );
    if (block.kind != TerminalGuiBlockKind.code) return rich;
    return Container(
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    block.language.isEmpty ? '코드' : block.language,
                    style: const TextStyle(
                      fontSize: 11,
                      color: VibeColors.onSurfaceDim,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('terminal-gui-copy-code-$index'),
                  tooltip: '코드 복사',
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  onPressed: () => unawaited(_copy(block.text)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: rich,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _runStyle(TerminalGuiRun run) {
    var foreground = _color(run.foreground, VibeColors.onSurface);
    var background = _color(run.background, Colors.transparent);
    if (run.flags & CellFlags.inverse != 0) {
      final previous = foreground;
      foreground = _color(run.background, VibeColors.surface);
      background = previous;
    }
    return TextStyle(
      color: run.flags & CellFlags.faint != 0
          ? foreground.withValues(alpha: 0.65)
          : foreground,
      backgroundColor: background,
      fontWeight: run.flags & CellFlags.bold != 0 ? FontWeight.w700 : null,
      fontStyle: run.flags & CellFlags.italic != 0 ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (run.flags & CellFlags.underline != 0) TextDecoration.underline,
        if (run.flags & CellAttr.strikethrough != 0) TextDecoration.lineThrough,
      ]),
    );
  }

  Color _color(int value, Color fallback) {
    final type = value & CellColor.typeMask;
    final color = value & CellColor.valueMask;
    if (type == CellColor.normal) return fallback;
    if (type == CellColor.rgb) return Color(0xFF000000 | color);
    final palette = [
      widget.theme.black,
      widget.theme.red,
      widget.theme.green,
      widget.theme.yellow,
      widget.theme.blue,
      widget.theme.magenta,
      widget.theme.cyan,
      widget.theme.white,
      widget.theme.brightBlack,
      widget.theme.brightRed,
      widget.theme.brightGreen,
      widget.theme.brightYellow,
      widget.theme.brightBlue,
      widget.theme.brightMagenta,
      widget.theme.brightCyan,
      widget.theme.brightWhite,
    ];
    if (color < 16) return palette[color];
    if (color >= 232) {
      final shade = 8 + (color.clamp(232, 255) - 232) * 10;
      return Color.fromARGB(255, shade, shade, shade);
    }
    final cube = (color - 16).clamp(0, 215);
    const levels = [0, 95, 135, 175, 215, 255];
    return Color.fromARGB(
      255,
      levels[cube ~/ 36],
      levels[(cube ~/ 6) % 6],
      levels[cube % 6],
    );
  }
}
