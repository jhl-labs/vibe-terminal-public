import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../settings/terminal_input_bindings.dart';

/// Android keys belong to one foreground terminal, including with the IME hidden.
class TerminalPhysicalKeyScope extends StatefulWidget {
  const TerminalPhysicalKeyScope({
    super.key,
    required this.enabled,
    required this.focusNode,
    required this.bindings,
    required this.onBinding,
    required this.child,
  });
  final bool enabled;
  final FocusNode focusNode;
  final TerminalInputBindings bindings;
  final void Function(TerminalInputBinding) onBinding;
  final Widget child;

  @override
  State<TerminalPhysicalKeyScope> createState() =>
      _TerminalPhysicalKeyScopeState();
}

class _TerminalPhysicalKeyScopeState extends State<TerminalPhysicalKeyScope>
    with WidgetsBindingObserver {
  bool _visible = true;
  bool _resumed = true;
  bool get eligible {
    final focus = FocusManager.instance.primaryFocus;
    return mounted &&
        widget.enabled &&
        _visible &&
        _resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        (widget.focusNode.hasFocus || focus == null || focus is FocusScopeNode);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
    FocusManager.instance.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(TerminalPhysicalKeyScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (eligible &&
        (widget.bindings.interceptVolume(true) ||
            widget.bindings.interceptVolume(false))) {
      _PhysicalKeyBridge.instance.attach(this);
    } else {
      _PhysicalKeyBridge.instance.detach(this);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_sync);
    _PhysicalKeyBridge.instance.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PhysicalKeyBridge {
  _PhysicalKeyBridge() {
    _channel.setMethodCallHandler(_receive);
  }
  static final instance = _PhysicalKeyBridge();
  static const _channel = MethodChannel('vibe_terminal/physical_keys');
  _TerminalPhysicalKeyScopeState? _owner;
  TerminalInputBindings? _bindings;
  int _token = 0;
  final _pending = <bool, Timer>{};

  void _cancel() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
  }

  void attach(_TerminalPhysicalKeyScopeState owner) {
    if (identical(_owner, owner) &&
        identical(_bindings, owner.widget.bindings)) {
      return;
    }
    _cancel();
    _owner = owner;
    _bindings = owner.widget.bindings;
    _token++;
    unawaited(
      _invoke('configure', {
        'token': _token,
        'up': _bindings!.interceptVolume(true),
        'down': _bindings!.interceptVolume(false),
      }),
    );
  }

  void detach(_TerminalPhysicalKeyScopeState owner) {
    if (!identical(_owner, owner)) return;
    _cancel();
    _owner = null;
    _bindings = null;
    _token++;
    unawaited(
      _invoke('configure', {'token': null, 'up': false, 'down': false}),
    );
  }

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      /* An older runner keeps system key behavior. */
    } on PlatformException {
      /* No input is sent if the native bridge is unavailable. */
    }
  }

  Future<void> _receive(MethodCall call) async {
    if (call.method == 'ready') {
      final owner = _owner;
      if (owner != null && owner.eligible) {
        _bindings = null;
        attach(owner);
      }
      return;
    }
    final args = call.arguments;
    final owner = _owner;
    if (args is! Map || owner == null || args['token'] != _token) return;
    if (call.method == 'cancel') {
      _cancel();
      return;
    }
    if (!owner.eligible || call.method != 'press' || args['up'] is! bool) {
      return;
    }
    final up = args['up'] as bool;
    final bindings = _bindings!;
    final token = _token;
    final single = bindings.forTrigger(
      up
          ? TerminalInputTrigger.volumeUpSingle
          : TerminalInputTrigger.volumeDownSingle,
    );
    final double = bindings.forTrigger(
      up
          ? TerminalInputTrigger.volumeUpDouble
          : TerminalInputTrigger.volumeDownDouble,
    );
    void apply(TerminalInputBinding binding) {
      if (_token != token || !identical(owner, _owner) || !owner.eligible) {
        return;
      }
      if (binding.action == TerminalInputAction.defaultBehavior) {
        unawaited(_invoke('systemVolume', {'token': token, 'up': up}));
      } else {
        owner.widget.onBinding(binding);
      }
    }

    if (double.action == TerminalInputAction.none) {
      apply(single);
      return;
    }
    final previous = _pending.remove(up);
    if (previous != null && previous.isActive) {
      previous.cancel();
      apply(double);
      return;
    }
    _pending[up] = Timer(
      Duration(milliseconds: bindings.doublePressMilliseconds),
      () {
        _pending.remove(up);
        apply(single);
      },
    );
  }
}
