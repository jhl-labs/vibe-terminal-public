import 'dart:async';

import 'package:flutter/material.dart';

class CommandPaletteEntry {
  const CommandPaletteEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.description,
    this.keywords = const [],
  });

  final String id;
  final String label;
  final String? description;
  final IconData icon;
  final List<String> keywords;
  final FutureOr<void> Function() onSelected;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return [
      label,
      description ?? '',
      ...keywords,
    ].join(' ').toLowerCase().contains(normalized);
  }
}

Future<void> showVibeCommandPalette(
  BuildContext context,
  List<CommandPaletteEntry> entries,
) async {
  final selected = await showDialog<CommandPaletteEntry>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _CommandPalette(entries: entries),
  );
  if (selected == null) return;
  await Future<void>.delayed(Duration.zero);
  await selected.onSelected();
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.entries});

  final List<CommandPaletteEntry> entries;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(CommandPaletteEntry entry) => Navigator.of(context).pop(entry);

  @override
  Widget build(BuildContext context) {
    final filtered = [
      for (final entry in widget.entries)
        if (entry.matches(_query)) entry,
    ];
    return Dialog(
      alignment: const Alignment(0, -0.62),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('command-palette-search'),
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '명령, 세션, Agent 검색…',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 18),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (filtered.isNotEmpty) _select(filtered.first);
              },
            ),
            const Divider(height: 1),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text('일치하는 명령이 없습니다.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return ListTile(
                      key: ValueKey('command-${entry.id}'),
                      leading: Icon(entry.icon),
                      title: Text(entry.label),
                      subtitle: entry.description == null
                          ? null
                          : Text(
                              entry.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => _select(entry),
                    );
                  },
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Text('Enter 실행  ·  Esc 닫기'),
                  Spacer(),
                  Text('Ctrl/Cmd+K'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
