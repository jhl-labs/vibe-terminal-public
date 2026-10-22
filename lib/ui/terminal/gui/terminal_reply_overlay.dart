import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../../ai/ai_chat_service.dart';
import '../../../ai/terminal_reply_suggestions.dart';
import '../../../settings/app_settings.dart';
import '../../../terminal/gui/terminal_interaction.dart';
import '../../../terminal/gui/terminal_auto_reply.dart';
import '../../../terminal/gui/terminal_interaction_controller.dart';
import '../../../terminal/gui/terminal_recap_controller.dart';
import '../../../terminal/gui/terminal_reply_suggestion_controller.dart';
import '../../shell/ai_data_consent.dart';
import 'terminal_recap_puppy.dart';
import 'terminal_reply_suggestion_panel.dart';

/// Screen monitoring while closed is opt-in and debounced.
///
/// AI가 설정되어 있으면 우측 하단에 퍼피 ReCap 버튼도 함께 띄운다. 답변 제안
/// 카드와 같은 자리를 쓰므로 카드가 열려 있는 동안에는 퍼피를 숨긴다.
class TerminalReplyOverlay extends StatefulWidget {
  const TerminalReplyOverlay({
    super.key,
    required this.terminal,
    required this.connected,
    required this.active,
    required this.child,
    this.agentTitle,
    this.aiSettings,
    this.aiService,
    this.aiConsentStore,
    this.inputActivity,
    this.autoReplyHistory,
    this.recapInputs,
    this.onOpened,
    this.onClosed,
  });

  final Terminal terminal;
  final bool connected;
  final bool active;
  final Widget child;
  final String Function()? agentTitle;
  final AiSettings? aiSettings;
  final AiChatService? aiService;
  final AiConsentStore? aiConsentStore;
  final Listenable? inputActivity;
  final TerminalAutoReplyHistory? autoReplyHistory;

  /// 퍼피 ReCap에 보낼 세션 사용자 입력. 없으면 화면 출력만 요약한다.
  final TerminalRecapInputLoader? recapInputs;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  @override
  State<TerminalReplyOverlay> createState() => _TerminalReplyOverlayState();
}

class _TerminalReplyOverlayState extends State<TerminalReplyOverlay>
    with WidgetsBindingObserver {
  TerminalInteractionController? _interaction;
  TerminalReplySuggestionController? _suggestions;
  late AiDataConsent _consent;
  bool _visible = true;
  bool _appActive = true;
  bool _applying = false;
  bool _automaticCard = false;
  bool _inputPrepared = false;
  final _overlayFocus = FocusNode();

  /// 터미널과 오버레이 전체를 감싸는 포커스 노드. 스스로 포커스를 받지 않고,
  /// 포커스가 이 안(터미널·카드·퍼피)에 있는지 확인하는 데만 쓴다.
  final _subtreeFocus = FocusNode(
    debugLabel: 'TerminalReplyOverlay',
    canRequestFocus: false,
    skipTraversal: true,
  );
  late TerminalAutoReply _automatic;
  bool Function()? _autoCurrent;
  late AiConsentStore _consentStore;
  late TerminalRecapController _recap;

  bool get _available =>
      widget.active && widget.connected && _visible && _appActive;
  bool get _configured =>
      widget.aiSettings?.isConfigured == true && widget.aiService != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _consentStore = widget.aiConsentStore ?? AiConsentStore();
    _consent = AiDataConsent(store: _consentStore);
    _attachAutomatic();
    _attachRecap();
    widget.inputActivity?.addListener(_localInput);
    HardwareKeyboard.instance.addHandler(_hardwareInput);
  }

  void _attachRecap() {
    _recap = TerminalRecapController(
      widget.terminal,
      // 최신 widget의 loader를 읽어 콜백이 바뀌어도 controller를 유지한다.
      loadInputs: () => widget.recapInputs?.call() ?? Future.value(const []),
    )..configure(widget.aiSettings, widget.aiService);
  }

  void _attachAutomatic() {
    _automatic = TerminalAutoReply(
      widget.terminal,
      history: widget.autoReplyHistory,
      title: () => widget.agentTitle?.call() ?? '',
      // 사용자가 ReCap 말풍선을 읽는 동안에는 자동 카드로 덮지 않는다.
      canSuggest: () => _available && _suggestions == null && !_recap.open,
      onReady: (current) async {
        final settings = widget.aiSettings;
        if (settings == null ||
            !await _consentStore.isApproved(
              AiConsentStore.destinationKey(settings),
            ) ||
            !current()) {
          return;
        }
        await _open(automatic: true, current: current);
      },
    );
  }

  void _configureAutomatic() => _automatic.setEnabled(
    _available &&
        _configured &&
        widget.aiSettings?.autoReplySuggestions == true,
  );

  /// 전역 키 처리기가 이 터미널의 키로 볼지. 다른 칸·입력란에 포커스가
  /// 있거나 위에 모달(동의 창 등)이 떠 있으면 그 키는 이 터미널 것이 아니다.
  /// 아무것도 포커스를 갖지 않을 때(포커스 범위 자체만 있을 때)는 받을 곳이
  /// 이 터미널뿐이므로 이 터미널 키로 본다.
  bool get _ownsKeyboard {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final primary = FocusManager.instance.primaryFocus;
    return primary == null ||
        primary is FocusScopeNode ||
        _subtreeFocus.hasFocus;
  }

  bool _hardwareInput(KeyEvent event) {
    if (!_available || event is KeyUpEvent || !_ownsKeyboard) return false;
    if (_recap.open && event.logicalKey == LogicalKeyboardKey.escape) {
      // 말풍선을 닫는 Escape는 터미널로 보내지 않는다.
      _recap.dismiss();
      return true;
    }
    if (_overlayFocus.hasFocus) return false;
    final escape =
        _automaticCard && event.logicalKey == LogicalKeyboardKey.escape;
    _localInput();
    return escape;
  }

  void _localInput() {
    if (_applying) return;
    _automatic.userInput();
    if (_automaticCard && _suggestions != null) _close(restoreFocus: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    if (!_available) {
      _detach();
      _recap.dismiss();
    }
    _configureAutomatic();
  }

  @override
  void didUpdateWidget(covariant TerminalReplyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiConsentStore != widget.aiConsentStore) {
      _consentStore = widget.aiConsentStore ?? AiConsentStore();
      _consent = AiDataConsent(store: _consentStore);
    }
    if (oldWidget.inputActivity != widget.inputActivity) {
      oldWidget.inputActivity?.removeListener(_localInput);
      widget.inputActivity?.addListener(_localInput);
    }
    if (oldWidget.terminal != widget.terminal ||
        oldWidget.autoReplyHistory != widget.autoReplyHistory) {
      _automatic.dispose();
      _attachAutomatic();
    }
    if (oldWidget.terminal != widget.terminal) {
      // 다른 세션의 터미널로 바뀌면 이전 요약 요청과 응답을 버린다.
      _recap.dispose();
      _attachRecap();
    } else {
      _recap.configure(widget.aiSettings, widget.aiService);
    }
    if (!_available) _recap.dismiss();
    if (!_available ||
        oldWidget.terminal != widget.terminal ||
        oldWidget.aiSettings != widget.aiSettings ||
        oldWidget.aiService != widget.aiService) {
      _detach();
    }
    _configureAutomatic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      _detach();
      _recap.dismiss();
    }
    _configureAutomatic();
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_automaticCard &&
        !_applying &&
        _suggestions?.hasContent == false &&
        _interaction?.prompt?.kind != TerminalInteractionKind.collapsed) {
      scheduleMicrotask(() {
        if (mounted &&
            _automaticCard &&
            !_applying &&
            _suggestions?.hasContent == false) {
          _close(restoreFocus: false);
        }
      });
    }
  }

  void _detach() {
    _suggestions?.removeListener(_changed);
    _suggestions?.dispose();
    _suggestions = null;
    _interaction?.removeListener(_changed);
    _interaction?.dispose();
    _interaction = null;
    _applying = false;
    _automaticCard = false;
    _inputPrepared = false;
    _autoCurrent = null;
  }

  void _close({bool restoreFocus = true}) {
    if (_suggestions == null) return;
    final prepared = _inputPrepared;
    _automatic.dismiss();
    setState(_detach);
    if (restoreFocus && prepared) widget.onClosed?.call();
  }

  Future<void> _open({bool automatic = false, bool Function()? current}) async {
    if (!_available || !_configured || _suggestions != null) return;
    if (automatic && _recap.open) return;
    // 답변 제안 카드가 퍼피 자리를 덮으므로 ReCap 말풍선을 먼저 닫는다.
    _recap.dismiss();
    if (!automatic) widget.onOpened?.call();
    if (!mounted || !_available) return;
    final interaction = TerminalInteractionController(
      widget.terminal,
      title: () => widget.agentTitle?.call() ?? '',
    )..addListener(_changed);
    final suggestions = TerminalReplySuggestionController(
      widget.terminal,
      interaction,
      draft: () => '',
    )..addListener(_changed);
    suggestions.configure(widget.aiSettings, widget.aiService, enabled: true);
    setState(() {
      _automaticCard = automatic;
      _inputPrepared = !automatic;
      _autoCurrent = current;
      _interaction = interaction;
      _suggestions = suggestions;
    });
    if (interaction.prompt?.kind != TerminalInteractionKind.collapsed) {
      await _request(suggestions);
    }
  }

  Future<void> _request(TerminalReplySuggestionController controller) async {
    await controller.request(
      (settings) => _automaticCard
          ? _consentStore.isApproved(AiConsentStore.destinationKey(settings))
          : _consent.request(context, settings),
      isCurrent: _autoCurrent,
    );
  }

  Future<void> _apply(TerminalReplySuggestion suggestion) async {
    final controller = _suggestions;
    if (controller == null || _applying || !_available) return;
    setState(() => _applying = true);
    if (_automaticCard) {
      _inputPrepared = true;
      widget.onOpened?.call();
    }
    final sent = await controller.apply(
      suggestion,
      canSend: () =>
          mounted && _available && identical(_suggestions, controller),
      sendConversation: (text) {
        widget.terminal.paste(text);
        widget.terminal.keyInput(TerminalKey.enter);
      },
    );
    if (!mounted || !identical(_suggestions, controller)) return;
    if (sent) {
      _close();
    } else {
      setState(() => _applying = false);
    }
  }

  Future<void> _openQuestion() async {
    final interaction = _interaction;
    final controller = _suggestions;
    final prompt = interaction?.prompt;
    if (interaction == null || controller == null || prompt == null) return;
    if (_automaticCard) {
      // Opening the hidden question is an explicit action. Its redraw replaces
      // the collapsed snapshot, so subsequent generation uses the new question.
      _automaticCard = false;
      _autoCurrent = null;
      _inputPrepared = true;
      widget.onOpened?.call();
    }
    if (await interaction.openQuestion(prompt) &&
        mounted &&
        _available &&
        identical(_suggestions, controller)) {
      await _request(controller);
    }
  }

  Future<void> _requestRecap() async {
    if (!_available || !_configured || _suggestions != null) return;
    await _recap.request((settings) => _consent.request(context, settings));
  }

  void _terminalPointerDown(PointerDownEvent _) {
    if (_suggestions != null) _close(restoreFocus: false);
    _recap.dismiss();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_hardwareInput);
    widget.inputActivity?.removeListener(_localInput);
    _automatic.dispose();
    _detach();
    _recap.dispose();
    _overlayFocus.dispose();
    _subtreeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _subtreeFocus,
    child: LayoutBuilder(builder: _buildLayers),
  );

  Widget _buildLayers(BuildContext context, BoxConstraints constraints) {
    final controller = _suggestions;
    final interaction = _interaction;
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          // 터미널을 누르면 제안 카드·ReCap 말풍선을 닫고 입력은 그대로 넘긴다.
          onPointerDown: _terminalPointerDown,
          child: widget.child,
        ),
        if (_available && controller == null)
          Positioned(
            right: 12,
            top: 12,
            child: Tooltip(
              message: _configured
                  ? 'AI 답변 제안'
                  : 'AI 답변 제안 · AI Chat 연결 설정이 필요합니다.',
              child: FilledButton.tonalIcon(
                key: const ValueKey('terminal-ai-suggest'),
                onPressed: _configured ? () => unawaited(_open()) : null,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('AI'),
              ),
            ),
          ),
        // 작은 화면에서 말풍선이 상단 AI 버튼과 겹쳐도 위에 그려지도록 뒤에 둔다.
        if (_available && _configured && controller == null)
          Positioned(
            right: 8,
            bottom: 8,
            child: TerminalRecapPuppy(
              controller: _recap,
              onRequest: () => unawaited(_requestRecap()),
              onDismiss: _recap.dismiss,
              maxBubbleWidth: math.max(
                0,
                math.min(340, constraints.maxWidth - 16),
              ),
              maxBubbleHeight: math.max(0, constraints.maxHeight - 16),
            ),
          ),
        if (_available && controller != null && interaction != null)
          Positioned(
            right: 12,
            bottom: 12,
            width: math.max(0, math.min(480, constraints.maxWidth - 24)),
            child: Focus(
              focusNode: _overlayFocus,
              autofocus: !_automaticCard,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _close();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Material(
                key: const ValueKey('terminal-reply-overlay'),
                elevation: 12,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(
                      0,
                      math.min(400, constraints.maxHeight - 24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome_outlined, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                controller.busy
                                    ? '답변 제안 생성 중…'
                                    : _applying
                                    ? '답변 전송 중…'
                                    : 'AI 답변 제안',
                              ),
                            ),
                            IconButton(
                              tooltip: '제안 닫기',
                              onPressed: _close,
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                      if (_applying) const LinearProgressIndicator(),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TerminalReplySuggestionPanel(
                                controller: controller,
                                showHeader: false,
                                onSelected: (suggestion) =>
                                    unawaited(_apply(suggestion)),
                              ),
                              if (interaction.error case final error?)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(error),
                                ),
                              if (!controller.busy && !_applying)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    8,
                                  ),
                                  child:
                                      interaction.prompt?.kind ==
                                          TerminalInteractionKind.collapsed
                                      ? TextButton(
                                          onPressed: interaction.busy
                                              ? null
                                              : () =>
                                                    unawaited(_openQuestion()),
                                          child: const Text('선택지 열고 제안 받기'),
                                        )
                                      : TextButton(
                                          onPressed: controller.canRequest
                                              ? () => unawaited(
                                                  _request(controller),
                                                )
                                              : null,
                                          child: const Text('현재 화면으로 다시 제안 받기'),
                                        ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
