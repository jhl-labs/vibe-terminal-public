import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Agent Chat 입력 초안을 패널 수명과 분리해 보관한다.
///
/// 우측 패널을 닫거나 다른 도구로 전환해도 작성 중인 목표와 피드백이 유지된다.
class AgentChatDraftNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    if (state == value) return;
    state = value;
  }

  void clear() => set('');
}

final agentChatDraftProvider = NotifierProvider<AgentChatDraftNotifier, String>(
  AgentChatDraftNotifier.new,
);
