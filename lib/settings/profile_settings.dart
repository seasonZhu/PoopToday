import 'package:flutter/material.dart';

import '../business.dart';
import '../reminders.dart';
import '../reminder_settings.dart';

class ProfileSettings extends StatefulWidget {
  const ProfileSettings({
    super.key,
    required this.business,
    required this.profiles,
    required this.onAction,
    this.reminders,
  });
  final Business business;
  final List<Map<String, Object?>> profiles;
  final Future<void> Function(String) onAction;
  final ReminderService? reminders;

  @override
  State<ProfileSettings> createState() => _ProfileSettingsState();
}

class _ProfileSettingsState extends State<ProfileSettings> {
  late List<Map<String, Object?>> profiles = widget.profiles;

  String maskedPhone(String value) => value.length == 11
      ? '${value.substring(0, 3)}****${value.substring(7)}'
      : value;

  @override
  Widget build(BuildContext context) => StatefulBuilder(
    builder: (context, updateSettings) => Scaffold(
      backgroundColor: const Color(0xFFFAFAF5),
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          for (final profile in profiles)
            ListTile(
              title: Text(
                (profile['nickname'] as String?)?.isNotEmpty == true
                    ? profile['nickname'] as String
                    : '本地用户档案',
              ),
              subtitle: Text(
                '${maskedPhone(profile['phone'] as String)} · ${(profile['id'] as String).substring(0, (profile['id'] as String).length.clamp(0, 8))}',
              ),
              onTap: () async {
                await widget.onAction(profile['id'] as String);
                profiles = await widget.business.profiles();
                if (context.mounted) updateSettings(() {});
              },
            ),
          for (final action in ['新增档案', '修改手机号', '删除档案'])
            ListTile(
              title: Text(action),
              onTap: () async {
                await widget.onAction(action);
                profiles = await widget.business.profiles();
                if (context.mounted) updateSettings(() {});
              },
            ),
          ListTile(
            title: const Text('导入备份'),
            onTap: () async {
              await widget.onAction('导入备份');
              profiles = await widget.business.profiles();
              if (context.mounted) updateSettings(() {});
            },
          ),
          ListTile(
            title: const Text('导出备份'),
            onTap: () async {
              await widget.onAction('导出备份');
              profiles = await widget.business.profiles();
              if (context.mounted) updateSettings(() {});
            },
          ),
          ListTile(
            title: const Text('推送设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    ReminderSettings(service: widget.reminders),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
