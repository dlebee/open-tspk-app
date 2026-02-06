import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../models/scheduled_dose.dart';
import '../providers/calendar_provider.dart';
import '../providers/medicine_provider.dart';
import '../widgets/log_dose_dialog.dart';
import '../widgets/log_flare_up_sheet.dart';
import '../widgets/log_scheduled_dose_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final scheduledDoses = ref.watch(scheduledDosesForDateProvider(date));
    final medicines = ref.watch(medicinesProvider).valueOrNull ?? [];

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
            onPressed: () => _showLogDoseDialog(context, ref, medicines),
            tooltip: 'Log dose',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            title: 'Today\'s doses',
            onTap: () => _showLogDoseDialog(context, ref, medicines),
          ),
          if (scheduledDoses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No doses scheduled for today. Add medicines and schedules, or log an unscheduled dose.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...scheduledDoses.map((d) => _DoseTile(
                  dose: d,
                  onTap: () => _showLogScheduledDoseDialog(context, ref, d),
                )),
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
