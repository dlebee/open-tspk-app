import 'dart:math';

import 'package:flutter_riverpod/misc.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../models/medicine_schedule.dart';
import '../providers/appointment_provider.dart';
import '../providers/dose_provider.dart';
import '../providers/flare_up_provider.dart';
import '../providers/medicine_provider.dart';
import '../ui/dusk_ui.dart';
import '../utils/date_utils.dart';

/// Three weeks of realistic drops, check-ins and visits. Used by Debug tools
/// and by the store screenshot script.
Future<void> seedDemoData(
  T Function<T>(ProviderListenable<T>) read, {
  bool logToday = false,
}) async {
  final rnd = Random(7);
  final now = DateTime.now();
  final start = addCalendarDays(dayOf(now), -21);
  final steroid = Medicine(
    name: 'Steroid drop',
    createdAt: start,
    schedules: [
      MedicineSchedule(
        eye: Eye.both,
        daysOfWeek: const [1, 2, 3, 4, 5, 6, 7],
        times: const ['08:00', '20:00'],
      ),
    ],
  );
  final lube = Medicine(
    name: 'Lubricant',
    createdAt: start,
    schedules: [
      MedicineSchedule(
        eye: Eye.both,
        daysOfWeek: const [1, 2, 3, 4, 5, 6, 7],
        times: const ['13:00', '22:00'],
      ),
    ],
  );
  final meds = read(medicinesProvider.notifier);
  await meds.add(steroid);
  await meds.add(lube);

  final doses = <MedicineDose>[];
  final flares = <FlareUp>[];
  for (var i = 0; i < 21; i++) {
    final day = addCalendarDays(start, i);
    for (final m in [steroid, lube]) {
      for (final t in m.schedules.first.times) {
        final at = atTime(day, t);
        if (rnd.nextDouble() < 0.08) continue; // left unlogged
        final skipped = rnd.nextDouble() < 0.05;
        doses.add(
          MedicineDose(
            medicineId: m.id,
            medicineName: m.name,
            eye: Eye.both,
            status: skipped ? DoseStatus.skipped : DoseStatus.taken,
            recordedAt: at,
            scheduledDate: day,
            scheduledTime: t,
            takenAt: skipped
                ? null
                : at.add(Duration(minutes: rnd.nextInt(25))),
          ),
        );
      }
    }
    if (i % 3 == 0 || i == 9 || i == 10) {
      final flare = i == 9 || i == 10;
      final right = flare
          ? (i == 9 ? EyeFeel.sore : EyeFeel.flaring)
          : (rnd.nextBool() ? EyeFeel.gritty : EyeFeel.calm);
      flares.add(
        FlareUp(
          date: day.add(Duration(hours: 18, minutes: rnd.nextInt(50))),
          leftEye: false,
          rightEye: right != EyeFeel.calm,
          rightPainLevel: right.painLevel,
          reason: flare ? 'Light hurts, Watery' : null,
        ),
      );
      if (flare) {
        doses.add(
          MedicineDose(
            medicineId: lube.id,
            medicineName: lube.name,
            eye: Eye.right,
            status: DoseStatus.taken,
            recordedAt: day.add(const Duration(hours: 15, minutes: 10)),
            takenAt: day.add(const Duration(hours: 15, minutes: 10)),
          ),
        );
      }
    }
  }
  // Today's past slots stay open so the Today screen has something to log,
  // unless [logToday] asks for them to be logged (store screenshots).
  if (logToday) {
    for (final m in [steroid, lube]) {
      for (final t in m.schedules.first.times) {
        final at = atTime(dayOf(now), t);
        if (at.isAfter(now)) continue;
        doses.add(
          MedicineDose(
            medicineId: m.id,
            medicineName: m.name,
            eye: Eye.both,
            status: DoseStatus.taken,
            recordedAt: at,
            scheduledDate: dayOf(now),
            scheduledTime: t,
            takenAt: at.add(const Duration(minutes: 4)),
          ),
        );
      }
    }
  }
  final dn = read(dosesProvider.notifier);
  for (final d in doses) {
    await dn.add(d);
  }
  final fn = read(flareUpsProvider.notifier);
  for (final f in flares) {
    await fn.add(f);
  }
  await read(appointmentsProvider.notifier).add(
    AppointmentNote(
      date: addCalendarDays(
        dayOf(now),
        7,
      ).add(const Duration(hours: 10, minutes: 30)),
      doctorOffice: 'Eye clinic',
      notes:
          'Can we lower the steroid to once a day?\nRight eye flares after screen-heavy days.',
    ),
  );
  await read(appointmentsProvider.notifier).add(
    AppointmentNote(
      date: start.add(const Duration(hours: 9)),
      doctorOffice: 'Eye clinic',
      notes: 'Started steroid drops.',
    ),
  );
}
