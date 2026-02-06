import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import '../providers/dose_provider.dart';

class LogScheduledDoseDialog extends ConsumerWidget {
  const LogScheduledDoseDialog({super.key, required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = dose.scheduledTime.split(':');
    final scheduledDateTime = DateTime(
      dose.scheduledDate.year,
      dose.scheduledDate.month,
      dose.scheduledDate.day,
      int.parse(parts[0]),
      parts.length > 1 ? int.parse(parts[1]) : 0,
    );

    return AlertDialog(
      title: Text(dose.medicineName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${dose.eye.name} • Scheduled: ${dose.scheduledTime}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const Text('Log as:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _logAndClose(
              context,
              ref,
              DoseStatus.taken,
              DateTime.now(),
            ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Taken now'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _logAndClose(
              context,
              ref,
              DoseStatus.taken,
              scheduledDateTime,
            ),
            icon: const Icon(Icons.schedule),
            label: const Text('Taken at scheduled time'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _logAndClose(
              context,
              ref,
              DoseStatus.skipped,
              null,
            ),
            icon: const Icon(Icons.cancel),
            label: const Text('Missed'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
            ),
          ),
          if (dose.dose != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _untakeAndClose(context, ref),
              icon: const Icon(Icons.undo, size: 20),
              label: const Text('Untake'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _logAndClose(
    BuildContext context,
    WidgetRef ref,
    DoseStatus status,
    DateTime? takenAt,
  ) async {
    if (dose.dose != null) {
      await ref.read(dosesProvider.notifier).delete(dose.dose!.id);
    }
    final newDose = MedicineDose(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      medicineId: dose.medicineId,
      eye: dose.eye,
      status: status,
      recordedAt: DateTime.now(),
      scheduledDate: dose.scheduledDate,
      scheduledTime: dose.scheduledTime,
      takenAt: takenAt,
    );
    await ref.read(dosesProvider.notifier).add(newDose);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _untakeAndClose(BuildContext context, WidgetRef ref) async {
    if (dose.dose != null) {
      await ref.read(dosesProvider.notifier).delete(dose.dose!.id);
    }
    if (context.mounted) Navigator.pop(context);
  }
}
