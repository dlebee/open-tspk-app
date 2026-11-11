import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/scheduled_dose.dart';
import '../providers/appointment_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/flare_up_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import '../utils/date_utils.dart';
import '../widgets/log_drop_sheet.dart';
import '../widgets/unscheduled_dose_dialog.dart';
import 'check_in_screen.dart';
import 'journey_screen.dart';
import 'visit_screen.dart';

class DayScreen extends ConsumerStatefulWidget {
  const DayScreen({super.key, required this.date});

  final DateTime date;

  @override
  ConsumerState<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends ConsumerState<DayScreen> {
  late DateTime _date = dayOf(widget.date);

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final scheduled = [...ref.watch(scheduledDosesForDateProvider(_date))]
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    final extras = ref.watch(unscheduledDosesForDateProvider(_date));
    final flareUps = ref.watch(flareUpsProvider).value ?? [];
    final checkIns = flareUps.where((f) => sameDay(f.date, _date)).toList();
    final visits = (ref.watch(appointmentsProvider).value ?? []).where((a) => sameDay(a.date, _date));
    final feel = feelsByDay(checkIns)[_date];
    final taken = scheduled.where((d) => d.status == ScheduledDoseStatus.taken).length;

    final events = <(DateTime, Widget)>[
      for (final d in scheduled)
        (
          atTime(_date, d.scheduledTime),
          _Event(
            time: d.scheduledTime,
            dot: switch (d.status) {
              ScheduledDoseStatus.taken => Dusk.amber,
              ScheduledDoseStatus.missed => Dusk.rose,
              _ => Dusk.textMuted,
            },
            title: d.medicineName,
            detail: switch (d.status) {
              ScheduledDoseStatus.taken =>
                '${eyeLabel(d.eye)} · taken ${d.takenAt != null ? hm(d.takenAt!) : ''}',
              ScheduledDoseStatus.skipped => 'Skipped',
              ScheduledDoseStatus.missed => 'Not logged',
              ScheduledDoseStatus.scheduled => '${eyeLabel(d.eye)} · coming up',
            },
            onTap: () => showLogDropSheet(context, d),
          ),
        ),
      for (final x in extras)
        (
          x.takenAt ?? x.recordedAt,
          _Event(
            time: hm(x.takenAt ?? x.recordedAt),
            dot: Dusk.sage,
            title: 'Extra ${x.medicineName ?? 'drop'}',
            detail: eyeLabel(x.eye),
            onTap: () => showDialog(context: context, builder: (_) => UnscheduledDoseDialog(dose: x)),
          ),
        ),
      for (final c in checkIns)
        (
          c.date,
          _Event(
            time: hm(c.date),
            dot: worse(c.leftFeel, c.rightFeel).fg,
            title: 'Check-in',
            detail: [
              'Left ${c.leftFeel.label.toLowerCase()}, right ${c.rightFeel.label.toLowerCase()}',
              if (c.reason != null) c.reason!,
              if (c.comment != null) c.comment!,
            ].join(' · '),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => CheckInScreen(existing: c))),
          ),
        ),
      for (final v in visits)
        (
          v.date,
          _Event(
            time: hm(v.date),
            dot: Dusk.amber,
            title: v.doctorOffice,
            detail: 'Doctor visit',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VisitScreen())),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return DuskPage(
      title: DateFormat('d MMMM').format(_date),
      subtitle: DateFormat('EEEE').format(_date),
      actions: [
        RoundIconButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous day',
          onPressed: () => setState(() => _date = addCalendarDays(_date, -1)),
        ),
        const SizedBox(width: 8),
        if (_date.isBefore(today))
          RoundIconButton(
            icon: Icons.chevron_right,
            tooltip: 'Next day',
            onPressed: () => setState(() => _date = addCalendarDays(_date, 1)),
          ),
      ],
      bottom: sameDay(_date, today)
          ? SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Dusk.surface,
                  foregroundColor: Dusk.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const CheckInScreen())),
                child: const Text('Check in now'),
              ),
            )
          : null,
      children: [
        Row(
          children: [
            Expanded(child: _Stat(label: 'Left eye', feel: feel?.$1)),
            const SizedBox(width: 8),
            Expanded(child: _Stat(label: 'Right eye', feel: feel?.$2)),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(label: 'Drops', value: scheduled.isEmpty ? '—' : '$taken of ${scheduled.length}'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (events.isEmpty)
          const Text('Nothing logged this day.', style: TextStyle(color: Dusk.textSecondary)),
        for (final e in events) e.$2,
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, this.feel, this.value});

  final String label;
  final EyeFeel? feel;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final f = feel;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: f != null && f.isFlare ? f.bg : Dusk.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Dusk.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value ?? f?.label ?? 'No check-in',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: f?.fg ?? Dusk.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _Event extends StatelessWidget {
  const _Event({
    required this.time,
    required this.dot,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final String time;
  final Color dot;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Dusk.surfaceHigh))),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(time, style: const TextStyle(fontSize: 13, color: Dusk.textMuted)),
            ),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, color: Dusk.text)),
                  Text(detail, style: const TextStyle(fontSize: 13, color: Dusk.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
