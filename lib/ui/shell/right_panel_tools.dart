import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../app/build_features.dart';
import '../../cli_config/cli_config_home.dart';
import '../../state/providers.dart';
import 'cli_config_panel.dart' show appIconFor;

/// 빌드 피처만으로 정해지는 우측 패널 도구 전체 목록. 설치 여부나 사용자가
/// 숨긴 항목과 무관하게, "이 빌드에서 켤 수 있는 도구가 무엇인가"를 답한다.
/// 설정 화면의 표시/숨김 체크리스트와 앱 셸의 실제 노출 목록이 같은 순서·
/// 조건을 쓰도록 한곳에 모아 둔다.
List<RightPanelTool> allRightPanelToolsForBuild(BuildFeatures features) {
  final isMobilePlatform = Platform.isAndroid || Platform.isIOS;
  return [
    // 분할 배치·칸 조작은 모든 빌드의 기본 도구라 항상 맨 앞.
    RightPanelTool.paneLayout,
    if (features.snippets) RightPanelTool.snippets,
    // 세션 정보는 스니펫 패널에 딸려 있던 탭이었다. 별도 도구로 분리했지만
    // 여전히 snippets 빌드 플래그를 공유한다(새 define을 추가하면
    // build-env·PRO_EDITION·public-release feature-map까지 다 건드려야
    // 해서, 원래 같이 묶여 있던 기능이라는 점을 근거로 재사용한다).
    if (features.snippets) RightPanelTool.sessionInfo,
    if (features.aiChat) RightPanelTool.aiChat,
    if (features.memo) RightPanelTool.memo,
    // 설치 여부와 무관하게 항상 후보에 포함한다. 미설치 상태는 CliConfigPanel
    // 안에서 안내한다 — 설치 감지는 로컬 PATH 기준이라 WSL 전용 설치를 놓칠
    // 수 있으므로, 감지 실패로 도구 자체를 숨기지 않는다.
    // CLI 전역 설정은 이 기기의 HOME·PATH를 읽으므로 모바일에서는 항상
    // "홈 없음/미설치"만 보인다. X11처럼 데스크톱에서만 노출한다.
    if (features.claudeSettings && !isMobilePlatform)
      RightPanelTool.claudeSettings,
    if (features.codexSettings && !isMobilePlatform)
      RightPanelTool.codexSettings,
    if (features.opencodeSettings && !isMobilePlatform)
      RightPanelTool.opencodeSettings,
    if (features.community && features.github) RightPanelTool.community,
    if (features.logs) RightPanelTool.logs,
  ];
}

/// [order]에 있는 도구를 그 순서대로 앞에 놓고, 없는 도구는 [candidates]의
/// 원래(빌드) 순서 그대로 뒤에 붙인다. [order]에만 있고 이번 빌드에 없는
/// 도구 이름은 조용히 무시한다.
List<RightPanelTool> applyRightPanelToolOrder(
  List<RightPanelTool> candidates,
  List<String> order,
) {
  final byName = {for (final t in candidates) t.name: t};
  final seen = <String>{};
  final result = <RightPanelTool>[];
  for (final name in order) {
    final tool = byName[name];
    if (tool != null && seen.add(name)) result.add(tool);
  }
  for (final tool in candidates) {
    if (seen.add(tool.name)) result.add(tool);
  }
  return result;
}

IconData rightPanelToolIcon(RightPanelTool tool) {
  return switch (tool) {
    RightPanelTool.paneLayout => Icons.dashboard_customize_outlined,
    RightPanelTool.snippets => Icons.code,
    RightPanelTool.sessionInfo => Icons.info_outline,
    RightPanelTool.aiChat => Icons.auto_awesome,
    RightPanelTool.memo => Icons.sticky_note_2_outlined,
    RightPanelTool.claudeSettings => appIconFor(CliConfigApp.claude),
    RightPanelTool.codexSettings => appIconFor(CliConfigApp.codex),
    RightPanelTool.opencodeSettings => appIconFor(CliConfigApp.opencode),
    RightPanelTool.community => Icons.groups_2_outlined,
    RightPanelTool.logs => Icons.receipt_long_outlined,
  };
}

/// 도구 이름. Pro 전용 앱(PRO_EDITION.md)은 `(PRO)`를 붙여 툴팁·명령 팔레트·
/// 모바일 도구 메뉴·설정 화면에서 바로 구분되게 한다.
String rightPanelToolLabel(RightPanelTool tool) {
  return switch (tool) {
    RightPanelTool.paneLayout => '화면 분할 관리',
    RightPanelTool.snippets => '스니펫',
    RightPanelTool.sessionInfo => '세션 정보',
    RightPanelTool.aiChat => 'AI Chat',
    RightPanelTool.memo => '메모',
    RightPanelTool.claudeSettings => 'Claude Settings',
    RightPanelTool.codexSettings => 'Codex Settings',
    RightPanelTool.opencodeSettings => 'OpenCode Settings',
    RightPanelTool.community => 'Community',
    RightPanelTool.logs => '로그',
  };
}
