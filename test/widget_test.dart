import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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
  testWidgets('导入预览取消不写入，本机变化后再次确认', (tester) async {
    sqfliteFfiInit();
    final app = (await tester.runAsync(
      () => Business.open(inMemoryDatabasePath, factory: databaseFactoryFfi),
    ))!;
    addTearDown(() => tester.runAsync(app.close));
    await tester.runAsync(() => app.createProfile('13800138000'));
    final backup = (await tester.runAsync(app.exportBackup))!;
    await tester.runAsync(() => app.updatePhone('13900139000'));
    final original = FilePickerPlatform.instance;
    FilePickerPlatform.instance = ImportPicker(backup);
    addTearDown(() => FilePickerPlatform.instance = original);
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.byTooltip('导入备份'));
    await waitFor(tester, find.textContaining('导入内容优先'));
    expect(find.textContaining('覆盖 1'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(app.phone), '13900139000');
    await tester.tap(find.byTooltip('导入备份'));
    await waitFor(tester, find.textContaining('导入内容优先'));
    await tester.runAsync(() => app.updatePhone('13700137000'));
    await tester.tap(find.text('确认'));
    await waitFor(tester, find.textContaining('导入内容优先'));
    expect(await tester.runAsync(app.phone), '13700137000');
    await tester.tap(find.text('确认'));
    await waitFor(tester, find.text('13800138000'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('导出先提示敏感数据，取消后保留档案', (tester) async {
    sqfliteFfiInit();
    final app = (await tester.runAsync(
      () => Business.open(inMemoryDatabasePath, factory: databaseFactoryFfi),
    ))!;
    addTearDown(() => tester.runAsync(app.close));
    await tester.runAsync(() => app.createProfile('13800138000'));
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.byTooltip('导出备份'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未加密'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(app.phone), '13800138000');
  });

  testWidgets('保存文件失败后业务数据保持不变', (tester) async {
    sqfliteFfiInit();
    final app = (await tester.runAsync(
      () => Business.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        now: () => DateTime(2026, 11, 9),
      ),
    ))!;
    addTearDown(() => tester.runAsync(app.close));
    await tester.runAsync(() => app.createProfile('13800138000'));
    final before = await tester.runAsync(app.exportBackup);
    final original = FilePickerPlatform.instance;
    final picker = FailingSavePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.byTooltip('导出备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await waitFor(tester, find.text('导出失败，请重试'));
    expect(picker.called, isTrue);
    expect(await tester.runAsync(app.exportBackup), before);
  });

  testWidgets('首页周月共享切换、空状态与柱子次数占比', (tester) async {
    sqfliteFfiInit();
    final app = (await tester.runAsync(
      () => Business.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        now: () => DateTime(2026, 11, 9, 12),
      ),
    ))!;
    addTearDown(() => tester.runAsync(app.close));
    await tester.runAsync(() async {
      await app.createProfile('13800138000');
      await app.saveToday('顺畅', '9');
    });
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('排便量分布'));
    await tester.ensureVisible(find.text('💩 × 9'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('💩 × 9'));
    await tester.pumpAndSettle();
    expect(find.text('1次 · 100.0%'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('周'));
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('2026-11-09 ～ 2026-11-15'));
    await tester.tap(find.byTooltip('前一周'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('暂无排便记录').first);
    expect(find.text('暂无排便记录'), findsNWidgets(2));
  });

  testWidgets('档案选择器与删除确认，最后档案删除后建档', (tester) async {
    sqfliteFfiInit();
    final app = (await tester.runAsync(
      () => Business.open(inMemoryDatabasePath, factory: databaseFactoryFfi),
    ))!;
    addTearDown(() => tester.runAsync(app.close));
    await tester.runAsync(() => app.createProfile('13800138000'));
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.text('13800138000'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('管理档案'));
    await tester.tap(find.text('删除档案'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('确认'));
    expect(find.textContaining('全部排便记录和日期状态'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(app.phone), '13800138000');
    await tester.tap(find.text('13800138000'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('删除档案'));
    await tester.tap(find.text('删除档案'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('确认'));
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('创建本地用户档案'));
  });

  testWidgets('自定义数值仅本次填写，不增加快捷项', (tester) async {
    sqfliteFfiInit();
    final app = (await tester.runAsync(
      () => Business.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        now: () => DateTime(2026, 11, 9, 12),
      ),
    ))!;
    addTearDown(() => tester.runAsync(app.close));
    await tester.runAsync(() => app.createProfile('13800138000'));
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.text('记录今天'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('😊 顺畅'));
    await tester.tap(find.text('😊 顺畅'));
    final input = find.widgetWithText(TextField, '自定义排便量（1～99）');
    await tester.ensureVisible(input);
    await tester.enterText(input, '9');
    await tester.ensureVisible(find.text('保存今天的记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存今天的记录'));
    await waitFor(tester, find.text('顺畅 · 💩 × 9'));
    expect(
      (await tester.runAsync(app.todayRecords))!.single['amount_value'],
      9,
    );
    expect(tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).length, 6);
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => !chip.selected),
      isTrue,
    );
    expect(find.text('新增选项'), findsNothing);
  });

  testWidgets('确认未排便可取消，点击与完整侧滑直接删除', (tester) async {
    sqfliteFfiInit();
    final app = (await tester.runAsync(
      () => Business.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        now: () => DateTime(2026, 11, 9, 12),
      ),
    ))!;
    addTearDown(() => tester.runAsync(app.close));
    await tester.runAsync(() async {
      await app.createProfile('13800138000');
      await app.saveToday('顺畅', '3');
    });
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.text('记录今天'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('确认当天未排便'));
    await tester.ensureVisible(find.text('确认当天未排便'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认当天未排便'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(app.todayRecords))!.length, 1);
    await tester.ensureVisible(find.byTooltip('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除记录'));
    await waitFor(tester, find.text('尚未填写'));
    expect(find.text('撤销'), findsNothing);
    await tester.runAsync(() => app.saveToday('顺畅', '3'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.text('记录今天'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('确认当天未排便'));
    await tester.scrollUntilVisible(
      find.byType(Dismissible),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await waitFor(tester, find.byType(Dismissible));
    await tester.ensureVisible(find.byType(Dismissible));
    await tester.drag(find.byType(Dismissible), const Offset(-800, 0));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('尚未填写'));
    expect((await tester.runAsync(app.todayRecords))!, isEmpty);
    await tester.runAsync(() => app.saveToday('顺畅', '3'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(PoopTodayApp(business: app));
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.text('记录今天'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('确认当天未排便'));
    await tester.ensureVisible(find.text('确认当天未排便'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认当天未排便'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await waitFor(tester, find.text('确认未排便'));
    expect((await tester.runAsync(app.todayRecords))!, isEmpty);
  });

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
    await waitFor(tester, find.text('记录今天'));
    await tester.tap(find.text('记录今天'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('保存今天的记录'));
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => !chip.selected),
      isTrue,
    );
    await tester.ensureVisible(find.text('保存今天的记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存今天的记录'));
    await waitFor(tester, find.text('请选择排便通畅度和排便量'));
    await tester.ensureVisible(find.text('😊 顺畅'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😊 顺畅'));
    await tester.ensureVisible(find.text('💩 × 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('💩 × 3'));
    await tester.ensureVisible(find.text('保存今天的记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存今天的记录'));
    await waitFor(tester, find.text('顺畅 · 💩 × 3'));
    expect(find.text('顺畅 · 💩 × 3'), findsOneWidget);
    await tester.tap(find.text('顺畅 · 💩 × 3'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('日历补录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日历补录'));
    await tester.pumpAndSettle();
    expect(find.text('一'), findsOneWidget);
    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await waitFor(tester, find.text('保存记录'));
    await tester.ensureVisible(find.text('顺畅 · 💩 × 3'));
    await tester.pumpAndSettle();
    final historical = await tester.runAsync(
      () => app.recordsForDate('2026-11-08'),
    );
    expect(historical!.single['ease_name'], '顺畅');
    await tester.tap(find.text('顺畅 · 💩 × 3'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('返回今天').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回今天').first);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的改动？'), findsNothing);
    expect(find.text('保存今天的记录'), findsOneWidget);
  });
}

class FailingSavePicker extends FilePickerPlatform {
  bool called = false;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    called = true;
    throw StateError('保存失败');
  }
}

class ImportPicker extends FilePickerPlatform {
  ImportPicker(this.source);
  final String source;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => ImportFile(source);
}

final class ImportFile extends PlatformFile {
  ImportFile(this.source);
  final String source;
  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(utf8.encode(source));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
