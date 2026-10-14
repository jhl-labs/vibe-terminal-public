import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/server_work_tabs.dart';
import '../../state/providers.dart';
import 'remote_session_manager_panel.dart';

/// 터미널과 보관함을 같은 작업 영역에서 전환하되 숨긴 화면도 유지한다.
class ServerWorkTabDeck extends ConsumerWidget {
  const ServerWorkTabDeck({super.key, required this.terminal});

  final Widget terminal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serverWorkTabsProvider);
    final sessions = ref.watch(sessionManagerProvider);
    final group = ref.watch(sessionGroupProvider).activeGroupId;
    final controller = ref.read(serverWorkTabsProvider.notifier);
    final activeId =
        state.tabs.any(
          (tab) => tab.id == state.activeId && tab.groupId == group,
        )
        ? state.activeId
        : null;

    Widget page(bool visible, Widget child) => Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: ExcludeFocus(excluding: !visible, child: child),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        page(activeId == null, terminal),
        for (final tab in state.tabs)
          if (tab.connection(sessions) case final connection?)
            KeyedSubtree(
              key: ValueKey('server-work-page-${tab.id}'),
              child: page(
                activeId == tab.id,
                RemoteSessionManagerPanel(
                  connection: connection,
                  onClose: () => controller.close(tab.id),
                  onActivated: () {
                    if (ref.read(serverWorkTabsProvider).activeId == tab.id) {
                      controller.showTerminal();
                    }
                  },
                  onBusyChanged: (busy) => controller.setBusy(tab.id, busy),
                ),
              ),
            ),
      ],
    );
  }
}
