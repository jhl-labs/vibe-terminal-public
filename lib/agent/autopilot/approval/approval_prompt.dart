/// Agent가 묻는 권한 요청의 종류. 정책이 종류별로 다르게 판단한다.
enum ApprovalKind { command, fileEdit, fileRead, network, other }

/// "이번만 Yes"를 고르기 위해 세션에 보낼 입력.
///
/// 숫자·문자 단축키를 쓰는 CLI는 [text], 선택 표시가 이미 그 항목에 있어
/// Enter로 확정하는 CLI는 [pressEnter].
class ApprovalAnswer {
  const ApprovalAnswer.text(String this.text);
  const ApprovalAnswer.enter() : text = null;

  final String? text;
  bool get pressEnter => text == null;

  @override
  String toString() => pressEnter ? '<Enter>' : text!;
}

/// 화면에서 해석한 권한 요청 하나.
class ApprovalPrompt {
  const ApprovalPrompt({
    required this.kind,
    required this.subject,
    required this.answer,
    required this.fingerprint,
  });

  final ApprovalKind kind;

  /// 승인 대상 원문(명령줄·경로·URL). 테두리 문자를 벗기고 여러 줄을 공백 하나로 합친 값.
  final String subject;
  final ApprovalAnswer answer;

  /// 같은 프롬프트인지 재확인할 때 비교하는 값(질문 줄 + subject).
  final String fingerprint;
}
