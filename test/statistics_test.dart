import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/business.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('月概览排除未来，周跨月、三态与档案隔离', () async {
    sqfliteFfiInit();
    final app = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      now: () => DateTime(2026, 11, 9, 12),
    );
    addTearDown(app.close);
    await app.createProfile('13800138000');
    await app.saveRecord(date: '2026-11-01', ease: '顺畅', amount: '4');
    await app.saveRecord(date: '2026-11-01', ease: '困难', amount: '3');
    await app.confirmNoPoop('2026-11-02');
    final month = await app.statistics(
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 30),
    );
    expect(month.total, 2);
    expect(month.recordedDays, 1);
    expect(month.confirmedDays, 1);
    expect(month.unfilledDays, 7);
    expect(month.amount.keys, ['3', '4']);
    final week = await app.statistics(
      DateTime(2026, 10, 26),
      DateTime(2026, 11, 1),
    );
    expect(week.total, 2);
    expect(week.unfilledDays, 6);
    final future = await app.statistics(
      DateTime(2026, 12),
      DateTime(2026, 12, 31),
    );
    expect(future.unfilledDays, 0);
    expect(future.total, 0);
    await app.createProfile('13900139000');
    expect(
      (await app.statistics(DateTime(2026, 11), DateTime(2026, 11, 30))).total,
      0,
    );
  });
}
