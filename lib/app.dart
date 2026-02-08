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
import 'screens/activity_log_screen.dart';
import 'screens/appointments_screen.dart';
import 'screens/calendar_screen.dart';
import 'widgets/log_scheduled_dose_dialog.dart';
import 'widgets/taken_time_picker.dart';
import 'screens/flare_ups_screen.dart';
import 'screens/home_screen.dart';
import 'screens/medicines_screen.dart';
import 'screens/settings_screen.dart';

import 'navigation_keys.dart';

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
    NotificationService.setOnOverrideTimeRequested((medicineId, eyeStr, scheduledDate, scheduledTime) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        showTakenTimePicker(ctx,
          medicineId: medicineId,
          eyeStr: eyeStr,
          scheduledDate: scheduledDate,
          scheduledTime: scheduledTime,
          onSaved: () => ref.read(dosesProvider.notifier).refresh(),
        );
      }
    });
    NotificationService.setOnNotificationTapped((medicineId, scheduleId, eyeStr, scheduledDate, scheduledTime) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        _handleNotificationTap(ctx, ref, medicineId, scheduleId, eyeStr, scheduledDate, scheduledTime);
      }
    });
    final highContrast = ref.watch(highContrastProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Thygeson',
      theme: _buildTheme(highContrast),
      home: const MainNavigator(),
    );
  }

  ThemeData _buildTheme(bool highContrast) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    );
    if (!highContrast) return base;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: Colors.blue.shade900,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
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
    // Navigate to home screen
    _MainNavigatorState.navigateToHome();
    
    // Pop any dialogs or modals that might be open
    Navigator.of(context).popUntil((route) => route.isFirst);
    
    // Get medicine and verify scheduleId matches
    final medicines = ref.read(medicinesProvider).valueOrNull ?? [];
    final medicine = medicines.firstWhere(
      (m) => m.id == medicineId,
      orElse: () => Medicine(name: 'Unknown', schedules: [], createdAt: DateTime.now()),
    );
    
    // Find schedule by ID and verify it matches
    MedicineSchedule? schedule;
    try {
      schedule = medicine.schedules.firstWhere((s) => s.id == scheduleId);
      // Verify eye matches
      if (schedule.eye.name != eyeStr) {
        print('[App] Warning: Schedule ${schedule.id} eye mismatch (expected ${schedule.eye.name}, got $eyeStr)');
      }
      // Verify time is in this schedule
      if (!schedule.times.contains(scheduledTime)) {
        print('[App] Warning: Schedule ${schedule.id} does not contain time $scheduledTime');
      }
    } catch (_) {
      print('[App] Warning: Schedule with ID $scheduleId not found for medicine ${medicine.id}');
    }
    
    final medicineName = medicine.name;
    
    // Parse eye
    final eye = Eye.values.firstWhere(
      (e) => e.name == eyeStr,
      orElse: () => Eye.both,
    );
    
    // Parse scheduled date
    final scheduledDt = DateTime.parse(scheduledDate);
    
    // Check if dose already exists (matching by medicineId, eye, date, and time)
    // Note: We've verified the scheduleId above
    final doses = ref.read(dosesProvider).valueOrNull ?? [];
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
      if (ctx != null) {
        showDialog(
          context: ctx,
          builder: (dialogCtx) => LogScheduledDoseDialog(dose: scheduledDose),
        );
      }
    });
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
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

  static const _screens = [
    HomeScreen(),
    CalendarScreen(),
    MedicinesScreen(),
    FlareUpsScreen(),
    AppointmentsScreen(),
    ActivityLogScreen(),
    SettingsScreen(),
  ];

  static const _items = [
    (icon: Icons.home, label: 'Home'),
    (icon: Icons.calendar_month, label: 'Calendar'),
    (icon: Icons.medication, label: 'Medicines'),
    (icon: Icons.warning_amber, label: 'Flare-ups'),
    (icon: Icons.event_note, label: 'Appointments'),
    (icon: Icons.history, label: 'Activity'),
    (icon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Text(
                'Thygeson',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            ...List.generate(_items.length, (i) {
              final item = _items[i];
              return ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                selected: _index == i,
                onTap: () {
                  setState(() => _index = i);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
      body: _screens[_index],
    );
  }
}
