/// 오케스트레이터 엔진이 세션을 관찰·조작하기 위한 추상 인터페이스.
///
/// 엔진이 SessionManager/TerminalEngine 구체 타입에 의존하지 않도록 하는
/// 의존성 역전 경계다. 프로덕션 구현은 SessionManager를 감싸고, 테스트는
/// 스크립트된 fake를 주입한다.
abstract interface class SessionPort {
  String get id;
  String get displayName;
  bool get isConnected;

  /// 같은 id라도 재접속/엔진 교체 시 달라지는 연결 식별자.
  /// 승인 및 본문 입력 시점의 대상을 제출 직전 다시 확인하는 데 쓴다.
  Object get connectionIdentity;

  /// SessionActivityTracker 기반 busy 여부(quiescence 보조 신호).
  bool get isBusy;

  /// 최근 화면 텍스트(마지막 줄이 현재 상태일 확률이 가장 높다).
  String readScreen({int maxLines});

  /// 정규화된 입력(키 토큰 디코드 완료)을 세션에 전송한다.
  void sendText(String normalizedInput);

  /// 실제 Enter 키 입력 경로로 현재 입력을 제출한다.
  void submit();
}

/// 현재 열린 세션 집합의 스냅샷 제공자.
abstract interface class SessionPortRegistry {
  /// 지금 존재하는 모든 세션 포트.
  List<SessionPort> sessions();

  /// id로 세션 포트를 찾는다. 없으면 null.
  SessionPort? byId(String id);
}
