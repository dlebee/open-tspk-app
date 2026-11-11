import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/medicine.dart';
import 'models/medicine_dose.dart';
import 'models/medicine_schedule.dart';
import 'models/scheduled_dose.dart';
import 'providers/dose_provider.dart';
import 'providers/medicine_provider.dart';
import 'providers/storage_provider.dart';
import 'providers/theme_provider.dart';
import 'services/notification_service.dart';
import 'widgets/log_scheduled_dose_dialog.dart';
import 'widgets/taken_time_picker.dart';
import 'screens/home_screen.dart';

import 'navigation_keys.dart';
import 'theme/dusk_theme.dart';
import 'providers/calendar_provider.dart';
import 'screens/check_in_screen.dart';
import 'screens/journey_screen.dart';
import 'screens/visit_screen.dart';
import 'ui/dusk_ui.dart';
import 'widgets/log_drop_sheet.dart';

class ThygesonApp extends ConsumerStatefulWidget {
  const ThygesonApp({super.key});

  @override
  ConsumerState<ThygesonApp> createState() => _ThygesonAppState();
}

class _ThygesonAppState extends ConsumerState<ThygesonApp> {
  @override
  void initState() {
    super.initState();
    // Set up notification service after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final storage = ref.read(storageServiceProvider);
      NotificationService.setStorage(storage);
    });
  }

  @override
  Widget build(BuildContext context) {
    NotificationService.setOnDoseAdded(() {
      ref.read(dosesProvider.notifier).refresh();
    });
    NotificationService.setOnOverrideTimeRequested((
      medicineId,
      eyeStr,
      scheduledDate,
      scheduledTime,
    ) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        showTakenTimePicker(
          ctx,
          medicineId: medicineId,
          eyeStr: eyeStr,
          scheduledDate: scheduledDate,
          scheduledTime: scheduledTime,
          onSaved: () => ref.read(dosesProvider.notifier).refresh(),
        );
      }
    });
    NotificationService.setOnNotificationTapped((
      medicineId,
      scheduleId,
      eyeStr,
      scheduledDate,
      scheduledTime,
    ) {
      // Wait for the app to be fully ready (providers loaded, UI rendered)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Navigate to home screen first
        _MainNavigatorState.navigateToHome();

        // Wait a bit longer for navigation and providers to be ready
        Future.delayed(const Duration(milliseconds: 500), () {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            // Ensure providers are loaded before showing dialog
            final medicines = ref.read(medicinesProvider).value;
            final doses = ref.read(dosesProvider).value;

            if (medicines != null && doses != null) {
              _handleNotificationTap(
                ctx,
                ref,
                medicineId,
                scheduleId,
                eyeStr,
                scheduledDate,
                scheduledTime,
              );
            } else {
              // Providers not ready yet, wait a bit more
              Future.delayed(const Duration(milliseconds: 500), () {
                final ctx2 = navigatorKey.currentContext;
                if (ctx2 != null && ctx2.mounted) {
                  _handleNotificationTap(
                    ctx2,
                    ref,
                    medicineId,
                    scheduleId,
                    eyeStr,
                    scheduledDate,
                    scheduledTime,
                  );
                }
              });
            }
          }
        });
      });
    });
    final highContrast = ref.watch(highContrastProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Thygeson',
      theme: buildDuskTheme(highContrast: highContrast),
      themeMode: ThemeMode.dark,
      home: const MainNavigator(),
      debugShowCheckedModeBanner: false,
    );
  }

  void _handleNotificationTap(
    BuildContext context,
    WidgetRef ref,
    String medicineId,
    String scheduleId,
    String eyeStr,
    String scheduledDate,
    String scheduledTime,
  ) {
    // Pop any dialogs or modals that might be open
    Navigator.of(context).popUntil((route) => route.isFirst);

    // Get medicine and schedule to create ScheduledDose
    final medicines = ref.read(medicinesProvider).value ?? [];
    final medicine = medicines.firstWhere(
      (m) => m.id == medicineId,
      orElse: () =>
          Medicine(name: 'Unknown', schedules: [], createdAt: DateTime.now()),
    );

    // Find schedule by ID
    MedicineSchedule? schedule;
    try {
      schedule = medicine.schedules.firstWhere((s) => s.id == scheduleId);
    } catch (_) {
      debugPrint(
        '[App] Warning: Schedule with ID $scheduleId not found for medicine ${medicine.id}',
      );
    }

    final medicineName = medicine.name;
    final eye = Eye.values.firstWhere(
      (e) => e.name == eyeStr,
      orElse: () => Eye.both,
    );

    // Parse scheduled date
    final scheduledDt = DateTime.parse(scheduledDate);

    // Check if dose already exists
    final doses = ref.read(dosesProvider).value ?? [];
    MedicineDose? existingDose;
    try {
      existingDose = doses.firstWhere(
        (d) =>
            d.medicineId == medicineId &&
            d.eye == eye &&
            d.scheduledDate != null &&
            d.scheduledDate!.year == scheduledDt.year &&
            d.scheduledDate!.month == scheduledDt.month &&
            d.scheduledDate!.day == scheduledDt.day &&
            d.scheduledTime == scheduledTime,
      );
    } catch (_) {
      // No existing dose found
    }

    // Determine status
    final parts = scheduledTime.split(':');
    final scheduledDateTime = DateTime(
      scheduledDt.year,
      scheduledDt.month,
      scheduledDt.day,
      int.parse(parts[0]),
      parts.length > 1 ? int.parse(parts[1]) : 0,
    );

    ScheduledDoseStatus status;
    DateTime? takenAt;
    if (existingDose != null) {
      if (existingDose.status == DoseStatus.taken) {
        status = ScheduledDoseStatus.taken;
        takenAt = existingDose.takenAt ?? existingDose.recordedAt;
      } else {
        status = ScheduledDoseStatus.skipped;
      }
    } else {
      // No existing dose - check if scheduled time has passed
      status = scheduledDateTime.isBefore(DateTime.now())
          ? ScheduledDoseStatus.missed
          : ScheduledDoseStatus.scheduled;
    }

    // Create scheduled dose - use schedule properties if available, otherwise generate from what we have
    final scheduledDose = schedule != null
        ? ScheduledDose(
            medicineId: medicineId,
            medicineName: medicineName,
            eye: eye,
            daysOfWeek: schedule.daysOfWeek,
            times: schedule.times,
            scheduledDate: scheduledDt,
            scheduledTime: scheduledTime,
            status: status,
            takenAt: takenAt,
            dose: existingDose,
          )
        : ScheduledDose(
            medicineId: medicineId,
            medicineName: medicineName,
            eye: eye,
            daysOfWeek: [], // Unknown if schedule not found
            times: [scheduledTime], // Only know the specific time
            scheduledDate: scheduledDt,
            scheduledTime: scheduledTime,
            status: status,
            takenAt: takenAt,
            dose: existingDose,
          );

    // Show dialog after a short delay to ensure navigation is complete
    Future.delayed(const Duration(milliseconds: 100), () {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showDialog(
          context: ctx,
          builder: (dialogCtx) => LogScheduledDoseDialog(dose: scheduledDose),
        );
      }
    });
  }
}

class MainNavigator extends ConsumerStatefulWidget {
  const MainNavigator({super.key});

  @override
  ConsumerState<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends ConsumerState<MainNavigator> {
  int _index = 0;

  static _MainNavigatorState? _instance;

  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }

  static void navigateToHome() {
    _instance?.setState(() {
      _instance!._index = 0;
    });
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _openPlus() {
    final now = DateTime.now();
    final today = dayOf(now);
    final todays = [...ref.read(scheduledDosesForDateProvider(today))]
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    // The drop to offer first: the earliest unlogged one that's due or overdue, else the next one.
    final open = todays.where(
      (d) =>
          d.status == ScheduledDoseStatus.missed ||
          d.status == ScheduledDoseStatus.scheduled,
    );
    final due = open.where(
      (d) => atTime(
        today,
        d.scheduledTime,
      ).isBefore(now.add(const Duration(minutes: 60))),
    );
    final suggested = due.firstOrNull ?? open.firstOrNull;

    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (suggested != null) ...[
                _PlusOption(
                  icon: Icons.water_drop,
                  highlighted: true,
                  title: 'Log the ${suggested.scheduledTime} drop',
                  subtitle:
                      '${suggested.medicineName} · ${eyeLabel(suggested.eye).toLowerCase()}',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showLogDropSheet(context, suggested);
                  },
                ),
                const SizedBox(height: 10),
              ],
              _PlusOption(
                icon: Icons.add,
                title: 'Extra drop',
                subtitle: 'Something outside your schedule',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showExtraDropSheet(context);
                },
              ),
              const SizedBox(height: 10),
              _PlusOption(
                icon: Icons.visibility_outlined,
                title: 'Check in on my eyes',
                subtitle: 'How they feel right now',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _push(const CheckInScreen());
                },
              ),
              const SizedBox(height: 10),
              _PlusOption(
                icon: Icons.event_note_outlined,
                title: 'Doctor visit',
                subtitle: 'Appointments and a summary to share',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _push(const VisitScreen());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: const [HomeScreen(), JourneyScreen()],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 16),
              child: _Dock(
                index: _index,
                onSelect: (i) => setState(() => _index = i),
                onPlus: _openPlus,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.index,
    required this.onSelect,
    required this.onPlus,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    Widget tab(int i, IconData icon, String label) {
      final on = index == i;
      return Expanded(
        child: Center(
          child: Semantics(
            selected: on,
            button: true,
            child: Material(
              color: on ? Dusk.amberSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => onSelect(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: on ? Dusk.amber : Dusk.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: on ? Dusk.amber : Dusk.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Dusk.surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Dusk.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          tab(0, Icons.wb_twilight, 'Today'),
          Semantics(
            button: true,
            label: 'Log a drop or check in',
            child: Material(
              color: Dusk.amber,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPlus,
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(Icons.add, color: Dusk.onAmber, size: 26),
                ),
              ),
            ),
          ),
          tab(1, Icons.insights, 'Journey'),
        ],
      ),
    );
  }
}

class _PlusOption extends StatelessWidget {
  const _PlusOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return DuskTile(
      radius: 20,
      color: highlighted ? const Color(0xFF2E2A22) : Dusk.surfaceHigh,
      border: highlighted ? Dusk.amberBorder : null,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: highlighted ? Dusk.amber : Dusk.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: highlighted ? Dusk.onAmber : Dusk.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Dusk.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Dusk.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
