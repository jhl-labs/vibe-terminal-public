import 'agent_session_role.dart';

/// 지시문에서 작업 종류(capability)를 규칙으로 추정한다.
///
/// CLI·모델에 비특화이며 한국어·영어 표현을 함께 본다. 확신이 없으면 null을
/// 돌려주고, 호출자는 null을 "허용"으로 다룬다(설계 §8: false negative 우선).
class AgentCapabilityClassifier {
  const AgentCapabilityClassifier._();

  /// git 작업. 커밋·푸시처럼 되돌리기 어려운 동작이 여기에 들어간다.
  static final List<RegExp> _git = [
    RegExp(
      r'\bgit\s+(add|commit|push|pull|rebase|merge|reset|checkout|tag|stash)\b',
      caseSensitive: false,
    ),
    RegExp(r'커밋'),
    RegExp(r'푸시'),
    RegExp(r'\bcommit\b', caseSensitive: false),
    RegExp(r'\bpush\s+to\b', caseSensitive: false),
  ];

  /// 테스트 실행.
  static final List<RegExp> _runTests = [
    RegExp(
      r'\b(flutter|dart|go|cargo|npm|yarn|make)\s+test\b',
      caseSensitive: false,
    ),
    RegExp(r'\bpytest\b', caseSensitive: false),
    RegExp(r'테스트(를)?\s*(실행|돌려)'),
  ];

  /// 리뷰·검토.
  static final List<RegExp> _review = [
    RegExp(r'\bcode\s+review\b', caseSensitive: false),
    RegExp(r'\breview\b', caseSensitive: false),
    RegExp(r'\baudit\b', caseSensitive: false),
    RegExp(r'리뷰'),
    RegExp(r'검토'),
  ];

  /// 설계·계획·설계 검증.
  static final List<RegExp> _design = [
    RegExp(r'\bdesign\b', caseSensitive: false),
    RegExp(r'\bspec\b', caseSensitive: false),
    RegExp(r'\barchitecture\b', caseSensitive: false),
    RegExp(r'\bverify\s+(the\s+)?design\b', caseSensitive: false),
    RegExp(r'\bdesign\s+review\b', caseSensitive: false),
    RegExp(r'설계'),
    RegExp(r'계획서'),
    // "검증해"만으로는 설계 검증인지 알 수 없다. 설계와 가까이 붙은 경우만 본다.
    RegExp(r'설계.{0,6}검증|검증.{0,6}설계'),
  ];

  /// 구현·수정.
  static final List<RegExp> _implement = [
    RegExp(r'\bimplement\b', caseSensitive: false),
    RegExp(r'\brefactor\b', caseSensitive: false),
    RegExp(r'\bfix\s+(the\s+)?bug\b', caseSensitive: false),
    RegExp(
      r'\badd\b.*\b(function|class|method|widget)\b',
      caseSensitive: false,
    ),
    RegExp(r'구현'),
    // "보고서 작성해"까지 구현으로 보지 않도록 코드·구현 문맥만 잡는다.
    RegExp(r'코드.{0,6}작성|구현.{0,6}작성'),
    RegExp(r'\bwrite\s+(the\s+)?code\b', caseSensitive: false),
    RegExp(r'수정해'),
    RegExp(r'리팩터'),
    RegExp(r'버그\s*(수정|고쳐)'),
  ];

  /// 우선순위: git > run_tests > review > design > implement.
  ///
  /// "구현하고 커밋해"처럼 여러 개가 걸리면 더 엄격한 쪽(git)으로 판정한다.
  static AgentCapability? classify(String prompt) {
    final text = prompt.trim();
    if (text.isEmpty) return null;
    if (_matches(_git, text)) return AgentCapability.git;
    if (_matches(_runTests, text)) return AgentCapability.runTests;
    if (_matches(_review, text)) return AgentCapability.review;
    if (_matches(_design, text)) return AgentCapability.design;
    if (_matches(_implement, text)) return AgentCapability.implement;
    return null;
  }

  static bool _matches(List<RegExp> patterns, String text) =>
      patterns.any((pattern) => pattern.hasMatch(text));
}
