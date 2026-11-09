import 'package:flutter/material.dart';
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
    title: '今天排便了吗',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
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
  final phoneController = TextEditingController();
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
      final currentRecords = await widget.business.todayRecords();
      if (!mounted) return;
      setState(() {
        phone = currentPhone;
        records = currentRecords;
        loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          error = '读取失败，请重试';
          loading = false;
        });
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (phone == null) {
        await widget.business.createProfile(phoneController.text.trim());
      } else {
        await widget.business.saveToday(ease, amount);
        ease = null;
        amount = null;
      }
      await refresh();
    } on ArgumentError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('今天排便了吗')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
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
                Text('本地用户档案 · $phone'),
                const SizedBox(height: 24),
                Text(
                  '今天 ${widget.business.today}',
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 24),
                const Text('排便通畅度（必选）'),
                Wrap(
                  spacing: 8,
                  children: Business.easeOptions
                      .map(
                        (value) => ChoiceChip(
                          label: Text(value),
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
                          label: Text(value),
                          selected: amount == value,
                          onSelected: saving
                              ? null
                              : (_) => setState(() => amount = value),
                        ),
                      )
                      .toList(),
                ),
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
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(
                  saving
                      ? '正在保存…'
                      : phone == null
                      ? '创建档案'
                      : '保存今天的记录',
                ),
              ),
              if (phone != null) ...[
                const SizedBox(height: 24),
                Text('今天的记录（${records.length}）'),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('尚未填写'),
                  ),
                ...records.map(
                  (record) => Card(
                    child: ListTile(
                      title: Text(
                        '${record['ease_name']} · ${record['amount_name']}',
                      ),
                      subtitle: Text(record['date'] as String),
                    ),
                  ),
                ),
              ],
            ],
          ),
  );
}
