import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/business.dart';
import 'package:poop_today/reminders.dart';
import 'package:poop_today/reminder_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'reminders_test.dart' show Notifications;

void main() {
  testWidgets('默认时间不申请权限，拒绝授权展示真实状态', (tester) async {
    sqfliteFfiInit();
    final business = (await tester.runAsync(
      () => Business.open(inMemoryDatabasePath, factory: databaseFactoryFfi),
    ))!;
    addTearDown(() => tester.runAsync(business.close));
    await tester.runAsync(() => business.createProfile('13800138000'));
    final platform = Notifications()..allowed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderSettings(service: ReminderService(business, platform)),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(platform.requests, 0);
    await tester.tap(find.byType(Switch));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(platform.requests, 1);
    expect(find.textContaining('系统设置'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
  });
}
