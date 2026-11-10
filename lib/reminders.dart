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

class ReminderService {
  ReminderService(this.business, this.adapter);
  final Business business;
  final NotificationAdapter adapter;
  Future<String?> _key() async {
    final profile = await business.activeProfile();
    return profile == null ? null : 'reminder:${profile['id']}';
  }

  Future<bool> enabled() async {
    final key = await _key();
    return key != null && await business.localSetting(key) == 'true';
  }

  Future<bool> setEnabled(bool value) async {
    final key = await _key();
    if (key == null) return false;
    final allowed = !value || await adapter.permission(request: true);
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
      // 预排未来 30 天共最多 60 条，控制在 iOS 待处理通知上限内。
      for (var day = 0; day < 30; day++) {
        for (final hour in [10, 22]) {
          final at = DateTime(now.year, now.month, now.day + day, hour);
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
    await adapter.replace(notifications);
  }
}
