import 'package:flutter/material.dart';
import '../../agent/session_bulk_action.dart';
import '../../agent/session_port.dart';

Future<void> showSessionBulkDialog(
  BuildContext context, {
  required SessionPortRegistry registry,
  required void Function(String id) close,
}) => showDialog<void>(
  context: context,
  builder: (_) => _BulkDialog(registry: registry, close: close),
);

class _BulkDialog extends StatefulWidget {
  const _BulkDialog({required this.registry, required this.close});
  final SessionPortRegistry registry;
  final void Function(String id) close;
  @override
  State<_BulkDialog> createState() => _BulkDialogState();
}

class _BulkDialogState extends State<_BulkDialog> {
  late List<SessionBulkTarget> _targets;
  final _selected = <String>{};
  final _text = TextEditingController();
  SessionBulkAction _action = SessionBulkAction.input;
  bool _submit = false;
  Map<String, String> _results = {};
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _targets = [
      for (final port in widget.registry.sessions())
        if (port.isConnected)
          SessionBulkTarget(port.id, port.displayName, port.connectionIdentity),
    ];
    _selected.retainAll(_targets.map((e) => e.id));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final targets = _targets.where((e) => _selected.contains(e.id)).toList();
    final action = _action;
    final text = _text.text;
    final submit = _submit;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${targets.length}개 세션에 적용할까요?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(targets.map((e) => '${e.name} (${e.id})').join('\n')),
              const Divider(),
              SelectableText(switch (action) {
                SessionBulkAction.input =>
                  '$text${submit ? '\n[Enter 제출]' : ''}',
                SessionBulkAction.interrupt =>
                  'Ctrl+C를 보냅니다. 프로세스가 신호를 무시할 수 있습니다.',
                SessionBulkAction.close =>
                  '세션 탭을 닫습니다. 로컬 프로세스는 종료될 수 있고, 지속 원격 세션은 서버에 남습니다. 작업공간 기록은 보존됩니다.',
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('선택한 세션에 적용'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      setState(
        () => _results = SessionBulkExecutor(
          widget.registry,
          widget.close,
        ).execute(targets, action, text: text, submit: submit),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('여러 세션 조작'),
    content: SizedBox(
      width: 640,
      height: 500,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<SessionBulkAction>(
                  value: _action,
                  isExpanded: true,
                  items: [
                    for (final action in SessionBulkAction.values)
                      DropdownMenuItem(
                        value: action,
                        child: Text(switch (action) {
                          SessionBulkAction.input => '동일 입력 보내기',
                          SessionBulkAction.interrupt => 'Ctrl+C 보내기',
                          SessionBulkAction.close => '세션 탭 닫기',
                        }),
                      ),
                  ],
                  onChanged: (value) => setState(() => _action = value!),
                ),
              ),
              IconButton(
                tooltip: '연결 목록 새로고침',
                onPressed: () => setState(_refresh),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              children: [
                for (final target in _targets)
                  CheckboxListTile(
                    value: _selected.contains(target.id),
                    title: Text(target.name),
                    subtitle: Text(_results[target.id] ?? target.id),
                    onChanged: (value) => setState(
                      () => value == true
                          ? _selected.add(target.id)
                          : _selected.remove(target.id),
                    ),
                  ),
              ],
            ),
          ),
          if (_action == SessionBulkAction.input) ...[
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '보낼 입력'),
            ),
            CheckboxListTile(
              value: _submit,
              title: const Text('입력 후 Enter로 제출'),
              onChanged: (value) => setState(() => _submit = value!),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty ? null : _execute,
        child: Text('${_selected.length}개 대상 검토'),
      ),
    ],
  );
}
