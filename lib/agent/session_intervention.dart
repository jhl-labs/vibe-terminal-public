import 'agent_attention.dart';
import 'session_port.dart';

/// 구조화 신호를 제공하는 세션만 구현하는 읽기 전용 확장이다.
/// 대기 신호는 실행을 제한할 뿐, 승인 권한을 부여하지 않는다.
abstract interface class SessionInterventionPort {
  String? get pendingIntervention;
}

class SessionInterventionDetector {
  const SessionInterventionDetector();

  String? inspect(SessionPort session, String screen) {
    if (session is SessionInterventionPort) {
      final message = (session as SessionInterventionPort).pendingIntervention;
      if (message != null && message.trim().isNotEmpty) return message;
    }
    // 처리한 승인 문구가 스크롤백에 남아 있어도 새 입력 프롬프트 아래의 과거
    // 질문을 활성 대기로 오인하지 않는다. 구조화 대기는 위에서 먼저 처리한다.
    final lastLine = screen.trimRight().split('\n').last.trim();
    if (RegExp(r'^(?:[❯›➜>]|[$#])\s*$').hasMatch(lastLine)) return null;
    final assessment = const AgentAttentionClassifier().inspect(screen);
    return assessment.needsInput
        ? '화면 감지: ${assessment.evidence ?? "승인·입력 대기"}'
        : null;
  }
}
