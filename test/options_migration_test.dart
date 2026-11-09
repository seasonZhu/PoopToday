import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/business.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('旧版文字统计独立归类，不猜测数值或通畅度', () {
    expect(Business.easeCategory({'ease_name': '很顺利'}), '旧版未分类');
    expect(Business.easeCategory({'ease_name': '顺畅'}), '顺畅');
    expect(Business.amountCategory({'amount_name': '很多'}), '旧版未分类');
    expect(Business.amountCategory({'amount_value': 3}), '3');
  });

  for (final version in [1, 2, 3]) {
    test('数据库 v$version 升级及重新打开保留历史含义和删除状态', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('options_migration');
      final path = '${dir.path}/db';
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE profiles (id TEXT PRIMARY KEY, phone TEXT NOT NULL UNIQUE, version INTEGER NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE records (id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, date TEXT NOT NULL, ease_id TEXT NOT NULL, ease_name TEXT NOT NULL, amount_id TEXT NOT NULL, amount_name TEXT NOT NULL, version INTEGER NOT NULL, created_at TEXT NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
            );
            if (version >= 2) {
              await db.execute(
                'ALTER TABLE records ADD COLUMN local_time TEXT',
              );
              await db.execute('ALTER TABLE records ADD COLUMN time_zone TEXT');
              await db.execute(
                'ALTER TABLE records ADD COLUMN utc_offset_minutes INTEGER',
              );
            }
            if (version >= 3) {
              await db.execute(
                'CREATE TABLE no_poop (profile_id TEXT NOT NULL, date TEXT NOT NULL, PRIMARY KEY(profile_id, date))',
              );
            }
          },
        ),
      );
      await db.insert('profiles', {
        'id': 'profile',
        'phone': '13800138000',
        'version': 2,
        'modified_at': 'old',
      });
      for (final name in ['少', '中', '多', '一小点', '已删除']) {
        await db.insert('records', {
          'id': name,
          'profile_id': 'profile',
          'date': '2026-11-08',
          'ease_id': 'custom.ease',
          'ease_name': '很顺利',
          'amount_id': 'custom.$name',
          'amount_name': name,
          'version': 7,
          'created_at': 'created',
          'modified_at': 'modified',
          'deleted': name == '已删除' ? 1 : 0,
          if (version >= 2) ...{
            'local_time': '09:30',
            'time_zone': 'EST',
            'utc_offset_minutes': -300,
          },
        });
      }
      final before = await db.query('records');
      await db.close();
      var app = await Business.open(path, factory: databaseFactoryFfi);
      try {
        await app.close();
        app = await Business.open(path, factory: databaseFactoryFfi);
        final rows = await app.recordsForDate('2026-11-08');
        expect(rows.map((r) => r['id']), ['一小点', '多', '中', '少']);
        expect(rows.map((r) => r['amount_value']), [null, 5, 3, 1]);
        // 通过原始数据库验证迁移未丢失公开读取接口隐藏的删除记录。
        final upgraded = await databaseFactoryFfi.openDatabase(path);
        for (final old in before) {
          final row = (await upgraded.query(
            'records',
            where: 'id = ?',
            whereArgs: [old['id']],
          )).single;
          for (final key in old.keys) {
            expect(row[key], old[key], reason: '${old['id']}.$key');
          }
        }
        await app.saveRecord(
          id: '一小点',
          date: '2026-11-08',
          time: version >= 2 ? '09:30' : null,
        );
        var edited = (await app.recordsForDate('2026-11-08'))
            .firstWhere((r) => r['id'] == '一小点');
        expect(edited['ease_name'], '很顺利');
        expect(edited['amount_name'], '一小点');
        expect(edited['amount_value'], isNull);
        await app.saveRecord(
          id: '一小点',
          date: '2026-11-08',
          ease: '一般',
          amount: '9',
        );
        edited = (await app.recordsForDate('2026-11-08'))
            .firstWhere((r) => r['id'] == '一小点');
        expect(edited['ease_name'], '一般');
        expect(edited['amount_value'], 9);
        for (final invalid in ['0', '100', '-1', '1.5', '01', '很多']) {
          await expectLater(app.saveToday('顺畅', invalid), throwsArgumentError);
        }
        await expectLater(app.saveToday('自定义', '3'), throwsArgumentError);
      } finally {
        await app.close();
        await dir.delete(recursive: true);
      }
    });
  }
}
