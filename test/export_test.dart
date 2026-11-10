import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/business.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('完整导出保留记录删除状态并最小化已删除档案', () async {
    sqfliteFfiInit();
    final app = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      now: () => DateTime(2026, 11, 9, 12),
    );
    addTearDown(app.close);
    await app.createProfile('13800138000');
    await app.deleteProfile();
    await app.createProfile('13900139000');
    await app.saveRecord(
      date: '2026-11-08',
      time: '10:00',
      ease: '顺畅',
      amount: '4',
    );
    await app.deleteRecord(
      (await app.recordsForDate('2026-11-08')).single['id'] as String,
    );
    await app.confirmNoPoop('2026-11-09');
    final data = jsonDecode(await app.exportBackup()) as Map<String, dynamic>;
    expect(data['format_version'], 1);
    expect(data['profiles'][0].keys.toSet(), {
      'id',
      'version',
      'modified_at',
      'deleted',
    });
    expect(data['records'].single['amount_value'], 4);
    expect(data['records'].single['deleted'], 1);
    expect(data['records'].single['local_time'], '10:00');
    expect(data['no_poop'].single['date'], '2026-11-09');
    expect(await app.exportBackup(), jsonEncode(data));
    expect(await app.phone(), '13900139000');
  });
}
