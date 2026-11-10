import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/business.dart';
import 'package:poop_today/reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Notifications implements NotificationAdapter {
  bool allowed = true;
  int requests = 0;
  List<ReminderNotification> pending = [];
  @override
  Future<bool> permission({bool request = false}) async {
    if (request) requests++;
    return allowed;
  }

  @override
  Future<void> replace(List<ReminderNotification> notifications) async {
    pending = notifications;
  }
}

void main() {
  test('时间配置校验、删除末项关闭及档案隔离', () async {
    sqfliteFfiInit();
    final business = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      now: () => DateTime(2026, 11, 10, 9),
    );
    addTearDown(business.close);
    await business.createProfile('13800138000');
    final platform = Notifications();
    final service = ReminderService(business, platform);
    await service.saveTimes([720, 630]);
    expect(await service.times(), [630, 720]);
    await expectLater(service.saveTimes([630, 630]), throwsArgumentError);
    await service.setEnabled(true);
    expect(platform.pending.first.at, DateTime(2026, 11, 10, 10, 30));
    expect(platform.pending.length, lessThanOrEqualTo(60));
    expect(await business.exportBackup(), isNot(contains('reminder:')));
    await service.saveTimes([]);
    expect(await service.enabled(), false);
    expect(await service.setEnabled(true), false);
    expect(platform.pending, isEmpty);
    await business.createProfile('13900139000');
    expect(await service.times(), [600, 1320]);
    expect(await service.enabled(), false);
  });
  test('重新打开保留当前档案配置，关闭后取消通知', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('reminders');
    var business = await Business.open(
      '${directory.path}/db',
      factory: databaseFactoryFfi,
    );
    final platform = Notifications();
    try {
      await business.createProfile('13800138000');
      await ReminderService(business, platform).setEnabled(true);
      await business.close();
      business = await Business.open(
        '${directory.path}/db',
        factory: databaseFactoryFfi,
      );
      final service = ReminderService(business, platform);
      expect(await service.enabled(), true);
      await service.setEnabled(false);
      expect(platform.pending, isEmpty);
    } finally {
      await business.close();
      await directory.delete(recursive: true);
    }
  });
  test('主动授权后调度，填写仅取消当天，切换档案不泄漏提醒', () async {
    sqfliteFfiInit();
    final business = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      now: () => DateTime(2026, 11, 10, 9),
    );
    addTearDown(business.close);
    await business.createProfile('13800138000');
    final platform = Notifications();
    final service = ReminderService(business, platform);
    await service.reconcile();
    expect(platform.requests, 0);
    expect(platform.pending, isEmpty);
    await service.setEnabled(true);
    expect(platform.pending.first.at, DateTime(2026, 11, 10, 10));
    expect(platform.pending[1].at, DateTime(2026, 11, 10, 22));
    await business.saveToday('顺畅', '2');
    await service.reconcile();
    expect(platform.pending.first.at, DateTime(2026, 11, 11, 10));
    expect(await business.exportBackup(), isNot(contains('reminder:')));
    await business.createProfile('13900139000');
    await service.reconcile();
    expect(platform.pending, isEmpty);
    platform.allowed = false;
    expect(await service.setEnabled(true), false);
    expect(await service.enabled(), false);
  });
}
