import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'panes/pane_layout.dart';
import 'panes/pane_layout_repository.dart';
export 'panes/pane_layout.dart';

final paneLayoutRepositoryProvider = Provider<PaneLayoutRepository>(
  (ref) => JsonPaneLayoutRepository(),
);

class SessionPaneStorageError extends Notifier<String?> {
  @override
  String? build() => null;
  void report(String? message) => state = message;
}

final sessionPaneStorageErrorProvider =
    NotifierProvider<SessionPaneStorageError, String?>(
      SessionPaneStorageError.new,
    );

/// Serializes durable edits; gesture previews and zoom belong to the view.
class SessionPaneLayouts extends Notifier<Map<String, SessionPaneLayout>> {
  final _edited = <String>{};
  final _history = <String, List<SessionPaneLayout>>{};
  Future<void> _pendingWrite = Future.value();
  late Future<void> _initialLoad;
  bool _loaded = false;
  int _revision = 0;
  @override
  Map<String, SessionPaneLayout> build() {
    _initialLoad = Future.microtask(_load);
    return const {};
  }

  Future<void> get ready => _initialLoad;
  Future<void> get pendingWrite => _pendingWrite;
  Future<void> _load() async {
    try {
      final decoded = await ref.read(paneLayoutRepositoryProvider).load();
      if (!ref.mounted) return;
      state = {
        ...decoded,
        for (final id in _edited)
          if (state[id] != null) id: state[id]!,
      };
      _loaded = true;
      ref.read(sessionPaneStorageErrorProvider.notifier).report(null);
      if (_edited.isNotEmpty) _save();
    } catch (error) {
      if (ref.mounted) {
        ref
            .read(sessionPaneStorageErrorProvider.notifier)
            .report('터미널 배치 복구 실패: $error');
      }
    }
  }

  bool canUndo(String group) => _history[group]?.isNotEmpty ?? false;
  void undo(String group, Set<String> available) {
    if (!canUndo(group)) return;
    final old = _history[group]!.removeLast();
    setLayout(
      group,
      old.forgetSessions(
        old.slots.where((id) => !available.contains(id)).toSet(),
      ),
    );
  }

  void setLayout(
    String group,
    SessionPaneLayout layout, {
    bool recordHistory = false,
  }) {
    final previous = state[group] ?? const SessionPaneLayout();
    if (state.containsKey(group) &&
        jsonEncode(previous.toJson()) == jsonEncode(layout.toJson())) {
      return;
    }
    if (recordHistory) {
      final history = _history.putIfAbsent(group, () => []);
      history.add(previous);
      if (history.length > 20) history.removeAt(0);
    }
    _edited.add(group);
    state = {...state, group: layout};
    if (_loaded) _save();
  }

  void retrySave() {
    if (!_loaded) {
      unawaited(_load());
    } else {
      _save();
    }
  }

  void _save() {
    final revision = ++_revision;
    final snapshot = state;
    final repository = ref.read(paneLayoutRepositoryProvider);
    _pendingWrite = _pendingWrite.then((_) async {
      if (revision != _revision) return;
      try {
        await repository.save(snapshot);
        if (ref.mounted && revision == _revision) {
          ref.read(sessionPaneStorageErrorProvider.notifier).report(null);
        }
      } catch (error) {
        if (ref.mounted && revision == _revision) {
          ref
              .read(sessionPaneStorageErrorProvider.notifier)
              .report('터미널 배치 저장 실패: $error');
        }
      }
    });
  }
}

final sessionPaneLayoutsProvider =
    NotifierProvider<SessionPaneLayouts, Map<String, SessionPaneLayout>>(
      SessionPaneLayouts.new,
    );
