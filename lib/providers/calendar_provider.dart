import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import 'appointment_provider.dart';
import 'dose_provider.dart';
import 'flare_up_provider.dart';
import 'medicine_provider.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Unscheduled (ad-hoc) doses for a given date. Uses takenAt or recordedAt for date.
final unscheduledDosesForDateProvider = Provider.family<List<MedicineDose>, DateTime>((ref, date) {
  final doses = ref.watch(dosesProvider).valueOrNull ?? [];
  final result = doses.where((d) {
    if (d.scheduledDate != null || d.scheduledTime != null) return false;
    final doseDate = d.takenAt ?? d.recordedAt;
    return _sameDay(doseDate, date);
  }).toList();
  result.sort((a, b) {
    final ta = a.takenAt ?? a.recordedAt;
    final tb = b.takenAt ?? b.recordedAt;
    return ta.compareTo(tb);
  });
  return result;
});

final unscheduledDosesForRangeProvider = Provider.family<Map<DateTime, List<MedicineDose>>, ({DateTime start, DateTime end})>((ref, range) {
  final doses = ref.watch(dosesProvider).valueOrNull ?? [];
  final result = <DateTime, List<MedicineDose>>{};
  var d = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);

  for (final dose in doses) {
    if (dose.scheduledDate != null || dose.scheduledTime != null) continue;
    final doseDate = dose.takenAt ?? dose.recordedAt;
    final dateKey = DateTime(doseDate.year, doseDate.month, doseDate.day);
    if (!dateKey.isBefore(range.start) && !dateKey.isAfter(end)) {
      result.putIfAbsent(dateKey, () => []).add(dose);
    }
  }

  for (final list in result.values) {
    list.sort((a, b) {
      final ta = a.takenAt ?? a.recordedAt;
      final tb = b.takenAt ?? b.recordedAt;
      return ta.compareTo(tb);
    });
  }
  return result;
});

final scheduledDosesForDateProvider = Provider.family<List<ScheduledDose>, DateTime>((ref, date) {
  final medicines = ref.watch(medicinesProvider).valueOrNull ?? [];
  final doses = ref.watch(dosesProvider).valueOrNull ?? [];
  return _generateScheduledDosesForDate(medicines, doses, date);
});

final scheduledDosesForRangeProvider = Provider.family<Map<DateTime, List<ScheduledDose>>, ({DateTime start, DateTime end})>((ref, range) {
  final medicines = ref.watch(medicinesProvider).valueOrNull ?? [];
  final doses = ref.watch(dosesProvider).valueOrNull ?? [];
  final result = <DateTime, List<ScheduledDose>>{};
  var d = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  while (!d.isAfter(end)) {
    result[d] = _generateScheduledDosesForDate(medicines, doses, d);
    d = d.add(const Duration(days: 1));
  }
  return result;
});

List<ScheduledDose> _generateScheduledDosesForDate(
  List<Medicine> medicines,
  List<MedicineDose> doses,
  DateTime date,
) {
  final dayOfWeek = date.weekday; // 1=Mon, 7=Sun
  final result = <ScheduledDose>[];
  final dateStr = DateTime(date.year, date.month, date.day);

  for (final medicine in medicines) {
    final createdDate = DateTime(
      medicine.createdAt.year,
      medicine.createdAt.month,
      medicine.createdAt.day,
    );
    if (date.isBefore(createdDate)) continue;

    for (var i = 0; i < medicine.schedules.length; i++) {
      final schedule = medicine.schedules[i];
      if (!schedule.daysOfWeek.contains(dayOfWeek)) continue;

      for (final time in schedule.times) {
        final scheduledDate = dateStr;
        MedicineDose? matchingDose;
        for (final d in doses) {
          if (d.medicineId == medicine.id &&
              d.eye == schedule.eye &&
              d.scheduledDate != null &&
              _sameDay(d.scheduledDate!, scheduledDate) &&
              d.scheduledTime == time) {
            matchingDose = d;
            break;
          }
        }

        ScheduledDoseStatus status;
        DateTime? takenAt;
        if (matchingDose != null) {
          status = matchingDose.status == DoseStatus.taken
              ? ScheduledDoseStatus.taken
              : ScheduledDoseStatus.skipped;
          takenAt = matchingDose.takenAt ?? matchingDose.recordedAt;
        } else {
          final parts = time.split(':');
          final scheduledDateTime = DateTime(
            scheduledDate.year,
            scheduledDate.month,
            scheduledDate.day,
            int.parse(parts[0]),
            parts.length > 1 ? int.parse(parts[1]) : 0,
          );
          status = scheduledDateTime.isBefore(DateTime.now())
              ? ScheduledDoseStatus.missed
              : ScheduledDoseStatus.scheduled;
        }

        result.add(ScheduledDose(
          medicineId: medicine.id,
          medicineName: medicine.name,
          eye: schedule.eye,
          scheduledDate: scheduledDate,
          scheduledTime: time,
          status: status,
          takenAt: takenAt,
          dose: matchingDose,
        ));
      }
    }
  }

  result.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  return result;
}

/// Flare-ups for a given date.
final flareUpsForDateProvider = Provider.family<List<FlareUp>, DateTime>((ref, date) {
  final flareUps = ref.watch(flareUpsProvider).valueOrNull ?? [];
  return flareUps.where((f) => _sameDay(f.date, date)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
});

/// Flare-ups for a date range.
final flareUpsForRangeProvider = Provider.family<Map<DateTime, List<FlareUp>>, ({DateTime start, DateTime end})>((ref, range) {
  final flareUps = ref.watch(flareUpsProvider).valueOrNull ?? [];
  final result = <DateTime, List<FlareUp>>{};
  var d = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);

  for (final flareUp in flareUps) {
    final dateKey = DateTime(flareUp.date.year, flareUp.date.month, flareUp.date.day);
    if (!dateKey.isBefore(range.start) && !dateKey.isAfter(end)) {
      result.putIfAbsent(dateKey, () => []).add(flareUp);
    }
  }

  for (final list in result.values) {
    list.sort((a, b) => a.date.compareTo(b.date));
  }
  return result;
});

/// Appointments for a given date.
final appointmentsForDateProvider = Provider.family<List<AppointmentNote>, DateTime>((ref, date) {
  final appointments = ref.watch(appointmentsProvider).valueOrNull ?? [];
  return appointments.where((a) => _sameDay(a.date, date)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
});

/// Appointments for a date range.
final appointmentsForRangeProvider = Provider.family<Map<DateTime, List<AppointmentNote>>, ({DateTime start, DateTime end})>((ref, range) {
  final appointments = ref.watch(appointmentsProvider).valueOrNull ?? [];
  final result = <DateTime, List<AppointmentNote>>{};
  var d = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);

  for (final appointment in appointments) {
    final dateKey = DateTime(appointment.date.year, appointment.date.month, appointment.date.day);
    if (!dateKey.isBefore(range.start) && !dateKey.isAfter(end)) {
      result.putIfAbsent(dateKey, () => []).add(appointment);
    }
  }

  for (final list in result.values) {
    list.sort((a, b) => a.date.compareTo(b.date));
  }
  return result;
});
