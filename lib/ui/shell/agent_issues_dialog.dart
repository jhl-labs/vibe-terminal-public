import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Read-only issue intake. The selected content becomes an editable launch goal.
Future<String?> showAgentIssuesDialog(
  BuildContext context,
  Future<List<Map<String, dynamic>>> Function() load,
) => showDialog<String>(context: context, builder: (_) => _IssuesDialog(load));

class _IssuesDialog extends StatefulWidget {
  const _IssuesDialog(this.load);
  final Future<List<Map<String, dynamic>>> Function() load;
  @override
  State<_IssuesDialog> createState() => _IssuesDialogState();
}

class _IssuesDialogState extends State<_IssuesDialog> {
  late Future<List<Map<String, dynamic>>> _rows;
  final _filter = TextEditingController();
  final _goal = TextEditingController();
  Map<String, dynamic>? _selected;
  @override
  void initState() {
    super.initState();
    _rows = widget.load();
  }

  @override
  void dispose() {
    _filter.dispose();
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('GitHub 이슈에서 작업 가져오기'),
    content: SizedBox(
      width: 800,
      height: 550,
      child: Column(
        children: [
          const Text(
            '현재 저장소의 열린 이슈 최대 100개를 읽습니다. 가져온 내용은 실행할 목표로 직접 검토·수정하세요.',
          ),
          TextField(
            controller: _filter,
            decoration: const InputDecoration(labelText: '번호·제목 검색'),
            onChanged: (_) => setState(() {}),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _rows,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      SelectableText('${snapshot.error}'),
                      TextButton(
                        onPressed: () => setState(() => _rows = widget.load()),
                        child: const Text('다시 읽기'),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!.where(
                  (row) => '${row['number']} ${row['title']}'
                      .toLowerCase()
                      .contains(_filter.text.toLowerCase()),
                );
                return ListView(
                  children: [
                    for (final row in rows)
                      ListTile(
                        selected: identical(row, _selected),
                        title: Text('#${row['number']} ${row['title']}'),
                        subtitle: Text('${row['url']}'),
                        onTap: () => setState(() {
                          _selected = row;
                          _goal.text =
                              'Implement issue #${row['number']}: ${row['title']}\nSource: ${row['url']}\n\n${row['body'] ?? ''}';
                        }),
                      ),
                  ],
                );
              },
            ),
          ),
          TextField(
            controller: _goal,
            minLines: 3,
            maxLines: 7,
            maxLength: 8000,
            decoration: const InputDecoration(
              labelText: '실행 목표 초안',
              helperText: '이슈 본문의 명령·요구 사항을 검토하세요. 자동 실행하지 않습니다.',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
      TextButton(
        onPressed: _selected == null
            ? null
            : () => Clipboard.setData(ClipboardData(text: _goal.text)),
        child: const Text('목표 복사'),
      ),
      FilledButton(
        onPressed: _selected == null
            ? null
            : () {
                if (_goal.text.trim().isEmpty || _goal.text.length > 8000) {
                  return;
                }
                Navigator.pop(context, _goal.text.trim());
              },
        child: const Text('Agent 시작 설정으로 가져오기'),
      ),
    ],
  );
}
