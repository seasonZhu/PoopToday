import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/business.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('同号档案可跳过所属数据或独立恢复且重复导入幂等', () async {
    sqfliteFfiInit();
    final source = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final dir = await Directory.systemTemp.createTemp('independent-');
    final target = await Business.open(
      '${dir.path}/target.db',
      factory: databaseFactoryFfi,
    );
    addTearDown(() async {
      await source.close();
      await target.close();
      await dir.delete(recursive: true);
    });
    await source.createProfile('13800138000');
    await source.saveToday('顺畅', '3');
    await target.createProfile('13800138000');
    final backup = await source.exportBackup();
    final id = (await source.profiles()).single['id'] as String;
    final skipped = await target.previewImport(backup, skippedProfileIds: {id});
    expect(skipped.skipped, 2);
    await target.applyImport(skipped);
    expect(await target.profiles(), hasLength(1));
    await target.applyImport(await target.previewImport(backup));
    expect(await target.profiles(), hasLength(2));
    expect((await target.previewImport(backup)).skipped, 2);
    expect(await target.todayRecords(), isEmpty);
    await target.selectProfile(id);
    expect(await target.todayRecords(), hasLength(1));
    await target.deleteProfile();
    await target.applyImport(await target.previewImport(backup));
    await target.selectProfile(id);
    expect(await target.todayRecords(), hasLength(1));
    expect(await target.profiles(), hasLength(2));
  });
  test('导入恢复删除记录且重复导入跳过', () async {
    sqfliteFfiInit();
    final app = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(app.close);
    await app.createProfile('13800138000');
    await app.saveToday('顺畅', '3');
    final backup = await app.exportBackup();
    await app.deleteRecord((await app.todayRecords()).single['id'] as String);
    final preview = await app.previewImport(backup);
    expect(preview.restored, 1);
    expect(await app.todayRecords(), isEmpty);
    await app.applyImport(preview);
    expect(await app.todayRecords(), hasLength(1));
    final again = await app.previewImport(backup);
    expect(again.skipped, 2);
  });
  test('日期覆盖、预览失效及内部冲突拒绝', () async {
    sqfliteFfiInit();
    final app = await Business.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(app.close);
    await app.createProfile('13800138000');
    await app.saveToday('顺畅', '3');
    final backup = await app.exportBackup();
    final id = (await app.todayRecords()).single['id'] as String;
    await app.confirmNoPoop(app.today, deleteRecords: true);
    final noPoop = await app.exportBackup();
    await app.applyImport(await app.previewImport(backup));
    expect((await app.dailyCounts())[app.today], 1);
    final preview = await app.previewImport(noPoop);
    expect(preview.cleared, 1);
    await app.saveToday('一般', '4');
    await expectLater(app.applyImport(preview), throwsStateError);
    expect(await app.todayRecords(), hasLength(2));
    await app.applyImport(await app.previewImport(noPoop));
    expect((await app.dailyCounts())[app.today], 0);
    await app.applyImport(await app.previewImport(backup));
    expect((await app.todayRecords()).single['id'], id);
    final invalid = jsonDecode(backup) as Map<String, dynamic>;
    invalid['no_poop'] = [
      {'profile_id': invalid['profiles'][0]['id'], 'date': app.today},
    ];
    await expectLater(
      app.previewImport(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(await app.todayRecords(), hasLength(1));
    invalid['format_version'] = 99;
    await expectLater(
      app.previewImport(jsonEncode(invalid)),
      throwsFormatException,
    );
  });
  test('事务写入失败全部回滚，空白设备恢复保留独立 UID', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('poop-import-');
    addTearDown(() => dir.delete(recursive: true));
    final source = await Business.open(
      '${dir.path}/source.db',
      factory: databaseFactoryFfi,
    );
    final target = await Business.open(
      '${dir.path}/target.db',
      factory: databaseFactoryFfi,
    );
    addTearDown(source.close);
    addTearDown(target.close);
    await source.createProfile('13800138000');
    await source.saveToday('顺畅', '3');
    final backup = await source.exportBackup();
    final raw = await databaseFactoryFfi.openDatabase('${dir.path}/target.db');
    await raw.execute(
      "CREATE TRIGGER reject_import BEFORE INSERT ON records BEGIN SELECT RAISE(ABORT, '模拟写入失败'); END",
    );
    await expectLater(
      target.applyImport(await target.previewImport(backup)),
      throwsA(isA<DatabaseException>()),
    );
    expect(await target.profiles(), isEmpty);
    await raw.execute('DROP TRIGGER reject_import');
    await target.applyImport(await target.previewImport(backup));
    expect(await target.todayRecords(), hasLength(1));
    await source.saveToday('顺畅', '3');
    await target.applyImport(
      await target.previewImport(await source.exportBackup()),
    );
    expect(await target.todayRecords(), hasLength(2));
  });
}
