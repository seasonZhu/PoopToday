import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'business.dart';
import 'reminders.dart';
import 'platform_notifications.dart';
import 'records/record_page.dart';

export 'app.dart';
export 'records/record_page.dart';
export 'records/record_calendar.dart';
export 'records/home_statistics.dart';

ReminderService? reminders;
final reminderNavigator = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final business = await Business.open(
      path.join(await getDatabasesPath(), 'poop_today.db'),
    );
    final platform = PlatformNotifications();
    String? pendingProfile;
    try {
      await platform.initialize((profileId) {
        if (reminderNavigator.currentState == null) {
          pendingProfile = profileId;
        } else {
          openReminder(business, profileId);
        }
      });
      reminders = ReminderService(business, platform);
    } catch (_) {
      reminders = null;
    }
    runApp(
      PoopTodayApp(
        business: business,
        reminders: reminders,
        navigatorKey: reminderNavigator,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pendingProfile != null) openReminder(business, pendingProfile!);
    });
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('数据打开失败，请重新打开应用'))),
      ),
    );
  }
}

Future<void> openReminder(Business business, String profileId) async {
  try {
    await business.selectProfile(profileId);
    await reminders?.reconcile();
    reminderNavigator.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => RecordPage(
          business: business,
          date: business.today,
          reminders: reminders,
        ),
      ),
      (route) => route.isFirst,
    );
  } catch (_) {
    // 已删除档案的旧通知不跳转。
  }
}
