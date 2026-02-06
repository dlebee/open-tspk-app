import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/scheduled_dose.dart';
import '../providers/calendar_provider.dart';
import '../widgets/log_scheduled_dose_dialog.dart';

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
        initialChildSize: 0.5,
        expand: false,
        builder: (_, controller) => _DayDetailSheet(
          date: date,
          controller: controller,
          onDoseTap: _showLogScheduledDose,
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
                          if (doses.isNotEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _miniIndicator(doses, ScheduledDoseStatus.taken, Colors.green),
                                _miniIndicator(doses, ScheduledDoseStatus.missed, Colors.red),
                                _miniIndicator(doses, ScheduledDoseStatus.skipped, Colors.orange),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(7, (i) {
        final date = range.start.add(Duration(days: i));
        final doses = dosesByDate[date] ?? [];
        final isToday = date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;

        return Card(
          color: isToday ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            title: Text(
              DateFormat('EEE, MMM d').format(date),
              style: TextStyle(fontWeight: isToday ? FontWeight.bold : null),
            ),
            subtitle: doses.isEmpty
                ? const Text('No doses')
                : Text(
                    '${doses.where((d) => d.status == ScheduledDoseStatus.taken).length}/${doses.length} taken',
                  ),
            trailing: _daySummary(doses),
            onTap: () => onDayTap(context, date, doses),
          ),
        );
      }),
    );
  }

  Widget _daySummary(List<ScheduledDose> doses) {
    final taken = doses.where((d) => d.status == ScheduledDoseStatus.taken).length;
    final missed = doses.where((d) => d.status == ScheduledDoseStatus.missed).length;
    final skipped = doses.where((d) => d.status == ScheduledDoseStatus.skipped).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (taken > 0) Icon(Icons.check_circle, color: Colors.green, size: 20),
        if (missed > 0) Icon(Icons.cancel, color: Colors.red, size: 20),
        if (skipped > 0) Icon(Icons.skip_next, color: Colors.orange, size: 20),
      ],
    );
  }
}

class _TodayView extends ConsumerWidget {
  const _TodayView({
    required this.date,
    required this.today,
    required this.onDoseTap,
  });

  final DateTime date;
  final DateTime today;
  final void Function(BuildContext, ScheduledDose) onDoseTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateKey = DateTime(date.year, date.month, date.day);
    final doses = ref.watch(scheduledDosesForDateProvider(dateKey));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DateFormat('EEEE, MMMM d, yyyy').format(date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (doses.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No doses scheduled for this day.'),
          )
        else
          ...doses.map((d) => Card(
                child: ListTile(
                  leading: Icon(
                    d.status == ScheduledDoseStatus.taken
                        ? Icons.check_circle
                        : d.status == ScheduledDoseStatus.skipped
                            ? Icons.skip_next
                            : Icons.cancel,
                    color: d.status == ScheduledDoseStatus.taken
                        ? Colors.green
                        : d.status == ScheduledDoseStatus.skipped
                            ? Colors.orange
                            : Colors.red,
                  ),
                  title: Text('${d.medicineName} - ${d.eye.name}'),
                  subtitle: Text('${d.scheduledTime} - ${d.status.name}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onDoseTap(context, d),
                ),
              )),
      ],
    );
  }
}

class _DayDetailSheet extends ConsumerWidget {
  const _DayDetailSheet({
    required this.date,
    required this.controller,
    required this.onDoseTap,
  });

  final DateTime date;
  final ScrollController controller;
  final void Function(BuildContext, ScheduledDose) onDoseTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doses = ref.watch(scheduledDosesForDateProvider(date));
    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DateFormat('EEEE, MMM d').format(date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (doses.isEmpty)
          const Text('No scheduled doses')
        else
          ...doses.map((d) => ListTile(
                leading: Icon(
                  d.status == ScheduledDoseStatus.taken
                      ? Icons.check_circle
                      : d.status == ScheduledDoseStatus.skipped
                          ? Icons.skip_next
                          : Icons.cancel,
                  color: d.status == ScheduledDoseStatus.taken
                      ? Colors.green
                      : d.status == ScheduledDoseStatus.skipped
                          ? Colors.orange
                          : Colors.red,
                ),
                title: Text('${d.medicineName} - ${d.eye.name}'),
                subtitle: Text('${d.scheduledTime} - ${d.status.name}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onDoseTap(context, d),
              )),
      ],
    );
  }
}
