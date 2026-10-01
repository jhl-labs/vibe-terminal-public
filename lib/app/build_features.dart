import 'package:flutter/foundation.dart';

/// 공개판은 기존 UI를 유지하며 지정된 사이드 앱만 소스에서 제외한다.
/// 제외된 앱은 빌드 모드나 환경 플래그로 다시 활성화할 수 없다.
class BuildFeatures {
  const BuildFeatures({
    this.snippets = true,
    this.aiChat = true,
    this.sftp = true,
    this.memo = true,
    this.claudeSettings = true,
    this.codexSettings = true,
    this.opencodeSettings = true,
    this.vault = true,
    this.portForward = true,
    this.browser = true,
    this.customApps = true,
    this.community = true,
    this.logs = true,
    this.x11 = true,
    this.externalControl = false,
    this.localBackgroundSessions = false,
    this.settingsTerminal = true,
    this.settingsInteraction = true,
    this.settingsShortcut = true,
    this.settingsNotifications = true,
    this.settingsX11 = true,
    this.updateCheck = false,
    bool? settingsGithub,
    bool? github,
    this.settingsAi = true,
    this.settingsAbout = true,
    this.telemetry = false,
  }) : settingsGithub = settingsGithub ?? github ?? true;

  static const current = BuildFeatures(
    // 공개판은 GitHub Release로 배포하므로 업데이트 확인을 항상 켠다.
    updateCheck: true,
    vault: false,
    browser: false,
    customApps: false,
    sftp: false,
    portForward: false,
    x11: false,
    settingsX11: false,
    // 공개판(Core)은 원격 텔레메트리를 포함하지 않는다.
    telemetry: false,
  );

  final bool snippets;
  final bool aiChat;
  final bool sftp;
  final bool memo;
  final bool claudeSettings;
  final bool codexSettings;
  final bool opencodeSettings;
  final bool vault;
  final bool portForward;
  final bool browser;
  final bool customApps;
  final bool community;
  final bool logs;
  final bool x11;

  /// 공개 빌드에서는 숨기며 내부 개발 빌드에서만 명시적으로 활성화한다.
  final bool externalControl;

  /// 로컬 데몬 동작과 별도로 작업 관리 화면의 노출만 결정한다.
  final bool localBackgroundSessions;
  final bool settingsTerminal;
  final bool settingsInteraction;
  final bool settingsShortcut;
  final bool settingsNotifications;
  final bool settingsX11;
  final bool settingsGithub;

  /// 시작할 때 GitHub Release에서 새 버전을 확인할지 여부.
  ///
  /// 다른 플래그와 달리 디버그에서도 기본값이 꺼짐이다. 이 기능은 공개
  /// 배포판(GitHub Release로 내보내는 빌드)에서만 의미가 있고, 사설 PRO
  /// 배포판은 스토어와 라이선스 키로 업데이트를 받기 때문이다
  /// (`docs/11-pro-distribution-and-licensing.md`). 개발 중에 매번 공개
  /// 저장소를 조회하는 것도 잡음이다.
  final bool updateCheck;
  final bool settingsAi;
  final bool settingsAbout;

  /// Crashlytics·Analytics·푸시 등 텔레메트리 기능 노출 여부. 공개판(Core)은
  /// 항상 꺼져 있으며, 모바일 Pro 빌드만 `build-env`에서 명시적으로 켠다.
  final bool telemetry;

  bool get github => settingsGithub;

  /// 값이 지정되지 않은 플래그의 기본값. 릴리즈에서는 끈다.
  @visibleForTesting
  static bool defaultWhenUnset({required bool releaseMode}) => !releaseMode;

  /// `true/1/yes/on/enable(d)`만 켬으로 본다. 그 밖의 값은 모두 끔이다.
  @visibleForTesting
  static bool isEnabled(String value) {
    switch (value.trim().toLowerCase()) {
      case 'enable':
      case 'enabled':
      case 'true':
      case '1':
      case 'yes':
      case 'on':
        return true;
      default:
        return false;
    }
  }
}
