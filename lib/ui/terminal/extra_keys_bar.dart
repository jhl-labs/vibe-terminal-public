import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../clipboard/clipboard_image.dart';
import '../../clipboard/image_paste.dart';
import '../../app/theme.dart';
import '../../session/session.dart';
import '../../state/providers.dart';
import 'action_bar_catalog.dart';

/// 모바일 보조 키보드 바. 특수키 + Ctrl sticky 모디파이어.
class ExtraKeysBar extends ConsumerStatefulWidget {
  const ExtraKeysBar({super.key, required this.session});
  final SessionInfo session;

  @override
  ConsumerState<ExtraKeysBar> createState() => _ExtraKeysBarState();
}

class _ExtraKeysBarState extends ConsumerState<ExtraKeysBar> {
  Terminal get _terminal => widget.session.engine.terminal;

  void _send(String text) {
    if (ref.read(ctrlStickyProvider) && text.length == 1) {
      // Ctrl+문자: 제어바이트(0x01~0x1A)로 변환. 예: 'a' → 0x01.
      final c = text.toLowerCase().codeUnitAt(0);
      if (c >= 0x61 && c <= 0x7a) {
        _terminal.textInput(String.fromCharCode(c - 0x60));
      } else {
        _terminal.textInput(text);
      }
      ref.read(ctrlStickyProvider.notifier).clear(); // sticky: 적용 후 해제
    } else {
      _terminal.textInput(text);
    }
  }

  void _sendKey(TerminalKey key) => _terminal.keyInput(key);

  /// Ctrl+문자 제어바이트를 직접 보낸다(sticky와 무관). 예: 'c' → 0x03.
  void _sendCtrl(String letter) {
    final c = letter.toLowerCase().codeUnitAt(0);
    _terminal.textInput(String.fromCharCode(c - 0x60));
  }

  /// 보조키바 항목 토큰을 실행한다. `text:` 사용자 정의 키는 문자열을 그대로
  /// 보내고, 그 외는 id에 맞는 동작을 수행한다.
  void _invokeItem(String token) {
    final custom = textTokenValue(token);
    if (custom != null) {
      _send(custom);
      return;
    }
    switch (token) {
      case 'paste':
        unawaited(_pasteClipboard());
      case 'image':
        unawaited(_pasteImage());
      case 'esc':
        _sendKey(TerminalKey.escape);
      case 'tab':
        _sendKey(TerminalKey.tab);
      case 'ctrl':
        ref.read(ctrlStickyProvider.notifier).toggle();
      case 'left':
        _sendKey(TerminalKey.arrowLeft);
      case 'down':
        _sendKey(TerminalKey.arrowDown);
      case 'up':
        _sendKey(TerminalKey.arrowUp);
      case 'right':
        _sendKey(TerminalKey.arrowRight);
      case 'enter':
        _sendKey(TerminalKey.enter);
      case 'slash':
        _send('/');
      case 'minus':
        _send('-');
      case 'pipe':
        _send('|');
      case 'tilde':
        _send('~');
      case 'star':
        _send('*');
      case 'home':
        _sendKey(TerminalKey.home);
      case 'end':
        _sendKey(TerminalKey.end);
      case 'pageUp':
        _sendKey(TerminalKey.pageUp);
      case 'pageDown':
        _sendKey(TerminalKey.pageDown);
      case 'ctrlC':
        _sendCtrl('c');
      case 'ctrlD':
        _sendCtrl('d');
      case 'ctrlL':
        _sendCtrl('l');
      case 'ctrlZ':
        _sendCtrl('z');
    }
  }

  /// 키보드가 떠 있으면 내리고, 아니면 활성 터미널에 포커스를 요청해 띄운다.
  void _toggleKeyboard() {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      ref.read(keyboardFocusRequestProvider.notifier).request();
    }
  }

  Future<void> _pasteClipboard() async {
    // 클립보드에 이미지가 있으면 텍스트 대신 업로드 흐름으로 전환한다.
    ClipboardImage? image;
    try {
      image = await readClipboardImage();
    } catch (_) {
      image = null;
    }
    if (!mounted) return;
    if (image != null) {
      await handleImagePaste(
        context: context,
        ref: ref,
        session: widget.session,
        image: image,
        sendText: _send,
        showSnack: _showSnack,
      );
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final settings = ref.read(appSettingsProvider);
    if (settings.confirmMultilinePaste &&
        (text.contains('\n') || text.contains('\r'))) {
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
      if (confirmed != true) return;
    }
    _terminal.paste(text);
  }

  /// 클립보드 이미지를 원격(/tmp) 또는 로컬 임시 디렉토리에 올리고, 그 경로를
  /// 터미널에 입력한다. claude/codex CLI 등에서 경로로 이미지를 참조할 수 있다.
  Future<void> _pasteImage() async {
    ClipboardImage? image;
    try {
      image = await readClipboardImage();
    } catch (_) {
      image = null;
    }
    if (!mounted) return;
    // 명시적 image 버튼: 클립보드에 이미지가 없으면 안내 메시지를 표시한다.
    if (image == null) {
      _showSnack('클립보드에 이미지가 없습니다');
      return;
    }
    await handleImagePaste(
      context: context,
      ref: ref,
      session: widget.session,
      image: image,
      sendText: _send,
      showSnack: _showSnack,
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 활성(토글 ON)은 accent로 채워 어두운 비활성 버튼과 확실히 구분한다.
    Widget btn(String label, VoidCallback onTap, {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(46, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: active
                ? VibeColors.accent
                : VibeColors.surfaceHigh,
            foregroundColor: active
                ? VibeColors.onAccent
                : VibeColors.onSurface,
            textStyle: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
            side: BorderSide(
              color: active ? VibeColors.accent : VibeColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );
    }

    final ctrlActive = ref.watch(ctrlStickyProvider);
    final items = ref.watch(
      appSettingsProvider.select((s) => s.extraKeysBarItems),
    );
    // 키보드가 떠 있는지로 토글 방향을 결정한다(떠 있으면 내림, 아니면 올림).
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    // 보조키바 공통 아이콘 버튼 스타일.
    ButtonStyle iconStyle() => IconButton.styleFrom(
      minimumSize: const Size(46, 38),
      backgroundColor: VibeColors.surfaceHigh,
      foregroundColor: VibeColors.onSurface,
      side: const BorderSide(color: VibeColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );

    Widget iconBtn(String tooltip, IconData icon, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            style: iconStyle(),
          ),
        );

    // 토큰 하나를 버튼 위젯으로. 알 수 없는 토큰은 null로 건너뛴다.
    Widget? itemWidget(String token) {
      final def = resolveExtraKeyToken(token);
      if (def == null) return null;
      final active = token == 'ctrl' && ctrlActive;
      void onTap() => _invokeItem(token);
      final text = def.buttonText;
      if (text != null) return btn(text, onTap, active: active);
      return iconBtn(def.label, def.icon ?? Icons.help_outline, onTap);
    }

    return Container(
      decoration: const BoxDecoration(
        color: VibeColors.surface,
        border: Border(top: BorderSide(color: VibeColors.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 키보드 토글은 보조키바 맨 첫칸으로 고정한다.
            iconBtn(
              keyboardVisible ? '키보드 숨기기' : '키보드 표시',
              keyboardVisible ? Icons.keyboard_hide : Icons.keyboard,
              _toggleKeyboard,
            ),
            for (final token in items) ?itemWidget(token),
          ],
        ),
      ),
    );
  }
}
