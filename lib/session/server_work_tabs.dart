import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'session.dart';

/// 보관함은 SSH 세션이 아니라 기존 연결을 빌려 쓰는 작업 화면이다.
class ServerWorkTab {
  const ServerWorkTab({
    required this.hostId,
    required this.groupId,
    required this.connectionId,
  });

  final String hostId;
  final String groupId;
  final String connectionId;
  String get id => '$groupId/$hostId';

  SessionInfo? connection(List<SessionInfo> sessions) {
    final candidates = sessions.where(
      (s) => s.host.id == hostId && s.groupId == groupId,
    );
    final available = candidates.where(supports);
    return available.where((s) => s.id == connectionId).firstOrNull ??
        available.firstOrNull ??
        candidates.firstOrNull;
  }

  static bool supports(SessionInfo session) =>
      session.host.keepsRemoteSession &&
      session.status == SessionStatus.connected &&
      !session.fellBackToDirectSsh;
}

class ServerWorkTabsState {
  const ServerWorkTabsState({
    this.tabs = const [],
    this.activeId,
    this.busyIds = const {},
  });

  final List<ServerWorkTab> tabs;
  final String? activeId;
  final Set<String> busyIds;
}

class ServerWorkTabs extends Notifier<ServerWorkTabsState> {
  @override
  ServerWorkTabsState build() {
    ref.listen(sessionManagerProvider, (_, sessions) {
      // 마지막 연결을 닫으면 탭도 정리한다. 일시적인 재연결은 탭을 유지한다.
      final tabs = state.tabs
          .where(
            (tab) => sessions.any(
              (s) => s.host.id == tab.hostId && s.groupId == tab.groupId,
            ),
          )
          .toList();
      if (tabs.length == state.tabs.length) return;
      final ids = tabs.map((tab) => tab.id).toSet();
      state = ServerWorkTabsState(
        tabs: tabs,
        activeId: ids.contains(state.activeId) ? state.activeId : null,
        busyIds: state.busyIds.intersection(ids),
      );
    });
    ref.listen(sessionGroupProvider.select((s) => s.activeGroupId), (_, _) {
      showTerminal();
    });
    ref.listen(activeSessionIdProvider, (_, _) {
      // 여러 작업을 여는 동안에는 마지막 결과까지 보관함을 유지한다.
      if (!state.busyIds.contains(state.activeId)) showTerminal();
    });
    return const ServerWorkTabsState();
  }

  void open(SessionInfo connection) {
    if (!ServerWorkTab.supports(connection)) return;
    final tab = ServerWorkTab(
      hostId: connection.host.id,
      groupId: connection.groupId,
      connectionId: connection.id,
    );
    state = ServerWorkTabsState(
      tabs: [
        for (final existing in state.tabs)
          if (existing.id == tab.id) tab else existing,
        if (!state.tabs.any((existing) => existing.id == tab.id)) tab,
      ],
      activeId: tab.id,
      busyIds: state.busyIds,
    );
  }

  void select(String id) {
    if (!state.tabs.any((tab) => tab.id == id)) return;
    state = ServerWorkTabsState(
      tabs: state.tabs,
      activeId: id,
      busyIds: state.busyIds,
    );
  }

  void showTerminal() {
    if (state.activeId == null) return;
    state = ServerWorkTabsState(tabs: state.tabs, busyIds: state.busyIds);
  }

  void setBusy(String id, bool busy) {
    if (!state.tabs.any((tab) => tab.id == id)) return;
    state = ServerWorkTabsState(
      tabs: state.tabs,
      activeId: state.activeId,
      busyIds: {...state.busyIds}
        ..remove(id)
        ..addAll(busy ? [id] : []),
    );
  }

  void close(String id) {
    if (state.busyIds.contains(id)) return;
    state = ServerWorkTabsState(
      tabs: state.tabs.where((tab) => tab.id != id).toList(),
      activeId: state.activeId == id ? null : state.activeId,
      busyIds: state.busyIds,
    );
  }
}

final serverWorkTabsProvider =
    NotifierProvider<ServerWorkTabs, ServerWorkTabsState>(ServerWorkTabs.new);
