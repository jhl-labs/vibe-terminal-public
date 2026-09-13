import 'package:flutter/material.dart';

/// 보조키바·터미널 헤더의 커스터마이징 항목 카탈로그.
///
/// 각 항목은 문자열 토큰으로 저장된다. 미리 정의된 액션은 짧은 id,
/// 사용자 정의 키는 `text:<문자열>` 형태다. 실제 동작 분기(키 전송/문자 전송/
/// 특수 처리)는 각 바의 렌더러가 id로 수행하며, 이 카탈로그는 표시 메타데이터만
/// 제공한다.

/// 사용자 정의 텍스트 토큰 prefix.
const String kTextTokenPrefix = 'text:';

/// 카탈로그 한 항목의 표시 메타데이터.
class ActionDef {
  const ActionDef({
    required this.id,
    required this.label,
    this.buttonText,
    this.icon,
  });

  /// 저장 토큰이자 렌더러의 동작 분기 키.
  final String id;

  /// 편집 화면에서 보여줄 사람이 읽는 이름.
  final String label;

  /// 바 버튼에 표시할 짧은 텍스트. null이면 [icon]을 쓴다.
  final String? buttonText;

  /// 버튼 아이콘. [buttonText]가 있으면 무시된다.
  final IconData? icon;
}

/// 보조키바 후보 액션들. 키보드 토글은 첫칸 고정이라 카탈로그에 포함하지 않는다.
const List<ActionDef> kExtraKeysCatalog = [
  ActionDef(id: 'paste', label: '붙여넣기', icon: Icons.content_paste),
  ActionDef(id: 'image', label: '이미지 붙여넣기', icon: Icons.image_outlined),
  ActionDef(id: 'esc', label: 'Esc', buttonText: 'Esc'),
  ActionDef(id: 'tab', label: 'Tab', buttonText: 'Tab'),
  ActionDef(id: 'ctrl', label: 'Ctrl (sticky)', buttonText: 'Ctrl'),
  ActionDef(id: 'left', label: '왼쪽 화살표', buttonText: '←'),
  ActionDef(id: 'down', label: '아래 화살표', buttonText: '↓'),
  ActionDef(id: 'up', label: '위 화살표', buttonText: '↑'),
  ActionDef(id: 'right', label: '오른쪽 화살표', buttonText: '→'),
  ActionDef(id: 'enter', label: 'Enter', buttonText: '⏎'),
  ActionDef(id: 'slash', label: '슬래시 /', buttonText: '/'),
  ActionDef(id: 'minus', label: '하이픈 -', buttonText: '-'),
  ActionDef(id: 'pipe', label: '파이프 |', buttonText: '|'),
  ActionDef(id: 'tilde', label: '틸드 ~', buttonText: '~'),
  ActionDef(id: 'star', label: '별표 *', buttonText: '*'),
  ActionDef(id: 'home', label: 'Home', buttonText: 'Home'),
  ActionDef(id: 'end', label: 'End', buttonText: 'End'),
  ActionDef(id: 'pageUp', label: 'PageUp', buttonText: 'PgUp'),
  ActionDef(id: 'pageDown', label: 'PageDown', buttonText: 'PgDn'),
  ActionDef(id: 'ctrlC', label: 'Ctrl+C', buttonText: '^C'),
  ActionDef(id: 'ctrlD', label: 'Ctrl+D', buttonText: '^D'),
  ActionDef(id: 'ctrlL', label: 'Ctrl+L', buttonText: '^L'),
  ActionDef(id: 'ctrlZ', label: 'Ctrl+Z', buttonText: '^Z'),
];

/// 터미널 헤더 후보 액션들.
const List<ActionDef> kTerminalHeaderCatalog = [
  ActionDef(id: 'sessionPrev', label: '이전 세션', icon: Icons.keyboard_arrow_up),
  ActionDef(id: 'sessionNext', label: '다음 세션', icon: Icons.keyboard_arrow_down),
  ActionDef(id: 'retry', label: '다시 연결', icon: Icons.refresh),
  ActionDef(id: 'zoomOut', label: '축소', icon: Icons.remove),
  ActionDef(id: 'zoomIn', label: '확대', icon: Icons.add),
  ActionDef(id: 'zoomReset', label: '줌 초기화', icon: Icons.center_focus_strong),
  ActionDef(id: 'repaint', label: '다시 그리기', icon: Icons.replay),
];

ActionDef? _lookup(List<ActionDef> catalog, String id) {
  for (final def in catalog) {
    if (def.id == id) return def;
  }
  return null;
}

/// 보조키바 토큰을 표시 메타로 변환한다. `text:` 토큰은 사용자 정의 라벨로
/// 동적 생성하고, 알 수 없는 토큰은 null을 반환한다.
ActionDef? resolveExtraKeyToken(String token) {
  if (token.startsWith(kTextTokenPrefix)) {
    final text = token.substring(kTextTokenPrefix.length);
    if (text.isEmpty) return null;
    return ActionDef(id: token, label: '"$text"', buttonText: text);
  }
  return _lookup(kExtraKeysCatalog, token);
}

/// 헤더 토큰을 표시 메타로 변환한다(헤더는 사용자 정의 미지원).
ActionDef? resolveHeaderToken(String token) =>
    _lookup(kTerminalHeaderCatalog, token);

/// `text:` 사용자 정의 토큰을 만든다.
String makeTextToken(String text) => '$kTextTokenPrefix$text';

/// 사용자 정의 토큰이면 원문 텍스트를, 아니면 null을 반환한다.
String? textTokenValue(String token) => token.startsWith(kTextTokenPrefix)
    ? token.substring(kTextTokenPrefix.length)
    : null;
