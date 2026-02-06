import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/dose_provider.dart';
import 'providers/theme_provider.dart';
import 'services/notification_service.dart';
import 'screens/activity_log_screen.dart';
import 'screens/appointments_screen.dart';
import 'screens/calendar_screen.dart';
import 'widgets/taken_time_picker.dart';
import 'screens/flare_ups_screen.dart';
import 'screens/home_screen.dart';
import 'screens/medicines_screen.dart';
import 'screens/settings_screen.dart';

import 'navigation_keys.dart';

class ThygesonApp extends ConsumerWidget {
  const ThygesonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _index = 0;

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
