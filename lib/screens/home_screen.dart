import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/flare_up.dart';
import '../models/medicine_dose.dart';
import '../models/scheduled_dose.dart';
import '../providers/calendar_provider.dart';
import '../providers/flare_up_provider.dart';
import '../providers/medicine_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import '../utils/date_utils.dart';
import '../widgets/log_drop_sheet.dart';
import '../widgets/unscheduled_dose_dialog.dart';
import 'check_in_screen.dart';
import 'drop_edit_screen.dart';
import 'drops_screen.dart';
import 'settings_screen.dart';

/// Today: one timeline for the whole day.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final medicinesAsync = ref.watch(medicinesProvider);
    final medicines = medicinesAsync.value ?? [];
    if (medicinesAsync.hasValue && medicines.isEmpty) {
      return _Welcome(
        onAdd: () => _push(const DropEditScreen()),
        onBackup: () => _push(const SettingsScreen()),
      );
    }

    final now = DateTime.now();
    final today = dayOf(now);
    final tomorrow = addCalendarDays(today, 1);
    final scheduled = [...ref.watch(scheduledDosesForDateProvider(today))]
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    final extras = ref.watch(unscheduledDosesForDateProvider(today));
    final tomorrowFirst = ([...ref.watch(scheduledDosesForDateProvider(tomorrow))]
          ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime)))
        .firstOrNull;
    final checkIns = (ref.watch(flareUpsProvider).value ?? [])
        .where((f) => sameDay(f.date, now))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final lastCheckIn = checkIns.lastOrNull;

    final next = scheduled.where((d) => d.status == ScheduledDoseStatus.scheduled).firstOrNull;
    final missed = scheduled.where((d) => d.status == ScheduledDoseStatus.missed).toList();

    // Timeline entries, in time order, with a "now" marker.
    final entries = <_Entry>[
      for (final d in scheduled) _Entry(atTime(today, d.scheduledTime), scheduled: d),
      for (final d in extras) _Entry(d.takenAt ?? d.recordedAt, extra: d),
      for (final c in checkIns) _Entry(c.date, checkIn: c),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final nowIndex = entries.indexWhere((e) => e.at.isAfter(now));
    final insertAt = nowIndex == -1 ? entries.length : nowIndex;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEEE d MMM').format(now),
                    style: const TextStyle(fontSize: 14, color: Dusk.textSecondary),
                  ),
                ),
                RoundIconButton(
                  icon: Icons.water_drop_outlined,
                  tooltip: 'Your drops',
                  onPressed: () => _push(const DropsScreen()),
                ),
                const SizedBox(width: 8),
                RoundIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onPressed: () => _push(const SettingsScreen()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _headline(next, scheduled, now),
              style: headingFont.copyWith(fontSize: 36, height: 1.1, color: Dusk.text),
            ),
            if (next != null) ...[
              const SizedBox(height: 8),
              Text(
                '${next.medicineName} · ${eyeLabel(next.eye).toLowerCase()} · ${next.scheduledTime}',
                style: const TextStyle(fontSize: 15, color: Dusk.textSecondary),
              ),
            ],
            const SizedBox(height: 18),
            _CheckInCard(
              last: lastCheckIn,
              onTap: () => _push(const CheckInScreen()),
            ),
            if (missed.isNotEmpty) ...[
              const SizedBox(height: 10),
              DuskTile(
                color: Dusk.roseSoft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                onTap: () => showLogDropSheet(context, missed.first),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Dusk.rose, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        missed.length == 1 ? '1 drop not logged yet' : '${missed.length} drops not logged yet',
                        style: const TextStyle(color: Dusk.rose, fontSize: 15),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Dusk.rose),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing scheduled today. Tap + to log an extra drop.',
                  style: TextStyle(color: Dusk.textSecondary),
                ),
              ),
            for (var i = 0; i <= entries.length; i++) ...[
              if (i == insertAt) _NowRow(now: now),
              if (i < entries.length)
                _entryRow(entries[i], highlighted: entries[i].scheduled != null && entries[i].scheduled == next),
            ],
            if (tomorrowFirst != null)
              _TimelineRow(
                time: 'Tmrw',
                dot: const SizedBox.shrink(),
                last: true,
                child: Text(
                  'Tomorrow starts ${tomorrowFirst.scheduledTime}',
                  style: const TextStyle(color: Dusk.textMuted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _headline(ScheduledDose? next, List<ScheduledDose> scheduled, DateTime now) {
    if (next == null) {
      if (scheduled.isEmpty) return 'A quiet\nday';
      return 'All done\nfor today';
    }
    final diff = atTime(next.scheduledDate, next.scheduledTime).difference(now);
    if (diff.inMinutes <= 5) return 'Next drop\nis due';
    if (diff.inMinutes < 60) return 'Next drop\nin ${diff.inMinutes} min';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h >= 3) return 'Next drop\nat ${next.scheduledTime}';
    return m == 0 ? 'Next drop\nin $h h' : 'Next drop\nin $h h $m min';
  }

  Widget _entryRow(_Entry e, {required bool highlighted}) {
    final d = e.scheduled;
    if (d != null) {
      if (highlighted) {
        return _TimelineRow(
          time: d.scheduledTime,
          timeColor: Dusk.text,
          dot: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Dusk.bg,
              border: Border.all(color: Dusk.amber, width: 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DuskTile(
              color: const Color(0xFF2E2A22),
              border: Dusk.amberBorder,
              radius: 20,
              onTap: () => showLogDropSheet(context, d),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.medicineName,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Dusk.text)),
                        const SizedBox(height: 2),
                        Text(eyeLabel(d.eye), style: const TextStyle(fontSize: 13, color: Dusk.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: Dusk.amber, shape: BoxShape.circle),
                    child: const Icon(Icons.water_drop, color: Dusk.onAmber),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final (dot, text, color) = switch (d.status) {
        ScheduledDoseStatus.taken => (
            _doneDot(),
            '${d.medicineName} · taken ${d.takenAt != null ? hm(d.takenAt!) : ''}',
            Dusk.textSecondary,
          ),
        ScheduledDoseStatus.skipped => (_ringDot(Dusk.textMuted), '${d.medicineName} · skipped', Dusk.textMuted),
        ScheduledDoseStatus.missed => (_ringDot(Dusk.rose), '${d.medicineName} · not logged', Dusk.rose),
        ScheduledDoseStatus.scheduled => (
            _ringDot(Dusk.border),
            '${d.medicineName} · ${eyeLabel(d.eye).toLowerCase()}',
            Dusk.textSecondary,
          ),
      };
      return _TimelineRow(
        time: d.scheduledTime,
        dot: dot,
        onTap: () => showLogDropSheet(context, d),
        child: Text(text, style: TextStyle(fontSize: 15, color: color)),
      );
    }
    if (e.extra != null) {
      final x = e.extra!;
      return _TimelineRow(
        time: hm(e.at),
        dot: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(color: Dusk.sageSoft, shape: BoxShape.circle),
          child: const Icon(Icons.add, size: 12, color: Dusk.sage),
        ),
        onTap: () => showDialog(context: context, builder: (_) => UnscheduledDoseDialog(dose: x)),
        child: Text('Extra ${x.medicineName ?? 'drop'} · ${eyeLabel(x.eye).toLowerCase()}',
            style: const TextStyle(fontSize: 15, color: Dusk.textSecondary)),
      );
    }
    final c = e.checkIn!;
    return _TimelineRow(
      time: hm(e.at),
      dot: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: worse(c.leftFeel, c.rightFeel).fg, shape: BoxShape.circle),
      ),
      onTap: () => _push(CheckInScreen(existing: c)),
      child: Text('Check-in · L ${c.leftFeel.label.toLowerCase()}, R ${c.rightFeel.label.toLowerCase()}',
          style: const TextStyle(fontSize: 15, color: Dusk.textSecondary)),
    );
  }

  Widget _doneDot() => Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(color: Dusk.amberSoft, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 12, color: Dusk.amber),
      );

  Widget _ringDot(Color c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 2)),
      );
}

class _Entry {
  _Entry(this.at, {this.scheduled, this.extra, this.checkIn});

  final DateTime at;
  final ScheduledDose? scheduled;
  final MedicineDose? extra;
  final FlareUp? checkIn;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.time,
    required this.dot,
    required this.child,
    this.onTap,
    this.timeColor = Dusk.textMuted,
    this.last = false,
  });

  final String time;
  final Widget dot;
  final Widget child;
  final VoidCallback? onTap;
  final Color timeColor;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 48,
              child: Center(
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 13,
                    color: timeColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 0,
                    bottom: last ? null : 0,
                    height: last ? 24 : null,
                    child: Container(width: 2, color: Dusk.surfaceHigh),
                  ),
                  dot,
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(alignment: Alignment.centerLeft, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowRow extends StatelessWidget {
  const _NowRow({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return _TimelineRow(
      time: hm(now),
      timeColor: Dusk.amber,
      dot: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: Dusk.amber, shape: BoxShape.circle),
      ),
      child: const Row(
        children: [
          Expanded(child: Divider(color: Dusk.amberBorder, thickness: 1)),
          SizedBox(width: 8),
          Text('NOW',
              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600, color: Dusk.amber)),
        ],
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({required this.last, required this.onTap});

  final FlareUp? last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = last;
    return DuskTile(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (c == null) ...[
            const Icon(Icons.visibility_outlined, color: Dusk.amber, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('How do your eyes feel?', style: TextStyle(fontSize: 15, color: Dusk.text)),
            ),
            const Text('Check in', style: TextStyle(color: Dusk.amber, fontWeight: FontWeight.w600)),
          ] else ...[
            Pill('L · ${c.leftFeel.label.toLowerCase()}', fg: c.leftFeel.fg, bg: c.leftFeel.bg),
            const SizedBox(width: 6),
            Pill('R · ${c.rightFeel.label.toLowerCase()}', fg: c.rightFeel.fg, bg: c.rightFeel.bg),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Checked in ${hm(c.date)}',
                  style: const TextStyle(fontSize: 13, color: Dusk.textSecondary)),
            ),
            const Icon(Icons.chevron_right, color: Dusk.textMuted),
          ],
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAdd, required this.onBackup});

  final VoidCallback onAdd;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String title, String sub, bool active) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? Dusk.amber : Dusk.surfaceHigh,
                  shape: BoxShape.circle,
                ),
                child: Text('$n',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active ? Dusk.onAmber : Dusk.textSecondary)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Dusk.text)),
                    Text(sub, style: const TextStyle(fontSize: 13, color: Dusk.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: (box.maxHeight - 160).clamp(0, double.infinity)),
              child: IntrinsicHeight(
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Dusk.amberSoft, borderRadius: BorderRadius.circular(22)),
                child: const Icon(Icons.visibility_outlined, color: Dusk.amber, size: 32),
              ),
              const SizedBox(height: 28),
              Text('Gentle on\ntired eyes.', style: headingFont.copyWith(fontSize: 36, height: 1.1, color: Dusk.text)),
              const SizedBox(height: 14),
              const Text(
                'Keep track of your drops and how each eye feels, so you and your doctor can see what helps.',
                style: TextStyle(fontSize: 16, height: 1.5, color: Dusk.textSecondary),
              ),
              const SizedBox(height: 32),
              step(1, 'Add your drops', 'Name, which eye, what times', true),
              step(2, 'Allow reminders', 'Log straight from the notification', false),
              step(3, 'Check in when your eyes feel off', 'Flare-ups build themselves', false),
              const Spacer(),
              PrimaryButton(label: 'Add my first drop', onPressed: onAdd),
              const SizedBox(height: 8),
              Center(child: TextButton(onPressed: onBackup, child: const Text('I have a backup'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
