import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/providers.dart';
import '../terminal/action_bar_catalog.dart';

/// 보조키바·터미널 헤더 표시 항목을 드래그로 선택·정렬하는 편집 화면.
class ActionBarEditorPage extends ConsumerWidget {
  const ActionBarEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: VibeColors.bg,
        appBar: AppBar(
          title: const Text('버튼 바 편집'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '보조키바'),
              Tab(text: '상단 헤더'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BarEditor(
              items: settings.extraKeysBarItems,
              catalog: kExtraKeysCatalog,
              resolve: resolveExtraKeyToken,
              allowCustom: true,
              fixedLeadingLabel: '⌨️ 키보드 토글(첫칸 고정)',
              onChanged: controller.setExtraKeysBarItems,
            ),
            _BarEditor(
              items: settings.terminalHeaderItems,
              catalog: kTerminalHeaderCatalog,
              resolve: resolveHeaderToken,
              allowCustom: false,
              onChanged: controller.setTerminalHeaderItems,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarEditor extends StatefulWidget {
  const _BarEditor({
    required this.items,
    required this.catalog,
    required this.resolve,
    required this.allowCustom,
    required this.onChanged,
    this.fixedLeadingLabel,
  });

  final List<String> items;
  final List<ActionDef> catalog;
  final ActionDef? Function(String token) resolve;
  final bool allowCustom;
  final ValueChanged<List<String>> onChanged;

  /// 편집 불가하지만 항상 첫칸에 표시되는 고정 항목 설명(보조키바의 키보드 토글).
  final String? fixedLeadingLabel;

  @override
  State<_BarEditor> createState() => _BarEditorState();
}

class _BarEditorState extends State<_BarEditor> {
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _add(String token) => widget.onChanged([...widget.items, token]);

  void _remove(int index) {
    widget.onChanged([...widget.items]..removeAt(index));
  }

  // onReorderItem은 newIndex를 제거 후 기준으로 이미 보정해 전달한다.
  void _reorder(int oldIndex, int newIndex) {
    final next = [...widget.items];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    widget.onChanged(next);
  }

  void _addCustom() {
    final text = _customController.text;
    if (text.isEmpty) return;
    _add(makeTextToken(text));
    _customController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final available = [
      for (final def in widget.catalog)
        if (!widget.items.contains(def.id)) def,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('표시 중 (드래그로 순서 변경)'),
        if (widget.fixedLeadingLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              widget.fixedLeadingLabel!,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          flex: 3,
          child: widget.items.isEmpty
              ? const Center(
                  child: Text(
                    '표시할 항목이 없습니다. 아래에서 추가하세요.',
                    style: TextStyle(color: VibeColors.onSurfaceDim),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: widget.items.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final token = widget.items[index];
                    final def = widget.resolve(token);
                    return Card(
                      key: ValueKey('item-$index-$token'),
                      color: VibeColors.surfaceHigh,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        dense: true,
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(
                            Icons.drag_handle,
                            color: VibeColors.onSurfaceDim,
                          ),
                        ),
                        title: Text(def?.label ?? token),
                        trailing: IconButton(
                          tooltip: '제거',
                          icon: const Icon(Icons.remove_circle_outline),
                          color: VibeColors.statusError,
                          onPressed: () => _remove(index),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1, color: VibeColors.borderSoft),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('사용 가능 (탭해서 추가)', padded: false),
                const SizedBox(height: 8),
                if (available.isEmpty)
                  const Text(
                    '모든 항목이 표시 중입니다.',
                    style: TextStyle(color: VibeColors.onSurfaceDim),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final def in available)
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text(def.label),
                          onPressed: () => _add(def.id),
                        ),
                    ],
                  ),
                if (widget.allowCustom) ...[
                  const SizedBox(height: 16),
                  const _SectionLabel('사용자 키 추가', padded: false),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customController,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '예: sudo  또는  ||',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _addCustom(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _addCustom,
                        child: const Text('추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '입력한 문자열을 그대로 터미널에 보내는 버튼이 추가됩니다.',
                    style: TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.padded = true});

  final String text;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: const TextStyle(
        color: VibeColors.onSurface,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    );
    if (!padded) return label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: label,
    );
  }
}
