import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:poop_today/business.dart';
import 'package:poop_today/main.dart';

void main() {
  testWidgets('创建档案后两项无预选，必选校验后保存并展示', (tester) async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('poop_widget');
    final app = await Business.open(
      '${dir.path}/db',
      factory: databaseFactoryFfi,
      now: () => DateTime(2026, 11, 9, 12),
    );
    addTearDown(() async {
      await app.close();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(PoopTodayApp(business: app));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '13800138000');
    await tester.tap(find.text('创建档案'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => !chip.selected),
      isTrue,
    );
    await tester.tap(find.text('保存今天的记录'));
    await tester.pumpAndSettle();
    expect(find.text('请选择排便通畅度和排便量'), findsOneWidget);
    await tester.tap(find.text('顺畅'));
    await tester.tap(find.text('中'));
    await tester.tap(find.text('保存今天的记录'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('顺畅 · 中'), findsOneWidget);
  });
}
