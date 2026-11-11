import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thygeson/app.dart';
import 'package:thygeson/models/appointment_note.dart';
import 'package:thygeson/models/flare_up.dart';
import 'package:thygeson/models/medicine.dart';
import 'package:thygeson/models/medicine_dose.dart';
import 'package:thygeson/models/medicine_schedule.dart';
import 'package:thygeson/models/notification_reminder_preference.dart';
import 'package:thygeson/providers/storage_provider.dart';
import 'package:thygeson/screens/journey_screen.dart';
import 'package:thygeson/services/storage_service.dart';
import 'package:thygeson/ui/dusk_ui.dart';

/// In-memory storage so widget tests don't touch the file system.
class MemoryStorage implements IStorageService {
  List<Medicine> medicines = [];
  List<MedicineDose> doses = [];
  List<FlareUp> flareUps = [];
  List<AppointmentNote> appointments = [];
  bool dev = false;
  bool sync = false;
  NotificationReminderPreference pref = const NotificationReminderPreference.defaultValue();
  int nextId = 1;

  @override
  Future<void> init() async {}
  @override
  List<Medicine> getMedicines() => medicines;
  @override
  Future<void> saveMedicines(List<Medicine> m) async => medicines = m;
  @override
  List<MedicineDose> getDoses() => doses;
  @override
  Future<void> saveDoses(List<MedicineDose> d) async => doses = d;
  @override
  List<FlareUp> getFlareUps() => flareUps;
  @override
  Future<void> saveFlareUps(List<FlareUp> f) async => flareUps = f;
  @override
  List<AppointmentNote> getAppointments() => appointments;
  @override
  Future<void> saveAppointments(List<AppointmentNote> a) async => appointments = a;
  @override
  bool getDeveloperMode() => dev;
  @override
  Future<void> setDeveloperMode(bool enabled) async => dev = enabled;
  @override
  bool getCloudSyncEnabled() => sync;
  @override
  Future<void> setCloudSyncEnabled(bool enabled) async => sync = enabled;
  @override
  NotificationReminderPreference getNotificationReminderPreference() => pref;
  @override
  Future<void> setNotificationReminderPreference(NotificationReminderPreference p) async => pref = p;
  @override
  int getNextNotificationId() => nextId;
  @override
  Future<void> setNextNotificationId(int id) async => nextId = id;
  @override
  Map<String, String> getAllPreferences() => {};
  @override
  Future<void> wipeAllData() async {
    medicines = [];
    doses = [];
    flareUps = [];
    appointments = [];
  }
}

/// Phone-sized test surface. [small] is an iPhone SE-sized screen.
void usePhone(WidgetTester tester, {bool small = false}) {
  tester.view.physicalSize = small ? const Size(375, 667) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget app(MemoryStorage storage) => ProviderScope(
      overrides: [
        storageServiceProvider.overrideWith((ref) => StorageServiceNotifier.withStorage(storage)),
      ],
      child: const ThygesonApp(),
    );

void main() {
  testWidgets('shows the welcome screen when there are no drops', (tester) async {
    usePhone(tester, small: true);
    await tester.pumpWidget(app(MemoryStorage()));
    await tester.pump();
    expect(find.text('Add my first drop'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Journey'), findsOneWidget);
  });

  testWidgets('shows the timeline once a drop exists', (tester) async {
    usePhone(tester);
    final storage = MemoryStorage()
      ..medicines = [
        Medicine(
          name: 'Steroid drop',
          createdAt: DateTime(2020),
          schedules: [
            MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['00:00', '23:59']),
          ],
        ),
      ];
    await tester.pumpWidget(app(storage));
    await tester.pump();
    expect(find.text('Add my first drop'), findsNothing);
    expect(find.textContaining('Steroid drop'), findsWidgets);
    expect(find.text('NOW'), findsOneWidget);
  });

  testWidgets('Journey tab renders the month grid', (tester) async {
    usePhone(tester);
    final storage = MemoryStorage()
      ..medicines = [
        Medicine(name: 'Lubricant', createdAt: DateTime(2020), schedules: [
          MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['12:00']),
        ]),
      ]
      ..flareUps = [
        FlareUp(date: DateTime.now(), leftEye: false, rightEye: true, rightPainLevel: PainLevel.bad),
      ];
    await tester.pumpWidget(app(storage));
    await tester.pump();
    await tester.tap(find.text('Journey'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Each day: left eye | right eye'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Right eye flaring'),
      200,
      scrollable: find.descendant(of: find.byType(JourneyScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('Right eye flaring'), findsOneWidget);
  });

  test('check-in levels round-trip through stored pain levels', () {
    for (final f in EyeFeel.values) {
      expect(feelFromPain(f != EyeFeel.calm, f.painLevel), f);
    }
    expect(feelFromPain(true, PainLevel.terrible), EyeFeel.flaring);
    expect(feelFromPain(true, null), EyeFeel.gritty);
    expect(feelFromPain(false, PainLevel.bad), EyeFeel.calm);
  });
}
