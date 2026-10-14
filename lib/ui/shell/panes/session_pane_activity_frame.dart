import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../session/session_activity.dart';
import '../../../session/session_attention.dart';
import 'pane_activity_frame.dart';

/// 세션 하나의 busy·Agent 상태만 구독하는 칸 테두리.
///
/// 앱 셸이 모든 세션의 활동 맵을 구독하면 한 세션의 busy/idle 전환마다 셸과
/// 모든 터미널 위젯이 다시 빌드된다. 세션이 많고 CPU가 약하면 이 재빌드가 입력을
/// 수백 ms씩 막는다. 칸마다 자기 상태만 고르면 바뀐 칸의 테두리만 다시 빌드된다.
class SessionPaneActivityFrame extends ConsumerWidget {
  const SessionPaneActivityFrame({
    super.key,
    required this.sessionId,
    required this.focused,
    required this.child,
  });

  final String sessionId;
  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(
      sessionActivityProvider.select((map) => map[sessionId] ?? false),
    );
    final attention = ref.watch(
      sessionAttentionProvider.select((map) => map[sessionId]?.state),
    );
    return PaneActivityFrame(
      focused: focused,
      activity: paneActivityFor(busy: busy, attention: attention),
      child: child,
    );
  }
}
