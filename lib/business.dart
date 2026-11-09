import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class Business {
  Business._(this._db, this.now);
  final Database _db;
  final DateTime Function() now;
  static const easeOptions = ['困难', '一般', '顺畅'];
  static const amountOptions = ['少', '中', '多'];

  static Future<Business> open(
    String path, {
    DatabaseFactory? factory,
    DateTime Function()? now,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await db.execute('ALTER TABLE records ADD COLUMN local_time TEXT');
          await db.execute('ALTER TABLE records ADD COLUMN time_zone TEXT');
          await db.execute(
            'ALTER TABLE records ADD COLUMN utc_offset_minutes INTEGER',
          );
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE profiles (id TEXT PRIMARY KEY, phone TEXT NOT NULL UNIQUE, version INTEGER NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE records (id TEXT PRIMARY KEY, profile_id TEXT NOT NULL REFERENCES profiles(id), date TEXT NOT NULL, local_time TEXT, time_zone TEXT, utc_offset_minutes INTEGER, ease_id TEXT NOT NULL, ease_name TEXT NOT NULL, amount_id TEXT NOT NULL, amount_name TEXT NOT NULL, version INTEGER NOT NULL, created_at TEXT NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
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

  Future<String?> phone() async {
    final rows = await _db.query('profiles', where: 'deleted = 0', limit: 1);
    return rows.isEmpty ? null : rows.first['phone'] as String;
  }

  Future<void> createProfile(String phone) async {
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      throw ArgumentError('请输入中国大陆 11 位手机号');
    }
    await _db.transaction((txn) async {
      await txn.insert('profiles', {
        'id': const Uuid().v4(),
        'phone': phone,
        'version': 1,
        'modified_at': now().toUtc().toIso8601String(),
      });
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
        where: 'deleted = 0',
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
          (amount != null && !amountOptions.contains(amount))) {
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
          'amount_id': 'preset.amount.${amountOptions.indexOf(amount)}',
          'amount_name': amount,
        },
        'version': old == null ? 1 : (old['version'] as int) + 1,
        'modified_at': timestamp,
      };
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
      'SELECT date, COUNT(*) AS count FROM records WHERE deleted = 0 AND profile_id = (SELECT id FROM profiles WHERE deleted = 0 LIMIT 1) GROUP BY date',
    );
    return {for (final row in rows) row['date'] as String: row['count'] as int};
  }

  Future<List<Map<String, Object?>>> todayRecords() => recordsForDate(today);

  Future<List<Map<String, Object?>>> recordsForDate(String date) async {
    final profiles = await _db.query(
      'profiles',
      where: 'deleted = 0',
      limit: 1,
    );
    if (profiles.isEmpty) return [];
    return _db.query(
      'records',
      where: 'profile_id = ? AND date = ? AND deleted = 0',
      whereArgs: [profiles.first['id'], date],
      orderBy: 'local_time IS NULL, local_time, created_at, rowid',
    );
  }

  Future<void> close() => _db.close();
}
