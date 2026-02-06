import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import '../providers/appointment_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/medicine_provider.dart';
import '../screens/appointments_screen.dart' show AppointmentForm;
import '../widgets/flare_up_emojis.dart';
import '../widgets/log_flare_up_sheet.dart';
import '../widgets/log_scheduled_dose_dialog.dart';
import '../widgets/unscheduled_dose_dialog.dart';

enum CalendarView { month, week, today }

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarView _view = CalendarView.month;
  DateTime _focusedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open menu',
        ),
        title: Text(_titleForView()),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _navigate(-1),
            tooltip: 'Previous',
          ),
          TextButton(
            onPressed: () => setState(() {
              _focusedDate = today;
              _view = CalendarView.today;
            }),
            child: const Text('Today'),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _navigate(1),
            tooltip: 'Next',
          ),
        ],
      ),
      body: Column(
        children: [
          SegmentedButton<CalendarView>(
            segments: const [
              ButtonSegment(value: CalendarView.month, label: Text('Month')),
              ButtonSegment(value: CalendarView.week, label: Text('Week')),
              ButtonSegment(value: CalendarView.today, label: Text('Today')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          Expanded(
            child: switch (_view) {
              CalendarView.month => _MonthGrid(
                focusedDate: _focusedDate,
                today: today,
                onDayTap: _showDayDetail,
              ),
              CalendarView.week => _WeekView(
                focusedDate: _focusedDate,
                today: today,
                onDayTap: _showDayDetail,
              ),
              CalendarView.today => _TodayView(
                date: _focusedDate,
                today: today,
                onDoseTap: _showLogScheduledDose,
                onUnscheduledDoseTap: _showUnscheduledDoseDialog,
                onFlareUpTap: _showFlareUp,
                onAppointmentTap: _showAppointment,
              ),
            },
          ),
        ],
      ),
    );
  }

  String _titleForView() {
    return switch (_view) {
      CalendarView.month => DateFormat('MMMM yyyy').format(_focusedDate),
      CalendarView.week => _weekRangeText(),
      CalendarView.today => DateFormat('EEEE, MMM d').format(_focusedDate),
    };
  }

  String _weekRangeText() {
    final start = _focusedDate.subtract(Duration(days: _focusedDate.weekday % 7));
    final end = start.add(const Duration(days: 6));
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
  }

  void _navigate(int delta) {
    setState(() {
      switch (_view) {
        case CalendarView.month:
          _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + delta, 1);
          break;
        case CalendarView.week:
          _focusedDate = _focusedDate.add(Duration(days: 7 * delta));
          break;
        case CalendarView.today:
          _focusedDate = _focusedDate.add(Duration(days: delta));
          break;
      }
    });
  }

  void _showDayDetail(BuildContext context, DateTime date, List<ScheduledDose> doses) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _DayDetailSheet(
          date: date,
          controller: controller,
          onDoseTap: _showLogScheduledDose,
          onUnscheduledDoseTap: _showUnscheduledDoseDialog,
          onFlareUpTap: _showFlareUp,
          onAppointmentTap: _showAppointment,
        ),
      ),
    );
  }

  void _showLogScheduledDose(BuildContext context, ScheduledDose dose) {
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

  void _showFlareUp(BuildContext context, WidgetRef ref, FlareUp flareUp) {
    showLogFlareUpSheet(context, ref, existing: flareUp);
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

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.focusedDate,
    required this.today,
    required this.onDayTap,
  });

  final DateTime focusedDate;
  final DateTime today;
  final void Function(BuildContext, DateTime, List<ScheduledDose>) onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstOfMonth = DateTime(focusedDate.year, focusedDate.month, 1);
    final gridStart = firstOfMonth.subtract(Duration(days: firstOfMonth.weekday % 7));
    final gridEnd = gridStart.add(const Duration(days: 41));
    final range = (start: gridStart, end: gridEnd);
    final dosesByDate = ref.watch(scheduledDosesForRangeProvider(range));
    final unscheduledByDate = ref.watch(unscheduledDosesForRangeProvider(range));
    final flareUpsByDate = ref.watch(flareUpsForRangeProvider(range));
    final appointmentsByDate = ref.watch(appointmentsForRangeProvider(range));

    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((d) => SizedBox(
              width: 40,
              child: Text(d, style: Theme.of(context).textTheme.labelSmall),
            )).toList(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 42,
              itemBuilder: (context, i) {
                final date = range.start.add(Duration(days: i));
                final dateKey = DateTime(date.year, date.month, date.day);
                final doses = dosesByDate[dateKey] ?? [];
                final isCurrentMonth = date.month == focusedDate.month;
                final isToday = date.year == today.year &&
                    date.month == today.month &&
                    date.day == today.day;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onDayTap(context, dateKey, doses),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isToday
                            ? Theme.of(context).colorScheme.primaryContainer
                            : isCurrentMonth
                                ? null
                                : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontWeight: isToday ? FontWeight.bold : null,
                              color: isCurrentMonth ? null : Colors.grey,
                            ),
                          ),
                          if (doses.isNotEmpty || (unscheduledByDate[dateKey]?.isNotEmpty ?? false) || (flareUpsByDate[dateKey]?.isNotEmpty ?? false) || (appointmentsByDate[dateKey]?.isNotEmpty ?? false))
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _miniIndicator(doses, ScheduledDoseStatus.taken, Colors.green),
                                _miniIndicator(doses, ScheduledDoseStatus.missed, Colors.red),
                                _miniIndicator(doses, ScheduledDoseStatus.skipped, Colors.orange),
                                _miniIndicator(doses, ScheduledDoseStatus.scheduled, Colors.grey),
                                if (unscheduledByDate[dateKey]?.isNotEmpty ?? false)
                                  Container(
                                    margin: const EdgeInsets.only(left: 1),
                                    width: 4,
                                    height: 4,
                                    decoration: const BoxDecoration(
                                        color: Colors.blue, shape: BoxShape.circle),
                                  ),
                                if (flareUpsByDate[dateKey]?.isNotEmpty ?? false)
                                  Container(
                                    margin: const EdgeInsets.only(left: 1),
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                        color: Colors.orange.shade700, shape: BoxShape.circle),
                                  ),
                                if (appointmentsByDate[dateKey]?.isNotEmpty ?? false)
                                  Container(
                                    margin: const EdgeInsets.only(left: 1),
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                        color: Colors.purple.shade600, shape: BoxShape.circle),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIndicator(List<ScheduledDose> doses, ScheduledDoseStatus status, Color color) {
    final count = doses.where((d) => d.status == status).length;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 1),
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _WeekView extends ConsumerWidget {
  const _WeekView({
    required this.focusedDate,
    required this.today,
    required this.onDayTap,
  });

  final DateTime focusedDate;
  final DateTime today;
  final void Function(BuildContext, DateTime, List<ScheduledDose>) onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = DateTime(
      focusedDate.year,
      focusedDate.month,
      focusedDate.day,
    ).subtract(Duration(days: focusedDate.weekday % 7));
    final range = (
      start: weekStart,
      end: weekStart.add(const Duration(days: 6)),
    );
    final dosesByDate = ref.watch(scheduledDosesForRangeProvider(range));
    final unscheduledByDate = ref.watch(unscheduledDosesForRangeProvider(range));
    final flareUpsByDate = ref.watch(flareUpsForRangeProvider(range));
    final appointmentsByDate = ref.watch(appointmentsForRangeProvider(range));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(7, (i) {
        final date = range.start.add(Duration(days: i));
        final doses = dosesByDate[date] ?? [];
        final unscheduled = unscheduledByDate[date] ?? [];
        final flareUps = flareUpsByDate[date] ?? [];
        final appointments = appointmentsByDate[date] ?? [];
        final isToday = date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;

        final takenCount = doses.where((d) => d.status == ScheduledDoseStatus.taken).length;
        final totalScheduled = doses.length;
        final unscheduledCount = unscheduled.length;
        final flareUpCount = flareUps.length;
        final appointmentCount = appointments.length;
        String subtitle;
        final parts = <String>[];
        if (totalScheduled > 0) {
          parts.add('$takenCount/$totalScheduled taken');
        }
        if (unscheduledCount > 0) {
          parts.add('$unscheduledCount ad-hoc');
        }
        if (flareUpCount > 0) {
          parts.add('$flareUpCount flare-up${flareUpCount > 1 ? 's' : ''}');
        }
        if (appointmentCount > 0) {
          parts.add('$appointmentCount appointment${appointmentCount > 1 ? 's' : ''}');
        }
        subtitle = parts.isEmpty ? 'No activity' : parts.join(', ');

        return Card(
          color: isToday ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            title: Text(
              DateFormat('EEE, MMM d').format(date),
              style: TextStyle(fontWeight: isToday ? FontWeight.bold : null),
            ),
            subtitle: Text(subtitle),
            trailing: _daySummary(doses, unscheduled, flareUps, appointments),
            onTap: () => onDayTap(context, date, doses),
          ),
        );
      }),
    );
  }

  Widget _daySummary(List<ScheduledDose> doses, List<MedicineDose> unscheduled, List<FlareUp> flareUps, List<AppointmentNote> appointments) {
    final taken = doses.where((d) => d.status == ScheduledDoseStatus.taken).length;
    final missed = doses.where((d) => d.status == ScheduledDoseStatus.missed).length;
    final skipped = doses.where((d) => d.status == ScheduledDoseStatus.skipped).length;
    final scheduled = doses.where((d) => d.status == ScheduledDoseStatus.scheduled).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (taken > 0) Icon(Icons.check_circle, color: Colors.green, size: 20),
        if (missed > 0) Icon(Icons.cancel, color: Colors.red, size: 20),
        if (skipped > 0) Icon(Icons.skip_next, color: Colors.orange, size: 20),
        if (scheduled > 0) Icon(Icons.schedule, color: Colors.grey, size: 20),
        if (unscheduled.isNotEmpty) Icon(Icons.medication, color: Colors.blue, size: 20),
        if (flareUps.isNotEmpty) Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
        if (appointments.isNotEmpty) Icon(Icons.event_note, color: Colors.purple.shade600, size: 20),
      ],
    );
  }
}

class _TodayView extends ConsumerWidget {
  const _TodayView({
    required this.date,
    required this.today,
    required this.onDoseTap,
    required this.onUnscheduledDoseTap,
    required this.onFlareUpTap,
    required this.onAppointmentTap,
  });

  final DateTime date;
  final DateTime today;
  final void Function(BuildContext, ScheduledDose) onDoseTap;
  final void Function(BuildContext, MedicineDose) onUnscheduledDoseTap;
  final void Function(BuildContext, WidgetRef, FlareUp) onFlareUpTap;
  final void Function(BuildContext, WidgetRef, AppointmentNote) onAppointmentTap;

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateKey = DateTime(date.year, date.month, date.day);
    final scheduledDoses = ref.watch(scheduledDosesForDateProvider(dateKey));
    final unscheduledDoses = ref.watch(unscheduledDosesForDateProvider(dateKey));
    final flareUps = ref.watch(flareUpsForDateProvider(dateKey));
    final appointments = ref.watch(appointmentsForDateProvider(dateKey));
    final medicines = ref.watch(medicinesProvider).valueOrNull ?? [];
    final medicineById = {for (final m in medicines) m.id: m};

    final hasScheduled = scheduledDoses.isNotEmpty;
    final hasUnscheduled = unscheduledDoses.isNotEmpty;
    final hasFlareUps = flareUps.isNotEmpty;
    final hasAppointments = appointments.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DateFormat('EEEE, MMMM d, yyyy').format(date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (hasScheduled)
          ...scheduledDoses.map((d) => Card(
                child: ListTile(
                  leading: Icon(
                    d.status == ScheduledDoseStatus.taken
                        ? Icons.check_circle
                        : d.status == ScheduledDoseStatus.skipped
                            ? Icons.skip_next
                            : d.status == ScheduledDoseStatus.scheduled
                                ? Icons.schedule
                                : Icons.cancel,
                    color: d.status == ScheduledDoseStatus.taken
                        ? Colors.green
                        : d.status == ScheduledDoseStatus.skipped
                            ? Colors.orange
                            : d.status == ScheduledDoseStatus.scheduled
                                ? Colors.blue
                                : Colors.red,
                  ),
                  title: Text('${d.medicineName} - ${d.eye.name}'),
                  subtitle: Text('${d.scheduledTime} - ${d.status.name}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onDoseTap(context, d),
                ),
              )),
        if (hasUnscheduled) ...[
          if (hasScheduled) const SizedBox(height: 16),
          Text(
            'Unscheduled doses',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...unscheduledDoses.map((d) {
            final name = medicineById[d.medicineId]?.name ?? 'Unknown';
            final t = d.takenAt ?? d.recordedAt;
            final timeStr =
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
            return Card(
              child: ListTile(
                leading: Icon(Icons.medication, color: Colors.green),
                title: Text('$name - ${d.eye.name}'),
                subtitle: Text('Taken at $timeStr'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onUnscheduledDoseTap(context, d),
              ),
            );
          }),
        ],
        if (hasFlareUps) ...[
          if (hasScheduled || hasUnscheduled) const SizedBox(height: 16),
          Text(
            'Flare-ups',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...flareUps.map((f) => Card(
                child: ListTile(
                  leading: FlareUpEyes(flareUp: f, size: 20),
                  title: Text(_formatDate(f.date)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (f.reason != null && f.reason!.isNotEmpty)
                        Text(
                          f.reason!,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      if (f.comment != null && f.comment!.isNotEmpty)
                        Text(f.comment!),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onFlareUpTap(context, ref, f),
                ),
              )),
        ],
        if (hasAppointments) ...[
          if (hasScheduled || hasUnscheduled || hasFlareUps) const SizedBox(height: 16),
          Text(
            'Appointments',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...appointments.map((a) {
            final timeStr = '${a.date.hour.toString().padLeft(2, '0')}:${a.date.minute.toString().padLeft(2, '0')}';
            return Card(
              child: ListTile(
                leading: Icon(Icons.event_note, color: Colors.purple.shade600),
                title: Text(a.doctorOffice),
                subtitle: Text('$timeStr${a.notes.isNotEmpty ? '\n${a.notes}' : ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onAppointmentTap(context, ref, a),
              ),
            );
          }),
        ],
        if (!hasScheduled && !hasUnscheduled && !hasFlareUps && !hasAppointments)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No activity for this day.'),
          ),
      ],
    );
  }
}

class _DayDetailSheet extends ConsumerWidget {
  const _DayDetailSheet({
    required this.date,
    required this.controller,
    required this.onDoseTap,
    required this.onUnscheduledDoseTap,
    required this.onFlareUpTap,
    required this.onAppointmentTap,
  });

  final DateTime date;
  final ScrollController controller;
  final void Function(BuildContext, ScheduledDose) onDoseTap;
  final void Function(BuildContext, MedicineDose) onUnscheduledDoseTap;
  final void Function(BuildContext, WidgetRef, FlareUp) onFlareUpTap;
  final void Function(BuildContext, WidgetRef, AppointmentNote) onAppointmentTap;

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledDoses = ref.watch(scheduledDosesForDateProvider(date));
    final unscheduledDoses = ref.watch(unscheduledDosesForDateProvider(date));
    final flareUps = ref.watch(flareUpsForDateProvider(date));
    final appointments = ref.watch(appointmentsForDateProvider(date));
    final medicines = ref.watch(medicinesProvider).valueOrNull ?? [];
    final medicineById = {for (final m in medicines) m.id: m};

    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DateFormat('EEEE, MMM d').format(date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (scheduledDoses.isNotEmpty) ...[
          ...scheduledDoses.map((d) => ListTile(
                leading: Icon(
                  d.status == ScheduledDoseStatus.taken
                      ? Icons.check_circle
                      : d.status == ScheduledDoseStatus.skipped
                          ? Icons.skip_next
                          : d.status == ScheduledDoseStatus.scheduled
                              ? Icons.schedule
                              : Icons.cancel,
                  color: d.status == ScheduledDoseStatus.taken
                      ? Colors.green
                      : d.status == ScheduledDoseStatus.skipped
                          ? Colors.orange
                          : d.status == ScheduledDoseStatus.scheduled
                              ? Colors.blue
                              : Colors.red,
                ),
                title: Text('${d.medicineName} - ${d.eye.name}'),
                subtitle: Text('${d.scheduledTime} - ${d.status.name}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onDoseTap(context, d),
              )),
        ],
        if (unscheduledDoses.isNotEmpty) ...[
          if (scheduledDoses.isNotEmpty) const SizedBox(height: 16),
          Text(
            'Unscheduled doses',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...unscheduledDoses.map((d) {
            final name = medicineById[d.medicineId]?.name ?? 'Unknown';
            final t = d.takenAt ?? d.recordedAt;
            final timeStr =
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
            return ListTile(
              leading: Icon(Icons.medication, color: Colors.green),
              title: Text('$name - ${d.eye.name}'),
              subtitle: Text('Taken at $timeStr'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onUnscheduledDoseTap(context, d),
            );
          }),
        ],
        if (flareUps.isNotEmpty) ...[
          if (scheduledDoses.isNotEmpty || unscheduledDoses.isNotEmpty) const SizedBox(height: 16),
          Text(
            'Flare-ups',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...flareUps.map((f) => ListTile(
                leading: FlareUpEyes(flareUp: f, size: 20),
                title: Text(_formatDate(f.date)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f.reason != null && f.reason!.isNotEmpty)
                      Text(
                        f.reason!,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    if (f.comment != null && f.comment!.isNotEmpty)
                      Text(f.comment!),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onFlareUpTap(context, ref, f),
              )),
        ],
        if (appointments.isNotEmpty) ...[
          if (scheduledDoses.isNotEmpty || unscheduledDoses.isNotEmpty || flareUps.isNotEmpty) const SizedBox(height: 16),
          Text(
            'Appointments',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...appointments.map((a) {
            final timeStr = '${a.date.hour.toString().padLeft(2, '0')}:${a.date.minute.toString().padLeft(2, '0')}';
            return ListTile(
              leading: Icon(Icons.event_note, color: Colors.purple.shade600),
              title: Text(a.doctorOffice),
              subtitle: Text('$timeStr${a.notes.isNotEmpty ? '\n${a.notes}' : ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onAppointmentTap(context, ref, a),
            );
          }),
        ],
        if (scheduledDoses.isEmpty && unscheduledDoses.isEmpty && flareUps.isEmpty && appointments.isEmpty)
          const Text('No activity for this day'),
      ],
    );
  }
}
