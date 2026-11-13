import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import '../providers/dose_provider.dart';
import '../providers/medicine_provider.dart';
import '../screens/check_in_screen.dart';
import '../services/notification_service.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import 'hold_button.dart';
import 'taken_time_picker.dart';

/// Records a scheduled dose as taken or skipped, replacing any earlier record.
Future<void> logScheduledDose(
  WidgetRef ref,
  ScheduledDose dose,
  DoseStatus status, {
  DateTime? takenAt,
}) async {
  if (dose.dose != null) {
    await ref.read(dosesProvider.notifier).delete(dose.dose!.id);
  }
  final scheduledAt = atTime(dose.scheduledDate, dose.scheduledTime);
  try {
    await NotificationService.cancelForSchedule(
      dose.medicineId,
      dose.scheduledDate,
      dose.scheduledTime,
      dose.eye,
    );
  } catch (e) {
    debugPrint('[logScheduledDose] Failed to cancel notifications: $e');
  }
  await ref.read(dosesProvider.notifier).add(MedicineDose(
        medicineId: dose.medicineId,
        medicineName: dose.medicineName,
        eye: dose.eye,
        status: status,
        recordedAt: status == DoseStatus.skipped ? scheduledAt : DateTime.now(),
        scheduledDate: dose.scheduledDate,
        scheduledTime: dose.scheduledTime,
        takenAt: status == DoseStatus.taken ? (takenAt ?? DateTime.now()) : null,
      ));
}

Future<void> showLogDropSheet(BuildContext context, ScheduledDose dose) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LogDropSheet(dose: dose),
  );
}

class _LogDropSheet extends ConsumerWidget {
  const _LogDropSheet({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logged = dose.status == ScheduledDoseStatus.taken ||
        dose.status == ScheduledDoseStatus.skipped;
    // A drop from an earlier day can't be "taken now": log the time it was taken.
    final earlierDay = dayOf(dose.scheduledDate).isBefore(dayOf(DateTime.now()));

    Future<void> run(Future<void> Function() action, String message) async {
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      try {
        await action();
        nav.pop();
        messenger.showSnackBar(SnackBar(content: Text(message)));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text("Couldn't save that. $e")));
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              switch (dose.status) {
                ScheduledDoseStatus.taken => '${dose.scheduledTime} · taken',
                ScheduledDoseStatus.skipped => '${dose.scheduledTime} · skipped',
                ScheduledDoseStatus.missed => earlierDay
                    ? '${DateFormat('EEE d MMM').format(dose.scheduledDate)} · ${dose.scheduledTime} · not logged'
                    : '${dose.scheduledTime} · not logged · ${lateBy(dose.scheduledDate, dose.scheduledTime)}',
                ScheduledDoseStatus.scheduled => '${dose.scheduledTime} · coming up',
              },
              style: TextStyle(
                color: dose.status == ScheduledDoseStatus.missed ? Dusk.rose : Dusk.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dose.medicineName,
              textAlign: TextAlign.center,
              style: headingFont.copyWith(fontSize: 28, color: Dusk.text),
            ),
            const SizedBox(height: 16),
            _EyeBadges(eye: dose.eye),
            if (dose.status == ScheduledDoseStatus.missed) ...[
              const SizedBox(height: 14),
              Text(
                earlierDay
                    ? 'Took it after all? Log when you took it, or mark it skipped.'
                    : "Missed the time? You can still take it. Log it here when you do.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Dusk.textSecondary),
              ),
            ],
            const SizedBox(height: 28),
            if (logged) ...[
              Icon(
                dose.status == ScheduledDoseStatus.taken ? Icons.check_circle : Icons.skip_next_rounded,
                size: 56,
                color: dose.status == ScheduledDoseStatus.taken ? Dusk.amber : Dusk.textMuted,
              ),
              const SizedBox(height: 8),
              Text(
                dose.status == ScheduledDoseStatus.taken && dose.takenAt != null
                    ? 'Taken at ${hm(dose.takenAt!)}'
                    : 'Skipped',
                style: const TextStyle(fontSize: 16, color: Dusk.text),
              ),
              const SizedBox(height: 24),
              if (dose.status == ScheduledDoseStatus.skipped) ...[
                if (earlierDay)
                  PrimaryButton(
                    label: 'Took it at ${dose.scheduledTime} after all',
                    onPressed: () => run(
                      () => logScheduledDose(
                        ref,
                        dose,
                        DoseStatus.taken,
                        takenAt: atTime(dose.scheduledDate, dose.scheduledTime),
                      ),
                      'Logged at ${dose.scheduledTime}',
                    ),
                  )
                else
                  HoldButton(
                    onConfirmed: () => run(
                      () => logScheduledDose(ref, dose, DoseStatus.taken),
                      'Logged ${dose.medicineName}',
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => run(() async {
                    await ref.read(dosesProvider.notifier).delete(dose.dose!.id);
                  }, 'Undone'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Dusk.text,
                    side: const BorderSide(color: Dusk.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Undo'),
                ),
              ),
            ] else ...[
              if (earlierDay)
                PrimaryButton(
                  label: 'Took it at ${dose.scheduledTime}',
                  onPressed: () => run(
                    () => logScheduledDose(
                      ref,
                      dose,
                      DoseStatus.taken,
                      takenAt: atTime(dose.scheduledDate, dose.scheduledTime),
                    ),
                    'Logged at ${dose.scheduledTime}',
                  ),
                )
              else
                HoldButton(
                  onConfirmed: () => run(
                    () => logScheduledDose(ref, dose, DoseStatus.taken),
                    'Logged ${dose.medicineName}',
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!earlierDay)
                    TextButton(
                      onPressed: () => run(
                        () => logScheduledDose(
                          ref,
                          dose,
                          DoseStatus.taken,
                          takenAt: atTime(dose.scheduledDate, dose.scheduledTime),
                        ),
                        'Logged at ${dose.scheduledTime}',
                      ),
                      child: Text('Took it at ${dose.scheduledTime}'),
                    ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showTakenTimePicker(
                        context,
                        medicineId: dose.medicineId,
                        eyeStr: dose.eye.name,
                        scheduledDate: dose.scheduledDate.toIso8601String(),
                        scheduledTime: dose.scheduledTime,
                        onSaved: () => ref.read(dosesProvider.notifier).refresh(),
                      );
                    },
                    child: const Text('Other time'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuietButton(
                      label: 'Skip this one',
                      onPressed: () => run(
                        () => logScheduledDose(ref, dose, DoseStatus.skipped),
                        'Skipped',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuietButton(
                      label: 'Eyes feel off?',
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CheckInScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Logging a drop that isn't on the schedule.
Future<void> showExtraDropSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ExtraDropSheet(),
  );
}

class _ExtraDropSheet extends ConsumerStatefulWidget {
  const _ExtraDropSheet();

  @override
  ConsumerState<_ExtraDropSheet> createState() => _ExtraDropSheetState();
}

class _ExtraDropSheetState extends ConsumerState<_ExtraDropSheet> {
  String? _medicineId;
  bool _left = true;
  bool _right = true;

  @override
  Widget build(BuildContext context) {
    final medicines = ref.watch(medicinesProvider).value ?? [];
    _medicineId ??= medicines.isEmpty ? null : medicines.first.id;
    final medicine = medicines.where((m) => m.id == _medicineId).firstOrNull;
    final eye = _left && _right
        ? Eye.both
        : _left
            ? Eye.left
            : _right
                ? Eye.right
                : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Extra drop', style: headingFont.copyWith(fontSize: 28, color: Dusk.text)),
            const SizedBox(height: 4),
            const Text('Outside your schedule', style: TextStyle(color: Dusk.textSecondary)),
            const SizedBox(height: 20),
            if (medicines.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a drop in Your drops first.', style: TextStyle(color: Dusk.textSecondary)),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in medicines)
                    ChoiceChip(
                      label: Text(m.name),
                      selected: m.id == _medicineId,
                      onSelected: (_) => setState(() => _medicineId = m.id),
                      selectedColor: Dusk.amberSoft,
                      labelStyle: TextStyle(color: m.id == _medicineId ? Dusk.amber : Dusk.text),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _EyeToggle(label: 'Left eye', on: _left, onTap: () => setState(() => _left = !_left)),
                  const SizedBox(width: 16),
                  _EyeToggle(label: 'Right eye', on: _right, onTap: () => setState(() => _right = !_right)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Tap an eye to leave it out', style: TextStyle(color: Dusk.textMuted, fontSize: 13)),
              const SizedBox(height: 24),
              HoldButton(
                label: eye == null ? 'Pick an eye' : 'Hold to log',
                onConfirmed: () async {
                  if (medicine == null || eye == null) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);
                  final now = DateTime.now();
                  await ref.read(dosesProvider.notifier).add(MedicineDose(
                        medicineId: medicine.id,
                        medicineName: medicine.name,
                        eye: eye,
                        status: DoseStatus.taken,
                        recordedAt: now,
                        takenAt: now,
                      ));
                  nav.pop();
                  messenger.showSnackBar(SnackBar(content: Text('Logged extra ${medicine.name}')));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EyeBadges extends StatelessWidget {
  const _EyeBadges({required this.eye});

  final Eye eye;

  @override
  Widget build(BuildContext context) {
    if (eye == Eye.other) {
      return const Pill('Pill / other', fg: Dusk.amber, bg: Dusk.amberSoft);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _EyeToggle(label: 'Left eye', on: eye != Eye.right),
        const SizedBox(width: 16),
        _EyeToggle(label: 'Right eye', on: eye != Eye.left),
      ],
    );
  }
}

class _EyeToggle extends StatelessWidget {
  const _EyeToggle({required this.label, required this.on, this.onTap});

  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Dusk.amber : Dusk.textMuted;
    return Semantics(
      selected: on,
      button: onTap != null,
      child: Material(
        color: on ? Dusk.amberSoft : Dusk.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: on ? Dusk.amber : Dusk.border, width: on ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SizedBox(
            width: 128,
            height: 84,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(on ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: fg, size: 26),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Dusk.surfaceHigh,
          foregroundColor: Dusk.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(label),
      ),
    );
  }
}
