import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../../../app/theme.dart';
import 'terminal_gui_links.dart';
import '../terminal_native_text_input.dart';
import '../../../terminal/gui/terminal_interaction.dart';
import '../../../terminal/gui/terminal_interaction_controller.dart';

class TerminalInteractionCard extends StatefulWidget {
  const TerminalInteractionCard({
    super.key,
    required this.controller,
    required this.prompt,
    required this.input,
  });
  final TerminalInteractionController controller;
  final TerminalInteraction prompt;
  final TextEditingController input;
  @override
  State<TerminalInteractionCard> createState() =>
      _TerminalInteractionCardState();
}

class _TerminalInteractionCardState extends State<TerminalInteractionCard> {
  TextEditingController get _text => widget.input;
  final _focus = FocusNode();
  bool get _composing =>
      _text.value.composing.isValid && !_text.value.composing.isCollapsed;
  bool get _enabled => !widget.controller.busy;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (_, event) {
      if ((event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
          _composing ||
          HardwareKeyboard.instance.isAltPressed) {
        return KeyEventResult.ignored;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (HardwareKeyboard.instance.isShiftPressed) {
        final value = _text.value;
        final start = value.selection.isValid
            ? value.selection.start
            : value.text.length;
        final end = value.selection.isValid
            ? value.selection.end
            : value.text.length;
        _text.value = TextEditingValue(
          text: value.text.replaceRange(start, end, '\n'),
          selection: TextSelection.collapsed(offset: start + 1),
        );
      } else {
        unawaited(_send());
      }
      return KeyEventResult.handled;
    };
  }

  Future<void> _send() async {
    if (!_enabled || _composing) return;
    final sent = await widget.controller.sendText(widget.prompt, _text.text);
    if (mounted && sent) _text.clear();
  }

  void _key(TerminalKey key, {bool shift = false, bool ctrl = false}) =>
      unawaited(
        widget.controller.key(widget.prompt, key, shift: shift, ctrl: ctrl),
      );
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.prompt;
    return Material(
      key: const ValueKey('terminal-interaction-card'),
      color: VibeColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.touch_app_outlined,
                  size: 18,
                  color: VibeColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${prompt.agent == 'claude'
                        ? 'Claude'
                        : prompt.agent == 'codex'
                        ? 'Codex'
                        : 'OpenCode'} · 응답 대기',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (widget.controller.busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              prompt.question,
              contextMenuBuilder: (context, state) =>
                  terminalGuiSelectionToolbar(
                    context,
                    state.contextMenuAnchors,
                    state.contextMenuButtonItems,
                    selectedText: state.widget.controller.selection.textInside(
                      state.widget.controller.text,
                    ),
                    hideToolbar: state.hideToolbar,
                  ),
            ),
            if (prompt.multiple)
              const Text('여러 항목을 선택할 수 있습니다.', style: TextStyle(fontSize: 12)),
            if (prompt.kind == TerminalInteractionKind.collapsed)
              FilledButton.icon(
                key: const ValueKey('terminal-interaction-open'),
                onPressed: _enabled
                    ? () => unawaited(widget.controller.openQuestion(prompt))
                    : null,
                icon: const Icon(Icons.question_answer_outlined),
                label: const Text('선택지 보기'),
              ),
            for (var i = 0; i < prompt.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton(
                  key: ValueKey('terminal-interaction-option-$i'),
                  onPressed:
                      _enabled &&
                          (!prompt.editing ||
                              prompt.agent == 'claude' ||
                              prompt.isCodexAsync) &&
                          (!prompt.horizontal || prompt.selected >= 0)
                      ? () => unawaited(widget.controller.choose(prompt, i))
                      : null,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        prompt.multiple
                            ? (prompt.options[i].checked
                                  ? Icons.check_box_outlined
                                  : Icons.check_box_outline_blank)
                            : (prompt.options[i].selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(prompt.options[i].label)),
                    ],
                  ),
                ),
              ),
            if (prompt.canAddNotes && !prompt.editing)
              TextButton.icon(
                onPressed: _enabled ? () => _key(TerminalKey.tab) : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('선택한 답변에 메시지 추가'),
              ),
            if (prompt.editing) ...[
              const SizedBox(height: 8),
              TerminalNativeTextInput(
                controller: _text,
                focusNode: _focus,
                enabled: _enabled,
                child: TextField(
                  key: const ValueKey('terminal-interaction-message'),
                  controller: _text,
                  focusNode: _focus,
                  enabled: _enabled,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                  onEditingComplete: () {},
                  onSubmitted: (_) => unawaited(_send()),
                  contextMenuBuilder: (context, state) =>
                      terminalGuiSelectionToolbar(
                        context,
                        state.contextMenuAnchors,
                        state.contextMenuButtonItems,
                        selectedText: state.widget.controller.selection
                            .textInside(state.widget.controller.text),
                        hideToolbar: state.hideToolbar,
                      ),
                  decoration: const InputDecoration(
                    labelText: '직접 답변 입력',
                    hintText: 'Enter로 전송 · Shift+Enter로 줄바꿈',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (context, value, _) => FilledButton.icon(
                  key: const ValueKey('terminal-interaction-send'),
                  onPressed:
                      _enabled && value.text.trim().isNotEmpty && !_composing
                      ? () => unawaited(_send())
                      : null,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    prompt.agent == 'claude' && prompt.multiple
                        ? '답변 적용 후 선택 계속'
                        : '답변 보내기',
                  ),
                ),
              ),
            ],
            if (prompt.kind != TerminalInteractionKind.collapsed)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (!prompt.editing ||
                      prompt.agent == 'claude' ||
                      prompt.isCodexAsync && prompt.options.isNotEmpty) ...[
                    IconButton(
                      tooltip: '이전 항목',
                      onPressed: _enabled
                          ? () => _key(
                              prompt.horizontal
                                  ? TerminalKey.arrowLeft
                                  : TerminalKey.arrowUp,
                            )
                          : null,
                      icon: Icon(
                        prompt.horizontal
                            ? Icons.chevron_left
                            : Icons.keyboard_arrow_up,
                      ),
                    ),
                    IconButton(
                      tooltip: '다음 항목',
                      onPressed: _enabled
                          ? () => _key(
                              prompt.horizontal
                                  ? TerminalKey.arrowRight
                                  : TerminalKey.arrowDown,
                            )
                          : null,
                      icon: Icon(
                        prompt.horizontal
                            ? Icons.chevron_right
                            : Icons.keyboard_arrow_down,
                      ),
                    ),
                    if (!prompt.editing || prompt.agent == 'claude')
                      TextButton(
                        onPressed: _enabled
                            ? () => _key(TerminalKey.enter)
                            : null,
                        child: Text(
                          prompt.kind == TerminalInteractionKind.review
                              ? '전체 답변 제출'
                              : prompt.multiple && prompt.agent == 'opencode'
                              ? '현재 항목 선택'
                              : '선택 확인',
                        ),
                      ),
                  ],
                  if (prompt.canNavigateQuestions &&
                      !(prompt.agent == 'opencode' && prompt.editing)) ...[
                    if (prompt.canNavigatePrevious)
                      TextButton(
                        onPressed: _enabled
                            ? () => _key(
                                prompt.isCodexAsync
                                    ? TerminalKey.arrowRight
                                    : prompt.agent == 'claude'
                                    ? TerminalKey.tab
                                    : prompt.agent == 'codex' && prompt.editing
                                    ? TerminalKey.keyP
                                    : TerminalKey.arrowLeft,
                                ctrl:
                                    prompt.agent == 'codex' &&
                                    prompt.editing &&
                                    !prompt.isCodexAsync,
                                shift:
                                    prompt.agent == 'claude' ||
                                    prompt.isCodexAsync,
                              )
                            : null,
                        child: const Text('이전 질문'),
                      ),
                    if (prompt.canNavigateNext)
                      TextButton(
                        onPressed: _enabled
                            ? () => _key(
                                prompt.isCodexAsync
                                    ? TerminalKey.arrowLeft
                                    : prompt.agent == 'claude'
                                    ? TerminalKey.tab
                                    : prompt.agent == 'codex' && prompt.editing
                                    ? TerminalKey.keyN
                                    : TerminalKey.arrowRight,
                                ctrl:
                                    prompt.agent == 'codex' &&
                                    prompt.editing &&
                                    !prompt.isCodexAsync,
                                shift: prompt.isCodexAsync,
                              )
                            : null,
                        child: const Text('다음 질문'),
                      ),
                  ],
                  if (prompt.isCodexAsync && !prompt.canNavigatePrevious)
                    TextButton(
                      onPressed: _enabled
                          ? () => _key(TerminalKey.arrowRight, shift: true)
                          : null,
                      child: const Text('질문 접기'),
                    ),
                  if (!prompt.isCodexAsync)
                    TextButton(
                      onPressed: _enabled
                          ? () => _key(TerminalKey.escape)
                          : null,
                      child: const Text('취소 (Esc)'),
                    ),
                ],
              ),
            if (widget.controller.error != null)
              Text(
                widget.controller.error!,
                style: const TextStyle(color: VibeColors.onSurfaceDim),
              ),
          ],
        ),
      ),
    );
  }
}
