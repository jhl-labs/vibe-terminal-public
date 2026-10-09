import '../settings/app_settings.dart';

/// 기기 사이에 맞추는 설정 항목. 패널 폭, X 서버, 동기화 설정, 프록시,
/// 실행 파일 경로, 텔레메트리, 도구 배치, 보조 키바, 단축키, 폰트(설치 폰트에
/// 의존)는 기기마다 다르므로 넣지 않는다. 토큰 같은 비밀값도 넣지 않는다.
abstract final class SyncedSettings {
  static const _topLevelKeys = [
    'terminalTheme',
    'terminalFontSize',
    'terminalLineHeight',
    'terminalScrollbackLines',
    'copyOnSelection',
    'rightClickPaste',
    'confirmMultilinePaste',
    'ctrlCBehavior',
    'notifications',
    'snippetGistId',
  ];

  static const _aiKeys = [
    'provider',
    'baseUrl',
    'model',
    'customPrompt',
    'maxContextLines',
    'maxLogContextLines',
    'chatFontSize',
  ];

  /// `AppSettings.toJson()` 형태의 맵에서 동기화 항목만 고른다.
  static Map<String, Object?> pick(Map<String, Object?> settingsJson) {
    final ai = settingsJson['ai'];
    return {
      for (final key in _topLevelKeys)
        if (settingsJson.containsKey(key)) key: settingsJson[key],
      if (ai is Map)
        'ai': {
          for (final key in _aiKeys)
            if (ai.containsKey(key)) key: ai[key],
        },
    };
  }

  static Map<String, Object?> extract(AppSettings settings) =>
      pick(settings.toJson());

  /// [values]에 있는 항목만 [local]에 덮어쓴다. 없는 항목과 비밀값은 그대로 둔다.
  static AppSettings applyTo(AppSettings local, Map<String, Object?> values) {
    final remote = AppSettings.fromJson(values);
    bool has(String key) => values.containsKey(key);
    final aiValues = values['ai'] is Map
        ? Map<String, Object?>.from(values['ai'] as Map)
        : const <String, Object?>{};
    final remoteAi = AiSettings.fromJson(aiValues);
    bool hasAi(String key) => aiValues.containsKey(key);
    return local.copyWith(
      terminalTheme: has('terminalTheme') ? remote.terminalTheme : null,
      terminalFontSize: has('terminalFontSize')
          ? remote.terminalFontSize
          : null,
      terminalLineHeight: has('terminalLineHeight')
          ? remote.terminalLineHeight
          : null,
      terminalScrollbackLines: has('terminalScrollbackLines')
          ? remote.terminalScrollbackLines
          : null,
      copyOnSelection: has('copyOnSelection') ? remote.copyOnSelection : null,
      rightClickPaste: has('rightClickPaste') ? remote.rightClickPaste : null,
      confirmMultilinePaste: has('confirmMultilinePaste')
          ? remote.confirmMultilinePaste
          : null,
      ctrlCBehavior: has('ctrlCBehavior') ? remote.ctrlCBehavior : null,
      notifications: has('notifications') ? remote.notifications : null,
      snippetGistId: has('snippetGistId') ? remote.snippetGistId : null,
      ai: local.ai.copyWith(
        provider: hasAi('provider') ? remoteAi.provider : null,
        baseUrl: hasAi('baseUrl') ? remoteAi.baseUrl : null,
        model: hasAi('model') ? remoteAi.model : null,
        customPrompt: hasAi('customPrompt') ? remoteAi.customPrompt : null,
        maxContextLines: hasAi('maxContextLines')
            ? remoteAi.maxContextLines
            : null,
        maxLogContextLines: hasAi('maxLogContextLines')
            ? remoteAi.maxLogContextLines
            : null,
        chatFontSize: hasAi('chatFontSize') ? remoteAi.chatFontSize : null,
      ),
    );
  }
}
