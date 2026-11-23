part of 'business.dart';

class _BackupImport {
  _BackupImport(this._db, this.now);

  final Database _db;
  final DateTime Function() now;

  Future<String> _importSnapshot(Transaction txn) async => jsonEncode({
    for (final table in ['profiles', 'records', 'no_poop', 'settings'])
      table: await txn.query(table, orderBy: 'rowid'),
  });

  void _validate(
    Map<String, Object?> data,
    Map<String, List<Map<String, Object?>>> rows,
  ) {
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
        Business.formatDate(DateTime.parse(v)) == v &&
        v.compareTo(Business.formatDate(now())) <= 0;
    require(
      timestamp(data['exported_at']) &&
          text(data['time_zone']) &&
          data['utc_offset_minutes'] is int,
      '备份时间或时区无效',
    );
    const columns = {
      'profiles': {
        'id',
        'phone',
        'nickname',
        'version',
        'modified_at',
        'deleted',
      },
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
  }

  Future<ImportPreview> previewImport(
    String source, {
    Set<String> skippedProfileIds = const {},
    bool preferLocal = false,
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
    final metadata = <String, Object?>{
      for (final key in ['exported_at', 'time_zone', 'utc_offset_minutes'])
        key: data[key],
    };
    _validate(metadata, rows);
    return _db.transaction((txn) async {
      var added = 0, overwritten = 0, restored = 0, skipped = 0, cleared = 0;
      for (final table in rows.keys) {
        final retained = rows[table]!
            .where(
              (row) => !skippedProfileIds.contains(
                row[table == 'profiles' ? 'id' : 'profile_id'],
              ),
            )
            .toList();
        skipped += rows[table]!.length - retained.length;
        rows[table] = retained;
      }

      final localProfiles = await txn.query('profiles', where: 'deleted = 0');
      final profileMapping = <String, String>{};
      for (final row in rows['profiles']!) {
        final matches = localProfiles
            .where(
              (local) =>
                  local['id'] == row['id'] ||
                  (row['deleted'] == 0 && local['phone'] == row['phone']),
            )
            .toList();
        if (matches.isEmpty) continue;
        final local = matches.firstWhere(
          (local) => local['id'] == row['id'],
          orElse: () => matches.first,
        );
        profileMapping[row['id'] as String] = local['id'] as String;
        row['id'] = local['id'];
        if (preferLocal) row.addAll(local);
      }
      for (final table in ['records', 'no_poop']) {
        final retained = <Map<String, Object?>>[];
        for (final row in rows[table]!) {
          row['profile_id'] =
              profileMapping[row['profile_id']] ?? row['profile_id'];
          if (preferLocal) {
            final sameRecord = table == 'records'
                ? await txn.query(
                    'records',
                    where: 'id = ?',
                    whereArgs: [row['id']],
                  )
                : <Map<String, Object?>>[];
            final opposite = await txn.query(
              table == 'records' ? 'no_poop' : 'records',
              where:
                  'profile_id = ? AND date = ?${table == 'no_poop' ? ' AND deleted = 0' : ''}',
              whereArgs: [row['profile_id'], row['date']],
            );
            if (sameRecord.isNotEmpty || opposite.isNotEmpty) {
              skipped++;
              continue;
            }
          }
          retained.add(row);
        }
        rows[table] = retained;
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
        metadata,
        rows,
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
    _validate(preview._metadata, preview._rows);
    await _db.transaction((txn) async {
      if (await _importSnapshot(txn) != preview._snapshot) {
        throw StateError('本机数据已变化，请重新预览并确认');
      }
      for (final row in preview._rows['profiles']!) {
        if (row['deleted'] == 1) {
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
          row['deleted'] == 1 ? {...row, 'phone': ''} : row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in preview._rows['records']!) {
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
      for (final row in preview._rows['no_poop']!) {
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
}

class ImportPreview {
  const ImportPreview._(
    this._metadata,
    this._rows,
    this._snapshot,
    this.added,
    this.overwritten,
    this.restored,
    this.skipped,
    this.cleared,
  );
  final Map<String, Object?> _metadata;
  final Map<String, List<Map<String, Object?>>> _rows;
  final String _snapshot;
  final int added, overwritten, restored, skipped, cleared;
}
