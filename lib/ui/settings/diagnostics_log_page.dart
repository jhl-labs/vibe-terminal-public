import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/error_reporter.dart';
import '../../app/theme.dart';

/// 설정 → 앱 정보 → 진단 로그. `crash.log`(미처리 오류, 직전 실행 종료 사유,
/// 백그라운드 서비스 중단)를 보여 주고 복사·지우기를 제공한다.
///
/// 사용자 이슈를 받을 때 adb 없이도 "설정에서 진단 로그를 복사해 보내 주세요"로
/// 원인을 받을 수 있게 하는 것이 목적이다. 터미널 내용은 여기에 실리지 않는다.
class DiagnosticsLogPage extends StatefulWidget {
  const DiagnosticsLogPage({super.key, this.reporter});

  /// 테스트에서 바꿔 끼운다. null 이면 전역 리포터.
  final AppErrorReporter? reporter;

  @override
  State<DiagnosticsLogPage> createState() => _DiagnosticsLogPageState();
}

class _DiagnosticsLogPageState extends State<DiagnosticsLogPage> {
  String? _log;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AppErrorReporter get _reporter => widget.reporter ?? appErrorReporter;

  Future<void> _load() async {
    await _reporter.flush();
    final text = await _reporter.readPersistedLog();
    if (!mounted) return;
    setState(() {
      _log = text;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    final text = _log;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('진단 로그를 복사했습니다.')));
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('진단 로그 지우기'),
        content: const Text('저장된 오류·종료 기록을 모두 지웁니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _reporter.clearPersistedLog();
    if (!mounted) return;
    setState(() => _log = '');
  }

  @override
  Widget build(BuildContext context) {
    final log = _log ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('진단 로그'),
        actions: [
          IconButton(
            key: const ValueKey('diagnostics-copy'),
            tooltip: '복사',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: log.isEmpty ? null : _copy,
          ),
          IconButton(
            key: const ValueKey('diagnostics-clear'),
            tooltip: '지우기',
            icon: const Icon(Icons.delete_outline),
            onPressed: log.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : log.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '기록된 오류나 비정상 종료가 없습니다.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '앱이 예기치 않게 끝났다면 이 로그를 복사해 문의에 붙여 주세요. '
                    '터미널 화면 내용은 포함되지 않습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: VibeColors.onSurfaceDim,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      log,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
