import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../providers/appointment_provider.dart';
import '../providers/flare_up_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
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
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                  icon: const Icon(Icons.chevron_left, color: Dusk.textSecondary),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: isCurrentMonth
                      ? null
                      : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
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
  });

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
    final label = feel == null
        ? '${DateFormat('EEEE d MMMM').format(date)}, no check-in'
        : '${DateFormat('EEEE d MMMM').format(date)}, left ${feel!.$1.label}, right ${feel!.$2.label}';
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
            ],
          ),
        ),
      ),
    );
  }
}
