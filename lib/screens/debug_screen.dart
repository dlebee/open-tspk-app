import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_version.dart';
import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../models/medicine_schedule.dart';
import '../providers/appointment_provider.dart';
import '../providers/dose_provider.dart';
import '../providers/flare_up_provider.dart';
import '../providers/medicine_provider.dart';
import '../providers/storage_provider.dart';
import '../services/notification_service.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import '../utils/date_utils.dart';
import 'notification_explorer_screen.dart';
import 'storage_explorer_screen.dart';

/// Admin / debug tools. Reached from Settings once developer mode is on
/// (tap the version number 7 times).
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  String _permission = 'Checking…';
  int? _pending;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final p = await NotificationService.permissionSummary();
    int? pending;
    try {
      pending = (await NotificationService.getPendingNotifications()).length;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _permission = p;
        _pending = pending;
      });
    }
  }

  Future<void> _run(String done, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showDuskSnack(context, done);
    } catch (e) {
      if (mounted) showDuskSnack(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _testIn(Duration d) => _run(
        'Test notification in ${d.inSeconds < 60 ? '${d.inSeconds} s' : '${d.inMinutes} min'}. Background the app to see it.',
        () => NotificationService.showTestNotification(delay: d),
      );

  /// Adds a drop scheduled two minutes from now, to test real dose reminders end to end.
  Future<void> _addDropSoon() => _run('Added "Test drop" for 2 minutes from now', () async {
        final at = DateTime.now().add(const Duration(minutes: 2));
        await ref.read(medicinesProvider.notifier).add(Medicine(
              name: 'Test drop',
              createdAt: DateTime.now(),
              schedules: [
                MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: [hm(at)]),
              ],
            ));
      });

  Future<void> _seedDemo() => _run('Added 3 weeks of demo data', () async {
        final rnd = Random(7);
        final now = DateTime.now();
        final start = addCalendarDays(dayOf(now), -21);
        final steroid = Medicine(
          name: 'Steroid drop',
          createdAt: start,
          schedules: [
            MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['08:00', '20:00']),
          ],
        );
        final lube = Medicine(
          name: 'Lubricant',
          createdAt: start,
          schedules: [
            MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['13:00', '22:00']),
          ],
        );
        final meds = ref.read(medicinesProvider.notifier);
        await meds.add(steroid);
        await meds.add(lube);

        final doses = <MedicineDose>[];
        final flares = <FlareUp>[];
        for (var i = 0; i < 21; i++) {
          final day = addCalendarDays(start, i);
          for (final m in [steroid, lube]) {
            for (final t in m.schedules.first.times) {
              final at = atTime(day, t);
              if (rnd.nextDouble() < 0.08) continue; // left unlogged
              final skipped = rnd.nextDouble() < 0.05;
              doses.add(MedicineDose(
                medicineId: m.id,
                medicineName: m.name,
                eye: Eye.both,
                status: skipped ? DoseStatus.skipped : DoseStatus.taken,
                recordedAt: at,
                scheduledDate: day,
                scheduledTime: t,
                takenAt: skipped ? null : at.add(Duration(minutes: rnd.nextInt(25))),
              ));
            }
          }
          if (i % 3 == 0 || i == 9 || i == 10) {
            final flare = i == 9 || i == 10;
            final right = flare ? (i == 9 ? EyeFeel.sore : EyeFeel.flaring) : (rnd.nextBool() ? EyeFeel.gritty : EyeFeel.calm);
            flares.add(FlareUp(
              date: day.add(Duration(hours: 18, minutes: rnd.nextInt(50))),
              leftEye: false,
              rightEye: right != EyeFeel.calm,
              rightPainLevel: right.painLevel,
              reason: flare ? 'Light hurts, Watery' : null,
            ));
            if (flare) {
              doses.add(MedicineDose(
                medicineId: lube.id,
                medicineName: lube.name,
                eye: Eye.right,
                status: DoseStatus.taken,
                recordedAt: day.add(const Duration(hours: 15, minutes: 10)),
                takenAt: day.add(const Duration(hours: 15, minutes: 10)),
              ));
            }
          }
        }
        // Today's past slots stay open so the Today screen has something to log.
        doses.removeWhere((d) => d.scheduledDate != null && sameDay(d.scheduledDate!, now));
        final dn = ref.read(dosesProvider.notifier);
        for (final d in doses) {
          await dn.add(d);
        }
        final fn = ref.read(flareUpsProvider.notifier);
        for (final f in flares) {
          await fn.add(f);
        }
        await ref.read(appointmentsProvider.notifier).add(AppointmentNote(
              date: addCalendarDays(dayOf(now), 7).add(const Duration(hours: 10, minutes: 30)),
              doctorOffice: 'Eye clinic',
              notes: 'Can we lower the steroid to once a day?\nRight eye flares after screen-heavy days.',
            ));
        await ref.read(appointmentsProvider.notifier).add(AppointmentNote(
              date: start.add(const Duration(hours: 9)),
              doctorOffice: 'Eye clinic',
              notes: 'Started steroid drops.',
            ));
      });

  @override
  Widget build(BuildContext context) {
    final medicines = ref.watch(medicinesProvider).value ?? [];
    final doses = ref.watch(dosesProvider).value ?? [];
    final flareUps = ref.watch(flareUpsProvider).value ?? [];
    final appointments = ref.watch(appointmentsProvider).value ?? [];

    Widget tile(String title, String? sub, VoidCallback onTap, {IconData icon = Icons.chevron_right}) => ListTile(
          shape: const RoundedRectangleBorder(),
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          trailing: Icon(icon, color: Dusk.textMuted),
          onTap: _busy ? null : onTap,
        );

    Widget group(List<Widget> children) => Material(
          color: Dusk.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        );

    return DuskPage(
      title: 'Debug tools',
      subtitle: 'For testing. Not shown to regular users.',
      actions: [
        IconButton(onPressed: _refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
      ],
      children: [
        const SectionLabel('Status'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Dusk.surface, borderRadius: BorderRadius.circular(18)),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 13, height: 1.6, color: Dusk.textSecondary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version $appVersionLabel', style: const TextStyle(color: Dusk.text, fontSize: 15)),
                Text(_permission),
                Text('Pending notifications: ${_pending ?? '…'}'),
                Text('Time zone: ${DateTime.now().timeZoneName} (UTC${DateTime.now().timeZoneOffset.isNegative ? '' : '+'}${DateTime.now().timeZoneOffset.inHours})'),
                Text('Data: ${medicines.length} drops · ${doses.length} doses · ${flareUps.length} check-ins · ${appointments.length} visits'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionLabel('Notifications'),
        group([
          tile('Send test in 5 seconds', 'Then background the app', () => _testIn(const Duration(seconds: 5)),
              icon: Icons.notifications_outlined),
          tile('Send test in 1 minute', null, () => _testIn(const Duration(minutes: 1)),
              icon: Icons.notifications_outlined),
          tile('Add a drop due in 2 minutes', 'Tests a real reminder with Taken / Skip actions', _addDropSoon,
              icon: Icons.alarm_add_outlined),
          tile('Ask for permission again', null,
              () => _run('Asked', () async => NotificationService.requestPermission()),
              icon: Icons.lock_open_outlined),
          tile('Reschedule all reminders', null, () => _run('Rescheduled', () async {
                await NotificationService.rescheduleAllNotifications(
                  storage: ref.read(storageServiceProvider),
                  medicines: medicines,
                );
              }), icon: Icons.sync),
          tile('Notification explorer', 'Everything scheduled', () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationExplorerScreen()),
              )),
        ]),
        const SizedBox(height: 20),
        const SectionLabel('Data'),
        group([
          tile('Add demo data', '3 weeks of drops, check-ins and visits', _seedDemo, icon: Icons.auto_awesome_outlined),
          tile('Storage explorer', 'Raw stored data', () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StorageExplorerScreen()),
              )),
        ]),
      ],
    );
  }
}
