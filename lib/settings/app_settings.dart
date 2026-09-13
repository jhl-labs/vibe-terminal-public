import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../app/theme.dart';

enum TerminalThemePreset {
  vibeDark,
  termiusDark,
  puttyClassic,
  amberCrt;

  String get label => switch (this) {
    TerminalThemePreset.vibeDark => 'Vibe dark',
    TerminalThemePreset.termiusDark => 'Termius dark',
    TerminalThemePreset.puttyClassic => 'PuTTY classic',
    TerminalThemePreset.amberCrt => 'Amber CRT',
  };

  String get description => switch (this) {
    TerminalThemePreset.vibeDark => '현재 Vibe Terminal 기본 팔레트',
    TerminalThemePreset.termiusDark => '낮은 대비의 차분한 SSH 작업 테마',
    TerminalThemePreset.puttyClassic => '검정 배경과 밝은 기본 ANSI 색상',
    TerminalThemePreset.amberCrt => '긴 로그 확인에 맞춘 호박색 콘솔',
  };

  TerminalTheme get terminalTheme => switch (this) {
    TerminalThemePreset.vibeDark => kVibeTerminalTheme,
    TerminalThemePreset.termiusDark => const TerminalTheme(
      cursor: Color(0xFF70F0A4),
      selection: Color(0x6656778E),
      foreground: Color(0xFFE3E8EF),
      background: Color(0xFF0B1017),
      black: Color(0xFF0B1017),
      red: Color(0xFFFF6E78),
      green: Color(0xFF70F0A4),
      yellow: Color(0xFFFFD166),
      blue: Color(0xFF82AAFF),
      magenta: Color(0xFFC792EA),
      cyan: Color(0xFF63E6E2),
      white: Color(0xFFE3E8EF),
      brightBlack: Color(0xFF546170),
      brightRed: Color(0xFFFF8E94),
      brightGreen: Color(0xFF93F5BC),
      brightYellow: Color(0xFFFFDC8A),
      brightBlue: Color(0xFFA4BFFF),
      brightMagenta: Color(0xFFD6A8F5),
      brightCyan: Color(0xFF8AF2EF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xAA6D5A1D),
      searchHitBackgroundCurrent: Color(0xFFFFD166),
      searchHitForeground: Color(0xFF0B1017),
    ),
    TerminalThemePreset.puttyClassic => const TerminalTheme(
      cursor: Color(0xFFFFFFFF),
      selection: Color(0x666E8FB8),
      foreground: Color(0xFFE6E6E6),
      background: Color(0xFF000000),
      black: Color(0xFF000000),
      red: Color(0xFFBB0000),
      green: Color(0xFF00BB00),
      yellow: Color(0xFFBBBB00),
      blue: Color(0xFF0000BB),
      magenta: Color(0xFFBB00BB),
      cyan: Color(0xFF00BBBB),
      white: Color(0xFFBBBBBB),
      brightBlack: Color(0xFF555555),
      brightRed: Color(0xFFFF5555),
      brightGreen: Color(0xFF55FF55),
      brightYellow: Color(0xFFFFFF55),
      brightBlue: Color(0xFF5555FF),
      brightMagenta: Color(0xFFFF55FF),
      brightCyan: Color(0xFF55FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xAA6D5A1D),
      searchHitBackgroundCurrent: Color(0xFFFFFF55),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalThemePreset.amberCrt => const TerminalTheme(
      cursor: Color(0xFFFFC15A),
      selection: Color(0x665F4B24),
      foreground: Color(0xFFFFCB72),
      background: Color(0xFF120D05),
      black: Color(0xFF120D05),
      red: Color(0xFFFF6A4D),
      green: Color(0xFFA7D46F),
      yellow: Color(0xFFFFC15A),
      blue: Color(0xFF76A7FF),
      magenta: Color(0xFFD988FF),
      cyan: Color(0xFF6DD7D0),
      white: Color(0xFFFFE3AD),
      brightBlack: Color(0xFF7A643F),
      brightRed: Color(0xFFFF8F78),
      brightGreen: Color(0xFFC9EA8F),
      brightYellow: Color(0xFFFFD88D),
      brightBlue: Color(0xFFA2C2FF),
      brightMagenta: Color(0xFFE3A8FF),
      brightCyan: Color(0xFF95E8E3),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xAA795B13),
      searchHitBackgroundCurrent: Color(0xFFFFC15A),
      searchHitForeground: Color(0xFF120D05),
    ),
  };
}

enum CtrlCBehavior {
  interruptOnly,
  copySelection;

  String get label => switch (this) {
    CtrlCBehavior.interruptOnly => '항상 인터럽트',
    CtrlCBehavior.copySelection => '선택 시 복사',
  };

  String get description => switch (this) {
    CtrlCBehavior.interruptOnly => 'Ctrl+C는 항상 원격 프로세스에 보냅니다.',
    CtrlCBehavior.copySelection => '선택 영역이 있으면 복사하고, 없으면 인터럽트로 보냅니다.',
  };
}

enum AiProviderType {
  openai,
  gemini,
  claude,
  openAiCompatible;

  String get label => switch (this) {
    AiProviderType.openai => 'OpenAI',
    AiProviderType.gemini => 'Gemini',
    AiProviderType.claude => 'Claude',
    AiProviderType.openAiCompatible => 'OpenAI compatible',
  };

  String get description => switch (this) {
    AiProviderType.openai => 'OpenAI Chat Completions API',
    AiProviderType.gemini => 'Google Gemini generateContent API',
    AiProviderType.claude => 'Anthropic Messages API',
    AiProviderType.openAiCompatible => '로컬 LLM, 사내 게이트웨이, 호환 프록시',
  };

  String get defaultModel => switch (this) {
    AiProviderType.openai => 'gpt-4.1-mini',
    AiProviderType.gemini => 'gemini-2.5-flash',
    AiProviderType.claude => 'claude-sonnet-4-5',
    AiProviderType.openAiCompatible => 'gpt-4.1-mini',
  };

  String get defaultBaseUrl => switch (this) {
    AiProviderType.openAiCompatible => 'https://api.openai.com/v1',
    _ => '',
  };

  bool get needsBaseUrl => this == AiProviderType.openAiCompatible;

  bool get requiresApiToken => this != AiProviderType.openAiCompatible;
}

class AiSettings {
  const AiSettings({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiToken,
    required this.customHeaders,
    required this.httpProxy,
    required this.httpsProxy,
    required this.customPrompt,
    required this.maxContextLines,
    required this.chatFontFamily,
    required this.chatFontSize,
  });

  static const apiTokenSecretRef = 'vibe_terminal.ai.api_token';
  static const customHeadersSecretRef = 'vibe_terminal.ai.custom_headers';
  static const minContextLines = 50;
  static const maxContextLineLimit = 500;
  static const minChatFontSize = 10.0;
  static const maxChatFontSize = 20.0;

  final AiProviderType provider;
  final String baseUrl;
  final String model;
  final String apiToken;
  final String customHeaders;
  final String httpProxy;
  final String httpsProxy;
  final String customPrompt;
  final int maxContextLines;
  final String chatFontFamily;
  final double chatFontSize;

  static const defaultSettings = AiSettings(
    provider: AiProviderType.openai,
    baseUrl: '',
    model: 'gpt-4.1-mini',
    apiToken: '',
    customHeaders: '',
    httpProxy: '',
    httpsProxy: '',
    customPrompt: '',
    maxContextLines: maxContextLineLimit,
    chatFontFamily: kMonoFontFamily,
    chatFontSize: 13,
  );

  List<String> get fontFallback => [
    for (final font in kMonoFontFallback)
      if (font != chatFontFamily) font,
  ];

  bool get isConfigured {
    if (model.trim().isEmpty) return false;
    if (provider.requiresApiToken && apiToken.trim().isEmpty) return false;
    if (provider.needsBaseUrl && baseUrl.trim().isEmpty) return false;
    return true;
  }

  AiSettings copyWith({
    AiProviderType? provider,
    String? baseUrl,
    String? model,
    String? apiToken,
    String? customHeaders,
    String? httpProxy,
    String? httpsProxy,
    String? customPrompt,
    int? maxContextLines,
    String? chatFontFamily,
    double? chatFontSize,
  }) {
    final nextProvider = provider ?? this.provider;
    return AiSettings(
      provider: nextProvider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiToken: apiToken ?? this.apiToken,
      customHeaders: customHeaders ?? this.customHeaders,
      httpProxy: httpProxy ?? this.httpProxy,
      httpsProxy: httpsProxy ?? this.httpsProxy,
      customPrompt: customPrompt ?? this.customPrompt,
      maxContextLines: (maxContextLines ?? this.maxContextLines)
          .clamp(minContextLines, maxContextLineLimit)
          .toInt(),
      chatFontFamily: chatFontFamily ?? this.chatFontFamily,
      chatFontSize: (chatFontSize ?? this.chatFontSize).clamp(
        minChatFontSize,
        maxChatFontSize,
      ),
    );
  }

  AiSettings withProviderDefaults(AiProviderType nextProvider) => copyWith(
    provider: nextProvider,
    baseUrl: nextProvider.defaultBaseUrl,
    model: nextProvider.defaultModel,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'baseUrl': baseUrl,
    'model': model,
    'httpProxy': httpProxy,
    'httpsProxy': httpsProxy,
    'customPrompt': customPrompt,
    'maxContextLines': maxContextLines,
    'chatFontFamily': chatFontFamily,
    'chatFontSize': chatFontSize,
  };

  factory AiSettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return AiSettings.defaultSettings;

    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    final defaults = AiSettings.defaultSettings;
    final provider = enumValue(
      AiProviderType.values,
      json['provider'] as String?,
      defaults.provider,
    );
    return defaults
        .withProviderDefaults(provider)
        .copyWith(
          baseUrl: json['baseUrl'] as String?,
          model: json['model'] as String?,
          customHeaders: json['customHeaders'] as String?,
          httpProxy: json['httpProxy'] as String?,
          httpsProxy: json['httpsProxy'] as String?,
          customPrompt: json['customPrompt'] as String?,
          maxContextLines: (json['maxContextLines'] as num?)?.round(),
          chatFontFamily: json['chatFontFamily'] as String?,
          chatFontSize: (json['chatFontSize'] as num?)?.toDouble(),
        );
  }
}

enum CloudSyncProviderType {
  github,
  googleDrive,
  iCloud;

  String get label => switch (this) {
    CloudSyncProviderType.github => 'GitHub',
    CloudSyncProviderType.googleDrive => 'Google Drive',
    CloudSyncProviderType.iCloud => 'Apple iCloud',
  };

  String get metricLabel => switch (this) {
    CloudSyncProviderType.github => 'API token usage',
    CloudSyncProviderType.googleDrive => 'Storage usage',
    CloudSyncProviderType.iCloud => 'iCloud storage',
  };

  bool get enabled => this == CloudSyncProviderType.github;
}

enum GitHubSyncHostType {
  githubDotCom,
  enterprise;

  String get label => switch (this) {
    GitHubSyncHostType.githubDotCom => 'GitHub.com',
    GitHubSyncHostType.enterprise => 'GitHub Enterprise',
  };
}

class GitHubSyncSettings {
  const GitHubSyncSettings({
    required this.hostType,
    required this.serverUrl,
    required this.appClientId,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.path,
    required this.token,
    required this.refreshToken,
    required this.tokenExpiresAt,
    required this.refreshTokenExpiresAt,
  });

  static const githubComServerUrl = 'https://github.com';
  static const githubComAppClientId = 'Iv23liLn58h7iXyuhKzi';

  static const defaultSettings = GitHubSyncSettings(
    hostType: GitHubSyncHostType.githubDotCom,
    serverUrl: githubComServerUrl,
    appClientId: '',
    owner: '',
    repo: '',
    branch: 'main',
    path: 'vibe-terminal/sync.enc.json',
    token: '',
    refreshToken: '',
    tokenExpiresAt: null,
    refreshTokenExpiresAt: null,
  );

  final GitHubSyncHostType hostType;
  final String serverUrl;
  final String appClientId;
  final String owner;
  final String repo;
  final String branch;
  final String path;
  final String token;
  final String refreshToken;
  final DateTime? tokenExpiresAt;
  final DateTime? refreshTokenExpiresAt;

  bool get isGitHubDotCom => hostType == GitHubSyncHostType.githubDotCom;

  String get effectiveServerUrl =>
      isGitHubDotCom ? githubComServerUrl : serverUrl.trim();

  String get effectiveAppClientId =>
      isGitHubDotCom ? githubComAppClientId : appClientId.trim();

  bool get targetConfigured =>
      effectiveServerUrl.isNotEmpty &&
      owner.trim().isNotEmpty &&
      repo.trim().isNotEmpty &&
      branch.trim().isNotEmpty &&
      path.trim().isNotEmpty;

  bool get isConfigured => targetConfigured && token.trim().isNotEmpty;

  bool get hasGitHubAppClient => effectiveAppClientId.isNotEmpty;

  GitHubSyncSettings copyWith({
    GitHubSyncHostType? hostType,
    String? serverUrl,
    String? appClientId,
    String? owner,
    String? repo,
    String? branch,
    String? path,
    String? token,
    String? refreshToken,
    Object? tokenExpiresAt = _unset,
    Object? refreshTokenExpiresAt = _unset,
  }) => GitHubSyncSettings(
    hostType: hostType ?? this.hostType,
    serverUrl: serverUrl ?? this.serverUrl,
    appClientId: appClientId ?? this.appClientId,
    owner: owner ?? this.owner,
    repo: repo ?? this.repo,
    branch: branch ?? this.branch,
    path: path ?? this.path,
    token: token ?? this.token,
    refreshToken: refreshToken ?? this.refreshToken,
    tokenExpiresAt: identical(tokenExpiresAt, _unset)
        ? this.tokenExpiresAt
        : tokenExpiresAt as DateTime?,
    refreshTokenExpiresAt: identical(refreshTokenExpiresAt, _unset)
        ? this.refreshTokenExpiresAt
        : refreshTokenExpiresAt as DateTime?,
  );

  Map<String, Object?> toJson() => {
    'hostType': hostType.name,
    'serverUrl': serverUrl,
    'appClientId': appClientId,
    'owner': owner,
    'repo': repo,
    'branch': branch,
    'path': path,
    'tokenExpiresAt': tokenExpiresAt?.toUtc().toIso8601String(),
    'refreshTokenExpiresAt': refreshTokenExpiresAt?.toUtc().toIso8601String(),
  };

  factory GitHubSyncSettings.fromJson(Map<String, Object?>? json) {
    final defaults = GitHubSyncSettings.defaultSettings;
    if (json == null) return defaults;
    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    DateTime? dateTime(Object? value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value)?.toUtc();
    }

    final serverUrl = json['serverUrl'] as String?;
    final inferredHostType =
        (serverUrl == null ||
            serverUrl.trim().isEmpty ||
            Uri.tryParse(serverUrl)?.host.toLowerCase() == 'github.com')
        ? GitHubSyncHostType.githubDotCom
        : GitHubSyncHostType.enterprise;

    return defaults.copyWith(
      hostType: enumValue(
        GitHubSyncHostType.values,
        json['hostType'] as String?,
        inferredHostType,
      ),
      serverUrl: serverUrl,
      appClientId: json['appClientId'] as String?,
      owner: json['owner'] as String?,
      repo: json['repo'] as String?,
      branch: json['branch'] as String?,
      path: json['path'] as String?,
      tokenExpiresAt: dateTime(json['tokenExpiresAt']),
      refreshTokenExpiresAt: dateTime(json['refreshTokenExpiresAt']),
    );
  }
}

const Object _unset = Object();

class CloudSyncSettings {
  const CloudSyncSettings({
    required this.provider,
    required this.enabled,
    required this.encryptionKey,
    required this.github,
    required this.googleDriveFolder,
    required this.iCloudFolder,
  });

  static const githubTokenSecretRef = 'vibe_terminal.sync.github.token';
  static const githubRefreshTokenSecretRef =
      'vibe_terminal.sync.github.refresh_token';
  static const encryptionKeySecretRef = 'vibe_terminal.sync.encryption_key';

  static const defaultSettings = CloudSyncSettings(
    provider: CloudSyncProviderType.github,
    enabled: false,
    encryptionKey: '',
    github: GitHubSyncSettings.defaultSettings,
    googleDriveFolder: '',
    iCloudFolder: '',
  );

  final CloudSyncProviderType provider;
  final bool enabled;
  final String encryptionKey;
  final GitHubSyncSettings github;
  final String googleDriveFolder;
  final String iCloudFolder;

  bool get encryptionConfigured => encryptionKey.trim().length >= 12;

  bool get isConfigured {
    if (!enabled || !encryptionConfigured) return false;
    return switch (provider) {
      CloudSyncProviderType.github => github.isConfigured,
      CloudSyncProviderType.googleDrive => googleDriveFolder.trim().isNotEmpty,
      CloudSyncProviderType.iCloud => iCloudFolder.trim().isNotEmpty,
    };
  }

  CloudSyncSettings copyWith({
    CloudSyncProviderType? provider,
    bool? enabled,
    String? encryptionKey,
    GitHubSyncSettings? github,
    String? googleDriveFolder,
    String? iCloudFolder,
  }) => CloudSyncSettings(
    provider: provider ?? this.provider,
    enabled: enabled ?? this.enabled,
    encryptionKey: encryptionKey ?? this.encryptionKey,
    github: github ?? this.github,
    googleDriveFolder: googleDriveFolder ?? this.googleDriveFolder,
    iCloudFolder: iCloudFolder ?? this.iCloudFolder,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'enabled': enabled,
    'github': github.toJson(),
    'googleDriveFolder': googleDriveFolder,
    'iCloudFolder': iCloudFolder,
  };

  factory CloudSyncSettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return CloudSyncSettings.defaultSettings;

    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    final defaults = CloudSyncSettings.defaultSettings;
    final githubJson = json['github'] is Map
        ? Map<String, Object?>.from(json['github'] as Map)
        : null;
    return defaults.copyWith(
      provider: enumValue(
        CloudSyncProviderType.values,
        json['provider'] as String?,
        defaults.provider,
      ),
      enabled: json['enabled'] as bool?,
      github: GitHubSyncSettings.fromJson(githubJson),
      googleDriveFolder: json['googleDriveFolder'] as String?,
      iCloudFolder: json['iCloudFolder'] as String?,
    );
  }
}

/// 보조키바 기본 배치. 모바일 키보드로 바로 칠 수 있는 문자키(`/`, `-` 등)는
/// 기본에서 빼고, 키보드로 내기 번거로운 특수키만 둔다. Enter는 화살표 우측에
/// 둔다. 빠진 키들은 카탈로그에 남아 있어 편집 화면에서 다시 추가할 수 있다.
const List<String> kDefaultExtraKeysBarItems = [
  'paste',
  'image',
  'esc',
  'tab',
  'ctrl',
  'left',
  'down',
  'up',
  'right',
  'enter',
];

/// 터미널 헤더 기본 배치(1단계 재배치 순서와 동일).
const List<String> kDefaultTerminalHeaderItems = [
  'sessionPrev',
  'sessionNext',
  'retry',
  'zoomOut',
  'zoomIn',
  'zoomReset',
  'repaint',
];

/// `다시 그리기`가 추가되기 전의 기본 헤더 배치. 이 배치를 그대로 쓰던 사용자는
/// 새 기본 액션을 자동으로 받되, 직접 편집한 배치는 건드리지 않는다.
const List<String> _legacyTerminalHeaderItemsWithoutRepaint = [
  'sessionPrev',
  'sessionNext',
  'retry',
  'zoomOut',
  'zoomIn',
  'zoomReset',
];

const Map<String, List<String>> kDefaultShortcutBindings = {
  'copy': ['Ctrl+Shift+C', 'Cmd+C'],
  'paste': ['Ctrl+V', 'Ctrl+Shift+V', 'Shift+Insert', 'Cmd+V'],
  'zoomIn': ['Ctrl+='],
  'zoomOut': ['Ctrl+-'],
  'zoomReset': ['Ctrl+0'],
  'sessionPrevious': ['Ctrl+Tab'],
  'commandPalette': ['Ctrl+K', 'Cmd+K'],
};

class NotificationSettings {
  const NotificationSettings({
    required this.enabled,
    required this.taskCompleteEnabled,
    this.agentAttentionEnabled = true,
  });

  final bool enabled;
  final bool taskCompleteEnabled;

  /// Agent Chat loop가 승인·답변·연장을 기다리거나 예약 실행이 끝났을 때
  /// 시스템 알림을 보낼지.
  final bool agentAttentionEnabled;

  static const defaultSettings = NotificationSettings(
    enabled: true,
    taskCompleteEnabled: true,
    agentAttentionEnabled: true,
  );

  bool get canShowTaskComplete => enabled && taskCompleteEnabled;

  bool get canShowAgentAttention => enabled && agentAttentionEnabled;

  NotificationSettings copyWith({
    bool? enabled,
    bool? taskCompleteEnabled,
    bool? agentAttentionEnabled,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    taskCompleteEnabled: taskCompleteEnabled ?? this.taskCompleteEnabled,
    agentAttentionEnabled: agentAttentionEnabled ?? this.agentAttentionEnabled,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'taskCompleteEnabled': taskCompleteEnabled,
    'agentAttentionEnabled': agentAttentionEnabled,
  };

  factory NotificationSettings.fromJson(Map<String, Object?>? json) {
    final defaults = NotificationSettings.defaultSettings;
    if (json == null) return defaults;
    return defaults.copyWith(
      enabled: json['enabled'] as bool?,
      taskCompleteEnabled: json['taskCompleteEnabled'] as bool?,
      agentAttentionEnabled: json['agentAttentionEnabled'] as bool?,
    );
  }
}

class XServerSettings {
  const XServerSettings({
    required this.autoStart,
    required this.executablePath,
    required this.displayNumber,
    required this.extraArgs,
  });

  static const defaultSettings = XServerSettings(
    autoStart: false,
    executablePath: '',
    displayNumber: 0,
    extraArgs: '-multiwindow -clipboard',
  );

  final bool autoStart;
  final String executablePath;
  final int displayNumber;
  final String extraArgs;

  XServerSettings copyWith({
    bool? autoStart,
    String? executablePath,
    int? displayNumber,
    String? extraArgs,
  }) => XServerSettings(
    autoStart: autoStart ?? this.autoStart,
    executablePath: executablePath ?? this.executablePath,
    displayNumber: (displayNumber ?? this.displayNumber).clamp(0, 99).toInt(),
    extraArgs: extraArgs ?? this.extraArgs,
  );

  Map<String, Object?> toJson() => {
    'autoStart': autoStart,
    'executablePath': executablePath,
    'displayNumber': displayNumber,
    'extraArgs': extraArgs,
  };

  factory XServerSettings.fromJson(Map<String, Object?>? json) {
    final defaults = XServerSettings.defaultSettings;
    if (json == null) return defaults;
    return defaults.copyWith(
      autoStart: json['autoStart'] as bool?,
      executablePath: json['executablePath'] as String?,
      displayNumber: (json['displayNumber'] as num?)?.round(),
      extraArgs: json['extraArgs'] as String?,
    );
  }
}

class AgentLaunchProfile {
  const AgentLaunchProfile({
    required this.id,
    required this.name,
    required this.cliName,
    required this.arguments,
    required this.isolateWorktree,
  });

  final String id;
  final String name;
  final String cliName;
  final List<String> arguments;
  final bool isolateWorktree;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'cliName': cliName,
    'arguments': arguments,
    'isolateWorktree': isolateWorktree,
  };

  static AgentLaunchProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = _profileString(value['id'], 100);
    final name = _profileString(value['name'], 60);
    final cliName = _profileString(value['cliName'], 20);
    if (id == null ||
        name == null ||
        cliName == null ||
        !const {'claude', 'codex', 'opencode'}.contains(cliName)) {
      return null;
    }
    final arguments = <String>[];
    if (value['arguments'] is List) {
      for (final item in (value['arguments'] as List).take(20)) {
        if (item is String &&
            item.isNotEmpty &&
            item.length <= 500 &&
            !item.contains(RegExp(r'[\r\n\x00]'))) {
          arguments.add(item);
        }
      }
    }
    return AgentLaunchProfile(
      id: id,
      name: name,
      cliName: cliName,
      arguments: List.unmodifiable(arguments),
      isolateWorktree: value['isolateWorktree'] != false,
    );
  }
}

class AgentRunProfile {
  const AgentRunProfile({
    required this.id,
    required this.name,
    required this.command,
  });

  final String id;
  final String name;
  final String command;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'command': command};

  static AgentRunProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = _profileString(value['id'], 100);
    final name = _profileString(value['name'], 60);
    final command = _profileString(value['command'], 4000);
    if (id == null ||
        name == null ||
        command == null ||
        command.contains('\u0000')) {
      return null;
    }
    return AgentRunProfile(id: id, name: name, command: command);
  }
}

String? _profileString(Object? value, int maximumLength) {
  if (value is! String) return null;
  final cleaned = value.trim();
  if (cleaned.isEmpty || cleaned.length > maximumLength) return null;
  return cleaned;
}

class AgentLaunchPreferences {
  const AgentLaunchPreferences({
    required this.isolateByDefault,
    required this.defaultArguments,
    this.profiles = const [],
    this.runProfiles = const [],
  });

  final bool isolateByDefault;

  /// CLI 이름을 키로 하고 셸 인자 하나를 문자열 하나로 보관한다.
  /// 자유 형식 셸 문자열을 저장하지 않아 실행 시 명령 삽입을 피한다.
  final Map<String, List<String>> defaultArguments;
  final List<AgentLaunchProfile> profiles;
  final List<AgentRunProfile> runProfiles;

  static const defaultSettings = AgentLaunchPreferences(
    isolateByDefault: true,
    defaultArguments: {},
  );

  List<String> argumentsFor(String cliName) =>
      List.unmodifiable(defaultArguments[cliName] ?? const <String>[]);

  AgentLaunchPreferences copyWith({
    bool? isolateByDefault,
    Map<String, List<String>>? defaultArguments,
    List<AgentLaunchProfile>? profiles,
    List<AgentRunProfile>? runProfiles,
  }) => AgentLaunchPreferences(
    isolateByDefault: isolateByDefault ?? this.isolateByDefault,
    defaultArguments: defaultArguments ?? this.defaultArguments,
    profiles: profiles ?? this.profiles,
    runProfiles: runProfiles ?? this.runProfiles,
  );

  AgentLaunchPreferences withArguments(String cliName, List<String> values) {
    final next = <String, List<String>>{
      ...defaultArguments,
      cliName: List.unmodifiable(values),
    };
    return copyWith(defaultArguments: Map.unmodifiable(next));
  }

  AgentLaunchPreferences withProfile(AgentLaunchProfile profile) => copyWith(
    profiles: List.unmodifiable([
      for (final existing in profiles)
        if (existing.id != profile.id) existing,
      profile,
    ]),
  );

  AgentLaunchPreferences withoutProfile(String id) => copyWith(
    profiles: List.unmodifiable([
      for (final profile in profiles)
        if (profile.id != id) profile,
    ]),
  );

  AgentLaunchPreferences withRunProfile(AgentRunProfile profile) => copyWith(
    runProfiles: List.unmodifiable([
      for (final existing in runProfiles)
        if (existing.id != profile.id) existing,
      profile,
    ]),
  );

  AgentLaunchPreferences withoutRunProfile(String id) => copyWith(
    runProfiles: List.unmodifiable([
      for (final profile in runProfiles)
        if (profile.id != id) profile,
    ]),
  );

  Map<String, Object?> toJson() => {
    'isolateByDefault': isolateByDefault,
    'defaultArguments': defaultArguments,
    if (profiles.isNotEmpty)
      'profiles': [for (final profile in profiles) profile.toJson()],
    if (runProfiles.isNotEmpty)
      'runProfiles': [for (final profile in runProfiles) profile.toJson()],
  };

  factory AgentLaunchPreferences.fromJson(Map<String, Object?>? json) {
    if (json == null) return defaultSettings;
    final parsed = <String, List<String>>{};
    final rawArguments = json['defaultArguments'];
    if (rawArguments is Map) {
      for (final entry in rawArguments.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        parsed[entry.key as String] = [
          for (final value in entry.value as List)
            if (value is String && value.isNotEmpty) value,
        ];
      }
    }
    final profiles = <AgentLaunchProfile>[];
    if (json['profiles'] is List) {
      for (final value in (json['profiles'] as List).take(50)) {
        final profile = AgentLaunchProfile.fromJson(value);
        if (profile != null && !profiles.any((item) => item.id == profile.id)) {
          profiles.add(profile);
        }
      }
    }
    final runProfiles = <AgentRunProfile>[];
    if (json['runProfiles'] is List) {
      for (final value in (json['runProfiles'] as List).take(50)) {
        final profile = AgentRunProfile.fromJson(value);
        if (profile != null &&
            !runProfiles.any((item) => item.id == profile.id)) {
          runProfiles.add(profile);
        }
      }
    }
    return AgentLaunchPreferences(
      isolateByDefault: json['isolateByDefault'] as bool? ?? true,
      defaultArguments: Map.unmodifiable(parsed),
      profiles: List.unmodifiable(profiles),
      runProfiles: List.unmodifiable(runProfiles),
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.terminalTheme,
    required this.terminalFontFamily,
    required this.terminalFontSize,
    required this.terminalLineHeight,
    required this.terminalScrollbackLines,
    required this.copyOnSelection,
    required this.rightClickPaste,
    required this.confirmMultilinePaste,
    required this.ctrlCBehavior,
    required this.extraKeysBarItems,
    required this.terminalHeaderItems,
    required this.shortcutBindings,
    required this.notifications,
    required this.leftPanelWidth,
    required this.rightPanelWidth,
    required this.xServer,
    required this.cloudSync,
    required this.ai,
    required this.agentLaunch,
  });

  final TerminalThemePreset terminalTheme;
  final String terminalFontFamily;
  final double terminalFontSize;
  final double terminalLineHeight;

  /// 터미널이 위로 되감을 수 있는 줄 수(스크롤백).
  ///
  /// 세션마다 이만큼의 줄을 메모리에 들고 있으므로, 크게 잡으면 그만큼
  /// 메모리를 더 쓴다. 세션이 여러 개면 합산된다.
  final int terminalScrollbackLines;

  final bool copyOnSelection;
  final bool rightClickPaste;
  final bool confirmMultilinePaste;
  final CtrlCBehavior ctrlCBehavior;

  /// 하단 보조키바 표시 항목(순서대로). 키보드 토글은 첫칸 고정이라 제외된다.
  final List<String> extraKeysBarItems;

  /// 상단 터미널 헤더 표시 항목(순서대로).
  final List<String> terminalHeaderItems;

  /// 터미널 로컬 액션별 단축키 목록. 예: {'copy': ['Ctrl+Shift+C', 'Cmd+C']}.
  final Map<String, List<String>> shortcutBindings;

  final NotificationSettings notifications;

  /// 데스크톱 좌측 세션 패널 폭.
  final double leftPanelWidth;

  /// 데스크톱 우측 도구 패널 폭. 모든 우측 패널이 공유한다.
  final double rightPanelWidth;

  final XServerSettings xServer;

  final CloudSyncSettings cloudSync;

  final AiSettings ai;

  final AgentLaunchPreferences agentLaunch;

  static const defaultSettings = AppSettings(
    terminalTheme: TerminalThemePreset.vibeDark,
    terminalFontFamily: kMonoFontFamily,
    terminalFontSize: 14,
    terminalLineHeight: 1.25,
    terminalScrollbackLines: defaultScrollbackLines,
    copyOnSelection: true,
    rightClickPaste: true,
    confirmMultilinePaste: false,
    ctrlCBehavior: CtrlCBehavior.interruptOnly,
    extraKeysBarItems: kDefaultExtraKeysBarItems,
    terminalHeaderItems: kDefaultTerminalHeaderItems,
    shortcutBindings: kDefaultShortcutBindings,
    notifications: NotificationSettings.defaultSettings,
    leftPanelWidth: 264,
    rightPanelWidth: 420,
    xServer: XServerSettings.defaultSettings,
    cloudSync: CloudSyncSettings.defaultSettings,
    ai: AiSettings.defaultSettings,
    agentLaunch: AgentLaunchPreferences.defaultSettings,
  );

  static const fontFamilies = [
    'Cascadia Mono',
    'Cascadia Code',
    'Consolas',
    'JetBrains Mono',
    'D2Coding',
    'Noto Sans Mono CJK KR',
    'monospace',
  ];

  static const minFontSize = 8.0;
  static const maxFontSize = 32.0;
  static const fontSizeStep = 1.0;
  static const minLineHeight = 1.0;
  static const maxLineHeight = 1.6;

  /// 스크롤백 허용 범위. 상한은 사용자 요청에 따른 10만 줄이다.
  ///
  /// 상한을 쓰면 세션 하나당 10만 줄을 메모리에 들고 있게 되므로, 설정 화면에
  /// 그 사실을 함께 표시한다.
  static const minScrollbackLines = 500;
  static const maxScrollbackLines = 100000;
  static const defaultScrollbackLines = 5000;
  static const minLeftPanelWidth = 264.0;
  static const maxLeftPanelWidth = 420.0;
  static const minRightPanelWidth = 320.0;
  static const maxRightPanelWidth = 920.0;

  TerminalTheme get resolvedTerminalTheme => terminalTheme.terminalTheme;

  List<String> get fontFallback => [
    for (final font in kMonoFontFallback)
      if (font != terminalFontFamily) font,
  ];

  AppSettings copyWith({
    TerminalThemePreset? terminalTheme,
    String? terminalFontFamily,
    double? terminalFontSize,
    double? terminalLineHeight,
    int? terminalScrollbackLines,
    bool? copyOnSelection,
    bool? rightClickPaste,
    bool? confirmMultilinePaste,
    CtrlCBehavior? ctrlCBehavior,
    List<String>? extraKeysBarItems,
    List<String>? terminalHeaderItems,
    Map<String, List<String>>? shortcutBindings,
    NotificationSettings? notifications,
    double? leftPanelWidth,
    double? rightPanelWidth,
    XServerSettings? xServer,
    CloudSyncSettings? cloudSync,
    AiSettings? ai,
    AgentLaunchPreferences? agentLaunch,
  }) => AppSettings(
    terminalTheme: terminalTheme ?? this.terminalTheme,
    terminalFontFamily: terminalFontFamily ?? this.terminalFontFamily,
    terminalFontSize: (terminalFontSize ?? this.terminalFontSize).clamp(
      minFontSize,
      maxFontSize,
    ),
    terminalLineHeight: (terminalLineHeight ?? this.terminalLineHeight).clamp(
      minLineHeight,
      maxLineHeight,
    ),
    terminalScrollbackLines:
        (terminalScrollbackLines ?? this.terminalScrollbackLines).clamp(
          minScrollbackLines,
          maxScrollbackLines,
        ),
    copyOnSelection: copyOnSelection ?? this.copyOnSelection,
    rightClickPaste: rightClickPaste ?? this.rightClickPaste,
    confirmMultilinePaste: confirmMultilinePaste ?? this.confirmMultilinePaste,
    ctrlCBehavior: ctrlCBehavior ?? this.ctrlCBehavior,
    extraKeysBarItems: extraKeysBarItems ?? this.extraKeysBarItems,
    terminalHeaderItems: terminalHeaderItems ?? this.terminalHeaderItems,
    shortcutBindings: shortcutBindings ?? this.shortcutBindings,
    notifications: notifications ?? this.notifications,
    leftPanelWidth: (leftPanelWidth ?? this.leftPanelWidth).clamp(
      minLeftPanelWidth,
      maxLeftPanelWidth,
    ),
    rightPanelWidth: (rightPanelWidth ?? this.rightPanelWidth).clamp(
      minRightPanelWidth,
      maxRightPanelWidth,
    ),
    xServer: xServer ?? this.xServer,
    cloudSync: cloudSync ?? this.cloudSync,
    ai: ai ?? this.ai,
    agentLaunch: agentLaunch ?? this.agentLaunch,
  );

  Map<String, Object?> toJson() => {
    'terminalTheme': terminalTheme.name,
    'terminalFontFamily': terminalFontFamily,
    'terminalFontSize': terminalFontSize,
    'terminalLineHeight': terminalLineHeight,
    'terminalScrollbackLines': terminalScrollbackLines,
    'copyOnSelection': copyOnSelection,
    'rightClickPaste': rightClickPaste,
    'confirmMultilinePaste': confirmMultilinePaste,
    'ctrlCBehavior': ctrlCBehavior.name,
    'extraKeysBarItems': extraKeysBarItems,
    'terminalHeaderItems': terminalHeaderItems,
    'shortcutBindings': shortcutBindings,
    'notifications': notifications.toJson(),
    'leftPanelWidth': leftPanelWidth,
    'rightPanelWidth': rightPanelWidth,
    'xServer': xServer.toJson(),
    'cloudSync': cloudSync.toJson(),
    'ai': ai.toJson(),
    'agentLaunch': agentLaunch.toJson(),
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    List<String>? stringList(Object? value) {
      if (value is! List) return null;
      final items = [
        for (final item in value)
          if (item is String) item,
      ];
      // 빈 리스트는 의미가 없으므로(구버전·손상 데이터) 기본값으로 폴백한다.
      return items.isEmpty ? null : items;
    }

    Map<String, List<String>>? shortcutMap(Object? value) {
      if (value is! Map) return null;
      final parsed = <String, List<String>>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) continue;
        final bindings = stringList(entry.value);
        if (bindings == null) continue;
        parsed[key] = bindings;
      }
      return parsed.isEmpty ? null : parsed;
    }

    final defaults = AppSettings.defaultSettings;
    final aiJson = json['ai'] is Map
        ? Map<String, Object?>.from(json['ai'] as Map)
        : null;
    final syncJson = json['cloudSync'] is Map
        ? Map<String, Object?>.from(json['cloudSync'] as Map)
        : null;
    final notificationJson = json['notifications'] is Map
        ? Map<String, Object?>.from(json['notifications'] as Map)
        : null;
    final xServerJson = json['xServer'] is Map
        ? Map<String, Object?>.from(json['xServer'] as Map)
        : null;
    final agentLaunchJson = json['agentLaunch'] is Map
        ? Map<String, Object?>.from(json['agentLaunch'] as Map)
        : null;
    final legacyAiPanelWidth = (aiJson?['panelWidth'] as num?)?.toDouble();
    final savedTerminalHeaderItems = stringList(json['terminalHeaderItems']);
    final terminalHeaderItems =
        savedTerminalHeaderItems != null &&
            listEquals(
              savedTerminalHeaderItems,
              _legacyTerminalHeaderItemsWithoutRepaint,
            )
        ? kDefaultTerminalHeaderItems
        : savedTerminalHeaderItems;
    return defaults.copyWith(
      terminalTheme: enumValue(
        TerminalThemePreset.values,
        json['terminalTheme'] as String?,
        defaults.terminalTheme,
      ),
      terminalFontFamily: json['terminalFontFamily'] as String?,
      terminalFontSize: (json['terminalFontSize'] as num?)?.toDouble(),
      terminalLineHeight: (json['terminalLineHeight'] as num?)?.toDouble(),
      terminalScrollbackLines: (json['terminalScrollbackLines'] as num?)
          ?.toInt(),
      copyOnSelection: json['copyOnSelection'] as bool?,
      rightClickPaste: json['rightClickPaste'] as bool?,
      confirmMultilinePaste: json['confirmMultilinePaste'] as bool?,
      ctrlCBehavior: enumValue(
        CtrlCBehavior.values,
        json['ctrlCBehavior'] as String?,
        defaults.ctrlCBehavior,
      ),
      extraKeysBarItems: stringList(json['extraKeysBarItems']),
      terminalHeaderItems: terminalHeaderItems,
      shortcutBindings: {
        ...defaults.shortcutBindings,
        ...?shortcutMap(json['shortcutBindings']),
      },
      notifications: NotificationSettings.fromJson(notificationJson),
      leftPanelWidth: (json['leftPanelWidth'] as num?)?.toDouble(),
      rightPanelWidth:
          (json['rightPanelWidth'] as num?)?.toDouble() ?? legacyAiPanelWidth,
      xServer: XServerSettings.fromJson(xServerJson),
      cloudSync: CloudSyncSettings.fromJson(syncJson),
      ai: AiSettings.fromJson(aiJson),
      agentLaunch: AgentLaunchPreferences.fromJson(agentLaunchJson),
    );
  }
}
