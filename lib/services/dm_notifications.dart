import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'device_credential_store.dart';
import 'dm_api.dart';

class DmNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initializing;
  static final _versions = <int, int>{};
  static int _epoch = 0;
  static VoidCallback? onOpenMessages;
  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> initialize() async {
    if (!_supported) return;
    return _initializing ??= _initialize();
  }

  static Future<void> _initialize() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_dm_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => onOpenMessages?.call(),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) onOpenMessages?.call();
  }

  static Future<bool?> requestPermission({bool once = false}) async {
    if (!_supported) return false;
    await initialize();
    final box = await Hive.openBox('dm_notification_preferences');
    if (once && box.get('requested', defaultValue: false) == true) return null;
    await box.put('requested', true);
    if (Platform.isAndroid) {
      return _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    return _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true, badge: true);
  }

  static Future<bool> show(int sessionId, int conversationId) async {
    if (!_supported) return false;
    final version = (_versions[conversationId] ?? 0) + 1;
    _versions[conversationId] = version;
    final epoch = _epoch;
    DmApi? api;
    try {
      await initialize();
      if (await DeviceCredentialStore.getSessionId() != sessionId) return false;
      api = await DmApi.open();
      if (api.sessionId != sessionId) return false;
      final data = await api.request('conversations/$conversationId/unread');
      if (epoch != _epoch ||
          _versions[conversationId] != version ||
          await DeviceCredentialStore.getSessionId() != sessionId) {
        return false;
      }
      final count = data['unread_count'] as int;
      if (count <= 0 || data['muted'] == true || data['blocked'] == true) {
        await cancel(conversationId);
        return false;
      }
      await _plugin.show(
        conversationId & 0x7fffffff,
        '树通 · 新私信',
        '你收到了$count条私信，点击查看',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'private_messages',
            '私信通知',
            channelDescription: '新的私信提醒',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      api?.close();
    }
  }

  static Future<void> cancel(int conversationId) async {
    _versions[conversationId] = (_versions[conversationId] ?? 0) + 1;
    if (!_supported) return;
    try {
      await initialize();
      await _plugin.cancel(conversationId & 0x7fffffff);
    } catch (_) {}
  }

  static Future<void> clear() async {
    _epoch++;
    _versions.clear();
    if (!_supported) return;
    try {
      await initialize();
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
