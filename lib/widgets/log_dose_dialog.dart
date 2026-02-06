import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../providers/dose_provider.dart';

class LogDoseDialog extends ConsumerStatefulWidget {
  const LogDoseDialog({super.key, required this.medicines});

  final List<Medicine> medicines;

  @override
  ConsumerState<LogDoseDialog> createState() => _LogDoseDialogState();
}

class _LogDoseDialogState extends ConsumerState<LogDoseDialog> {
  Medicine? _medicine;
  Eye _eye = Eye.both;
  DateTime _takenAt = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log dose'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Medicine>(
              value: _medicine,
              decoration: const InputDecoration(labelText: 'Medicine'),
              items: widget.medicines
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                  .toList(),
              onChanged: (m) => setState(() => _medicine = m),
            ),
            const SizedBox(height: 16),
            Text('Where', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<Eye>(
              segments: const [
                ButtonSegment(value: Eye.left, label: Text('Left')),
                ButtonSegment(value: Eye.right, label: Text('Right')),
                ButtonSegment(value: Eye.both, label: Text('Both')),
                ButtonSegment(value: Eye.other, label: Text('Other (e.g. pill)')),
              ],
              selected: {_eye},
              onSelectionChanged: (s) => setState(() => _eye = s.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Taken at'),
              subtitle: Text(
                '${_takenAt.hour.toString().padLeft(2, '0')}:${_takenAt.minute.toString().padLeft(2, '0')}',
              ),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_takenAt),
                );
                if (time != null) {
                  setState(() {
                    _takenAt = DateTime(
                      _takenAt.year,
                      _takenAt.month,
                      _takenAt.day,
                      time.hour,
                      time.minute,
                    );
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _medicine == null
              ? null
              : () async {
                  final dose = MedicineDose(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    medicineId: _medicine!.id,
                    eye: _eye,
                    status: DoseStatus.taken,
                    recordedAt: DateTime.now(),
                    scheduledDate: null,
                    scheduledTime: null,
                    takenAt: _takenAt,
                  );
                  await ref.read(dosesProvider.notifier).add(dose);
                  if (mounted) Navigator.pop(context);
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
