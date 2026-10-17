import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Receives physical character keys only after Android/Flutter text input has
/// declined them. Normal IME edits and editing/navigation keys keep their path.
class TerminalNativeTextInput extends StatefulWidget {
  const TerminalNativeTextInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.child,
    this.canInsert,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final Widget child;

  /// Optional policy checked against the latest editing value at delivery time.
  /// A terminal can restrict fallback to fully committed input; a normal editor
  /// can accept it at any non-composing selection.
  final bool Function(TextEditingValue value)? canInsert;

  @override
  State<TerminalNativeTextInput> createState() =>
      _TerminalNativeTextInputState();
}

class _TerminalNativeTextInputState extends State<TerminalNativeTextInput>
    with WidgetsBindingObserver {
  bool _visible = true;
  bool _resumed = true;

  bool get _ownsInput =>
      mounted &&
      widget.enabled &&
      _visible &&
      _resumed &&
      widget.focusNode.hasPrimaryFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    widget.focusNode.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(TerminalNativeTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.focusNode != widget.focusNode) {
      _AndroidTextInputBridge.instance.detach(this);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_sync);
      widget.focusNode.addListener(_sync);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_ownsInput) {
      _AndroidTextInputBridge.instance.attach(this);
    } else {
      _AndroidTextInputBridge.instance.detach(this);
    }
  }

  void insert(String text) {
    if (!_ownsInput ||
        text.length != 1 ||
        text.codeUnitAt(0) < 0x20 ||
        text.codeUnitAt(0) > 0x7e) {
      return;
    }
    final value = widget.controller.value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    if (widget.canInsert?.call(value) == false) return;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    widget.controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_sync);
    _AndroidTextInputBridge.instance.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AndroidTextInputBridge {
  _AndroidTextInputBridge._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'unhandledCharacter') return;
      final args = call.arguments;
      if (args is! Map || args['token'] != _token) return;
      final text = args['text'];
      if (text is String) _active?.insert(text);
    });
  }

  static final instance = _AndroidTextInputBridge._();
  // Keep the established Android channel name shared with the GUI editor.
  static const _channel = MethodChannel('vibe_terminal/gui_text_input');
  _TerminalNativeTextInputState? _active;
  int _token = 0;

  void attach(_TerminalNativeTextInputState client) {
    if (identical(_active, client)) return;
    _active = client;
    unawaited(_activate(++_token));
  }

  void detach(_TerminalNativeTextInputState client) {
    if (!identical(_active, client)) return;
    _active = null;
    unawaited(_activate(null));
  }

  Future<void> _activate(int? token) async {
    try {
      await _channel.invokeMethod<void>('activate', token);
    } on MissingPluginException {
      // Desktop and Android runners without this bridge retain normal editing.
    } on PlatformException {
      // Optional compatibility path; do not interrupt the standard IME client.
    }
  }
}
