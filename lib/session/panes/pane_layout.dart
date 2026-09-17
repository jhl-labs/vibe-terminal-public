/// Layout data and transformations deliberately have no Flutter or I/O dependency.
enum PaneAxis { leftRight, topBottom }

enum PanePreset {
  single,
  columns,
  rows,
  leftLarge,
  rightLarge,
  topLarge,
  bottomLarge,
  grid,
}

sealed class PaneNode {
  const PaneNode(this.id);
  final String id;
  Iterable<PaneLeaf> get leaves;
  Map<String, Object?> toJson();
}

class PaneLeaf extends PaneNode {
  const PaneLeaf(super.id, [this.sessionId]);
  final String? sessionId;
  @override
  Iterable<PaneLeaf> get leaves => [this];
  @override
  Map<String, Object?> toJson() => {'id': id, 'session': sessionId};
}

class PaneSplit extends PaneNode {
  const PaneSplit(
    super.id,
    this.axis,
    this.first,
    this.second, {
    this.ratio = .5,
    this.link,
  });
  final PaneAxis axis;
  final PaneNode first;
  final PaneNode second;
  final double ratio;
  final String? link;
  @override
  Iterable<PaneLeaf> get leaves => [...first.leaves, ...second.leaves];
  PaneSplit copy({
    PaneNode? first,
    PaneNode? second,
    double? ratio,
    bool unlink = false,
  }) => PaneSplit(
    id,
    axis,
    first ?? this.first,
    second ?? this.second,
    ratio: ratio ?? this.ratio,
    link: unlink ? null : link,
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'axis': axis.name,
    'ratio': ratio,
    'link': link,
    'first': first.toJson(),
    'second': second.toJson(),
  };
}

class SessionPaneLayout {
  const SessionPaneLayout({
    this.root = const PaneLeaf('p0'),
    this.focusedPaneId = 'p0',
  });
  final PaneNode root;
  final String focusedPaneId;
  List<PaneLeaf> get panes {
    final positions = <(PaneLeaf, double, double)>[];
    void walk(PaneNode node, double x, double y, double w, double h) {
      if (node is PaneLeaf) {
        positions.add((node, x, y));
        return;
      }
      final split = node as PaneSplit;
      if (split.axis == PaneAxis.leftRight) {
        walk(split.first, x, y, w * split.ratio, h);
        walk(split.second, x + w * split.ratio, y, w * (1 - split.ratio), h);
      } else {
        walk(split.first, x, y, w, h * split.ratio);
        walk(split.second, x, y + h * split.ratio, w, h * (1 - split.ratio));
      }
    }

    walk(root, 0, 0, 1, 1);
    positions.sort((a, b) {
      final row = a.$3.compareTo(b.$3);
      return row == 0 ? a.$2.compareTo(b.$2) : row;
    });
    return positions.map((p) => p.$1).toList();
  }

  int get count => panes.length;
  List<String> get slots =>
      panes.map((p) => p.sessionId).whereType<String>().toList();
  PaneLeaf get focused =>
      panes.firstWhere((p) => p.id == focusedPaneId, orElse: () => panes.first);
  PaneLeaf? pane(String id) {
    for (final p in panes) {
      if (p.id == id) return p;
    }
    return null;
  }

  PaneLeaf? paneForSession(String id) {
    for (final p in panes) {
      if (p.sessionId == id) return p;
    }
    return null;
  }

  SessionPaneLayout focus(String id) => pane(id) == null || focusedPaneId == id
      ? this
      : SessionPaneLayout(root: root, focusedPaneId: id);
  SessionPaneLayout selectSession(String id) {
    final existing = paneForSession(id);
    return existing == null ? assign(focused.id, id) : focus(existing.id);
  }

  SessionPaneLayout assign(String paneId, String? sessionId) {
    if (pane(paneId) == null) return this;
    if (sessionId != null && paneForSession(sessionId) != null) {
      return focus(paneForSession(sessionId)!.id);
    }
    return SessionPaneLayout(
      root: _map(root, (n) => n.id == paneId ? PaneLeaf(paneId, sessionId) : n),
      focusedPaneId: paneId,
    );
  }

  /// Only explicit removals prune references; a partially restored session list does not.
  SessionPaneLayout forgetSessions(Set<String> ids) => SessionPaneLayout(
    root: _map(
      root,
      (n) => n is PaneLeaf && ids.contains(n.sessionId) ? PaneLeaf(n.id) : n,
    ),
    focusedPaneId: focusedPaneId,
  );

  String _nextId(String prefix) {
    final ids = <String>{};
    void visit(PaneNode n) {
      ids.add(n.id);
      if (n is PaneSplit) {
        visit(n.first);
        visit(n.second);
      }
    }

    visit(root);
    var i = 0;
    while (ids.contains('$prefix$i')) {
      i++;
    }
    return '$prefix$i';
  }

  SessionPaneLayout split(
    String paneId,
    PaneAxis axis, {
    String? sessionId,
    bool before = false,
  }) {
    final leaf = pane(paneId);
    if (leaf == null ||
        count >= 4 ||
        (sessionId != null && paneForSession(sessionId) != null)) {
      return this;
    }
    final added = PaneLeaf(_nextId('p'), sessionId);
    final node = PaneSplit(
      _nextId('s'),
      axis,
      before ? added : leaf,
      before ? leaf : added,
    );
    return SessionPaneLayout(
      root: _map(root, (n) => n.id == paneId ? node : n),
      focusedPaneId: added.id,
    );
  }

  SessionPaneLayout remove(String id) {
    if (pane(id) == null) return this;
    PaneNode? prune(PaneNode node) {
      if (node.id == id) return null;
      if (node is! PaneSplit) return node;
      final a = prune(node.first), b = prune(node.second);
      if (a == null) return b;
      if (b == null) return a;
      return node.copy(first: a, second: b, unlink: true);
    }

    final next = prune(root) ?? PaneLeaf(id);
    return SessionPaneLayout(
      root: next,
      focusedPaneId: next.leaves.any((p) => p.id == focusedPaneId)
          ? focusedPaneId
          : next.leaves.first.id,
    );
  }

  SessionPaneLayout swap(String from, String to) {
    final a = pane(from), b = pane(to);
    if (a == null || b == null || from == to) return this;
    return SessionPaneLayout(
      root: _map(
        root,
        (n) => n.id == from
            ? PaneLeaf(from, b.sessionId)
            : n.id == to
            ? PaneLeaf(to, a.sessionId)
            : n,
      ),
      focusedPaneId: to,
    );
  }

  SessionPaneLayout moveSession(
    String sessionId,
    String target, {
    PaneAxis? edge,
    bool before = false,
  }) {
    final source = paneForSession(sessionId);
    if (pane(target) == null || source?.id == target) return this;
    if (edge == null) {
      return source == null
          ? assign(target, sessionId)
          : swap(source.id, target);
    }
    final base = source == null ? this : remove(source.id);
    return base.split(target, edge, sessionId: sessionId, before: before);
  }

  SessionPaneLayout resize(
    String splitId,
    double ratio, {
    bool unlink = false,
  }) {
    if (!ratio.isFinite) return this;
    String? link;
    _map(root, (n) {
      if (n is PaneSplit && n.id == splitId) link = n.link;
      return n;
    });
    return SessionPaneLayout(
      root: _map(
        root,
        (n) =>
            n is PaneSplit &&
                (n.id == splitId || (link != null && n.link == link))
            ? n.copy(
                ratio: n.id == splitId || !unlink
                    ? ratio.clamp(.01, .99)
                    : n.ratio,
                unlink: unlink,
              )
            : n,
      ),
      focusedPaneId: focusedPaneId,
    );
  }

  SessionPaneLayout preset(PanePreset preset, List<String> available) {
    final active = this.focused.sessionId;
    final ordered = <String>{
      ...slots.where(available.contains),
      ...available,
    }.toList();
    final size = switch (preset) {
      PanePreset.single => 1,
      PanePreset.columns || PanePreset.rows => 2,
      PanePreset.grid => 4,
      _ => 3,
    };
    final ids = ordered.take(size).toList();
    if (active != null && available.contains(active)) {
      if (!ids.contains(active)) {
        if (ids.length == size) ids.removeLast();
        ids.add(active);
      }
      if (preset != PanePreset.columns &&
          preset != PanePreset.rows &&
          preset != PanePreset.grid) {
        ids.remove(active);
        ids.insert(0, active);
      }
    }
    PaneLeaf leaf(int index) =>
        PaneLeaf('p$index', index < ids.length ? ids[index] : null);
    final a = leaf(0), b = leaf(1), c = leaf(2), d = leaf(3);
    final node = switch (preset) {
      PanePreset.single => a,
      PanePreset.columns => PaneSplit('s0', PaneAxis.leftRight, a, b),
      PanePreset.rows => PaneSplit('s0', PaneAxis.topBottom, a, b),
      PanePreset.leftLarge => PaneSplit(
        's0',
        PaneAxis.leftRight,
        a,
        PaneSplit('s1', PaneAxis.topBottom, b, c),
        ratio: .6,
      ),
      PanePreset.rightLarge => PaneSplit(
        's0',
        PaneAxis.leftRight,
        PaneSplit('s1', PaneAxis.topBottom, b, c),
        a,
        ratio: .4,
      ),
      PanePreset.topLarge => PaneSplit(
        's0',
        PaneAxis.topBottom,
        a,
        PaneSplit('s1', PaneAxis.leftRight, b, c),
        ratio: .6,
      ),
      PanePreset.bottomLarge => PaneSplit(
        's0',
        PaneAxis.topBottom,
        PaneSplit('s1', PaneAxis.leftRight, b, c),
        a,
        ratio: .4,
      ),
      PanePreset.grid => PaneSplit(
        's0',
        PaneAxis.leftRight,
        PaneSplit('s1', PaneAxis.topBottom, a, c, link: 'grid'),
        PaneSplit('s2', PaneAxis.topBottom, b, d, link: 'grid'),
      ),
    };
    final focused =
        node.leaves
            .where((p) => active != null && p.sessionId == active)
            .firstOrNull ??
        node.leaves.first;
    return SessionPaneLayout(root: node, focusedPaneId: focused.id);
  }

  Map<String, Object?> toJson() => {
    'root': root.toJson(),
    'focus': focusedPaneId,
  };
  static SessionPaneLayout fromJson(Object? value) {
    if (value is! Map) return const SessionPaneLayout();
    if (!value.containsKey('root')) return _legacy(value);
    final seen = <String>{}, sessions = <String>{};
    var leafCount = 0;
    PaneNode parse(Object? raw, int depth) {
      if (depth > 3) throw const FormatException('분할 깊이 초과');
      if (raw is! Map ||
          raw['id'] is! String ||
          (raw['id'] as String).isEmpty ||
          !seen.add(raw['id'] as String)) {
        throw const FormatException('분할 ID 오류');
      }
      final id = raw['id'] as String;
      if (raw.containsKey('axis')) {
        final axis = PaneAxis.values
            .where((v) => v.name == raw['axis'])
            .firstOrNull;
        if (axis == null) throw const FormatException('분할 방향 오류');
        final ratio = raw['ratio'];
        return PaneSplit(
          id,
          axis,
          parse(raw['first'], depth + 1),
          parse(raw['second'], depth + 1),
          ratio: ratio is num && ratio.isFinite
              ? ratio.toDouble().clamp(.01, .99)
              : .5,
          link: raw['link'] is String ? raw['link'] as String : null,
        );
      }
      if (++leafCount > 4) throw const FormatException('최대 4칸');
      final session = raw['session'];
      return PaneLeaf(
        id,
        session is String && session.isNotEmpty && sessions.add(session)
            ? session
            : null,
      );
    }

    try {
      var root = parse(value['root'], 0);
      // Only the aligned grid representation can carry linked dividers.
      final aligned =
          root is PaneSplit &&
          root.axis == PaneAxis.leftRight &&
          root.first is PaneSplit &&
          root.second is PaneSplit &&
          (root.first as PaneSplit).axis == PaneAxis.topBottom &&
          (root.second as PaneSplit).axis == PaneAxis.topBottom &&
          (root.first as PaneSplit).link != null &&
          (root.first as PaneSplit).link == (root.second as PaneSplit).link &&
          (root.first as PaneSplit).ratio == (root.second as PaneSplit).ratio;
      if (!aligned) {
        root = _map(root, (n) => n is PaneSplit ? n.copy(unlink: true) : n);
      }
      final focus = value['focus'];
      return SessionPaneLayout(
        root: root,
        focusedPaneId: root.leaves.any((p) => p.id == focus)
            ? focus as String
            : root.leaves.first.id,
      );
    } on FormatException {
      return const SessionPaneLayout();
    }
  }

  static SessionPaneLayout _legacy(Map value) {
    final count = [1, 2, 4].contains(value['count'])
        ? value['count'] as int
        : 1;
    final ids = value['slots'] is List
        ? (value['slots'] as List)
              .whereType<String>()
              .toSet()
              .take(count)
              .toList()
        : <String>[];
    var next = const SessionPaneLayout().preset(
      count == 4
          ? PanePreset.grid
          : count == 2
          ? PanePreset.columns
          : PanePreset.single,
      ids,
    );
    double ratio(Object? v) =>
        v is num && v.isFinite ? v.toDouble().clamp(.2, .8) : .5;
    next = next.resize('s0', ratio(value['horizontal']));
    if (count == 4) next = next.resize('s1', ratio(value['vertical']));
    final focus = value['focus'] is int
        ? (value['focus'] as int).clamp(0, count - 1)
        : 0;
    return next.focus('p$focus');
  }
}

PaneNode _map(PaneNode node, PaneNode Function(PaneNode) transform) {
  final mapped = node is PaneSplit
      ? node.copy(
          first: _map(node.first, transform),
          second: _map(node.second, transform),
        )
      : node;
  return transform(mapped);
}
