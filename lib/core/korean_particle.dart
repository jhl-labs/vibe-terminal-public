/// 한국어 조사 선택 도우미.
///
/// 사용자에게 보여 주는 문장에 변수를 끼울 때 "design을/를" 같은 어색한 표기가
/// 남지 않도록, 앞 단어의 받침을 보고 조사를 고른다.
library;

/// 목적격 조사(을/를)를 붙인 `단어+조사`를 돌려준다.
///
/// 마지막 글자가 한글 음절이면 받침 유무로 을/를을 고르고, 영문·숫자처럼
/// 읽는 방법이 사람마다 다른 단어에는 `을(를)`을 쓴다. 예) `design을(를)`,
/// `구현을`, `리뷰를`.
String withObjectParticle(String word) {
  final trimmed = word.trimRight();
  if (trimmed.isEmpty) return word;
  final last = trimmed.codeUnitAt(trimmed.length - 1);
  // 한글 음절 영역(가~힣)이 아니면 읽는 소리를 알 수 없다.
  if (last < 0xAC00 || last > 0xD7A3) return '$word을(를)';
  // 음절 = ((초성 * 21) + 중성) * 28 + 종성. 나머지가 0이면 받침이 없다.
  final hasFinalConsonant = (last - 0xAC00) % 28 != 0;
  return '$word${hasFinalConsonant ? '을' : '를'}';
}
