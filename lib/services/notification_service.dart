import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import 'storage_service.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static StorageService? _storage;
  static void Function(String medicineId, String eye, String scheduledDate, String scheduledTime)? _onOverrideTimeRequested;
  static void Function()? _onDoseAdded;

  static void setStorage(StorageService storage) {
    _storage = storage;
  }

  static void setOnOverrideTimeRequested(void Function(String, String, String, String) fn) {
    _onOverrideTimeRequested = fn;
  }

  static void setOnDoseAdded(void Function() fn) {
    _onDoseAdded = fn;
  }

  static Future<void> init() async {
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || _storage == null) return;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final medicineId = map['medicineId'] as String?;
      final eyeStr = map['eye'] as String?;
      final scheduledDate = map['scheduledDate'] as String?;
      final scheduledTime = map['scheduledTime'] as String?;
      if (medicineId == null || eyeStr == null || scheduledDate == null || scheduledTime == null) return;

      final eye = Eye.values.firstWhere((e) => e.name == eyeStr, orElse: () => Eye.both);
      final scheduledDt = DateTime.parse(scheduledDate);

      switch (response.actionId) {
        case 'skip':
          _addDose(medicineId, eye, scheduledDt, scheduledTime, DoseStatus.skipped, null);
          break;
        case 'taken_on_time':
          final takenAt = DateTime(scheduledDt.year, scheduledDt.month, scheduledDt.day,
              int.parse(scheduledTime.split(':')[0]), int.parse(scheduledTime.split(':')[1]));
          _addDose(medicineId, eye, scheduledDt, scheduledTime, DoseStatus.taken, takenAt);
          break;
        case 'taken_now':
          _addDose(medicineId, eye, scheduledDt, scheduledTime, DoseStatus.taken, DateTime.now());
          break;
        case 'taken_at_override':
          _onOverrideTimeRequested?.call(medicineId, eyeStr, scheduledDate, scheduledTime);
          break;
      }
    } catch (_) {}
  }

  static void _addDose(String medicineId, Eye eye, DateTime scheduledDate, String scheduledTime, DoseStatus status, DateTime? takenAt) {
    final storage = _storage;
    if (storage == null) return;
    final doses = storage.getDoses();
    // Look up medicine name for denormalization
    final medicines = storage.getMedicines();
    final medicine = medicines.firstWhere((m) => m.id == medicineId, orElse: () => Medicine(id: '', name: 'Unknown', schedules: [], createdAt: DateTime.now()));
    
    // For skipped doses, use scheduled date/time as recordedAt
    // For taken doses, use DateTime.now() as recordedAt
    DateTime recordedAt;
    if (status == DoseStatus.skipped) {
      final parts = scheduledTime.split(':');
      recordedAt = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
        int.parse(parts[0]),
        parts.length > 1 ? int.parse(parts[1]) : 0,
      );
    } else {
      recordedAt = DateTime.now();
    }
    
    final dose = MedicineDose(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      medicineId: medicineId,
      medicineName: medicine.name,
      eye: eye,
      status: status,
      recordedAt: recordedAt,
      scheduledDate: scheduledDate,
      scheduledTime: scheduledTime,
      takenAt: takenAt,
    );
    storage.saveDoses([...doses, dose]);
    _onDoseAdded?.call();
  }

  /// Notification IDs must fit in 32-bit int. Use hash-based scheme.
  static int _id(int medicinePart, int scheduleIndex, int dayOfWeek, int timeIndex) {
    return medicinePart * 100000 + scheduleIndex * 1000 + dayOfWeek * 10 + timeIndex;
  }

  static int _medicinePart(String medicineId) {
    return (medicineId.hashCode % 1000).abs();
  }

  static Future<void> scheduleForMedicine(Medicine medicine) async {
    await cancelForMedicine(medicine.id);
    final medicinePart = _medicinePart(medicine.id);
    for (var si = 0; si < medicine.schedules.length; si++) {
      final schedule = medicine.schedules[si];
      for (final dayOfWeek in schedule.daysOfWeek) {
        for (var ti = 0; ti < schedule.times.length; ti++) {
          final time = schedule.times[ti];
          final parts = time.split(':');
          final hour = int.parse(parts[0]);
          final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
          final now = tz.TZDateTime.now(tz.local);
          var scheduled = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day,
            hour,
            minute,
          );
          while (scheduled.weekday != dayOfWeek) {
            scheduled = scheduled.add(const Duration(days: 1));
          }
          if (scheduled.isBefore(now)) {
            scheduled = scheduled.add(const Duration(days: 7));
          }
          final id = _id(medicinePart, si, dayOfWeek, ti);
          final scheduledDateStr = '${scheduled.year}-${scheduled.month.toString().padLeft(2, '0')}-${scheduled.day.toString().padLeft(2, '0')}';
          final payload = jsonEncode({
            'medicineId': medicine.id,
            'eye': schedule.eye.name,
            'scheduledDate': scheduledDateStr,
            'scheduledTime': time,
          });
          await _plugin.zonedSchedule(
            id,
            '${medicine.name} - ${schedule.eye.name}',
            'Scheduled: $time',
            scheduled,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'thygeson_meds',
                'Medicine reminders',
                channelDescription: 'Reminders for scheduled medicine',
                actions: [
                  const AndroidNotificationAction('skip', 'Skip'),
                  const AndroidNotificationAction('taken_on_time', 'Taken on time'),
                  const AndroidNotificationAction('taken_now', 'Taken now'),
                  const AndroidNotificationAction('taken_at_override', 'Taken at...'),
                ],
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
                categoryIdentifier: 'thygeson_meds',
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: payload,
          );
        }
      }
    }
  }

  static Future<void> cancelForMedicine(String medicineId) async {
    final medicinePart = _medicinePart(medicineId);
    for (var si = 0; si < 100; si++) {
      for (var d = 1; d <= 7; d++) {
        for (var ti = 0; ti < 100; ti++) {
          await _plugin.cancel(_id(medicinePart, si, d, ti));
        }
      }
    }
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  static void addDoseFromOverride(String medicineId, Eye eye, DateTime scheduledDate, String scheduledTime, DateTime takenAt) {
    _addDose(medicineId, eye, scheduledDate, scheduledTime, DoseStatus.taken, takenAt);
  }
}
