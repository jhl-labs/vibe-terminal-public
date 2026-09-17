import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../session/session.dart';
import '../../state/providers.dart';

Future<void> requestCloseSession(
  BuildContext context,
  WidgetRef ref,
  SessionInfo session,
) async {
  final manager = ref.read(sessionManagerProvider.notifier);
  if (!session.host.keepsRemoteSession) {
    manager.closeSession(session.id);
    return;
  }

  final connected = session.status == SessionStatus.connected;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(connected ? '서버의 작업을 종료할까요?' : '탭을 닫을까요?'),
      content: Text(
        connected
            ? '이 탭을 닫으면 서버에서 실행 중인 작업도 종료됩니다. 네트워크가 끊기거나 앱을 다시 시작할 때는 자동으로 이어집니다.'
            : '현재는 서버에 종료 명령을 보낼 수 없습니다. 탭을 닫으면 종료 요청을 저장하고, 이 서버에 다시 연결될 때 안전하게 정리합니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: VibeColors.statusError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(connected ? '작업 종료' : '탭 닫기'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final terminated = await manager.terminatePersistentSession(session.id);
  manager.closeSession(session.id);
  if (!terminated && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('종료 요청을 저장했습니다. 이 서버에 다시 연결하면 정리합니다.')),
    );
  }
}
