import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:poop_today/business.dart';

void main() {
  test('旧版档案迁移保留身份并允许同号独立档案', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('profiles_upgrade');
    final path = '${dir.path}/db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE profiles (id TEXT PRIMARY KEY, phone TEXT NOT NULL UNIQUE, version INTEGER NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            "INSERT INTO profiles VALUES ('old-id', '13800138000', 1, '2026-11-09', 0)",
          );
        },
      ),
    );
    await db.close();
    final app = await Business.open(path, factory: databaseFactoryFfi);
    try {
      expect((await app.profiles()).single['id'], 'old-id');
      await app.close();
      final migrated = await databaseFactoryFfi.openDatabase(path);
      await migrated.insert('profiles', {
        'id': 'imported-id',
        'phone': '13800138000',
        'version': 1,
        'modified_at': '2026-11-09',
      });
      await migrated.close();
      final reopened = await Business.open(path, factory: databaseFactoryFfi);
      try {
        expect((await reopened.profiles()).length, 2);
        await reopened.selectProfile('imported-id');
        expect(await reopened.phone(), '13800138000');
        await expectLater(
          reopened.updatePhone('13800138000'),
          throwsArgumentError,
        );
      } finally {
        await reopened.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('档案隔离、修改、删除与重启恢复', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('profiles');
    final path = '${dir.path}/db';
    var app = await Business.open(path, factory: databaseFactoryFfi);
    try {
      await app.createProfile('13800138000', nickname: '家人');
      expect((await app.profiles()).single['nickname'], '家人');
      final first = (await app.profiles()).single['id'] as String;
      await app.saveToday('顺畅', '3');
      await expectLater(app.createProfile('13800138000'), throwsArgumentError);
      await app.createProfile('13900139000');
      expect(await app.todayRecords(), isEmpty);
      await app.confirmNoPoop(app.today);
      await app.selectProfile(first);
      expect((await app.todayRecords()).length, 1);
      expect((await app.dailyCounts())[app.today], 1);
      await app.updatePhone('13700137000', nickname: '自己');
      expect((await app.activeProfile())?['id'], first);
      final backup = await app.exportBackup();
      await app.updatePhone('13700137000', nickname: '临时');
      await app.applyImport(await app.previewImport(backup));
      expect((await app.activeProfile())?['nickname'], '自己');
      await app.close();
      app = await Business.open(path, factory: databaseFactoryFfi);
      expect(await app.phone(), '13700137000');
      await app.deleteProfile();
      expect(await app.phone(), '13900139000');
      await app.deleteProfile();
      expect(await app.phone(), isNull);
      await app.createProfile('13700137000');
      expect((await app.profiles()).single['id'], isNot(first));
    } finally {
      await app.close();
      await dir.delete(recursive: true);
    }
  });
}
