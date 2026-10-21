import 'dart:async';

import 'package:flutter/material.dart';
import '../../security/host_key_store.dart';

/// SSH 전송 계층은 호스트 키 확인을 2분까지 기다리고, sshd의 기본
/// LoginGraceTime도 120초다. 그보다 조금 먼저 창을 닫아, 이미 끊긴 연결을
/// 사용자가 뒤늦게 승인하는 일이 없게 한다.
const hostKeyPromptTimeout = Duration(seconds: 110);

Future<bool> showHostKeyPrompt(
  BuildContext context, {
  required String hostAlias,
  required String fingerprint,
  required HostKeyVerdict verdict,
  Duration timeout = hostKeyPromptTimeout,
}) async {
  final isMismatch = verdict == HostKeyVerdict.mismatch;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExpiringDialog(
      timeout: timeout,
      child: AlertDialog(
        icon: Icon(
          isMismatch ? Icons.warning_amber_rounded : Icons.vpn_key,
          color: isMismatch ? Colors.red : null,
        ),
        title: Text(
          isMismatch ? '$hostAlias · 호스트 키 불일치 경고' : '$hostAlias · 새 호스트 키 신뢰',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMismatch)
              const Text(
                '저장된 키와 다릅니다. 중간자 공격일 수 있습니다. '
                '서버 관리자와 지문을 직접 대조하기 전에는 신뢰하지 마세요.',
              ),
            const SizedBox(height: 8),
            SelectableText(
              fingerprint,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(
              '${timeout.inSeconds}초 안에 확인하지 않으면 연결을 취소합니다.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: isMismatch
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isMismatch ? '위험을 감수하고 신뢰' : '신뢰'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// [timeout]이 지나면 스스로 닫히며 `false`(신뢰하지 않음)를 돌려주는 대화상자.
class _ExpiringDialog extends StatefulWidget {
  const _ExpiringDialog({required this.timeout, required this.child});

  final Duration timeout;
  final Widget child;

  @override
  State<_ExpiringDialog> createState() => _ExpiringDialogState();
}

class _ExpiringDialogState extends State<_ExpiringDialog> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.timeout, () {
      if (mounted) Navigator.pop(context, false);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
