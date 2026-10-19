import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/providers.dart';
import 'gui/terminal_gui_mode.dart';

/// Explicit opt-in for clicks sent to the terminal, independent of keyboard IME.
class TerminalTouchModes extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.listen(sessionManagerProvider, (_, sessions) {
      final ids = sessions.map((session) => session.id).toSet();
      if (state.any((id) => !ids.contains(id))) {
        state = state.intersection(ids);
      }
    });
    return const {};
  }

  void toggle(String sessionId) {
    state = state.contains(sessionId)
        ? (Set<String>.of(state)..remove(sessionId))
        : {...state, sessionId};
  }
}

final terminalTouchModesProvider =
    NotifierProvider<TerminalTouchModes, Set<String>>(TerminalTouchModes.new);

class TerminalTouchModeButton extends ConsumerWidget {
  const TerminalTouchModeButton({
    super.key,
    required this.sessionId,
    this.enabled = true,
    this.onActivate,
    this.iconSize,
  });

  final String sessionId;
  final bool enabled;
  final VoidCallback? onActivate;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      terminalTouchModesProvider.select((ids) => ids.contains(sessionId)),
    );
    final gui = ref.watch(
      terminalGuiModesProvider.select((ids) => ids.contains(sessionId)),
    );
    return IconButton(
      key: ValueKey('terminal-touch-toggle-$sessionId'),
      tooltip: gui
          ? '터치 제어는 터미널 모드에서 사용'
          : selected
          ? '터치 제어 끄기'
          : '터치 제어 켜기',
      isSelected: selected && !gui,
      color: selected && !gui ? VibeColors.accent : null,
      iconSize: iconSize,
      icon: const Icon(Icons.touch_app_outlined),
      selectedIcon: const Icon(Icons.touch_app),
      onPressed: !enabled || gui
          ? null
          : () {
              onActivate?.call();
              ref.read(terminalTouchModesProvider.notifier).toggle(sessionId);
            },
    );
  }
}
