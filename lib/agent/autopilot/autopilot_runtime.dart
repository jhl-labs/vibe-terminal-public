import '../../session/session_attention.dart';
import '../agent_launcher.dart';
import '../session_port.dart';
import 'autopilot_state.dart';
import 'autopilot_timing.dart';

/// 자율사용 흐름(승인·한도 대기·재개)과 게이트가 쓰는 좁은 실행 환경.
///
/// [AutopilotController]가 구현한다. 흐름은 Riverpod·provider를 직접 읽지 않고
/// 이 인터페이스만 거친다. 안전 불변식은 구현 한 곳에 모아 둔다:
/// - 세션당 타이머 하나([schedule]는 이전 예약을 취소한다).
/// - 작업 토큰([beginOperation]/[isCurrent]): 사람 입력·끄기가 진행 중 작업을 무효화한다.
/// - 연결 식별([sameConnection]): 재연결된 세션에 이전 작업의 키를 보내지 않는다.
/// - 주입 표시([inject]): 우리가 보낸 입력을 사용자 입력으로 오인하지 않는다.
abstract interface class AutopilotRuntime {
  AutopilotTiming get timing;

  // --- 세션 상태 ------------------------------------------------------------

  /// 세션 상태. 켠 적이 없으면 null.
  AutopilotState? stateAt(String id);

  /// 세션 상태. 없으면 기본값.
  AutopilotState stateOf(String id);

  void setState(String id, AutopilotState next);

  // --- 타이머·작업 토큰 ------------------------------------------------------

  /// [delay] 뒤 [action]을 실행한다. 이 세션의 이전 예약은 취소한다.
  void schedule(String id, Duration delay, void Function() action);

  /// 이 세션에 예약된 타이머가 있는지.
  bool hasTimer(String id);

  /// [delay] 뒤 승인·한도 확인(안정화 직후 판단)을 다시 예약한다.
  void scheduleSettledCheck(String id, Duration delay);

  /// 새 작업을 시작하고 그 토큰을 돌려준다. 이전 작업 토큰은 무효가 된다.
  Object beginOperation(String id);

  /// [operation]이 아직 이 세션의 현재 작업이고 세션이 켜져 있는지.
  bool isCurrent(String id, Object operation);

  Future<void> sleep(Duration duration);

  // --- 세션 입출력 -----------------------------------------------------------

  SessionPort? portOf(String id);

  /// [port]가 연결돼 있고 [identity]를 잡을 때와 같은 연결인지.
  bool sameConnection(SessionPort port, Object identity);

  /// 지금 화면·제목에서 판별한 CLI. 없으면 켤 때 기록한 CLI.
  AgentCli? liveCli(String id, AutopilotState current);

  /// 사용자 입력으로 오인하지 않도록 표시한 채 [send]를 실행한다.
  void inject(String id, void Function() send);

  // --- 앱 서비스 -------------------------------------------------------------

  /// 판정 LLM(앱 AI 설정)이 준비됐는지.
  bool get aiConfigured;

  /// 세션 출력이 진행 중인지(활동 추적기).
  bool isBusy(String id);

  /// 우리가 새 작업을 제출했음을 활동 추적기에 알린다.
  void markTaskSubmitted(String id);

  /// 마지막 busy→idle 전이 시각.
  DateTime? idleSince(String id);

  /// 사용자가 마지막으로 키를 친 시각.
  DateTime? lastUserInputAt(String id);

  /// Agent Chat 루프가 이 세션을 관찰 중인지.
  bool observedByAgentChat(String id);

  SessionAttention? attentionOf(String id);

  /// 이 컨트롤러 이름으로 "Agent 확인 필요" 표시를 올린다.
  void raiseBlock(
    String id, {
    required String message,
    required String agentHint,
  });

  /// 이 컨트롤러가 올린 "Agent 확인 필요" 표시만 내린다.
  void clearBlock(String id);

  /// 알림 설정·세션 음소거를 따라 사람에게 알린다.
  Future<void> notify(String id, String title, String body);

  /// 세션 진단 기록에 남긴다.
  void record(String id, String message);
}
