import 'package:flutter/material.dart';

import '../business.dart';
import 'about_page.dart';
import '../reminders.dart';
import '../reminder_settings.dart';

class ProfileSettings extends StatelessWidget {
  const ProfileSettings({
    super.key,
    required this.business,
    required this.profiles,
    required this.onAction,
    this.reminders,
  });
  final Business business;
  final List<Map<String, Object?>> profiles;
  final Future<void> Function(String, {String? profileId}) onAction;
  final ReminderService? reminders;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAFAF5),
    appBar: AppBar(
      title: const Text('设置'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ListTile(
          title: const Text('本地档案管理'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LocalProfileManagement(
                  business: business,
                  onAction: onAction,
                ),
              ),
            );
            if (context.mounted &&
                (await business.profiles()).isEmpty &&
                context.mounted) {
              Navigator.pop(context);
            }
          },
        ),
        ListTile(
          title: const Text('推送设置'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ReminderSettings(service: reminders),
            ),
          ),
        ),
        ListTile(
          title: const Text('关于'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AboutPage()),
          ),
        ),
      ],
    ),
  );
}

class LocalProfileManagement extends StatefulWidget {
  const LocalProfileManagement({
    super.key,
    required this.business,
    required this.onAction,
  });
  final Business business;
  final Future<void> Function(String, {String? profileId}) onAction;
  @override
  State<LocalProfileManagement> createState() => _LocalProfileManagementState();
}

class _LocalProfileManagementState extends State<LocalProfileManagement> {
  List<Map<String, Object?>> profiles = [];
  String? activeId;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final values = await widget.business.profiles();
    final active = await widget.business.activeProfile();
    if (mounted) {
      setState(() {
        profiles = values;
        activeId = active?['id'] as String?;
        busy = false;
      });
    }
  }

  Future<void> act(String action, {String? id}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.onAction(action, profileId: id);
      await load();
      if (mounted && profiles.isEmpty) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String masked(String phone) => phone.length == 11
      ? '${phone.substring(0, 3)}****${phone.substring(7)}'
      : phone;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      backgroundColor: const Color(0xFFFAFAF5),
      appBar: AppBar(
        title: const Text('本地档案管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: '新增档案',
            icon: const Icon(Icons.add),
            onPressed: busy ? null : () => act('新增档案'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('共 ${profiles.length} 个档案 · 点击档案切换使用'),
          for (final profile in profiles) ...[
            ListTile(
              title: Text(
                (profile['nickname'] as String?)?.isNotEmpty == true
                    ? profile['nickname'] as String
                    : '本地用户档案',
              ),
              subtitle: Text(
                '${masked(profile['phone'] as String)}${profile['id'] == activeId ? ' · 当前默认档案' : ''}',
              ),
              trailing: profile['id'] == activeId
                  ? const Icon(Icons.check)
                  : null,
              onTap: busy ? null : () => act(profile['id'] as String),
            ),
            Wrap(
              children: [
                for (final action in ['修改手机号', '删除档案', '导入备份', '导出备份'])
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => act(action, id: profile['id'] as String),
                    child: Text(
                      action == '修改手机号'
                          ? '编辑'
                          : action == '删除档案'
                          ? '删除'
                          : action,
                    ),
                  ),
              ],
            ),
            const Divider(),
          ],
          if (busy && profiles.isEmpty) const Center(child: Text('正在加载…')),
        ],
      ),
    ),
  );
}
