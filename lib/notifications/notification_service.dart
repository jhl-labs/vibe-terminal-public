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

  static const _channelId = 'task_complete';

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
    await _plugin.initialize(settings);
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
        _counter++,
        '작업 완료',
        '$sessionName 세션의 작업이 끝났습니다.',
        details,
      );
    } catch (_) {
      // 알림 실패는 핵심 기능에 영향이 없으므로 무시한다.
    }
  }
}
