import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'business.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final business = await Business.open(
      path.join(await getDatabasesPath(), 'poop_today.db'),
    );
    runApp(PoopTodayApp(business: business));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('数据打开失败，请重新打开应用'))),
      ),
    );
  }
}

class PoopTodayApp extends StatelessWidget {
  const PoopTodayApp({super.key, required this.business});
  final Business business;
  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    title: '今天排便了吗',
    theme: ThemeData(
      colorSchemeSeed: Colors.teal,
      scaffoldBackgroundColor: const Color(0xFFFFFCF5),
      useMaterial3: true,
    ),
    home: RecordPage(business: business),
  );
}

class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.business});
  final Business business;
  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  bool exporting = false;

  Future<void> exportBackup() async {
    setState(() => exporting = true);
    try {
      if (!await confirm('备份未加密，包含手机号及排便数据，请妥善保管。是否继续保存？')) return;
      final data = await widget.business.exportBackup();
      final result = await FilePicker.saveFile(
        fileName: 'poop-today-${widget.business.today}.json',
        bytes: Uint8List.fromList(utf8.encode(data)),
        mimeType: 'application/json',
      );
      if (mounted && result != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('备份已保存')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  bool importing = false;

  Future<void> importBackup() async {
    if (!await discard()) return;
    setState(() => importing = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final source = utf8.decode(await file.readAsBytes());
      while (mounted) {
        final preview = await widget.business.previewImport(source);
        if (!await confirm(
          '导入内容优先，可能覆盖修改或恢复已删除记录。\n新增 ${preview.added}／覆盖 ${preview.overwritten}／恢复 ${preview.restored}／跳过 ${preview.skipped}\n日期清空影响：${preview.cleared} 条记录。是否导入？',
        )) {
          return;
        }
        try {
          await widget.business.applyImport(preview);
          editing = null;
          ease = null;
          amount = null;
          localTime = null;
          await refresh();
          return;
        } on StateError catch (error) {
          if (!error.message.contains('重新预览')) rethrow;
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  final phoneController = TextEditingController();
  final amountController = TextEditingController();
  late String selectedDate = widget.business.today;
  late DateTime calendarMonth = DateTime.parse(widget.business.today);
  int calendarRevision = 0;
  Map<String, int> counts = {};
  Map<String, Object?>? editing;
  String? localTime;
  bool get dirty =>
      (ease != null && ease != editing?['ease_name']) ||
      (amount != null &&
          amount !=
              (editing?['amount_value'] ?? editing?['amount_name'])
                  ?.toString()) ||
      localTime != editing?['local_time'] ||
      (editing != null && selectedDate != editing?['date']);

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('放弃未保存的改动？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> selectDate() async {
    final today = DateTime.parse(widget.business.today);
    final date = await showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择记录日期'),
        content: SizedBox(
          width: 340,
          height: 380,
          child: RecordCalendar(
            selected: DateTime.parse(selectedDate),
            today: today,
            counts: counts,
          ),
        ),
      ),
    );
    if (date == null || !mounted) return;
    setState(() {
      selectedDate = Business.formatDate(date);
    });
    await refresh();
  }

  bool calendarHome = true;
  String? phone;
  String? ease;
  String? amount;
  String? error;
  bool loading = true;
  bool saving = false;
  List<Map<String, Object?>> records = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final currentPhone = await widget.business.phone();
      final currentRecords = await widget.business.recordsForDate(selectedDate);
      final currentCounts = await widget.business.dailyCounts();
      if (!mounted) return;
      setState(() {
        counts = currentCounts;
        phone = currentPhone;
        records = currentRecords;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '读取失败，请重试';
          loading = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (phone == null) {
        await widget.business.createProfile(phoneController.text.trim());
      } else {
        await widget.business.saveRecord(
          date: selectedDate,
          id: editing?['id'] as String?,
          time: localTime,
          ease: ease,
          amount: amount,
        );
        editing = null;
        localTime = null;
        ease = null;
        amount = null;
        amountController.clear();
      }
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存成功')));
      }
    } on ArgumentError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<bool> confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> confirmDay() async {
    final hasRecords = (counts[selectedDate] ?? 0) > 0;
    if (hasRecords && !await confirm('删除当天记录并确认未排便？')) return;
    if (!mounted) return;
    setState(() => saving = true);
    try {
      await widget.business.confirmNoPoop(
        selectedDate,
        deleteRecords: hasRecords,
      );
      await refresh();
    } catch (_) {
      if (mounted) setState(() => error = '操作失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> deleteRecord(String id) async {
    setState(() => saving = true);
    try {
      await widget.business.deleteRecord(id);
      await refresh();
    } catch (_) {
      if (mounted) setState(() => error = '删除失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> manageProfiles() async {
    if (!await discard() || !mounted) return;
    final profiles = await widget.business.profiles();
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('管理档案'),
        children: [
          for (final profile in profiles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, profile['id'] as String),
              child: Text(
                '${profile['phone']}${profiles.where((p) => p['phone'] == profile['phone']).length > 1 ? ' · ${(profile['id'] as String).substring(0, 8)}' : ''}',
              ),
            ),
          for (final action in ['新增档案', '修改手机号', '删除档案'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, action),
              child: Text(action),
            ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    setState(() => saving = true);
    try {
      if (action == '删除档案') {
        if (!await confirm('删除档案 $phone？将清除该档案的全部排便记录和日期状态，删除最后一个档案后需重新建档。')) {
          return;
        }
        await widget.business.deleteProfile();
      } else if (action == '新增档案' || action == '修改手机号') {
        final controller = TextEditingController(
          text: action == '修改手机号' ? phone : '',
        );
        final value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(action),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              decoration: const InputDecoration(labelText: '手机号'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('保存'),
              ),
            ],
          ),
        );
        // 对话框退出动画结束后释放输入控制器。
        await Future<void>.delayed(const Duration(milliseconds: 300));
        controller.dispose();
        if (value == null) return;
        if (action == '新增档案') {
          await widget.business.createProfile(value);
        } else {
          await widget.business.updatePhone(value);
        }
      } else {
        await widget.business.selectProfile(action);
      }
      if (!mounted) return;
      setState(() {
        editing = null;
        ease = null;
        amount = null;
        localTime = null;
        amountController.clear();
        phoneController.clear();
        selectedDate = widget.business.today;
        calendarMonth = DateTime.parse(widget.business.today);
        calendarRevision++;
        calendarHome = true;
        error = null;
      });
      await refresh();
    } on ArgumentError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) setState(() => error = '档案操作失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    phoneController.dispose();
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: calendarHome && !dirty,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      if (await discard() && mounted) {
        setState(() {
          ease = null;
          amount = null;
          amountController.clear();
          editing = null;
          localTime = null;
          calendarHome = true;
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('今天排便了吗', style: TextStyle(fontSize: 20)),
        actions: [
          IconButton(
            tooltip: '导入备份',
            onPressed: importing || exporting ? null : importBackup,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: '导出备份',
            onPressed: exporting || importing ? null : exportBackup,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          if (phone != null)
            TextButton(
              onPressed: saving ? null : manageProfiles,
              child: Text(phone!),
            ),
        ],
        leading: calendarHome
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: saving
                    ? null
                    : () async {
                        if (!await discard() || !mounted) return;
                        setState(() {
                          calendarHome = true;
                          editing = null;
                          ease = null;
                          amount = null;
                          localTime = null;
                          amountController.clear();
                        });
                      },
              ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: PageStorageKey(calendarHome),
              padding: const EdgeInsets.all(24),
              children: [
                if (phone == null) ...[
                  const Text('创建本地用户档案', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    decoration: const InputDecoration(labelText: '手机号'),
                  ),
                ] else ...[
                  if (calendarHome)
                    HomeStatistics(
                      business: widget.business,
                      month: calendarMonth,
                      selected: DateTime.parse(selectedDate),
                      overview: true,
                    ),
                  Offstage(
                    offstage: !calendarHome,
                    child: SizedBox(
                      height: 380,
                      child: RecordCalendar(
                        key: ValueKey(calendarRevision),
                        initialMonth: calendarMonth,
                        onMonthChanged: (month) =>
                            setState(() => calendarMonth = month),
                        selected: DateTime.parse(selectedDate),
                        today: DateTime.parse(widget.business.today),
                        counts: counts,
                        onSelected: (date) async {
                          setState(() {
                            selectedDate = Business.formatDate(date);
                            calendarHome = false;
                          });
                          await refresh();
                        },
                      ),
                    ),
                  ),
                  if (calendarHome) ...[
                    const Text('次数表示排便次数 · — 表示未排便 · 留空表示尚未填写'),
                    TextButton(
                      onPressed: () async {
                        setState(() {
                          selectedDate = widget.business.today;
                          calendarHome = false;
                        });
                        await refresh();
                      },
                      child: const Text('记录今天'),
                    ),
                  ],
                  if (calendarHome)
                    HomeStatistics(
                      business: widget.business,
                      month: calendarMonth,
                      selected: DateTime.parse(selectedDate),
                    ),
                  if (!calendarHome) ...[
                    const SizedBox(height: 24),
                    Text(
                      '记录日期 $selectedDate',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: saving ? null : selectDate,
                          child: const Text('日历补录'),
                        ),
                        TextButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (!await discard() || !mounted) return;
                                  setState(() {
                                    selectedDate = widget.business.today;
                                    ease = null;
                                    amount = null;
                                    amountController.clear();
                                    editing = null;
                                    localTime = null;
                                  });
                                  await refresh();
                                },
                          child: const Text('返回今天'),
                        ),
                      ],
                    ),
                    if (counts.isNotEmpty)
                      Text(
                        '每日次数 · ${counts.entries.map((e) => '${e.key} ${e.value}次').join('，')}',
                      ),
                    TextButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (time != null && mounted) {
                                setState(
                                  () => localTime =
                                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                );
                              }
                            },
                      child: Text(localTime ?? '具体时间（选填）'),
                    ),
                    if (localTime != null)
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => setState(() => localTime = null),
                        child: const Text('清除时间'),
                      ),
                    if (editing != null) ...[
                      const Text('正在编辑记录，未重新选择的选项保留原名称'),
                      TextButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!await discard() || !mounted) return;
                                setState(() {
                                  selectedDate = editing!['date'] as String;
                                  editing = null;
                                  ease = null;
                                  amount = null;
                                  localTime = null;
                                  amountController.clear();
                                });
                                await refresh();
                              },
                        child: const Text('取消编辑'),
                      ),
                    ],
                    const Text('排便通畅度（必选）'),
                    Wrap(
                      spacing: 8,
                      children: Business.easeOptions
                          .map(
                            (value) => ChoiceChip(
                              label: Text(
                                '${const {'困难': '😣', '一般': '😐', '顺畅': '😊'}[value]} $value',
                              ),
                              selected: ease == value,
                              onSelected: saving
                                  ? null
                                  : (_) => setState(() => ease = value),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('排便量（必选）'),
                    Wrap(
                      spacing: 8,
                      children: Business.amountOptions
                          .map(
                            (value) => ChoiceChip(
                              label: Text('💩 × $value'),
                              selected: amount == value,
                              onSelected: saving
                                  ? null
                                  : (_) => setState(() {
                                      amount = value;
                                      amountController.clear();
                                    }),
                            ),
                          )
                          .toList(),
                    ),
                    TextFormField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '自定义排便量（1～99）',
                      ),
                      onChanged: (value) =>
                          setState(() => amount = value.isEmpty ? null : value),
                    ),
                  ],
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (phone == null || !calendarHome)
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(
                      saving
                          ? '正在保存…'
                          : phone == null
                          ? '创建档案'
                          : editing != null
                          ? '保存修改'
                          : selectedDate == widget.business.today
                          ? '保存今天的记录'
                          : '保存记录',
                    ),
                  ),
                if (phone != null && !calendarHome) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: saving ? null : confirmDay,
                    child: const Text('确认当天未排便'),
                  ),
                  Text('所选日期的记录（${records.length}）'),
                  if (records.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(counts[selectedDate] == 0 ? '确认未排便' : '尚未填写'),
                    ),
                  ...records.map(
                    (record) => Dismissible(
                      key: ValueKey(record['id']),
                      direction: saving
                          ? DismissDirection.none
                          : DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        await deleteRecord(record['id'] as String);
                        return false;
                      },
                      child: Card(
                        child: ListTile(
                          title: Text(
                            "${record['ease_name']} · ${record['amount_value'] == null ? record['amount_name'] : '💩 × ${record['amount_value']}'}",
                          ),
                          trailing: IconButton(
                            tooltip: '删除记录',
                            onPressed: saving
                                ? null
                                : () => deleteRecord(record['id'] as String),
                            icon: const Icon(Icons.delete_outline),
                          ),
                          subtitle: Text(
                            '${record['date']} ${record['local_time'] ?? '未填写时间'}',
                          ),
                          onTap: saving
                              ? null
                              : () async {
                                  if (!await discard() || !mounted) return;
                                  setState(() {
                                    editing = record;
                                    ease =
                                        Business.easeOptions.contains(
                                          record['ease_name'],
                                        )
                                        ? record['ease_name'] as String
                                        : null;
                                    amount = record['amount_value']?.toString();
                                    amountController.text =
                                        amount != null &&
                                            !Business.amountOptions.contains(
                                              amount,
                                            )
                                        ? amount!
                                        : '';
                                    localTime = record['local_time'] as String?;
                                  });
                                },
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    ),
  );
}

class RecordCalendar extends StatefulWidget {
  const RecordCalendar({
    super.key,
    required this.selected,
    required this.today,
    required this.counts,
    this.onSelected,
    this.initialMonth,
    this.onMonthChanged,
  });
  final DateTime? initialMonth;
  final ValueChanged<DateTime>? onMonthChanged;
  final DateTime selected;
  final DateTime today;
  final Map<String, int> counts;
  final ValueChanged<DateTime>? onSelected;
  @override
  State<RecordCalendar> createState() => _RecordCalendarState();
}

class _RecordCalendarState extends State<RecordCalendar> {
  late DateTime month =
      widget.initialMonth ??
      DateTime(widget.selected.year, widget.selected.month);
  void changeMonth(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
    widget.onMonthChanged?.call(month);
  }

  @override
  Widget build(BuildContext context) {
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              onPressed: month.year == 1 && month.month == 1
                  ? null
                  : () => changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${month.year}年${month.month}月',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed:
                  DateTime(month.year, month.month + 1).isAfter(widget.today)
                  ? null
                  : () => changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(child: Center(child: Text(day))),
          ],
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 7,
            mainAxisExtent: 42,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var index = 0; index < offset + days; index++)
                if (index < offset)
                  const SizedBox()
                else
                  Builder(
                    builder: (context) {
                      final date = DateTime(
                        month.year,
                        month.month,
                        index - offset + 1,
                      );
                      final count = widget.counts[Business.formatDate(date)];
                      return TextButton(
                        onPressed: date.isAfter(widget.today)
                            ? null
                            : () => widget.onSelected != null
                                  ? widget.onSelected!(date)
                                  : Navigator.pop(context, date),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side:
                              Business.formatDate(date) ==
                                  Business.formatDate(widget.today)
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                        ),
                        child: Text(
                          '${date.day}${count == null
                              ? ''
                              : count == 0
                              ? '\n—'
                              : '\n$count次'}',
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => widget.onSelected != null
              ? widget.onSelected!(widget.today)
              : Navigator.pop(context, widget.today),
          child: const Text('返回今天'),
        ),
      ],
    );
  }
}

class HomeStatistics extends StatefulWidget {
  const HomeStatistics({
    super.key,
    required this.business,
    required this.month,
    required this.selected,
    this.overview = false,
  });
  final Business business;
  final DateTime month;
  final DateTime selected;
  final bool overview;
  @override
  State<HomeStatistics> createState() => _HomeStatisticsState();
}

class _HomeStatisticsState extends State<HomeStatistics> {
  bool weekly = false;
  late DateTime week = monday(widget.selected);
  DateTime monday(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);
  @override
  void didUpdateWidget(HomeStatistics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) week = monday(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final start = weekly
        ? week
        : DateTime(widget.month.year, widget.month.month);
    final end = weekly
        ? DateTime(week.year, week.month, week.day + 6)
        : DateTime(widget.month.year, widget.month.month + 1, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.overview) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('周')),
              ButtonSegment(value: false, label: Text('月')),
            ],
            selected: {weekly},
            onSelectionChanged: (value) =>
                setState(() => weekly = value.single),
          ),
          if (weekly)
            Row(
              children: [
                IconButton(
                  tooltip: '前一周',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                    () => week = DateTime(week.year, week.month, week.day - 7),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${Business.formatDate(start)} ～ ${Business.formatDate(end)}',
                  ),
                ),
                IconButton(
                  tooltip: '后一周',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                    () => week = DateTime(week.year, week.month, week.day + 7),
                  ),
                ),
              ],
            ),
        ],
        FutureBuilder<PeriodStatistics>(
          key: ValueKey('$start-$end'),
          future: widget.business.statistics(start, end),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('统计读取失败');
            final data = snapshot.data;
            if (data == null) return const Text('正在读取统计…');
            if (widget.overview) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${widget.month.year}年${widget.month.month}月概览\n排便总次数 ${data.total} · 已排便 ${data.recordedDays}天\n确认未排便 ${data.confirmedDays}天 · 尚未填写 ${data.unfilledDays}天',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                distribution('排便通畅度分布', data.ease, data.total),
                distribution('排便量分布', data.amount, data.total),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget distribution(String title, Map<String, int> values, int total) {
    final maximum = values.values.fold<int>(1, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (total == 0)
            const Text('暂无排便记录')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: values.entries.map((entry) {
                  final label = title == '排便量分布' && entry.key != '旧版未分类'
                      ? '💩 × ${entry.key}'
                      : entry.key;
                  final detail =
                      '${entry.value}次 · ${(entry.value / total * 100).toStringAsFixed(1)}%';
                  return Semantics(
                    label: '$label，$detail',
                    button: true,
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(label),
                          content: Text(detail),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                      child: SizedBox(
                        width: 100,
                        height: 170,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${entry.value}次'),
                            Container(
                              width: 32,
                              height: 110 * entry.value / maximum,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            Text(label),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
