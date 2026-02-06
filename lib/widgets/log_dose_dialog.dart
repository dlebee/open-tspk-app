import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelSmall,
              ),
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
              title: const Text('Date'),
              subtitle: Text(_isToday(_takenAt)
                  ? 'Today'
                  : DateFormat('MMM d, yyyy').format(_takenAt)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _takenAt,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() {
                    _takenAt = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      _takenAt.hour,
                      _takenAt.minute,
                    );
                  });
                }
              },
            ),
            ListTile(
              title: const Text('Time'),
              subtitle: Text(
                '${_takenAt.hour.toString().padLeft(2, '0')}:${_takenAt.minute.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.access_time),
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
                    medicineName: _medicine!.name,
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

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }
}
