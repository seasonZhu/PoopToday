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
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE profiles (id TEXT PRIMARY KEY, phone TEXT NOT NULL UNIQUE, version INTEGER NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE records (id TEXT PRIMARY KEY, profile_id TEXT NOT NULL REFERENCES profiles(id), date TEXT NOT NULL, ease_id TEXT NOT NULL, ease_name TEXT NOT NULL, amount_id TEXT NOT NULL, amount_name TEXT NOT NULL, version INTEGER NOT NULL, created_at TEXT NOT NULL, modified_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
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

  Future<void> saveToday(String? ease, String? amount) async {
    if (!easeOptions.contains(ease) || !amountOptions.contains(amount)) {
      throw ArgumentError('请选择排便通畅度和排便量');
    }
    final date = today;
    final timestamp = now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      final profiles = await txn.query(
        'profiles',
        where: 'deleted = 0',
        limit: 1,
      );
      if (profiles.isEmpty) throw StateError('请先创建档案');
      await txn.insert('records', {
        'id': const Uuid().v4(),
        'profile_id': profiles.first['id'],
        'date': date,
        'ease_id': 'preset.ease.${easeOptions.indexOf(ease!)}',
        'ease_name': ease,
        'amount_id': 'preset.amount.${amountOptions.indexOf(amount!)}',
        'amount_name': amount,
        'version': 1,
        'created_at': timestamp,
        'modified_at': timestamp,
      });
    });
  }

  Future<List<Map<String, Object?>>> todayRecords() async {
    final profiles = await _db.query(
      'profiles',
      where: 'deleted = 0',
      limit: 1,
    );
    if (profiles.isEmpty) return [];
    return _db.query(
      'records',
      where: 'profile_id = ? AND date = ? AND deleted = 0',
      whereArgs: [profiles.first['id'], today],
      orderBy: 'created_at, rowid',
    );
  }

  Future<void> close() => _db.close();
}
