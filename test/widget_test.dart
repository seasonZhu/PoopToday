import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:poop_today/business.dart';
import 'package:poop_today/main.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets('创建档案后两项无预选，必选校验后保存并展示', (tester) async {
    sqfliteFfiInit();
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('poop_widget'),
    ))!;
    final app = (await tester.runAsync(
      () => Business.open(
        '${dir.path}/db',
        factory: databaseFactoryFfi,
        now: () => DateTime(2026, 11, 9, 12),
      ),
    ))!;
    addTearDown(() async {
      await tester.runAsync(app.close);
      await tester.runAsync(() => dir.delete(recursive: true));
    });
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '13800138000');
    await tester.tap(find.text('创建档案'));
    await waitFor(tester, find.text('保存今天的记录'));
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
    await waitFor(tester, find.text('顺畅 · 中'));
    expect(find.text('顺畅 · 中'), findsOneWidget);
  });
}
