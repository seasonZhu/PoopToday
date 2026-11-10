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
      final value =
          service != null &&
          await service.enabled() &&
          await service.adapter.permission();
      if (mounted) {
        setState(() {
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
        const ListTile(title: Text('10:00'), subtitle: Text('当地时间')),
        const Divider(),
        const ListTile(title: Text('22:00'), subtitle: Text('当地时间')),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(message!),
          ),
      ],
    ),
  );
}
