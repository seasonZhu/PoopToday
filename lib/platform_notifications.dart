import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import 'reminders.dart';

class PlatformNotifications implements NotificationAdapter {
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
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload != null) {
      onOpen(launch!.notificationResponse!.payload!);
    }
  }

  @override
  Future<bool> permission({bool request = false}) async {
    if (Platform.isAndroid) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      return (request
              ? await android.requestNotificationsPermission()
              : await android.areNotificationsEnabled()) ??
          false;
    }
    if (Platform.isIOS) {
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
  Future<void> replace(List<ReminderNotification> notifications) async {
    final zone = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(zone.identifier);
    await plugin.cancelAll();
    for (var i = 0; i < notifications.length; i++) {
      final notification = notifications[i];
      final at = notification.at;
      await plugin.zonedSchedule(
        i,
        '今天排便了吗',
        '点击填写或查看今天的记录',
        tz.TZDateTime(location, at.year, at.month, at.day, at.hour, at.minute),
        const NotificationDetails(
          android: AndroidNotificationDetails('daily_record', '填写提醒'),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: notification.profileId,
      );
    }
  }
}
