import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../session/session.dart';
import '../../session/session_manager.dart'
    show RemoteWorkTermination, SessionCloseIntent;
import '../../state/providers.dart';

/// 대화상자의 선택. 취소(바깥 탭·뒤로가기 포함)는 null이다.
enum _CloseChoice { detach, terminate }

/// 작업 이어가기 탭을 닫을 때 확인한다. "탭만 닫기"는 서버의 tmux 작업을
/// 남겨 두므로 다른 기기나 보관함에서 다시 열 수 있다.
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
  final choice = await showDialog<_CloseChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(connected ? '서버의 작업을 종료할까요?' : '탭을 닫을까요?'),
      content: Text(
        connected
            ? '작업을 종료하면 서버에서 실행 중인 작업도 끝납니다. 다른 기기에서 이 작업을 보고 있으면 끝내지 않고 탭만 닫습니다. 탭만 닫으면 작업은 서버에 남고, 서버 작업 보관함에서 다시 열 수 있습니다.'
            : '현재는 서버에 종료 명령을 보낼 수 없습니다. 작업 종료를 고르면 종료 요청을 저장하고 이 서버에 다시 연결될 때 정리합니다. 탭만 닫으면 작업은 서버에 남습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('취소'),
        ),
        OutlinedButton(
          key: const ValueKey('session-close-detach'),
          onPressed: () => Navigator.of(dialogContext).pop(_CloseChoice.detach),
          child: const Text('탭만 닫기'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: VibeColors.statusError,
          ),
          onPressed: () =>
              Navigator.of(dialogContext).pop(_CloseChoice.terminate),
          child: const Text('작업 종료'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == _CloseChoice.detach) {
    manager.closeSession(
      session.id,
      intent: SessionCloseIntent.detachRemoteWork,
    );
    return;
  }

  final outcome = await manager.terminateAndCloseSession(session.id);
  if (!context.mounted) return;
  final notice = switch (outcome) {
    RemoteWorkTermination.terminated => null,
    RemoteWorkTermination.keptForOtherDevice =>
      '다른 기기에서 이 작업을 보고 있어 서버의 작업은 남겨 두고 탭만 닫았습니다.',
    RemoteWorkTermination.queued =>
      connected
          ? '서버에서 종료 명령이 실패했습니다. 종료 요청을 저장했으며 다음 연결 때 다시 시도합니다.'
          : '종료 요청을 저장했습니다. 이 서버에 다시 연결하면 정리합니다.',
    RemoteWorkTermination.failed =>
      '종료 요청을 저장하지 못했습니다. 서버에 작업이 남아 있으니 서버 작업 보관함에서 직접 종료해 주세요.',
  };
  if (notice != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
  }
}
