import 'package:flutter/material.dart';

Future<void> showLocalBackgroundSessionsDialog(
  BuildContext context, {
  required Future<List<Map<String, dynamic>>> Function() load,
  required Future<void> Function(Map<String, dynamic>) attach,
  required Future<void> Function(String) terminate,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _BackgroundDialog(load: load, attach: attach, terminate: terminate),
);

class _BackgroundDialog extends StatefulWidget {
  const _BackgroundDialog({
    required this.load,
    required this.attach,
    required this.terminate,
  });
  final Future<List<Map<String, dynamic>>> Function() load;
  final Future<void> Function(Map<String, dynamic>) attach;
  final Future<void> Function(String) terminate;
  @override
  State<_BackgroundDialog> createState() => _BackgroundDialogState();
}

class _BackgroundDialogState extends State<_BackgroundDialog> {
  late Future<List<Map<String, dynamic>>> _list;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _list = widget.load();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _list = widget.load());
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _terminate(Map<String, dynamic> session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백그라운드 프로세스를 종료할까요?'),
        content: Text(
          '${session['executable']} · PID ${session['pid']}\n실행 중인 작업과 터미널 화면 기록을 종료·정리합니다. 파일과 Git 작업공간은 보존합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('프로세스 종료'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _run(() => widget.terminate(session['id'] as String));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('로컬 백그라운드 작업'),
    content: SizedBox(
      width: 740,
      height: 460,
      child: Column(
        children: [
          const Text(
            '데몬을 사용하는 로컬 탭은 닫아도 작업이 유지됩니다. 여기서 다시 연결하거나 프로세스를 종료할 수 있습니다.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) SelectableText(_error!),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _list,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText('${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.data!.isEmpty) {
                  return const Center(child: Text('백그라운드 작업이 없습니다.'));
                }
                return ListView(
                  children: [
                    for (final session in snapshot.data!)
                      ListTile(
                        title: Text(
                          '${session['executable']} · ${session['directory'] ?? ''}',
                        ),
                        subtitle: Text(
                          'PID ${session['pid']} · ${session['exitCode'] == null ? '실행 중' : '종료 ${session['exitCode']}'}${session['attached'] == true ? ' · 연결됨' : ''}${session['journalTruncated'] == true ? ' · 과거 기록 일부 생략, 현재 화면 복원' : ''}',
                        ),
                        trailing: Wrap(
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => widget.attach(session)),
                              child: const Text('연결'),
                            ),
                            IconButton(
                              tooltip: '프로세스 종료',
                              onPressed: _busy
                                  ? null
                                  : () => _terminate(session),
                              icon: const Icon(Icons.stop_circle_outlined),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => setState(() => _list = widget.load()),
        child: const Text('새로고침'),
      ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  );
}
