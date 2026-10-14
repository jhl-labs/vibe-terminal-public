import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../state/providers.dart';

class TerminalGuiModes extends Notifier<Set<String>> {
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

final terminalGuiModesProvider =
    NotifierProvider<TerminalGuiModes, Set<String>>(TerminalGuiModes.new);

class TerminalGuiModeButton extends ConsumerWidget {
  const TerminalGuiModeButton({
    super.key,
    required this.sessionId,
    this.onActivate,
    this.iconSize,
  });
  final String sessionId;
  final VoidCallback? onActivate;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      terminalGuiModesProvider.select((ids) => ids.contains(sessionId)),
    );
    final label = enabled ? '터미널 모드로 돌아가기' : 'GUI 문서 모드';
    return IconButton(
      key: ValueKey('terminal-gui-toggle-$sessionId'),
      tooltip: label,
      iconSize: iconSize,
      color: enabled ? VibeColors.accent : null,
      icon: Icon(enabled ? Icons.terminal : Icons.article_outlined),
      onPressed: () {
        onActivate?.call();
        ref.read(terminalGuiModesProvider.notifier).toggle(sessionId);
      },
    );
  }
}
