import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_note.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import '../providers/appointment_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/medicine_provider.dart';
import '../providers/appointment_provider.dart';
import '../screens/appointments_screen.dart' show AppointmentForm;
import '../widgets/log_dose_dialog.dart';
import '../widgets/log_flare_up_sheet.dart';
import '../widgets/log_scheduled_dose_dialog.dart';
import '../widgets/unscheduled_dose_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayScheduled = ref.watch(scheduledDosesForDateProvider(today));
    final todayUnscheduled = ref.watch(unscheduledDosesForDateProvider(today));
    final yesterdayScheduled = ref.watch(scheduledDosesForDateProvider(yesterday));
    final yesterdayUnscheduled = ref.watch(unscheduledDosesForDateProvider(yesterday));

    final allMedicines = ref.watch(medicinesProvider).valueOrNull ?? [];
    final activeMedicines = ref.watch(medicinesProvider).valueOrNull ?? [];
    final medicineById = {for (final m in allMedicines) m.id: m};
    final appointments = ref.watch(appointmentsProvider).valueOrNull ?? [];
    final nextAppointment = appointments
        .where((a) => a.date.isAfter(now))
        .fold<AppointmentNote?>(
          null,
          (prev, curr) => prev == null || curr.date.isBefore(prev.date) ? curr : prev,
        );

    final todayEmpty = todayScheduled.isEmpty && todayUnscheduled.isEmpty;
    final yesterdayEmpty = yesterdayScheduled.isEmpty && yesterdayUnscheduled.isEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open menu',
        ),
        title: const Text('Thygeson'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showLogDoseDialog(context, ref, activeMedicines),
            tooltip: 'Log dose',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            title: 'Today\'s doses',
            onTap: () => _showLogDoseDialog(context, ref, activeMedicines),
          ),
          if (todayEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No doses for today. Add medicines and schedules, or log an unscheduled dose.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            ...todayScheduled.map((d) => _DoseTile(
                  dose: d,
                  onTap: () => _showLogScheduledDoseDialog(context, ref, d),
                )),
            if (todayUnscheduled.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Unscheduled doses',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...todayUnscheduled.map((d) {
                final name = d.medicineName ?? medicineById[d.medicineId]?.name ?? 'Unknown';
                final t = d.takenAt ?? d.recordedAt;
                final timeStr =
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                return _UnscheduledDoseTile(
                  medicineName: name,
                  dose: d,
                  timeStr: timeStr,
                  onTap: () => _showUnscheduledDoseDialog(context, d),
                );
              }),
            ],
          ],
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'Yesterday\'s doses',
            onTap: () => _showLogDoseDialog(context, ref, activeMedicines),
          ),
          if (yesterdayEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No doses for yesterday.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            ...yesterdayScheduled.map((d) => _DoseTile(
                  dose: d,
                  onTap: () => _showLogScheduledDoseDialog(context, ref, d),
                )),
            if (yesterdayUnscheduled.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Unscheduled doses',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...yesterdayUnscheduled.map((d) {
                final name = d.medicineName ?? medicineById[d.medicineId]?.name ?? 'Unknown';
                final t = d.takenAt ?? d.recordedAt;
                final timeStr =
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                return _UnscheduledDoseTile(
                  medicineName: name,
                  dose: d,
                  timeStr: timeStr,
                  onTap: () => _showUnscheduledDoseDialog(context, d),
                );
              }),
            ],
          ],
          if (nextAppointment != null) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: 'Next appointment'),
            Card(
              child: ListTile(
                leading: Icon(Icons.event_note, color: Colors.purple.shade600),
                title: Text(nextAppointment.doctorOffice),
                subtitle: Text(
                  _formatAppointmentDate(nextAppointment.date) +
                      (nextAppointment.notes.isNotEmpty ? '\n${nextAppointment.notes}' : ''),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAppointment(context, ref, nextAppointment),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _SectionHeader(title: 'Quick actions'),
          ListTile(
            leading: const Icon(Icons.warning_amber),
            title: const Text('Log flare-up'),
            onTap: () => _showLogFlareUp(context, ref),
          ),
        ],
      ),
    );
  }

  String _formatAppointmentDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final appointmentDate = DateTime(date.year, date.month, date.day);
    final daysDiff = appointmentDate.difference(today).inDays;
    
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    
    if (daysDiff == 0) {
      return 'Today at $timeStr';
    } else if (daysDiff == 1) {
      return 'Tomorrow at $timeStr';
    } else if (daysDiff > 1 && daysDiff <= 7) {
      return '$dateStr at $timeStr (in $daysDiff days)';
    } else {
      return '$dateStr at $timeStr';
    }
  }

  void _showLogFlareUp(BuildContext context, WidgetRef ref) {
    showLogFlareUpSheet(context, ref);
  }

  void _showLogDoseDialog(
    BuildContext context,
    WidgetRef ref,
    List<Medicine> medicines,
  ) {
    if (medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add medicines first')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => LogDoseDialog(medicines: medicines),
    );
  }

  void _showLogScheduledDoseDialog(
    BuildContext context,
    WidgetRef ref,
    ScheduledDose dose,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => LogScheduledDoseDialog(dose: dose),
    );
  }

  void _showUnscheduledDoseDialog(BuildContext context, MedicineDose dose) {
    showDialog(
      context: context,
      builder: (ctx) => UnscheduledDoseDialog(dose: dose),
    );
  }

  void _showAppointment(BuildContext context, WidgetRef ref, AppointmentNote appointment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppointmentForm(
        existing: appointment,
        onSave: (a) async {
          await ref.read(appointmentsProvider.notifier).update(a);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onDelete: () async {
          await ref.read(appointmentsProvider.notifier).delete(appointment.id);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (onTap != null)
            TextButton(
              onPressed: onTap,
              child: const Text('Log dose'),
            ),
        ],
      ),
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose, this.onTap});

  final ScheduledDose dose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (dose.status) {
      ScheduledDoseStatus.taken => Colors.green,
      ScheduledDoseStatus.skipped => Colors.orange,
      ScheduledDoseStatus.missed => Colors.red,
      ScheduledDoseStatus.scheduled => Colors.blue.shade700,
    };
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(Icons.medication, color: statusColor),
        ),
        title: Text('${dose.medicineName} - ${dose.eye.name}'),
        subtitle: Text(
          dose.status == ScheduledDoseStatus.missed
              ? 'Scheduled: ${dose.scheduledTime} (missed)'
              : dose.status == ScheduledDoseStatus.scheduled
                  ? 'Scheduled: ${dose.scheduledTime} (upcoming)'
                  : dose.takenAt != null
                      ? 'Scheduled: ${dose.scheduledTime} • Taken: ${_formatTime(dose.takenAt!)}'
                      : 'Scheduled: ${dose.scheduledTime}',
        ),
        trailing: Chip(
          label: Text(
            dose.status.name,
            style: const TextStyle(fontSize: 12),
          ),
          backgroundColor: statusColor.withOpacity(0.2),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _UnscheduledDoseTile extends StatelessWidget {
  const _UnscheduledDoseTile({
    required this.medicineName,
    required this.dose,
    required this.timeStr,
    required this.onTap,
  });

  final String medicineName;
  final MedicineDose dose;
  final String timeStr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Colors.green.withOpacity(0.2),
          child: Icon(Icons.medication, color: Colors.green),
        ),
        title: Text('$medicineName - ${dose.eye.name}'),
        subtitle: Text('Taken at $timeStr'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
