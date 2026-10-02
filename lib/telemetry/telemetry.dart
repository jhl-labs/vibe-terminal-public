import 'dart:ui';

import '../ai/secret_masker.dart';
import '../app/error_reporter.dart';
import '../data/models/host.dart';
import '../settings/ai_provider_type.dart' show AiProviderType;

/// 텔레메트리 payload 에 실릴 수 있는 문자열을 정화한다. 기존 비밀값 마스킹 뒤에
/// 호스트·주소·홈 경로를 치환한다. 스택 트레이스의 `package:` 경로는 건드리지 않는다.
String sanitizeForTelemetry(String text) {
  var out = maskTerminalSecrets(text);
  // URL은 호스트뿐 아니라 경로·query·userinfo에도 비밀값이 들어갈 수 있다.
  // package:/dart: 스택 프레임과 달리 // authority를 갖는 URL 전체를 가린다.
  out = out.replaceAll(
    RegExp(r'''\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s<>"']+'''),
    '<url>',
  );
  // SSH 별칭처럼 점이 없는 호스트와 사용자명도 보호한다.
  out = out.replaceAll(
    RegExp(r'(?<![\w/])[\w.-]+@[\w.-]+(?::\d{1,5})?(?![\w.])'),
    '<host>',
  );
  out = out.replaceAll(
    RegExp(
      r'(?<![\w:])\[?(?:(?:[a-fA-F0-9]{1,4}:){7}[a-fA-F0-9]{1,4}|[a-fA-F0-9:]*::[a-fA-F0-9:.]*)(?:%[\w]+)?\]?(?::\d{1,5})?(?![\w:])',
    ),
    '<host>',
  );
  // user@host[:port] 또는 host:port. host 는 IPv4(정확히 네 옥텟) 또는
  // TLD 형태(마지막 라벨이 영문 2자 이상)인 도메인만 인정해 "1.2.3", "3.14" 같은
  // 버전·소수 문자열과 "12:30" 같은 시각 표기는 건드리지 않는다.
  // package:/dart: 스킴은 제외.
  out = out.replaceAllMapped(
    RegExp(
      r'(?<![\w:/])(?:[\w.-]+@)?(?:(?:\d{1,3}\.){3}\d{1,3}|(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})(?::\d{1,5})?(?![\w.])',
    ),
    (m) => '<host>',
  );
  // 홈 디렉터리 경로: *nix 의 /home/<user>, /Users/<user>, /root, 윈도우의
  // <드라이브>:\Users\<user> (역슬래시·슬래시 모두). 대소문자는 구분하지 않는다.
  out = out.replaceAllMapped(
    RegExp(
      r'[A-Za-z]:[\\/]Users[\\/][^\\/\s]+|/(?:home|Users)/[^/\s]+|/root(?=[/\\]|$)',
      caseSensitive: false,
    ),
    (m) => '<path>',
  );
  return out;
}

/// Analytics 로 보내는 이벤트. 이름과 파라미터를 생성자에서 고정해 자유 문자열이
/// 들어갈 길을 없앤다.
class TelemetryEvent {
  const TelemetryEvent._(this.name, this.params);

  final String name;
  final Map<String, Object> params;

  static const _knownClis = {'claude', 'codex', 'opencode', 'gemini'};

  factory TelemetryEvent.sessionOpen(HostConnectionType kind) =>
      TelemetryEvent._('session_open', {'kind': kind.name});
  factory TelemetryEvent.paneSplit({required int paneCount}) =>
      TelemetryEvent._('pane_split', {'pane_count': paneCount});
  factory TelemetryEvent.aiChatSend(
    AiProviderType provider, {
    required bool includesLog,
  }) => TelemetryEvent._('ai_chat_send', {
    'provider': provider.name,
    'includes_log': includesLog ? 1 : 0,
  });
  factory TelemetryEvent.agentRunStart({required String cli}) =>
      TelemetryEvent._('agent_run_start', {
        'cli': _knownClis.contains(cli) ? cli : 'other',
      });
  factory TelemetryEvent.snippetRun() =>
      const TelemetryEvent._('snippet_run', {});
  factory TelemetryEvent.keychainKeyCreate() =>
      const TelemetryEvent._('keychain_key_create', {});
}

/// 포그라운드에서 받은 푸시 메시지.
class TelemetryMessage {
  const TelemetryMessage({this.title, this.body, this.url});
  final String? title;
  final String? body;
  final Uri? url;
}

/// 사용자가 설정에서 고르는 세 토글.
class TelemetrySettings {
  const TelemetrySettings({
    this.crashReports = true,
    this.usageStats = true,
    this.announcements = true,
    this.configured = false,
  });

  final bool crashReports;
  final bool usageStats;
  final bool announcements;

  /// 앱이 한 번이라도 결정해 저장한 값인지. 저장된 설정에 이 키가 없으면(이
  /// 버전 이전에 설치한 사용자, 또는 키가 없는 기본 생성자) 로케일 기준 기본값을
  /// 다시 정해 저장해야 한다. 앱이 쓰는 JSON 은 항상 configured=true 다.
  final bool configured;

  static const _eea = {
    'AT',
    'BE',
    'BG',
    'HR',
    'CY',
    'CZ',
    'DK',
    'EE',
    'FI',
    'FR',
    'DE',
    'GR',
    'HU',
    'IE',
    'IT',
    'LV',
    'LT',
    'LU',
    'MT',
    'NL',
    'PL',
    'PT',
    'RO',
    'SK',
    'SI',
    'ES',
    'SE',
    'IS',
    'LI',
    'NO',
    'GB',
  };

  static bool isEeaLocale(Locale locale) =>
      _eea.contains(locale.countryCode?.toUpperCase());

  /// 첫 실행 기본값. EEA 는 사용 통계만 꺼 둔다(GDPR 동의 기본값).
  static TelemetrySettings defaultsFor(Locale? locale) =>
      TelemetrySettings(usageStats: locale == null || !isEeaLocale(locale));

  TelemetrySettings copyWith({
    bool? crashReports,
    bool? usageStats,
    bool? announcements,
    bool? configured,
  }) => TelemetrySettings(
    crashReports: crashReports ?? this.crashReports,
    usageStats: usageStats ?? this.usageStats,
    announcements: announcements ?? this.announcements,
    configured: configured ?? this.configured,
  );

  Map<String, dynamic> toJson() => {
    'crashReports': crashReports,
    'usageStats': usageStats,
    'announcements': announcements,
    // 앱이 쓰는 값은 언제나 "결정된" 값이다.
    'configured': true,
  };

  /// 값이 bool 이 아니면(손상·수동 편집) 기본값으로 읽어 절대 throw 하지 않는다.
  static bool _flag(Map<String, dynamic> json, String key, bool fallback) {
    final value = json[key];
    return value is bool ? value : fallback;
  }

  factory TelemetrySettings.fromJson(Map<String, dynamic> json) =>
      TelemetrySettings(
        crashReports: _flag(json, 'crashReports', true),
        usageStats: _flag(json, 'usageStats', true),
        announcements: _flag(json, 'announcements', true),
        configured: json['configured'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is TelemetrySettings &&
      other.crashReports == crashReports &&
      other.usageStats == usageStats &&
      other.announcements == announcements &&
      other.configured == configured;

  @override
  int get hashCode =>
      Object.hash(crashReports, usageStats, announcements, configured);
}

/// iOS 알림 권한 거부를 앱 셸에 한 번만 전달하는 래치. 셸이 콜백을 걸기 전에
/// 거부가 일어나면(부팅 순서: initialize→applySettings 가 셸 마운트보다 먼저)
/// 보류해 두었다가 콜백이 설정될 때 한 번 전달한다. [reset] 뒤에는 다시 알린다.
class AnnouncementDenialLatch {
  void Function()? _callback;
  bool _reported = false;
  bool _pending = false;

  void Function()? get callback => _callback;

  set callback(void Function()? value) {
    _callback = value;
    if (_pending && value != null) {
      _pending = false;
      _reported = true;
      value();
    }
  }

  /// 거부가 관측됐다. 콜백이 있으면 즉시(한 번만), 없으면 보류.
  void denied() {
    if (_reported) return;
    final cb = _callback;
    if (cb == null) {
      _pending = true;
      return;
    }
    _reported = true;
    cb();
  }

  /// 공지가 꺼졌다. 다음 거부는 다시 알린다.
  void reset() {
    _reported = false;
    _pending = false;
  }
}

/// 앱이 보는 텔레메트리 경계. 구현은 각 플랫폼 진입점이 고른다.
abstract class Telemetry {
  Future<void> initialize(TelemetrySettings settings);
  Future<void> applySettings(TelemetrySettings settings);
  void recordError(AppErrorRecord record);
  void setKey(String key, Object value);
  void logEvent(TelemetryEvent event);
  Stream<TelemetryMessage> get messages;

  /// iOS 에서 사용자가 알림 권한을 거부해 공지 토픽을 구독할 수 없을 때 호출된다.
  /// 앱 셸이 이를 받아 공지 토글을 끈다. 거부 한 번에 최대 한 번만 호출하며,
  /// 콜백을 걸기 전에 일어난 거부는 콜백이 설정되는 시점에 전달된다.
  set onAnnouncementsDenied(void Function()? callback);
}
