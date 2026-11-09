import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:poop_today/business.dart';

void main() {
  test('确认未排便事务失败回滚', () async {
    sqfliteFfiInit();
    final clock = DateTime(2026, 11, 9, 12);
    final app = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      now: () => clock,
    );
    addTearDown(app.close);
    await app.createProfile('13800138000');
    await app.saveToday('顺畅', '3');
    final id = (await app.todayRecords()).single['id'] as String;
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      "CREATE TRIGGER fail_confirmation BEFORE INSERT ON no_poop BEGIN SELECT RAISE(ABORT, '注入失败'); END",
    );
    await expectLater(
      app.confirmNoPoop(app.today, deleteRecords: true),
      throwsA(anything),
    );
    expect((await app.todayRecords()).single['id'], id);
    expect(await app.dailyCounts(), {'2026-11-09': 1});
    await db.execute('DROP TRIGGER fail_confirmation');
    await app.deleteRecord(id);
    await app.confirmNoPoop(app.today);
    expect(await app.dailyCounts(), {'2026-11-09': 0});
    expect(await app.todayRecords(), isEmpty);
  });
  test('确认、移入、删除和新增保持日期互斥', () async {
    sqfliteFfiInit();
    final app = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      now: () => DateTime(2026, 11, 9, 12),
    );
    addTearDown(app.close);
    await app.createProfile('13800138000');
    await app.confirmNoPoop('2026-11-08');
    expect((await app.dailyCounts())['2026-11-08'], 0);
    await app.saveToday('顺畅', '3');
    final id = (await app.todayRecords()).single['id'] as String;
    await app.saveRecord(id: id, date: '2026-11-08');
    expect(await app.dailyCounts(), {'2026-11-08': 1});
    await expectLater(app.confirmNoPoop('2026-11-08'), throwsStateError);
    await app.deleteRecord(id);
    expect(await app.dailyCounts(), isEmpty);
    await app.confirmNoPoop('2026-11-08');
    await app.saveRecord(date: '2026-11-08', ease: '顺畅', amount: '3');
    expect(await app.dailyCounts(), {'2026-11-08': 1});
  });
}
