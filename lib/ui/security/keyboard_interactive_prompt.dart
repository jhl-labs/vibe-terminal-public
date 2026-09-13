import 'package:flutter/material.dart';

import '../../ssh/ssh_service.dart';

/// 서버가 보낸 keyboard-interactive 질문을 그대로 보여주고 응답을 한 번만
/// 반환한다. OTP·비밀번호가 앱 상태나 저장소에 남지 않도록 컨트롤러는 다이얼로그
/// 수명과 함께 즉시 폐기한다.
Future<List<String>?> showKeyboardInteractivePrompt(
  BuildContext context, {
  required String hostAlias,
  required KeyboardInteractiveRequest request,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _KeyboardInteractiveDialog(hostAlias: hostAlias, request: request),
  );
}

class _KeyboardInteractiveDialog extends StatefulWidget {
  const _KeyboardInteractiveDialog({
    required this.hostAlias,
    required this.request,
  });

  final String hostAlias;
  final KeyboardInteractiveRequest request;

  @override
  State<_KeyboardInteractiveDialog> createState() =>
      _KeyboardInteractiveDialogState();
}

class _KeyboardInteractiveDialogState
    extends State<_KeyboardInteractiveDialog> {
  late final List<TextEditingController> _controllers = [
    for (final _ in widget.request.prompts) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, [
      for (final controller in _controllers) controller.text,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final title = request.name.trim().isEmpty
        ? '${widget.hostAlias} · 추가 인증'
        : '${widget.hostAlias} · ${request.name.trim()}';
    return AlertDialog(
      icon: const Icon(Icons.phonelink_lock),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (request.instruction.trim().isNotEmpty) ...[
                Text(request.instruction.trim()),
                const SizedBox(height: 12),
              ],
              for (var i = 0; i < request.prompts.length; i++) ...[
                TextField(
                  key: ValueKey('keyboard-interactive-$i'),
                  controller: _controllers[i],
                  autofocus: i == 0,
                  obscureText: !request.prompts[i].echo,
                  enableSuggestions: request.prompts[i].echo,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: request.prompts[i].text.trim().isEmpty
                        ? '응답 ${i + 1}'
                        : request.prompts[i].text.trim(),
                  ),
                  textInputAction: i == request.prompts.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onSubmitted: i == request.prompts.length - 1
                      ? (_) => _submit()
                      : null,
                ),
                if (i != request.prompts.length - 1) const SizedBox(height: 10),
              ],
              const SizedBox(height: 10),
              const Text(
                '응답은 이 인증 요청에만 사용되며 저장되지 않습니다.',
                style: TextStyle(fontSize: 12),
              ),
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
          onPressed: request.prompts.isEmpty ? null : _submit,
          child: const Text('응답'),
        ),
      ],
    );
  }
}
