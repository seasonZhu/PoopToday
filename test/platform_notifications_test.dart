import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:poop_today/platform_notifications.dart';
import 'package:poop_today/reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var exact = true;
  var revoked = false;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    exact = true;
    revoked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'requestNotificationsPermission':
        case 'areNotificationsEnabled':
        case 'requestExactAlarmsPermission':
          return true;
        case 'canScheduleExactNotifications':
          return exact;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'zonedSchedule':
          if (revoked &&
              ((call.arguments as Map)['platformSpecifics']
                      as Map)['scheduleMode'] ==
                  'exactAllowWhileIdle') {
            throw PlatformException(code: 'exact_alarms_not_permitted');
          }
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'Asia/Shanghai',
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      null,
    );
  });

  test('Android 后台权限状态与两个设置入口调用原生接口', () async {
    final settingsCalls = <String>[];
    messenger.setMockMethodCallHandler(PlatformNotifications.settingsChannel, (
      call,
    ) async {
      settingsCalls.add(call.method);
      return call.method == 'backgroundAllowed' ? false : null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        PlatformNotifications.settingsChannel,
        null,
      ),
    );
    final adapter = PlatformNotifications();
    expect(await adapter.backgroundAllowed(), false);
    await adapter.openBackgroundSettings();
    await adapter.openBannerSettings();
    expect(settingsCalls, [
      'backgroundAllowed',
      'openBackgroundSettings',
      'openBannerSettings',
    ]);
  });

  test('Android 重排仅取消待触发任务，通知编号不随列表位置改变', () async {
    final adapter = PlatformNotifications();
    await adapter.initialize((_) {});
    final first = ReminderNotification(
      DateTime.now().add(const Duration(days: 1)),
      'profile',
    );
    final second = ReminderNotification(
      DateTime.now().add(const Duration(days: 2)),
      'profile',
    );
    await adapter.replace([first, second]);
    final previous =
        calls.where((c) => c.method == 'zonedSchedule').last.arguments as Map;
    calls.clear();
    await adapter.replace([second]);
    expect(calls.any((c) => c.method == 'cancelAll'), false);
    expect(calls.any((c) => c.method == 'cancelAllPendingNotifications'), true);
    final scheduled = calls.last.arguments as Map;
    expect(scheduled['id'], previous['id']);
    expect(
      (scheduled['platformSpecifics'] as Map)['scheduleMode'],
      'exactAllowWhileIdle',
    );
    calls.clear();
    await adapter.replace([]);
    expect(calls.any((c) => c.method == 'cancelAll'), false);
  });

  test('Android 未授权精确闹钟仍保留普通提醒，主动开启才申请权限', () async {
    exact = false;
    final adapter = PlatformNotifications();
    await adapter.initialize((_) {});
    await adapter.permission();
    expect(calls.any((c) => c.method == 'requestExactAlarmsPermission'), false);
    await adapter.permission(request: true);
    expect(calls.any((c) => c.method == 'requestExactAlarmsPermission'), true);
    await adapter.replace([
      ReminderNotification(
        DateTime.now().add(const Duration(days: 1)),
        'profile',
      ),
    ]);
    expect(
      ((calls.last.arguments as Map)['platformSpecifics']
          as Map)['scheduleMode'],
      'inexactAllowWhileIdle',
    );
  });

  test('Android 调度期间精确权限被撤销时退回普通提醒', () async {
    revoked = true;
    final adapter = PlatformNotifications();
    await adapter.initialize((_) {});
    await adapter.replace([
      ReminderNotification(
        DateTime.now().add(const Duration(days: 1)),
        'profile',
      ),
    ]);
    final modes = calls
        .where((c) => c.method == 'zonedSchedule')
        .map(
          (c) =>
              ((c.arguments as Map)['platformSpecifics']
                  as Map)['scheduleMode'],
        );
    expect(modes, ['exactAllowWhileIdle', 'inexactAllowWhileIdle']);
  });
}
