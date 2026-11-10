import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class ConfirmationRequired implements Exception {}

class Business {
  Business._(this._db, this.now);
  final Database _db;
  final DateTime Function() now;
  static const easeOptions = ['困难', '一般', '顺畅'];
  static const amountOptions = ['1', '2', '3', '4'];

  static String easeCategory(Map<String, Object?> record) {
    final name = record['ease_name'];
    return easeOptions.contains(name) ? name as String : '旧版未分类';
  }

  static String amountCategory(Map<String, Object?> record) {
    final value = record['amount_value'];
    return value is int && value >= 1 && value <= 99 ? '$value' : '旧版未分类';
  }

  static Future<Business> open(
    String path, {
    DatabaseFactory? factory,
    DateTime Function()? now,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = OFF');
        },
        onOpen: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 6) {
            await db.execute('ALTER TABLE profiles ADD COLUMN nickname TEXT');
          }
          if (oldVersion < 5) {
            await db.execute(
              'CREATE TABLE profiles_new (id TEXT PRIMARY KEY, phone TEXT NOT NULL, version INTEGER NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, nickname TEXT)',
            );
            await db.execute('INSERT INTO profiles_new (id, phone, version, modified_at, deleted) SELECT id, phone, version, modified_at, deleted FROM profiles');
            await db.execute('DROP TABLE profiles');
            await db.execute('ALTER TABLE profiles_new RENAME TO profiles');
            await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
            );
          }
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE records ADD COLUMN local_time TEXT');
            await db.execute('ALTER TABLE records ADD COLUMN time_zone TEXT');
            await db.execute(
              'ALTER TABLE records ADD COLUMN utc_offset_minutes INTEGER',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'CREATE TABLE no_poop (profile_id TEXT NOT NULL REFERENCES profiles(id), date TEXT NOT NULL, PRIMARY KEY(profile_id, date))',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE records ADD COLUMN amount_value INTEGER',
            );
            await db.execute(
              "UPDATE records SET amount_value = CASE amount_name WHEN '少' THEN 1 WHEN '中' THEN 3 WHEN '多' THEN 5 END",
            );
          }
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
          );
          await db.execute(
            'CREATE TABLE no_poop (profile_id TEXT NOT NULL REFERENCES profiles(id), date TEXT NOT NULL, PRIMARY KEY(profile_id, date))',
          );
          await db.execute(
            'CREATE TABLE profiles (id TEXT PRIMARY KEY, phone TEXT NOT NULL, version INTEGER NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, nickname TEXT)',
          );
          await db.execute(
            'CREATE TABLE records (id TEXT PRIMARY KEY, profile_id TEXT NOT NULL REFERENCES profiles(id), date TEXT NOT NULL, local_time TEXT, time_zone TEXT, utc_offset_minutes INTEGER, ease_id TEXT NOT NULL, ease_name TEXT NOT NULL, amount_id TEXT NOT NULL, amount_name TEXT NOT NULL, amount_value INTEGER, version INTEGER NOT NULL, created_at TEXT NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
          );
        },
      ),
    );
    return Business._(db, now ?? DateTime.now);
  }

  String get today {
    final date = now();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<List<Map<String, Object?>>> profiles() =>
      _db.query('profiles', where: 'deleted = 0', orderBy: 'rowid');

  Future<Map<String, Object?>?> activeProfile() async {
    final rows = await _db.query("profiles", where: _activeWhere, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<String?> phone() async {
    final rows = await _db.query('profiles', where: _activeWhere, limit: 1);
    return rows.isEmpty ? null : rows.first['phone'] as String;
  }

  static const _activeWhere =
      "deleted = 0 AND id = (SELECT id FROM profiles WHERE deleted = 0 ORDER BY id = COALESCE((SELECT value FROM settings WHERE key = 'profile'), '') DESC, rowid LIMIT 1)";

  Future<void> selectProfile(String id) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'profiles',
        where: 'id = ? AND deleted = 0',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('档案不存在');
      await txn.insert('settings', {
        'key': 'profile',
        'value': id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _validatePhone(
    Transaction txn,
    String phone, {
    String? except,
  }) async {
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      throw ArgumentError('请输入中国大陆 11 位手机号');
    }
    final rows = await txn.query(
      'profiles',
      where: 'phone = ? AND deleted = 0 AND id != ?',
      whereArgs: [phone, except ?? ''],
    );
    if (rows.isNotEmpty) throw ArgumentError('该手机号已有有效档案');
  }

  Future<void> createProfile(String phone, {String? nickname}) async {
    await _db.transaction((txn) async {
      await _validatePhone(txn, phone);
      final id = const Uuid().v4();
      await txn.insert('profiles', {
        'id': id,
        'phone': phone,
        'nickname': nickname?.trim(),
        'version': 1,
        'modified_at': now().toUtc().toIso8601String(),
      });
      await txn.insert('settings', {
        'key': 'profile',
        'value': id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> updatePhone(String phone, {String? nickname}) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('profiles', where: _activeWhere);
      if (rows.isEmpty) throw StateError('请先创建档案');
      final row = rows.first;
      if (nickname == null || phone != row['phone']) {
        await _validatePhone(txn, phone, except: row['id'] as String);
      }
      await txn.update(
        'profiles',
        {
          'phone': phone,
          'nickname': nickname?.trim() ?? row['nickname'],
          'version': (row['version'] as int) + 1,
          'modified_at': now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    });
  }

  Future<void> deleteProfile() async {
    await _db.transaction((txn) async {
      final rows = await txn.query('profiles', where: _activeWhere);
      if (rows.isEmpty) throw StateError('请先创建档案');
      final row = rows.first;
      await txn.delete(
        'records',
        where: 'profile_id = ?',
        whereArgs: [row['id']],
      );
      await txn.delete(
        'no_poop',
        where: 'profile_id = ?',
        whereArgs: [row['id']],
      );
      await txn.update(
        'profiles',
        {
          'phone': '',
          'deleted': 1,
          'version': (row['version'] as int) + 1,
          'modified_at': now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    });
  }

  Future<void> saveToday(String? ease, String? amount) =>
      saveRecord(date: today, ease: ease, amount: amount);

  Future<void> saveRecord({
    required String date,
    String? id,
    String? time,
    String? ease,
    String? amount,
  }) async {
    final current = now();
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        formatDate(parsed) != date ||
        date.compareTo(formatDate(current)) > 0) {
      throw ArgumentError('请选择今天或过去的日期');
    }
    if (time != null) {
      if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
        throw ArgumentError('请输入有效时间');
      }
      final local = DateTime.parse('${date}T$time:00');
      if (local.isAfter(current)) throw ArgumentError('不能记录未来时刻');
    }
    await _db.transaction((txn) async {
      final profiles = await txn.query(
        'profiles',
        where: _activeWhere,
        limit: 1,
      );
      if (profiles.isEmpty) throw StateError('请先创建档案');
      final existing = id == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'records',
              where: 'id = ? AND profile_id = ? AND deleted = 0',
              whereArgs: [id, profiles.first['id']],
            );
      if (id != null && existing.isEmpty) throw StateError('记录不存在');
      final old = existing.isEmpty ? null : existing.first;
      if ((ease == null && old == null) ||
          (amount == null && old == null) ||
          (ease != null && !easeOptions.contains(ease)) ||
          (amount != null && !RegExp(r'^[1-4]$').hasMatch(amount))) {
        throw ArgumentError('请选择排便通畅度和排便量');
      }
      final timestamp = current.toUtc().toIso8601String();
      final keepZone =
          old != null && old['date'] == date && old['local_time'] == time;
      final local = time == null ? null : DateTime.parse('${date}T$time:00');
      final values = <String, Object?>{
        'date': date,
        'local_time': time,
        'time_zone': keepZone ? old['time_zone'] : local?.timeZoneName,
        'utc_offset_minutes': keepZone
            ? old['utc_offset_minutes']
            : local?.timeZoneOffset.inMinutes,
        if (ease != null) ...{
          'ease_id': 'preset.ease.${easeOptions.indexOf(ease)}',
          'ease_name': ease,
        },
        if (amount != null) ...{
          'amount_id': 'numeric.amount.$amount',
          'amount_name': amount,
          'amount_value': int.parse(amount),
        },
        'version': old == null ? 1 : (old['version'] as int) + 1,
        'modified_at': timestamp,
      };
      await txn.delete(
        'no_poop',
        where: 'profile_id = ? AND date = ?',
        whereArgs: [profiles.first['id'], date],
      );
      if (id == null) {
        await txn.insert('records', {
          ...values,
          'id': const Uuid().v4(),
          'profile_id': profiles.first['id'],
          'created_at': timestamp,
        });
      } else {
        await txn.update('records', values, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  static String formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<Map<String, int>> dailyCounts() async {
    final rows = await _db.rawQuery(
      'SELECT date, COUNT(*) AS count FROM records WHERE deleted = 0 AND profile_id = (SELECT id FROM profiles WHERE $_activeWhere) GROUP BY date',
    );
    final confirmations = await _db.rawQuery(
      'SELECT date FROM no_poop WHERE profile_id = (SELECT id FROM profiles WHERE $_activeWhere)',
    );
    return {
      for (final row in confirmations) row['date'] as String: 0,
      for (final row in rows) row['date'] as String: row['count'] as int,
    };
  }

  Future<List<Map<String, Object?>>> todayRecords() => recordsForDate(today);

  Future<List<Map<String, Object?>>> recordsForDate(String date) async {
    final profiles = await _db.query('profiles', where: _activeWhere, limit: 1);
    if (profiles.isEmpty) return [];
    return _db.query(
      'records',
      where: 'profile_id = ? AND date = ? AND deleted = 0',
      whereArgs: [profiles.first['id'], date],
      orderBy:
          'local_time IS NULL, local_time DESC, created_at DESC, rowid DESC',
    );
  }

  Future<void> confirmNoPoop(String date, {bool deleteRecords = false}) async {
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        formatDate(parsed) != date ||
        date.compareTo(today) > 0) {
      throw ArgumentError('请选择今天或过去的日期');
    }
    await _db.transaction((txn) async {
      final profiles = await txn.query(
        'profiles',
        where: _activeWhere,
        limit: 1,
      );
      if (profiles.isEmpty) throw StateError('请先创建档案');
      final profile = profiles.first['id'];
      final records = await txn.query(
        'records',
        where: 'profile_id = ? AND date = ? AND deleted = 0',
        whereArgs: [profile, date],
      );
      if (records.isNotEmpty && !deleteRecords) throw StateError('需要确认删除当天记录');
      for (final record in records) {
        await txn.update(
          'records',
          {
            'deleted': 1,
            'version': (record['version'] as int) + 1,
            'modified_at': now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [record['id']],
        );
      }
      await txn.insert('no_poop', {
        'profile_id': profile,
        'date': date,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<void> deleteRecord(String id) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'records',
        where:
            'id = ? AND deleted = 0 AND profile_id = (SELECT id FROM profiles WHERE $_activeWhere)',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('记录不存在');
      await txn.update(
        'records',
        {
          'deleted': 1,
          'version': (rows.first['version'] as int) + 1,
          'modified_at': now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<PeriodStatistics> statistics(DateTime start, DateTime end) async {
    final first = formatDate(start);
    final last = formatDate(end).compareTo(today) > 0 ? today : formatDate(end);
    return _db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT * FROM records WHERE deleted = 0 AND profile_id = (SELECT id FROM profiles WHERE $_activeWhere) AND date >= ? AND date <= ?',
        [first, last],
      );
      final confirmations = await txn.rawQuery(
        'SELECT date FROM no_poop WHERE profile_id = (SELECT id FROM profiles WHERE $_activeWhere) AND date >= ? AND date <= ?',
        [first, last],
      );
      final recordedDays = rows.map((r) => r['date']).toSet().length;
      final days = first.compareTo(last) > 0
          ? 0
          : DateTime.utc(
                      DateTime.parse(last).year,
                      DateTime.parse(last).month,
                      DateTime.parse(last).day,
                    )
                    .difference(
                      DateTime.utc(start.year, start.month, start.day),
                    )
                    .inDays +
                1;
      final ease = {for (final name in easeOptions) name: 0};
      final amount = {for (final value in amountOptions) value: 0};
      for (final row in rows) {
        final e = easeCategory(row);
        final a = amountCategory(row);
        ease[e] = (ease[e] ?? 0) + 1;
        amount[a] = (amount[a] ?? 0) + 1;
      }
      final keys = amount.keys.toList()
        ..sort(
          (a, b) => (int.tryParse(a) ?? 100).compareTo(int.tryParse(b) ?? 100),
        );
      return PeriodStatistics(
        rows.length,
        recordedDays,
        confirmations.length,
        days - recordedDays - confirmations.length,
        ease,
        {for (final key in keys) key: amount[key]!},
      );
    });
  }

  Future<String> exportBackup() => _db.transaction((txn) async {
    final profiles = await txn.query('profiles', orderBy: 'rowid');
    final records = await txn.rawQuery(
      'SELECT records.* FROM records JOIN profiles ON records.profile_id = profiles.id WHERE profiles.deleted = 0 ORDER BY records.rowid',
    );
    final confirmations = await txn.rawQuery(
      'SELECT no_poop.* FROM no_poop JOIN profiles ON no_poop.profile_id = profiles.id WHERE profiles.deleted = 0 ORDER BY no_poop.rowid',
    );
    final current = now();
    return jsonEncode({
      'format_version': 1,
      'exported_at': current.toUtc().toIso8601String(),
      'time_zone': current.timeZoneName,
      'utc_offset_minutes': current.timeZoneOffset.inMinutes,
      'profiles': [
        for (final profile in profiles)
          if (profile['deleted'] == 0)
            profile
          else
            {
              for (final key in ['id', 'version', 'modified_at', 'deleted'])
                key: profile[key],
            },
      ],
      'records': records,
      'no_poop': confirmations,
    });
  });

  Future<String> _importSnapshot(Transaction txn) async => jsonEncode({
    for (final table in ['profiles', 'records', 'no_poop', 'settings'])
      table: await txn.query(table, orderBy: 'rowid'),
  });

  Future<ImportPreview> previewImport(
    String source, {
    Set<String> skippedProfileIds = const {},
  }) async {
    final data = jsonDecode(source);
    if (data is! Map || data['format_version'] != 1) {
      throw const FormatException('不支持的备份版本，请先使用原版本升级并重新导出');
    }
    final rows = <String, List<Map<String, Object?>>>{};
    for (final table in ['profiles', 'records', 'no_poop']) {
      if (data[table] is! List) throw const FormatException('备份缺少数据列表');
      rows[table] = (data[table] as List).map((r) {
        if (r is! Map) throw const FormatException('备份对象损坏');
        return Map<String, Object?>.from(r);
      }).toList();
    }
    void require(bool valid, String reason) {
      if (!valid) throw FormatException(reason);
    }

    bool text(Object? v) => v is String && v.isNotEmpty;
    bool timestamp(Object? v) =>
        v is String &&
        DateTime.tryParse(v) != null &&
        !DateTime.parse(v).isAfter(now());
    bool date(Object? v) =>
        v is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
        DateTime.tryParse(v) != null &&
        formatDate(DateTime.parse(v)) == v &&
        v.compareTo(today) <= 0;
    require(
      timestamp(data['exported_at']) &&
          text(data['time_zone']) &&
          data['utc_offset_minutes'] is int,
      '备份时间或时区无效',
    );
    const columns = {
      'profiles': {'id', 'phone', 'nickname', 'version', 'modified_at', 'deleted'},
      'records': {
        'id',
        'profile_id',
        'date',
        'local_time',
        'time_zone',
        'utc_offset_minutes',
        'ease_id',
        'ease_name',
        'amount_id',
        'amount_name',
        'amount_value',
        'version',
        'created_at',
        'modified_at',
        'deleted',
      },
      'no_poop': {'profile_id', 'date'},
    };
    for (final table in rows.keys) {
      for (final row in rows[table]!) {
        final required = {...columns[table]!}..remove('nickname');
        if (table == 'profiles') {
          require(row['nickname'] == null || row['nickname'] is String, '昵称无效');
        }
        if (table == 'profiles' && row['deleted'] == 1) {
          required.remove('phone');
        }
        require(
          required.every(row.containsKey) &&
              row.keys.every(columns[table]!.contains),
          '备份字段缺失或未知',
        );
      }
    }
    final profiles = <String, Map<String, Object?>>{};
    final ids = <String>{};
    for (final table in ['profiles', 'records']) {
      for (final row in rows[table]!) {
        require(
          text(row['id']) && ids.add(row['id'] as String),
          '备份包含重复或矛盾 UID',
        );
        require(
          row['version'] is int &&
              (row['version'] as int) > 0 &&
              timestamp(row['modified_at']) &&
              [0, 1].contains(row['deleted']),
          '对象版本、删除状态或时间无效',
        );
        if (table == 'profiles') {
          require(
            row['deleted'] == 1 ||
                (row['phone'] is String &&
                    RegExp(r'^1[3-9]\d{9}$').hasMatch(row['phone'] as String)),
            '档案手机号无效',
          );
          profiles[row['id'] as String] = row;
        }
      }
    }
    final days = <String>{};
    for (final row in rows['no_poop']!) {
      require(
        date(row['date']) && profiles[row['profile_id']]?['deleted'] == 0,
        '未排便确认日期或档案引用无效',
      );
      require(days.add('${row['profile_id']}/${row['date']}'), '重复日期状态');
    }
    for (final row in rows['records']!) {
      require(
        profiles[row['profile_id']]?['deleted'] == 0 &&
            date(row['date']) &&
            timestamp(row['created_at']),
        '记录日期、时间或档案引用无效',
      );
      for (final key in ['ease_id', 'ease_name', 'amount_id', 'amount_name']) {
        require(text(row[key]), '记录缺少历史选项');
      }
      final amount = row['amount_value'];
      require(
        amount == null || (amount is int && amount >= 1 && amount <= 99),
        '排便量无效',
      );
      final time = row['local_time'];
      require(
        time == null ||
            (time is String &&
                RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time) &&
                !DateTime.parse('${row['date']}T$time:00').isAfter(now()) &&
                text(row['time_zone']) &&
                row['utc_offset_minutes'] is int),
        '记录具体时间或时区无效',
      );
      require(
        row['deleted'] == 1 ||
            !days.contains('${row['profile_id']}/${row['date']}'),
        '备份内排便记录与未排便确认互斥：${row['date']}',
      );
    }
    return _db.transaction((txn) async {
      var added = 0, overwritten = 0, restored = 0, skipped = 0, cleared = 0;
      final filtered = <String, dynamic>{...data};
      for (final table in rows.keys) {
        filtered[table] = rows[table]!
            .where(
              (row) => !skippedProfileIds.contains(
                row[table == 'profiles' ? 'id' : 'profile_id'],
              ),
            )
            .toList();
        skipped += rows[table]!.length - (filtered[table] as List).length;
        rows[table] = List<Map<String, Object?>>.from(filtered[table] as List);
      }

      for (final table in rows.keys) {
        for (final row in rows[table]!) {
          final where = table == 'no_poop'
              ? 'profile_id = ? AND date = ?'
              : 'id = ?';
          final args = table == 'no_poop'
              ? [row['profile_id'], row['date']]
              : [row['id']];
          final old = await txn.query(table, where: where, whereArgs: args);
          if (old.isEmpty) {
            added++;
          } else if (row.entries.every((e) => old.first[e.key] == e.value)) {
            skipped++;
          } else if (old.first['deleted'] == 1 && row['deleted'] == 0) {
            restored++;
          } else {
            overwritten++;
          }
          if (table == 'no_poop') {
            cleared += Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM records WHERE profile_id = ? AND date = ? AND deleted = 0',
                args,
              ),
            )!;
          }
        }
      }
      return ImportPreview._(
        jsonEncode(filtered),
        await _importSnapshot(txn),
        added,
        overwritten,
        restored,
        skipped,
        cleared,
      );
    });
  }

  Future<void> applyImport(ImportPreview preview) async {
    // 提交前重新校验，避免预览期间跨日或时间变化。
    await previewImport(preview._source);
    final data = jsonDecode(preview._source) as Map<String, dynamic>;
    await _db.transaction((txn) async {
      if (await _importSnapshot(txn) != preview._snapshot) {
        throw StateError('本机数据已变化，请重新预览并确认');
      }
      for (final raw in data['profiles'] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        if (row['deleted'] == 1) {
          row['phone'] = '';
          await txn.delete(
            'records',
            where: 'profile_id = ?',
            whereArgs: [row['id']],
          );
          await txn.delete(
            'no_poop',
            where: 'profile_id = ?',
            whereArgs: [row['id']],
          );
        }
        await txn.insert(
          'profiles',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final raw in data['records'] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        if (row['deleted'] == 0) {
          await txn.delete(
            'no_poop',
            where: 'profile_id = ? AND date = ?',
            whereArgs: [row['profile_id'], row['date']],
          );
        }
        await txn.insert(
          'records',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final raw in data['no_poop'] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        await txn.update(
          'records',
          {'deleted': 1},
          where: 'profile_id = ? AND date = ? AND deleted = 0',
          whereArgs: [row['profile_id'], row['date']],
        );
        await txn.insert(
          'no_poop',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> close() => _db.close();
}

class PeriodStatistics {
  const PeriodStatistics(
    this.total,
    this.recordedDays,
    this.confirmedDays,
    this.unfilledDays,
    this.ease,
    this.amount,
  );
  final int total;
  final int recordedDays;
  final int confirmedDays;
  final int unfilledDays;
  final Map<String, int> ease;
  final Map<String, int> amount;
}

class ImportPreview {
  const ImportPreview._(
    this._source,
    this._snapshot,
    this.added,
    this.overwritten,
    this.restored,
    this.skipped,
    this.cleared,
  );
  final String _source;
  final String _snapshot;
  final int added, overwritten, restored, skipped, cleared;
}
