import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:poop_today/business.dart';

void main() {
  test('历史日期支持多条、时间排序和修改日期，重启后保留', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('calendar');
    final path = '${dir.path}/db';
    var app = await Business.open(
      path,
      factory: databaseFactoryFfi,
      now: () => DateTime(2026, 11, 9, 12),
    );
    try {
      await app.createProfile('13800138000');
      await app.saveRecord(date: '2026-11-08', ease: '顺畅', amount: '3');
      await app.saveRecord(
        date: '2026-11-08',
        time: '09:30',
        ease: '困难',
        amount: '1',
      );
      final records = await app.recordsForDate('2026-11-08');
      expect(records.map((r) => r['ease_name']), ['困难', '顺畅']);
      await app.saveRecord(
        id: records.first['id'] as String,
        date: '2026-11-09',
        time: '12:00',
      );
      await expectLater(
        app.saveRecord(
          date: '2026-11-09',
          time: '12:01',
          ease: '一般',
          amount: '5',
        ),
        throwsArgumentError,
      );
      await expectLater(
        app.saveRecord(date: '2026-11-10', ease: '一般', amount: '5'),
        throwsArgumentError,
      );
      await app.close();
      app = await Business.open(
        path,
        factory: databaseFactoryFfi,
        now: () => DateTime.utc(2026, 11, 10),
      );
      expect(
        (await app.recordsForDate('2026-11-09')).single['ease_name'],
        '困难',
      );
      expect((await app.recordsForDate('2026-11-08')).length, 1);
      expect((await app.dailyCounts())['2026-11-09'], 1);
    } finally {
      await app.close();
      await dir.delete(recursive: true);
    }
  });
  test('创建档案并保存今天记录，关闭后重新读取', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('poop_today');
    final path = '${directory.path}/test.db';
    DateTime now() => DateTime(2026, 11, 9, 12);
    var app = await Business.open(path, factory: databaseFactoryFfi, now: now);
    try {
      await expectLater(app.createProfile('123'), throwsArgumentError);
      await app.createProfile('13800138000');
      await expectLater(app.saveToday(null, '3'), throwsArgumentError);
      await expectLater(app.saveToday('顺畅', null), throwsArgumentError);
      expect(await app.todayRecords(), isEmpty);
      await app.saveToday('顺畅', '99');
      await expectLater(app.saveToday('顺畅', '100'), throwsArgumentError);
      await expectLater(app.saveToday('顺畅', '0'), throwsArgumentError);
      await app.close();
      app = await Business.open(path, factory: databaseFactoryFfi, now: now);
      expect(await app.phone(), '13800138000');
      final records = await app.todayRecords();
      expect(records.single['amount_value'], 99);
      expect(records.single['date'], '2026-11-09');
      await app.saveToday('顺畅', '99');
      expect((await app.todayRecords()).length, 2);
      await expectLater(app.createProfile('13800138000'), throwsArgumentError);
      expect(records.single['ease_name'], '顺畅');
    } finally {
      await app.close();
      await directory.delete(recursive: true);
    }
  });
}
