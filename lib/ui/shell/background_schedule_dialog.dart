import 'package:flutter/material.dart';
import '../../data/models/host.dart';

Future<void> showBackgroundScheduleDialog(
  BuildContext context, {
  required List<Host> hosts,
  required Future<Map<String, dynamic>> Function() load,
  required Future<void> Function(Map<String, dynamic>) save,
  required Future<void> Function(String) remove,
  required Future<bool> Function() autostartEnabled,
  required Future<void> Function(bool) autostart,
}) => showDialog<void>(
  context: context,
  builder: (_) => _Schedules(
    hosts: hosts,
    load: load,
    save: save,
    remove: remove,
    autostartEnabled: autostartEnabled,
    autostart: autostart,
  ),
);

class _Schedules extends StatefulWidget {
  const _Schedules({
    required this.hosts,
    required this.load,
    required this.save,
    required this.remove,
    required this.autostartEnabled,
    required this.autostart,
  });
  final List<Host> hosts;
  final Future<Map<String, dynamic>> Function() load;
  final Future<void> Function(Map<String, dynamic>) save;
  final Future<void> Function(String) remove;
  final Future<bool> Function() autostartEnabled;
  final Future<void> Function(bool) autostart;
  @override
  State<_Schedules> createState() => _SchedulesState();
}

class _SchedulesState extends State<_Schedules> {
  late Future<Map<String, dynamic>> _data;
  bool _auto = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _data = widget.load();
    widget
        .autostartEnabled()
        .then((value) {
          if (mounted) setState(() => _auto = value);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _data = widget.load());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditSchedule(
        hosts: widget.hosts,
        initial: existing,
        save: widget.save,
      ),
    );
    if (mounted) setState(() => _data = widget.load());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('앱 종료 중 명령 예약'),
    content: SizedBox(
      width: 760,
      height: 540,
      child: Column(
        children: [
          const Text(
            '로컬 데몬이 지정한 호스트 설정으로 명령을 실행합니다. 앱 창을 닫아도 계속됩니다. CLI 권한 요청은 자동 승인하지 않으므로 필요하면 백그라운드 작업에 연결하세요.',
          ),
          SwitchListTile(
            title: const Text('다음 로그인부터 백그라운드 예약 시작'),
            subtitle: const Text('컴퓨터 전원이 꺼져 있거나 로그인 전에는 실행하지 않습니다.'),
            value: _auto,
            onChanged: _busy
                ? null
                : (value) => _run(() async {
                    await widget.autostart(value);
                    if (mounted) setState(() => _auto = value);
                  }),
          ),
          if (_error != null) SelectableText(_error!),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText('${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                if (data['error'] != null) {
                  return SelectableText('예약 저장소 오류: ${data['error']}');
                }
                final tasks = (data['tasks'] as List).cast<Map>();
                return ListView(
                  children: [
                    for (final row in tasks)
                      ListTile(
                        title: Text('${row['title']}'),
                        subtitle: Text(
                          '${row['nextRunAt'] ?? '완료'} · ${row['timezone'] ?? 'UTC'}\n${row['lastResult'] ?? ''}',
                        ),
                        leading: Checkbox(
                          value: row['enabled'] == true,
                          onChanged: _busy
                              ? null
                              : (value) => _run(
                                  () => widget.save({
                                    ...Map<String, dynamic>.from(row),
                                    'enabled': value,
                                  }),
                                ),
                        ),
                        onTap: _busy
                            ? null
                            : () => _edit(Map<String, dynamic>.from(row)),
                        trailing: IconButton(
                          tooltip: '예약 삭제',
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => widget.remove(row['id'] as String),
                                ),
                          icon: const Icon(Icons.delete_outline),
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
        onPressed: _busy ? null : () => setState(() => _data = widget.load()),
        child: const Text('새로고침'),
      ),
      FilledButton(
        onPressed: _busy || widget.hosts.isEmpty ? null : _edit,
        child: const Text('명령 예약'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  );
}

class _EditSchedule extends StatefulWidget {
  const _EditSchedule({required this.hosts, this.initial, required this.save});
  final Future<void> Function(Map<String, dynamic>) save;
  final List<Host> hosts;
  final Map<String, dynamic>? initial;
  @override
  State<_EditSchedule> createState() => _EditScheduleState();
}

class _EditScheduleState extends State<_EditSchedule> {
  late final TextEditingController _title,
      _command,
      _at,
      _zone,
      _hour,
      _minutes,
      _directory;
  late String _kind, _host;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final v = widget.initial ?? {};
    _kind = v['kind'] as String? ?? 'once';
    _host = widget.hosts.any((h) => h.id == v['hostId'])
        ? v['hostId'] as String
        : widget.hosts.first.id;
    _title = TextEditingController(text: v['title'] as String? ?? '');
    _command = TextEditingController(text: v['commandText'] as String? ?? '');
    _at = TextEditingController(
      text:
          v['nextRunAt'] as String? ??
          DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
    );
    _zone = TextEditingController(text: v['timezone'] as String? ?? 'UTC');
    _hour = TextEditingController(
      text:
          '${v['hour'] ?? 9}:${(v['minute'] ?? 0).toString().padLeft(2, '0')}',
    );
    _minutes = TextEditingController(text: '${v['minutes'] ?? 30}');
    _directory = TextEditingController(
      text:
          v['workingDirectory'] as String? ??
          widget.hosts.first.workingDirectory ??
          '',
    );
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _command,
      _at,
      _zone,
      _hour,
      _minutes,
      _directory,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final parts = _hour.text.split(':');
      final task = <String, dynamic>{
        if (widget.initial?['id'] != null) 'id': widget.initial!['id'],
        'title': _title.text.trim(),
        'commandText': _command.text,
        'hostId': _host,
        'workingDirectory': _directory.text.trim(),
        'kind': _kind,
        'enabled': true,
        if (_kind == 'once')
          'nextRunAt': DateTime.parse(_at.text).toUtc().toIso8601String(),
        if (_kind == 'interval') 'minutes': int.parse(_minutes.text),
        if (_kind == 'daily') ...{
          'timezone': _zone.text.trim(),
          'hour': int.parse(parts[0]),
          'minute': int.parse(parts[1]),
        },
      };
      if (_title.text.trim().isEmpty || _command.text.trim().isEmpty) {
        throw const FormatException('제목과 실행 명령을 입력하세요.');
      }
      await widget.save(task);
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '저장하지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: IgnorePointer(
      ignoring: _saving,
      child: AlertDialog(
        title: const Text('백그라운드 명령 예약'),
        content: SizedBox(
          width: 660,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '제목'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _host,
                  items: [
                    for (final host in widget.hosts)
                      DropdownMenuItem(value: host.id, child: Text(host.alias)),
                  ],
                  onChanged: (value) => setState(() => _host = value!),
                  decoration: const InputDecoration(labelText: '로컬 호스트'),
                ),
                TextField(
                  controller: _directory,
                  decoration: const InputDecoration(
                    labelText: '작업 디렉터리 (비우면 호스트 기본값)',
                  ),
                ),
                TextField(
                  controller: _command,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '실행할 명령',
                    hintText: '예: 프로젝트 테스트 또는 Agent CLI 명령',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  items: const [
                    DropdownMenuItem(value: 'once', child: Text('한 번')),
                    DropdownMenuItem(value: 'interval', child: Text('분 간격')),
                    DropdownMenuItem(
                      value: 'daily',
                      child: Text('매일 · 지정 시간대'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _kind = value!),
                ),
                if (_kind == 'once')
                  TextField(
                    controller: _at,
                    decoration: const InputDecoration(
                      labelText: '실행 시각 (ISO 8601, 시간대 없으면 현재 지역)',
                    ),
                  ),
                if (_kind == 'interval')
                  TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '간격 (분)'),
                  ),
                if (_kind == 'daily') ...[
                  TextField(
                    controller: _hour,
                    decoration: const InputDecoration(labelText: '시각 HH:MM'),
                  ),
                  TextField(
                    controller: _zone,
                    decoration: const InputDecoration(
                      labelText: 'IANA 시간대',
                      hintText: 'Asia/Seoul',
                    ),
                  ),
                  const Text('DST로 없는 시각은 건너뛰고 반복되는 시각은 하루 한 번 실행합니다.'),
                ],
                if (_error != null) Text(_error!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: const Text('명령과 시각 확인 · 저장'),
          ),
        ],
      ),
    ),
  );
}
