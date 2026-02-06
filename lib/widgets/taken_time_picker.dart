import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/notification_service.dart';

void showTakenTimePicker(
  BuildContext context, {
  required String medicineId,
  required String eyeStr,
  required String scheduledDate,
  required String scheduledTime,
  required void Function() onSaved,
}) {
  showDialog(
    context: context,
    builder: (ctx) => _TakenTimePickerDialog(
      medicineId: medicineId,
      eye: Eye.values.firstWhere((e) => e.name == eyeStr, orElse: () => Eye.both),
      scheduledDate: DateTime.parse(scheduledDate),
      scheduledTime: scheduledTime,
      onSaved: onSaved,
    ),
  );
}

class _TakenTimePickerDialog extends StatefulWidget {
  const _TakenTimePickerDialog({
    required this.medicineId,
    required this.eye,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.onSaved,
  });

  final String medicineId;
  final Eye eye;
  final DateTime scheduledDate;
  final String scheduledTime;
  final VoidCallback onSaved;

  @override
  State<_TakenTimePickerDialog> createState() => _TakenTimePickerDialogState();
}

class _TakenTimePickerDialogState extends State<_TakenTimePickerDialog> {
  late DateTime _takenAt;

  @override
  void initState() {
    super.initState();
    _takenAt = DateTime(
      widget.scheduledDate.year,
      widget.scheduledDate.month,
      widget.scheduledDate.day,
      int.parse(widget.scheduledTime.split(':')[0]),
      int.parse(widget.scheduledTime.split(':')[1]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('When did you take it?'),
      content: ListTile(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            // The notification service's _addDose is called from the notification handler.
            // For override we need to add the dose ourselves - we have the storage.
            // Actually the notification handler for taken_at_override calls _onOverrideTimeRequested
            // which should show this dialog. When the user taps Save, we need to add the dose.
            // The NotificationService doesn't have a public method to add dose. Let me add one.
            NotificationService.addDoseFromOverride(
              widget.medicineId,
              widget.eye,
              widget.scheduledDate,
              widget.scheduledTime,
              _takenAt,
            );
            widget.onSaved();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
