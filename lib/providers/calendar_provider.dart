import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import 'dose_provider.dart';
import 'medicine_provider.dart';

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
          status = ScheduledDoseStatus.missed;
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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
