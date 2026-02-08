import 'dart:convert';

/// Notification reminder preference - which reminders to show before scheduled time
/// Stores a set of enabled reminder minutes (0 = at scheduled time, 5, 10, 15)
class NotificationReminderPreference {
  final Set<int> enabledReminders;

  /// Default: at scheduled time and 15 minutes before
  static const Set<int> defaultReminders = {0, 15};

  const NotificationReminderPreference(this.enabledReminders);

  /// Default constructor with at scheduled time and 15 minutes before enabled
  const NotificationReminderPreference.defaultValue() : enabledReminders = defaultReminders;

  /// Check if a specific reminder is enabled
  bool isEnabled(int minutes) => enabledReminders.contains(minutes);

  /// Toggle a specific reminder
  NotificationReminderPreference toggle(int minutes) {
    final newSet = Set<int>.from(enabledReminders);
    if (newSet.contains(minutes)) {
      newSet.remove(minutes);
    } else {
      newSet.add(minutes);
    }
    return NotificationReminderPreference(newSet);
  }

  /// Get display name for the current selection
  String get displayName {
    if (enabledReminders.isEmpty) {
      return 'None';
    }
    final sorted = enabledReminders.toList()..sort((a, b) => b.compareTo(a));
    return sorted.map((m) => m == 0 ? 'At scheduled time' : '$m min').join('/');
  }

  /// Serialize to JSON for storage
  String toJson() => jsonEncode(enabledReminders.toList());

  /// Deserialize from JSON string
  static NotificationReminderPreference fromJson(String json) {
    try {
      final list = jsonDecode(json) as List;
      final reminders = list.map((e) => e as int).toSet();
      return NotificationReminderPreference(reminders);
    } catch (e) {
      return const NotificationReminderPreference.defaultValue();
    }
  }
}
