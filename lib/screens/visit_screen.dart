import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/appointment_note.dart';
import '../models/scheduled_dose.dart';
import '../providers/appointment_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/flare_up_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import '../utils/date_utils.dart';
import 'appointments_screen.dart' show AppointmentForm;
import 'journey_screen.dart';

class VisitScreen extends ConsumerWidget {
  const VisitScreen({super.key});

  void _edit(BuildContext context, WidgetRef ref, [AppointmentNote? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppointmentForm(
        existing: existing,
        onSave: (a) async {
          final n = ref.read(appointmentsProvider.notifier);
          existing == null ? await n.add(a) : await n.update(a);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onDelete: existing == null
            ? null
            : () async {
                await ref.read(appointmentsProvider.notifier).delete(existing.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final appointments = [...ref.watch(appointmentsProvider).value ?? <AppointmentNote>[]]
      ..sort((a, b) => a.date.compareTo(b.date));
    final upcoming = appointments.where((a) => a.date.isAfter(now)).toList();
    final past = appointments.where((a) => !a.date.isAfter(now)).toList().reversed.toList();
    final next = upcoming.firstOrNull;
    final lastVisit = past.firstOrNull;

    final since = dayOf(lastVisit?.date ?? addCalendarDays(now, -30));
    final today = dayOf(now);
    final flareUps = (ref.watch(flareUpsProvider).value ?? [])
        .where((f) => !dayOf(f.date).isBefore(since))
        .toList();
    final flareCount = flareUps.where((f) => f.isFlare).length;
    final scheduledByDay = ref.watch(scheduledDosesForRangeProvider((start: since, end: today)));
    final extrasByDay = ref.watch(unscheduledDosesForRangeProvider((start: since, end: today)));
    final allScheduled = scheduledByDay.values.expand((l) => l).toList();
    final taken = allScheduled.where((d) => d.status == ScheduledDoseStatus.taken).length;
    final missed = allScheduled.where((d) => d.status == ScheduledDoseStatus.missed).length;
    final extras = extrasByDay.values.fold<int>(0, (n, l) => n + l.length);
    final feels = feelsByDay(flareUps);
    final days = calendarDaysBetween(since, today) + 1;

    String summary() {
      final b = StringBuffer()
        ..writeln('Thygeson summary · ${DateFormat('d MMM y').format(since)} to ${DateFormat('d MMM y').format(today)}')
        ..writeln()
        ..writeln('Scheduled drops taken: $taken of ${allScheduled.length - allScheduled.where((d) => d.status == ScheduledDoseStatus.scheduled).length}')
        ..writeln('Not logged: $missed')
        ..writeln('Extra drops: $extras')
        ..writeln('Flare-ups (sore or flaring): $flareCount')
        ..writeln();
      final flares = flareUps.where((f) => f.isFlare).toList()..sort((a, b) => a.date.compareTo(b.date));
      if (flares.isNotEmpty) {
        b.writeln('Flare-ups:');
        for (final f in flares) {
          b.writeln('- ${DateFormat('EEE d MMM HH:mm').format(f.date)}: left ${f.leftFeel.label.toLowerCase()}, '
              'right ${f.rightFeel.label.toLowerCase()}'
              '${f.reason != null ? ' (${f.reason})' : ''}${f.comment != null ? ' — ${f.comment}' : ''}');
        }
        b.writeln();
      }
      if (next != null && next.notes.trim().isNotEmpty) {
        b
          ..writeln('Questions for ${next.doctorOffice}:')
          ..writeln(next.notes.trim());
      }
      return b.toString();
    }

    return DuskPage(
      title: 'Doctor visits',
      actions: [
        TextButton.icon(
          onPressed: () => _edit(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add visit'),
        ),
      ],
      bottom: Builder(
        builder: (btnCtx) => PrimaryButton(
          label: 'Share summary with doctor',
          onPressed: () {
            final box = btnCtx.findRenderObject() as RenderBox?;
            SharePlus.instance.share(ShareParams(
              text: summary(),
              subject: 'Thygeson summary',
              sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
            ));
          },
        ),
      ),
      children: [
        if (next != null) ...[
          DuskTile(
            radius: 20,
            onTap: () => _edit(context, ref, next),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _inDays(calendarDaysBetween(today, dayOf(next.date))),
                  style: const TextStyle(color: Dusk.amber, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(next.doctorOffice, style: headingFont.copyWith(fontSize: 24, color: Dusk.text)),
                Text(DateFormat('EEEE d MMMM · HH:mm').format(next.date),
                    style: const TextStyle(color: Dusk.textSecondary)),
                if (next.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('TO ASK',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: Dusk.textSecondary)),
                  const SizedBox(height: 4),
                  Text(next.notes.trim(), style: const TextStyle(fontSize: 15, height: 1.5, color: Dusk.text)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ] else ...[
          DuskTile(
            onTap: () => _edit(context, ref),
            child: const Row(
              children: [
                Icon(Icons.event_available_outlined, color: Dusk.amber),
                SizedBox(width: 12),
                Expanded(
                  child: Text('No visit planned. Add one to keep your questions in one place.',
                      style: TextStyle(color: Dusk.textSecondary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        SectionLabel(lastVisit == null
            ? 'Last 30 days'
            : 'Since your last visit · ${DateFormat('d MMM').format(lastVisit.date)}'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Dusk.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Num('$flareCount', 'Flare-ups'),
                  _Num('$extras', 'Extra drops'),
                  _Num('$missed', 'Not logged'),
                ],
              ),
              const SizedBox(height: 16),
              for (final (label, pick) in [
                ('Left eye', (EyeFeel l, EyeFeel r) => l),
                ('Right eye', (EyeFeel l, EyeFeel r) => r),
              ]) ...[
                Text(label, style: const TextStyle(fontSize: 12, color: Dusk.textSecondary)),
                const SizedBox(height: 4),
                ExcludeSemantics(
                  child: SizedBox(
                    height: 16,
                    child: Row(
                      children: [
                        for (var i = 0; i < days; i++)
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 0.5),
                              color: () {
                                final f = feels[addCalendarDays(since, i)];
                                return f == null ? Dusk.surfaceHigh : pick(f.$1, f.$2).tone;
                              }(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        if (upcoming.length > 1 || past.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionLabel('All visits'),
          for (final a in [...upcoming.skip(1), ...past])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(a.doctorOffice),
              subtitle: Text(DateFormat('d MMM y · HH:mm').format(a.date)),
              trailing: const Icon(Icons.chevron_right, color: Dusk.textMuted),
              onTap: () => _edit(context, ref, a),
            ),
        ],
      ],
    );
  }

  String _inDays(int d) => switch (d) {
        0 => 'Today',
        1 => 'Tomorrow',
        _ => 'In $d days',
      };
}

class _Num extends StatelessWidget {
  const _Num(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: headingFont.copyWith(fontSize: 24, color: Dusk.text)),
          Text(label, style: const TextStyle(fontSize: 12, color: Dusk.textSecondary)),
        ],
      ),
    );
  }
}
