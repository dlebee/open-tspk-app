import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_reminder_preference.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

final notificationReminderPreferenceProvider = StateNotifierProvider<NotificationReminderPreferenceNotifier, NotificationReminderPreference>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return NotificationReminderPreferenceNotifier(storage);
});

class NotificationReminderPreferenceNotifier extends StateNotifier<NotificationReminderPreference> {
  NotificationReminderPreferenceNotifier(this._storage) : super(const NotificationReminderPreference.defaultValue()) {
    _load();
  }

  final IStorageService _storage;

  Future<void> _load() async {
    try {
      final preference = _storage.getNotificationReminderPreference();
      state = preference;
    } catch (e) {
      // If loading fails, use default value
      state = const NotificationReminderPreference.defaultValue();
    }
  }

  Future<void> setPreference(NotificationReminderPreference preference) async {
    await _storage.setNotificationReminderPreference(preference);
    state = preference;
  }

  Future<void> toggleReminder(int minutes) async {
    final updated = state.toggle(minutes);
    await _storage.setNotificationReminderPreference(updated);
    state = updated;
  }
}
