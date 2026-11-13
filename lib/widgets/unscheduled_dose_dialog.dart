import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import '../providers/calendar_provider.dart';
import '../providers/dose_provider.dart';
import '../providers/medicine_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import 'log_drop_sheet.dart';

/// Details of an extra (unscheduled) drop. If the same drop had a scheduled time that
/// day that is still open, the extra can be turned into that dose: someone who missed
/// their 08:00 drop and logged it later as "extra" can say it was the 08:00 one.
class UnscheduledDoseDialog extends ConsumerWidget {
  const UnscheduledDoseDialog({super.key, required this.dose});

  final MedicineDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicines = ref.watch(medicinesProvider).value ?? [];
    final medicineName = dose.medicineName ??
        medicines.where((m) => m.id == dose.medicineId).map((m) => m.name).firstOrNull ??
        'Unknown';
    final takenAt = dose.takenAt ?? dose.recordedAt;

    final open = ref
        .watch(scheduledDosesForDateProvider(dayOf(takenAt)))
        .where((d) =>
            d.medicineId == dose.medicineId &&
            (d.status == ScheduledDoseStatus.missed || d.status == ScheduledDoseStatus.scheduled))
        .toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    Future<void> countAs(ScheduledDose d) async {
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      await ref.read(dosesProvider.notifier).delete(dose.id);
      await logScheduledDose(ref, d, DoseStatus.taken, takenAt: takenAt);
      nav.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Logged as your ${d.scheduledTime} drop, taken at ${hm(takenAt)}')),
      );
    }

    return AlertDialog(
      title: Text('Extra $medicineName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${eyeLabel(dose.eye)} · taken at ${hm(takenAt)}',
            style: const TextStyle(color: Dusk.textSecondary),
          ),
          if (open.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Was this one of your scheduled drops?',
              style: TextStyle(fontSize: 14, color: Dusk.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            for (final d in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => countAs(d),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Dusk.amber,
                      side: const BorderSide(color: Dusk.amberBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('This was my ${d.scheduledTime} drop'),
                  ),
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            await ref.read(dosesProvider.notifier).delete(dose.id);
            nav.pop();
          },
          style: TextButton.styleFrom(foregroundColor: Dusk.rose),
          child: const Text('Delete'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
