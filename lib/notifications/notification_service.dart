import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 로컬 시스템 알림을 보내는 얇은 래퍼. 지원 플랫폼이 아니거나 초기화/표시가
/// 실패해도 앱 동작에는 영향이 없도록 모든 실패를 삼킨다.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  int _counter = 0;

  /// 사용자가 payload 가 있는 알림을 탭했을 때 호출된다. 앱 셸이 설정한다.
  /// 플러그인 초기화 시점과 무관하게 응답 핸들러가 이 필드를 늦게 읽는다.
  void Function(String payload)? onPayloadTapped;

  static const _channelId = 'task_complete';
  static const _announcementChannelId = 'announcements';

  /// 공지 푸시는 항상 같은 id 로 띄워 여러 건이 쌓이지 않게 한다.
  static const _announcementId = 2001;

  bool get _supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;

  Future<void> _ensureInit() async {
    if (_initialized || !_supported) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        onPayloadTapped?.call(payload);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// 세션 작업 완료 알림을 표시한다.
  Future<void> showTaskComplete(String sessionName) async {
    if (!_supported) return;
    try {
      await _ensureInit();
      const android = AndroidNotificationDetails(
        _channelId,
        '작업 완료 알림',
        channelDescription: '세션의 작업이 끝나면 알립니다.',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(
        android: android,
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      );
      await _plugin.show(
        id: _counter++,
        title: '작업 완료',
        body: '$sessionName 세션의 작업이 끝났습니다.',
        notificationDetails: details,
      );
    } catch (_) {
      // 알림 실패는 핵심 기능에 영향이 없으므로 무시한다.
    }
  }

  /// 공지·업데이트 푸시를 포그라운드에서 로컬 알림으로 보여 준다.
  /// [url] 이 있으면 payload 로 실어 탭 시 [onPayloadTapped] 로 전달한다.
  Future<void> showAnnouncement({
    required String title,
    required String body,
    Uri? url,
  }) async {
    if (!_supported) return;
    try {
      await _ensureInit();
      const android = AndroidNotificationDetails(
        _announcementChannelId,
        '공지',
        channelDescription: '새 버전과 중요한 공지를 알립니다.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const details = NotificationDetails(
        android: android,
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      );
      await _plugin.show(
        id: _announcementId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: url?.toString(),
      );
    } catch (_) {
      // 알림 실패는 핵심 기능에 영향이 없으므로 무시한다.
    }
  }
}
