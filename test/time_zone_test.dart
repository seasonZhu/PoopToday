import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/business.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('跨时区重新打开保留日期、当地时间和原时区', () async {
    final databasePath = Platform.environment['POOP_TIME_ZONE_DB'];
    if (databasePath != null) {
      sqfliteFfiInit();
      final app = await Business.open(
        databasePath,
        factory: databaseFactoryFfi,
        now: () => DateTime(2026, 11, 10, 12),
      );
      try {
        if (Platform.environment['TZ'] == 'America/New_York') {
          await app.createProfile('13800138000');
          await app.saveRecord(
            date: '2026-11-08',
            time: '09:30',
            ease: '一般',
            amount: '中',
          );
        } else {
          final record = (await app.recordsForDate('2026-11-08')).single;
          expect(record['local_time'], '09:30');
          expect(record['utc_offset_minutes'], -300);
          expect(record['time_zone'], 'EST');
          await app.saveRecord(
            id: record['id'] as String,
            date: '2026-11-08',
            time: '09:30',
            amount: '多',
          );
          final edited = (await app.recordsForDate('2026-11-08')).single;
          expect(edited['utc_offset_minutes'], -300);
          expect(edited['time_zone'], 'EST');
        }
      } finally {
        await app.close();
      }
      return;
    }
    final directory = await Directory.systemTemp.createTemp('poop_timezone');
    try {
      var sdk = File(Platform.resolvedExecutable).parent;
      while (!File('${sdk.path}/bin/flutter').existsSync()) {
        if (sdk.parent.path == sdk.path) throw StateError('未找到 Flutter SDK');
        sdk = sdk.parent;
      }
      final flutter = '${sdk.path}/bin/flutter';
      for (final zone in ['America/New_York', 'Asia/Shanghai']) {
        final result = await Process.run(
          flutter,
          ['test', 'test/time_zone_test.dart', '--timeout', '45s'],
          environment: {
            'TZ': zone,
            'POOP_TIME_ZONE_DB': '${directory.path}/db',
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
