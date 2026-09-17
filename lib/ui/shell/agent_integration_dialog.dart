import 'dart:async';
import 'package:flutter/material.dart';
import '../../agent/agent_integration.dart';

typedef AgentIntegrationLoader =
    Future<AgentIntegrationPlan> Function(bool remove);
typedef AgentIntegrationApplier =
    Future<void> Function(AgentIntegrationPlan plan);

Future<void> showAgentIntegrationDialog(
  BuildContext context, {
  required String title,
  required AgentIntegrationLoader load,
  required AgentIntegrationApplier apply,
  String Function()? diagnostic,
}) => showDialog<void>(
  context: context,
  builder: (_) => _IntegrationDialog(
    title: title,
    load: load,
    apply: apply,
    diagnostic: diagnostic,
  ),
);

class _IntegrationDialog extends StatefulWidget {
  const _IntegrationDialog({
    required this.title,
    required this.load,
    required this.apply,
    this.diagnostic,
  });
  final String title;
  final AgentIntegrationLoader load;
  final AgentIntegrationApplier apply;
  final String Function()? diagnostic;
  @override
  State<_IntegrationDialog> createState() => _IntegrationDialogState();
}

class _IntegrationDialogState extends State<_IntegrationDialog> {
  late Future<AgentIntegrationPlan> _plan;
  bool _remove = false;
  bool _busy = false;
  String? _message;
  Timer? _diagnosticTimer;
  @override
  void initState() {
    super.initState();
    _plan = widget.load(false);
    if (widget.diagnostic != null) {
      _diagnosticTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _diagnosticTimer?.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _message = null;
    _plan = widget.load(_remove);
  });
  Future<void> _apply(AgentIntegrationPlan plan) async {
    setState(() => _busy = true);
    try {
      await widget.apply(plan);
      if (!mounted) return;
      setState(() {
        _message = _remove
            ? '연동 등록을 해제했습니다.'
            : '설정 파일을 설치했습니다. CLI에서 hook 신뢰와 이벤트 수신을 확인하세요.';
        _plan = widget.load(_remove);
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.title} CLI 연동'),
    content: SizedBox(
      width: 720,
      height: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 작업공간의 설정만 변경합니다. 기존 사용자 hook을 보존합니다. Codex는 /hooks에서 신뢰가 필요하며, tmux에서는 allow-passthrough 설정이 필요합니다. 설치됨은 이벤트 수신 검증을 뜻하지 않습니다.',
          ),
          if (widget.diagnostic != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(widget.diagnostic!()),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibe Terminal 연동 제거'),
            value: _remove,
            onChanged: _busy
                ? null
                : (value) {
                    _remove = value;
                    _reload();
                  },
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_message!),
            ),
          Expanded(
            child: FutureBuilder<AgentIntegrationPlan>(
              future: _plan,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SingleChildScrollView(
                    child: SelectableText('${snapshot.error}'),
                  );
                }
                final plan = snapshot.data;
                if (plan == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Node ${plan.nodeVersion} · ${plan.changes.length}개 파일 변경',
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final change in plan.changes)
                            ExpansionTile(
                              title: Text(change.path),
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('현재 내용'),
                                ),
                                SelectableText(change.before ?? '(파일 없음)'),
                                const Divider(),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('적용할 내용'),
                                ),
                                SelectableText(change.after ?? '(파일 삭제)'),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy || plan.changes.isEmpty
                            ? null
                            : () => _apply(plan),
                        child: Text(_busy ? '처리 중…' : '검토한 변경 적용'),
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
      TextButton(onPressed: _busy ? null : _reload, child: const Text('다시 진단')),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  );
}
