import 'time_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
  bool? precise;
  bool? background;
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
      final adapter = service?.adapter;
      final preciseAllowed = adapter is PreciseNotificationAdapter
          ? await (adapter as PreciseNotificationAdapter).precisePermission()
          : null;
      final backgroundAllowed = adapter is AndroidReminderSettings
          ? await (adapter as AndroidReminderSettings).backgroundAllowed()
          : null;
      final configured = await service?.times() ?? <int>[];
      final value =
          service != null &&
          await service.enabled() &&
          await service.adapter.permission();
      if (mounted) {
        setState(() {
          precise = preciseAllowed;
          background = backgroundAllowed;
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

  Future<void> requestPrecisePermission() async {
    setState(() => busy = true);
    try {
      await widget.service?.adapter.permission(request: true);
      await load();
    } catch (_) {
      if (mounted) setState(() => message = '无法打开提醒授权，请在系统设置中检查');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openAndroidSettings({required bool banner}) async {
    final adapter = widget.service?.adapter;
    if (adapter is! AndroidReminderSettings) return;
    setState(() => busy = true);
    try {
      final settings = adapter as AndroidReminderSettings;
      if (banner) {
        await settings.openBannerSettings();
      } else {
        await settings.openBackgroundSettings();
      }
      await load();
    } catch (_) {
      if (mounted) setState(() => message = '无法打开设置，请在系统应用设置中检查');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(bool value) async {
    setState(() => busy = true);
    try {
      final allowed = await widget.service!.setEnabled(value);
      await load();
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
    final picked = await showWheelTimePicker(
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
      if (mounted) setState(() => message = '最多设置4个提醒时间，且时间不可重复');
    } catch (_) {
      if (mounted) setState(() => message = '提醒设置失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showTips() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('推送提醒说明'),
        content: SingleChildScrollView(
          child: Text(
            defaultTargetPlatform == TargetPlatform.android
                ? 'Android 提醒可能受到系统通知权限、电池优化和后台运行限制影响。\n\n'
                      '后台收不到提醒时，请按以下顺序检查：\n1. 开启“填写提醒”，并允许系统通知与准时提醒。\n2. 长按桌面应用图标进入“应用信息／应用详情”，在“电池／耗电管理／后台管理”中允许后台活动，选择“无限制／不限制／完全允许”等选项。\n3. 如果手机提供“自启动／关联启动”选项，请允许本应用启动。\n\n不同品牌和系统版本的入口名称会有差异。系统电池优化已豁免后，仍需检查厂商的后台管理设置。\n\n'
                      '需要顶部弹出时，请进入本应用的系统通知设置，允许通知，并检查“填写提醒”类别的“横幅／悬浮通知／顶部显示”等选项，关闭静默通知；同时检查勿扰模式。\n\n'
                      '最多预排未来30天内的60条提醒；时间越多，覆盖天数越短。请定期打开应用更新提醒。\n\n'
                      '提醒仅对当前档案生效，当天已有排便记录时不再提醒。'
                : '请在 iOS 系统设置中允许本应用发送通知，并按需开启横幅和声音。\n\n'
                      '最多预排未来30天内的60条提醒；时间越多，覆盖天数越短。请定期打开应用更新提醒。\n\n'
                      '提醒仅对当前档案生效，当天已有排便记录时不再提醒。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('推送设置'),
      actions: [
        IconButton(
          tooltip: '推送提醒说明',
          onPressed: showTips,
          icon: const Icon(Icons.info_outline),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (defaultTargetPlatform == TargetPlatform.android &&
            widget.service?.adapter is AndroidReminderSettings) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('系统权限'),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.battery_saver_outlined),
                  title: const Text('设置后台运行权限'),
                  subtitle: Text(
                    background == null
                        ? '允许后台活动，减少提醒延迟'
                        : background!
                        ? '系统电池优化已豁免，厂商后台管理请另行检查'
                        : '后台运行受电池优化限制',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy ? null : () => openAndroidSettings(banner: false),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('设置顶部横幅通知'),
                  subtitle: const Text('在系统中开启“填写提醒”的横幅通知'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy ? null : () => openAndroidSettings(banner: true),
                ),
                if (precise != null) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.alarm_outlined),
                    title: const Text('准时提醒'),
                    subtitle: Text(precise! ? '已允许准时提醒' : '未允许，通知可能延迟'),
                    trailing: precise!
                        ? const Icon(Icons.check)
                        : const Icon(Icons.chevron_right),
                    onTap: busy || precise! ? null : requestPrecisePermission,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('提醒时间'),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('填写提醒'),
                subtitle: Text(
                  widget.service == null
                      ? '通知暂不可用，请重新打开应用重试'
                      : '仅当前档案生效，最多设置4个时间',
                ),
                value: enabled,
                onChanged: busy || widget.service == null ? null : change,
              ),
              const Divider(height: 1),
              for (final time in times)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(
                    '${(time ~/ 60).toString().padLeft(2, '0')}:${(time % 60).toString().padLeft(2, '0')}',
                  ),
                  subtitle: const Text('每天 · 当地时间 · 点击编辑'),
                  onTap: busy ? null : () => editTime(time),
                  trailing: IconButton(
                    tooltip: '删除提醒时间',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: busy
                        ? null
                        : () => updateTimes(
                            times.where((v) => v != time).toList(),
                          ),
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text('新增提醒时间（${times.length}/4）'),
                enabled: !busy && widget.service != null && times.length < 4,
                onTap: editTime,
              ),
            ],
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
