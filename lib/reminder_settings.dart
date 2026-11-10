import 'package:flutter/material.dart';

import 'reminders.dart';

class ReminderSettings extends StatefulWidget {
  const ReminderSettings({super.key, required this.service});
  final ReminderService? service;
  @override
  State<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<ReminderSettings>
    with WidgetsBindingObserver {
  List<int> times = [];
  bool enabled = false;
  bool busy = true;
  String? message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    final service = widget.service;
    try {
      await service?.reconcile();
      final configured = await service?.times() ?? <int>[];
      final value =
          service != null &&
          await service.enabled() &&
          await service.adapter.permission();
      if (mounted) {
        setState(() {
          times = configured;
          enabled = value;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          message = '无法读取通知状态，请重试';
        });
      }
    }
  }

  Future<void> change(bool value) async {
    setState(() => busy = true);
    try {
      final allowed = await widget.service!.setEnabled(value);
      if (mounted) {
        setState(() {
          enabled = value && allowed;
          message = allowed ? null : '通知权限未开启，请在系统设置中允许通知后重试';
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = '提醒设置失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editTime([int? old]) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: old == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: old ~/ 60, minute: old % 60),
    );
    if (picked == null || !mounted) return;
    final value = picked.hour * 60 + picked.minute;
    await updateTimes([...times.where((v) => v != old), value]);
  }

  Future<void> updateTimes(List<int> values) async {
    setState(() => busy = true);
    try {
      await widget.service!.saveTimes(values);
      if (mounted) setState(() => message = null);
      await load();
    } on ArgumentError {
      if (mounted) setState(() => message = '提醒时间不可重复');
    } catch (_) {
      if (mounted) setState(() => message = '提醒设置失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('推送设置')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: SwitchListTile(
            title: const Text('填写提醒'),
            subtitle: Text(
              widget.service == null ? '通知暂不可用，请重新打开应用重试' : '仅当前档案生效',
            ),
            value: enabled,
            onChanged: busy || widget.service == null ? null : change,
          ),
        ),
        const SizedBox(height: 24),
        const Text('最多预排未来30天内的60条提醒；时间越多，覆盖天数越短。请定期打开应用更新提醒。'),
        for (final time in times)
          ListTile(
            title: Text(
              '${(time ~/ 60).toString().padLeft(2, '0')}:${(time % 60).toString().padLeft(2, '0')}',
            ),
            subtitle: const Text('当地时间'),
            onTap: busy ? null : () => editTime(time),
            trailing: IconButton(
              tooltip: '删除提醒时间',
              icon: const Icon(Icons.delete_outline),
              onPressed: busy
                  ? null
                  : () => updateTimes(times.where((v) => v != time).toList()),
            ),
          ),
        TextButton.icon(
          onPressed: busy || widget.service == null ? null : editTime,
          icon: const Icon(Icons.add),
          label: const Text('新增提醒时间'),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(message!),
          ),
      ],
    ),
  );
}
