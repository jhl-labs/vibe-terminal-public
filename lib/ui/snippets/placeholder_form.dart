import 'package:flutter/material.dart';

/// 스니펫 실행 직전 `{{name}}` 값을 입력받는 다이얼로그.
/// 확인 시 {name: value} 맵, 취소/dismiss 시 null 반환.
Future<Map<String, String>?> showPlaceholderForm(
  BuildContext context,
  List<String> names,
) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => _PlaceholderDialog(names: names),
  );
}

class _PlaceholderDialog extends StatefulWidget {
  const _PlaceholderDialog({required this.names});

  final List<String> names;

  @override
  State<_PlaceholderDialog> createState() => _PlaceholderDialogState();
}

class _PlaceholderDialogState extends State<_PlaceholderDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {for (final n in widget.names) n: TextEditingController()};
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('값 입력'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in widget.names)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: _controllers[n],
                  decoration: InputDecoration(labelText: n),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            for (final n in widget.names) n: _controllers[n]!.text,
          }),
          child: const Text('확인'),
        ),
      ],
    );
  }
}
