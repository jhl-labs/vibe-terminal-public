import 'package:flutter/material.dart';
import '../../security/host_key_store.dart';

Future<bool> showHostKeyPrompt(
  BuildContext context, {
  required String hostAlias,
  required String fingerprint,
  required HostKeyVerdict verdict,
}) async {
  final isMismatch = verdict == HostKeyVerdict.mismatch;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
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
  );
  return result ?? false;
}
