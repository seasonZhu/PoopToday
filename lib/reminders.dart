import 'dart:convert';

import 'business.dart';

class ReminderNotification {
  const ReminderNotification(this.at, this.profileId);
  final DateTime at;
  final String profileId;
}

abstract interface class NotificationAdapter {
  Future<bool> permission({bool request = false});
  Future<void> replace(List<ReminderNotification> notifications);
}

abstract interface class PreciseNotificationAdapter {
  /// 非 Android 平台返回 null。
  Future<bool?> precisePermission();
}

abstract interface class AndroidReminderSettings {
  Future<bool?> backgroundAllowed();
  Future<void> openBackgroundSettings();
  Future<void> openBannerSettings();
}

class ReminderService {
  ReminderService(this.business, this.adapter);
  final Business business;
  final NotificationAdapter adapter;
  Future<String?> _key() async {
    final profile = await business.activeProfile();
    return profile == null ? null : 'reminder:${profile['id']}';
  }

  Future<List<int>> times() async {
    final key = await _key();
    final saved = key == null
        ? null
        : await business.localSetting('$key:times');
    return saved == null
        ? [600, 1320]
        : List<int>.from(jsonDecode(saved) as List);
  }

  Future<void> saveTimes(List<int> values) async {
    if (values.length > 4 ||
        values.any((v) => v < 0 || v >= 1440) ||
        values.toSet().length != values.length) {
      throw ArgumentError('提醒时间不可重复且必须是有效当地时间');
    }
    final key = await _key();
    if (key == null) return;
    final sorted = [...values]..sort();
    await business.saveLocalSetting('$key:times', jsonEncode(sorted));
    if (sorted.isEmpty) await business.saveLocalSetting(key, 'false');
    await reconcile();
  }

  Future<bool> enabled() async {
    final key = await _key();
    return key != null && await business.localSetting(key) == 'true';
  }

  Future<bool> setEnabled(bool value) async {
    final key = await _key();
    if (key == null) return false;
    final allowed =
        !value ||
        ((await times()).isNotEmpty && await adapter.permission(request: true));
    await business.saveLocalSetting(key, '${value && allowed}');
    await reconcile();
    return allowed;
  }

  Future<void> _queue = Future.value();
  Future<void> reconcile() {
    final result = _queue.then((_) => _reconcile());
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> _reconcile() async {
    final notifications = <ReminderNotification>[];
    final profile = await business.activeProfile();
    if (profile != null && await enabled() && await adapter.permission()) {
      final now = business.now();
      final counts = await business.dailyCounts();
      final configuredTimes = await times();
      // 预排未来 30 天共最多 60 条，控制在 iOS 待处理通知上限内。
      for (var day = 0; day < 30; day++) {
        for (final minute in configuredTimes) {
          final at = DateTime(
            now.year,
            now.month,
            now.day + day,
            minute ~/ 60,
            minute % 60,
          );
          final date =
              '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
          if (at.isAfter(now) && !counts.containsKey(date)) {
            notifications.add(
              ReminderNotification(at, profile['id'] as String),
            );
          }
        }
      }
    }
    notifications.sort((a, b) => a.at.compareTo(b.at));
    await adapter.replace(notifications.take(60).toList());
  }
}
