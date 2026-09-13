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
    this.community = true,
    this.logs = true,
    this.x11 = true,
    this.settingsTerminal = true,
    this.settingsInteraction = true,
    this.settingsShortcut = true,
    this.settingsNotifications = true,
    this.settingsX11 = true,
    bool? settingsGithub,
    bool? github,
    this.settingsAi = true,
    this.settingsAbout = true,
  }) : settingsGithub = settingsGithub ?? github ?? true;

  static const current = BuildFeatures(
    vault: false,
    browser: false,
    sftp: false,
    portForward: false,
    x11: false,
    settingsX11: false,
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
  final bool community;
  final bool logs;
  final bool x11;
  final bool settingsTerminal;
  final bool settingsInteraction;
  final bool settingsShortcut;
  final bool settingsNotifications;
  final bool settingsX11;
  final bool settingsGithub;
  final bool settingsAi;
  final bool settingsAbout;

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
