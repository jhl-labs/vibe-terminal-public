import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../ai/ai_chat_service.dart';
import '../../ai/secret_masker.dart';
import '../../ai/terminal_reply_suggestions.dart';
import '../../settings/app_settings.dart';
import 'terminal_gui_document.dart';
import 'terminal_interaction.dart';
import 'terminal_interaction_controller.dart';

class TerminalReplySuggestionSnapshot {
  const TerminalReplySuggestionSnapshot(this.prompt, this.context, this.draft);
  final TerminalInteraction? prompt;
  final String context;
  final String draft;
  String get key =>
      '${prompt == null ? 'screen:$context' : 'prompt:${prompt!.revision}'}\u0000$draft';
}

/// Session-local request state; neither generation nor background output sends input.
class TerminalReplySuggestionController extends ChangeNotifier {
  TerminalReplySuggestionController(
    this.terminal,
    this.interaction, {
    required this.draft,
  }) {
    terminal.addListener(checkCurrent);
    interaction.addListener(checkCurrent);
  }
  final Terminal terminal;
  final TerminalInteractionController interaction;
  final String Function() draft;
  AiSettings? _settings;
  AiChatService? _service;
  bool _enabled = false;
  bool _disposed = false;
  bool busy = false;
  String? error;
  List<TerminalReplySuggestion> items = const [];
  AiCancelToken? _cancel;
  Timer? _timer;
  int _generation = 0;
  bool _submitting = false;
  TerminalReplySuggestionSnapshot? _snapshot;
  bool get hasContent => busy || error != null || items.isNotEmpty;
  bool get configured => _settings?.isConfigured == true && _service != null;
  bool get canRequest =>
      _enabled &&
      configured &&
      !_submitting &&
      !interaction.busy &&
      interaction.captureCurrent()?.kind != TerminalInteractionKind.collapsed;

  void configure(
    AiSettings? settings,
    AiChatService? service, {
    required bool enabled,
  }) {
    if (!identical(settings, _settings) ||
        !identical(service, _service) ||
        enabled != _enabled) {
      clear();
    }
    _settings = settings;
    _service = service;
    _enabled = enabled;
  }

  TerminalReplySuggestionSnapshot _capture() => TerminalReplySuggestionSnapshot(
    interaction.captureCurrent(),
    TerminalGuiDocument.capture(
      terminal,
      maxLines: (_settings?.maxContextLines ?? 50).clamp(50, 500),
      maxCharacters: 12000,
    ).text,
    draft(),
  );

  String _currentKey() {
    final prompt = interaction.captureCurrent();
    final context = prompt == null
        ? TerminalGuiDocument.capture(
            terminal,
            maxLines: (_settings?.maxContextLines ?? 50).clamp(50, 500),
            maxCharacters: 12000,
          ).text
        : prompt.revision;
    return '${prompt == null ? 'screen' : 'prompt'}:$context\u0000${draft()}';
  }

  void checkCurrent() {
    if (_disposed || _snapshot == null || !hasContent) return;
    _timer ??= Timer(const Duration(milliseconds: 80), () {
      _timer = null;
      if (_snapshot != null && _snapshot!.key != _currentKey()) {
        clear();
      }
    });
  }

  Future<void> request(
    Future<bool> Function(AiSettings) consent, {
    bool Function()? isCurrent,
  }) async {
    if (!canRequest || busy) return;
    clear();
    final generation = _generation;
    final settings = _settings!;
    final service = _service!;
    busy = true;
    notifyListeners();
    bool valid() => !_disposed && _enabled && generation == _generation;
    try {
      if (!await consent(settings) || !valid()) return;
      if (!canRequest || isCurrent?.call() == false) return;
      final snapshot = _capture();
      _snapshot = snapshot;
      final token = _cancel = AiCancelToken();
      final result = await token.run(
        () => TerminalReplySuggestionService(service).generate(
          settings: settings,
          context: snapshot.context,
          draft: snapshot.draft,
          prompt: snapshot.prompt,
          cancelToken: token,
        ),
      );
      if (valid() &&
          isCurrent?.call() != false &&
          snapshot.key == _currentKey()) {
        items = result;
      }
    } on AiChatCancelledException {
      // Explicit cancellation and stale generations leave no failure message.
    } catch (e) {
      if (valid()) {
        error = maskTerminalSecrets(
          e is AiChatException ? e.message : '답변 제안을 가져오지 못했습니다. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (valid()) {
        busy = false;
        _cancel = null;
        notifyListeners();
      }
    }
  }

  TerminalReplySuggestionSnapshot? take(TerminalReplySuggestion suggestion) {
    if (_disposed || busy || !items.contains(suggestion)) return null;
    if (!_enabled || interaction.busy || _snapshot?.key != _currentKey()) {
      clear();
      return null;
    }
    final snapshot = _snapshot;
    clear();
    return snapshot;
  }

  /// Both terminal presentations share the same stale-reply and CLI guards.
  Future<bool> apply(
    TerminalReplySuggestion suggestion, {
    required bool Function() canSend,
    required void Function(String) sendConversation,
    Future<bool> Function(TerminalInteraction, String)? sendEditing,
  }) async {
    if (_submitting || !canSend()) return false;
    final snapshot = take(suggestion);
    if (snapshot == null) return false;
    final generation = _generation;
    bool valid() =>
        !_disposed && _enabled && generation == _generation && canSend();
    _submitting = true;
    notifyListeners();
    try {
      interaction.refresh();
      var prompt = interaction.prompt;
      if (suggestion.optionNumber != null && prompt != null) {
        final index = prompt.options.indexWhere(
          (o) => o.number == suggestion.optionNumber,
        );
        if (index < 0) return false;
        final custom = prompt.options[index].custom;
        final identity = prompt.identity;
        if (!await interaction.choose(prompt, index, submit: !custom) ||
            !valid()) {
          return false;
        }
        if (!custom) return true;
        prompt = interaction.prompt;
        if (prompt == null || prompt.identity != identity) return false;
        if (!prompt.editing && prompt.canAddNotes) {
          if (!await interaction.key(prompt, TerminalKey.tab) || !valid()) {
            return false;
          }
          prompt = interaction.prompt;
          if (prompt == null || prompt.identity != identity) return false;
        }
      }
      if (!valid() ||
          (snapshot.prompt != null &&
              prompt?.identity != snapshot.prompt!.identity)) {
        return false;
      }
      if (prompt != null && prompt.editing) {
        return await (sendEditing ?? interaction.sendText)(
          prompt,
          suggestion.text,
        );
      }
      if (prompt == null) {
        sendConversation(suggestion.text);
        return true;
      }
      return false;
    } finally {
      _submitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void clear() {
    _generation++;
    _cancel?.cancel();
    _cancel = null;
    _timer?.cancel();
    _timer = null;
    _snapshot = null;
    final changed = hasContent;
    busy = false;
    items = const [];
    error = null;
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    terminal.removeListener(checkCurrent);
    interaction.removeListener(checkCurrent);
    super.dispose();
  }
}
