import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine_dose.dart';
import '../providers/dose_provider.dart';
import '../providers/medicine_provider.dart';

class UnscheduledDoseDialog extends ConsumerWidget {
  const UnscheduledDoseDialog({super.key, required this.dose});

  final MedicineDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicines = ref.watch(medicinesProvider).valueOrNull ?? [];
    final medicineName = dose.medicineName ??
        medicines
            .where((m) => m.id == dose.medicineId)
            .map((m) => m.name)
            .firstOrNull ??
        'Unknown';

    final takenAt = dose.takenAt ?? dose.recordedAt;
    final timeStr =
        '${takenAt.hour.toString().padLeft(2, '0')}:${takenAt.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: Text(medicineName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${dose.eye.name} • Taken at $timeStr'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () => _untakeAndClose(context, ref),
          child: const Text('Untake'),
        ),
      ],
    );
  }

  Future<void> _untakeAndClose(BuildContext context, WidgetRef ref) async {
    await ref.read(dosesProvider.notifier).delete(dose.id);
    if (context.mounted) Navigator.pop(context);
  }
}
