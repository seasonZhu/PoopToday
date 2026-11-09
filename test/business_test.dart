import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:poop_today/business.dart';

void main() {
  test('创建档案并保存今天记录，关闭后重新读取', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('poop_today');
    final path = '${directory.path}/test.db';
    DateTime now() => DateTime(2026, 11, 9, 12);
    var app = await Business.open(path, factory: databaseFactoryFfi, now: now);
    try {
      await expectLater(app.createProfile('123'), throwsArgumentError);
      await app.createProfile('13800138000');
      await expectLater(app.saveToday(null, '中'), throwsArgumentError);
      await expectLater(app.saveToday('顺畅', null), throwsArgumentError);
      expect(await app.todayRecords(), isEmpty);
      await app.saveToday('顺畅', '中');
      await app.close();
      app = await Business.open(path, factory: databaseFactoryFfi, now: now);
      expect(await app.phone(), '13800138000');
      final records = await app.todayRecords();
      expect(records.single['date'], '2026-11-09');
      expect(records.single['ease_name'], '顺畅');
    } finally {
      await app.close();
      await directory.delete(recursive: true);
    }
  });
}
