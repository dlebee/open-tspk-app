import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import '../providers/appointment_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/flare_up_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import '../widgets/log_drop_sheet.dart';
import '../widgets/unscheduled_dose_dialog.dart';
import 'day_screen.dart';
import 'visit_screen.dart';

/// Worst feel per eye for every day that has check-ins.
Map<DateTime, (EyeFeel, EyeFeel)> feelsByDay(List<FlareUp> flareUps) {
  final map = <DateTime, (EyeFeel, EyeFeel)>{};
  for (final f in flareUps) {
    final d = dayOf(f.date);
    final prev = map[d];
    map[d] = prev == null
        ? (f.leftFeel, f.rightFeel)
        : (worse(prev.$1, f.leftFeel), worse(prev.$2, f.rightFeel));
  }
  return map;
}

class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _showAllMissed = false;
  bool _showAllExtras = false;
  bool _showAllSkipped = false;

  void _open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final flareUps = ref.watch(flareUpsProvider).value ?? [];
    final appointments = ref.watch(appointmentsProvider).value ?? [];
    final feels = feelsByDay(flareUps);
    final now = DateTime.now();
    final today = dayOf(now);
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - 1;

    final monthEnd = DateTime(_month.year, _month.month, daysInMonth);
    final range = (start: first, end: monthEnd.isAfter(today) ? today : monthEnd);
    final hasPast = !first.isAfter(today);
    final scheduledByDay = hasPast
        ? ref.watch(scheduledDosesForRangeProvider(range))
        : const <DateTime, List<ScheduledDose>>{};
    final extrasByDay = hasPast
        ? ref.watch(unscheduledDosesForRangeProvider(range))
        : const <DateTime, List<MedicineDose>>{};
    final missed = [
      for (final e in scheduledByDay.entries)
        ...e.value.where((d) => d.status == ScheduledDoseStatus.missed),
    ]..sort((a, b) => atTime(b.scheduledDate, b.scheduledTime).compareTo(atTime(a.scheduledDate, a.scheduledTime)));
    final skipped = [
      for (final e in scheduledByDay.entries)
        ...e.value.where((d) => d.status == ScheduledDoseStatus.skipped),
    ]..sort((a, b) => atTime(b.scheduledDate, b.scheduledTime).compareTo(atTime(a.scheduledDate, a.scheduledTime)));
    final extras = [for (final l in extrasByDay.values) ...l]
      ..sort((a, b) => (b.takenAt ?? b.recordedAt).compareTo(a.takenAt ?? a.recordedAt));
    int missedOn(DateTime d) =>
        (scheduledByDay[d] ?? const []).where((x) => x.status == ScheduledDoseStatus.missed).length;
    int skippedOn(DateTime d) =>
        (scheduledByDay[d] ?? const []).where((x) => x.status == ScheduledDoseStatus.skipped).length;

    final monthFlares = flareUps
        .where((f) => f.date.year == _month.year && f.date.month == _month.month && f.isFlare)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final nextVisit = appointments
        .where((a) => a.date.isAfter(now))
        .fold<AppointmentNote?>(null, (p, c) => p == null || c.date.isBefore(p.date) ? c : p);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
          children: [
            Text('Journey', style: headingFont.copyWith(fontSize: 32, color: Dusk.text)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(DateFormat('MMMM y').format(_month),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Dusk.text)),
                ),
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => setState(() {
                    _month = DateTime(_month.year, _month.month - 1);
                    _showAllMissed = _showAllExtras = _showAllSkipped = false;
                  }),
                  icon: const Icon(Icons.chevron_left, color: Dusk.textSecondary),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: isCurrentMonth
                      ? null
                      : () => setState(() {
                          _month = DateTime(_month.year, _month.month + 1);
                          _showAllMissed = _showAllExtras = _showAllSkipped = false;
                        }),
                  icon: const Icon(Icons.chevron_right),
                  color: Dusk.textSecondary,
                  disabledColor: Dusk.border,
                ),
              ],
            ),
            const Text('Each day: left eye | right eye',
                style: TextStyle(fontSize: 13, color: Dusk.textSecondary)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.95,
              children: [
                for (final w in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Center(
                    child: Text(w,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Dusk.textMuted)),
                  ),
                for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                for (var d = 1; d <= daysInMonth; d++)
                  _DayCell(
                    date: DateTime(_month.year, _month.month, d),
                    feel: feels[DateTime(_month.year, _month.month, d)],
                    isToday: DateTime(_month.year, _month.month, d) == today,
                    isFuture: DateTime(_month.year, _month.month, d).isAfter(today),
                    missed: missedOn(DateTime(_month.year, _month.month, d)),
                    skipped: skippedOn(DateTime(_month.year, _month.month, d)),
                    extras: extrasByDay[DateTime(_month.year, _month.month, d)]?.length ?? 0,
                    onTap: () => _open(DayScreen(date: DateTime(_month.year, _month.month, d))),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final f in EyeFeel.values)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: f.tone, borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(width: 6),
                      Text(f.label, style: const TextStyle(fontSize: 12, color: Dusk.textSecondary)),
                    ],
                  ),
                const Text('Blank: no check-in', style: TextStyle(fontSize: 12, color: Dusk.textMuted)),
                const _LegendDot(color: Dusk.rose, label: 'Drop not logged'),
                const _LegendDot(color: Dusk.textSecondary, label: 'Skipped'),
                const _LegendDot(color: Dusk.sage, label: 'Extra drop'),
              ],
            ),
            const SizedBox(height: 24),
            SectionLabel(isCurrentMonth ? 'This month' : DateFormat('MMMM').format(_month)),
            if (nextVisit != null && isCurrentMonth) ...[
              DuskTile(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onTap: () => _open(const VisitScreen()),
                child: Row(
                  children: [
                    const Icon(Icons.event_note_outlined, color: Dusk.amber, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${nextVisit.doctorOffice} · ${DateFormat('EEE d MMM, HH:mm').format(nextVisit.date)}',
                              style: const TextStyle(fontSize: 15, color: Dusk.text)),
                          const Text('Prepare a summary for your doctor',
                              style: TextStyle(fontSize: 13, color: Dusk.amber, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (monthFlares.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No flare-ups logged.', style: TextStyle(color: Dusk.textSecondary)),
              ),
            for (final f in monthFlares.take(8)) ...[
              DuskTile(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onTap: () => _open(DayScreen(date: dayOf(f.date))),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: worse(f.leftFeel, f.rightFeel).fg, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_flareTitle(f), style: const TextStyle(fontSize: 15, color: Dusk.text)),
                          Text(
                            '${DateFormat('EEE d MMM · HH:mm').format(f.date)}${f.reason != null ? ' · ${f.reason}' : ''}',
                            style: const TextStyle(fontSize: 13, color: Dusk.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Dusk.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (missed.isNotEmpty) ...[
              const SizedBox(height: 18),
              SectionLabel('Drops not logged · ${missed.length}'),
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  'Took one after all? Tap it to log when you took it, or mark it skipped.',
                  style: TextStyle(fontSize: 13, color: Dusk.textSecondary),
                ),
              ),
              for (final d in missed.take(_showAllMissed ? missed.length : 5)) ...[
                _DoseRow(
                  dotColor: Dusk.rose,
                  title: '${d.medicineName} · ${eyeLabel(d.eye).toLowerCase()}',
                  subtitle: '${DateFormat('EEE d MMM').format(d.scheduledDate)} · ${d.scheduledTime} · not logged',
                  onTap: () => showLogDropSheet(context, d),
                ),
                const SizedBox(height: 6),
              ],
              if (missed.length > 5 && !_showAllMissed)
                TextButton(
                  onPressed: () => setState(() => _showAllMissed = true),
                  child: Text('Show all ${missed.length}'),
                ),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 18),
              SectionLabel('Skipped · ${skipped.length}'),
              for (final d in skipped.take(_showAllSkipped ? skipped.length : 5)) ...[
                _DoseRow(
                  dotColor: Dusk.textSecondary,
                  title: '${d.medicineName} · ${eyeLabel(d.eye).toLowerCase()}',
                  subtitle: '${DateFormat('EEE d MMM').format(d.scheduledDate)} · ${d.scheduledTime} · skipped',
                  onTap: () => showLogDropSheet(context, d),
                ),
                const SizedBox(height: 6),
              ],
              if (skipped.length > 5 && !_showAllSkipped)
                TextButton(
                  onPressed: () => setState(() => _showAllSkipped = true),
                  child: Text('Show all ${skipped.length}'),
                ),
            ],
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 18),
              SectionLabel('Extra drops · ${extras.length}'),
              for (final x in extras.take(_showAllExtras ? extras.length : 5)) ...[
                _DoseRow(
                  dotColor: Dusk.sage,
                  title: 'Extra ${x.medicineName ?? 'drop'} · ${eyeLabel(x.eye).toLowerCase()}',
                  subtitle: '${DateFormat('EEE d MMM · HH:mm').format(x.takenAt ?? x.recordedAt)} · tap to edit or remove',
                  onTap: () => showDialog(context: context, builder: (_) => UnscheduledDoseDialog(dose: x)),
                ),
                const SizedBox(height: 6),
              ],
              if (extras.length > 5 && !_showAllExtras)
                TextButton(
                  onPressed: () => setState(() => _showAllExtras = true),
                  child: Text('Show all ${extras.length}'),
                ),
            ],
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => _open(const VisitScreen()),
                child: const Text('Doctor visits'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _flareTitle(FlareUp f) {
    final l = f.leftFeel, r = f.rightFeel;
    if (l.isFlare && r.isFlare) return 'Both eyes ${worse(l, r).label.toLowerCase()}';
    if (l.isFlare) return 'Left eye ${l.label.toLowerCase()}';
    return 'Right eye ${r.label.toLowerCase()}';
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.feel,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
    this.missed = 0,
    this.skipped = 0,
    this.extras = 0,
  });

  final int missed;
  final int skipped;
  final int extras;

  final DateTime date;
  final (EyeFeel, EyeFeel)? feel;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = isFuture ? const Color(0xFF232220) : Dusk.surface;
    final l = feel?.$1.tone ?? empty;
    final r = feel?.$2.tone ?? empty;
    final label = [
      DateFormat('EEEE d MMMM').format(date),
      feel == null ? 'no check-in' : 'left ${feel!.$1.label}, right ${feel!.$2.label}',
      if (missed > 0) missed == 1 ? '1 drop not logged' : '$missed drops not logged',
      if (skipped > 0) skipped == 1 ? '1 drop skipped' : '$skipped drops skipped',
      if (extras > 0) extras == 1 ? '1 extra drop' : '$extras extra drops',
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: isToday ? Border.all(color: Dusk.amber, width: 2) : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(child: Container(color: l)),
                  Container(width: 2, color: Dusk.bg),
                  Expanded(child: Container(color: r)),
                ],
              ),
              Positioned(
                left: 5,
                top: 3,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isFuture ? Dusk.textMuted : Dusk.textSecondary,
                  ),
                ),
              ),
              if (missed > 0 || skipped > 0 || extras > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    children: [
                      if (missed > 0) const _Marker(color: Dusk.rose),
                      if (skipped > 0) const _Marker(color: Dusk.textSecondary),
                      if (extras > 0) const _Marker(color: Dusk.sage),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small dot on a day: rose for a drop not logged, sage for an extra drop.
/// Outlined in the background colour so it reads on any feel fill.
class _Marker extends StatelessWidget {
  const _Marker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Dusk.bg, width: 1.5),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Marker(color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Dusk.textSecondary)),
      ],
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dotColor, required this.title, required this.subtitle, required this.onTap});

  final Color dotColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DuskTile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, color: Dusk.text)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: Dusk.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Dusk.textMuted),
        ],
      ),
    );
  }
}
