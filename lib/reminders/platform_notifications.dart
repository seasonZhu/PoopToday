import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import 'reminders.dart';

class PlatformNotifications
    implements
        NotificationAdapter,
        PreciseNotificationAdapter,
        AndroidReminderSettings {
  static const settingsChannel = MethodChannel('poop_today/reminder_settings');
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void> initialize(void Function(String) onOpen) async {
    data.initializeTimeZones();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) onOpen(response.payload!);
      },
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!
          .createNotificationChannel(
            const AndroidNotificationChannel(
              'daily_record',
              '填写提醒',
              importance: Importance.high,
            ),
          );
    }
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload != null) {
      onOpen(launch!.notificationResponse!.payload!);
    }
  }

  @override
  Future<bool> permission({bool request = false}) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      final allowed =
          (request
              ? await android.requestNotificationsPermission()
              : await android.areNotificationsEnabled()) ??
          false;
      if (request && allowed && await precisePermission() != true) {
        await android.requestExactAlarmsPermission();
      }
      return allowed;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()!;
      if (request) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  @override
  Future<bool?> backgroundAllowed() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    return await settingsChannel.invokeMethod<bool>('backgroundAllowed');
  }

  @override
  Future<void> openBackgroundSettings() async {
    await settingsChannel.invokeMethod<void>('openBackgroundSettings');
  }

  @override
  Future<void> openBannerSettings() async {
    await settingsChannel.invokeMethod<void>('openBannerSettings');
  }

  @override
  Future<bool?> precisePermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    return await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!
            .canScheduleExactNotifications() ??
        false;
  }

  @override
  Future<void> replace(List<ReminderNotification> notifications) async {
    final zone = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(zone.identifier);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final exact = isAndroid && await precisePermission() == true;
    if (isAndroid) {
      // 只取消待触发任务，保留消息栏中已经投递的提醒。
      await plugin.cancelAllPendingNotifications();
    } else {
      await plugin.cancelAll();
    }
    for (var i = 0; i < notifications.length; i++) {
      final notification = notifications[i];
      final at = notification.at;
      final id = isAndroid
          ? at.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute
          : i;
      Future<void> schedule(AndroidScheduleMode mode) => plugin.zonedSchedule(
        id,
        '拉💩了冒',
        '点击填写或查看今天的记录',
        tz.TZDateTime(location, at.year, at.month, at.day, at.hour, at.minute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_record',
            '填写提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: mode,
        payload: notification.profileId,
      );
      try {
        await schedule(
          exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } on PlatformException catch (error) {
        if (!exact || error.code != 'exact_alarms_not_permitted') rethrow;
        // 授权可能在查询之后被撤销，退回普通提醒。
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }
  }
}
