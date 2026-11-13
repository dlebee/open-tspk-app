import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thygeson/app.dart';
import 'package:thygeson/models/appointment_note.dart';
import 'package:thygeson/models/flare_up.dart';
import 'package:thygeson/models/medicine.dart';
import 'package:thygeson/models/medicine_dose.dart';
import 'package:thygeson/models/medicine_schedule.dart';
import 'package:thygeson/widgets/unscheduled_dose_dialog.dart';
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

  test('lateBy reads naturally', () {
    final day = DateTime(2026, 11, 13);
    expect(lateBy(day, '08:00', DateTime(2026, 11, 13, 8, 20)), '20 min late');
    expect(lateBy(day, '08:00', DateTime(2026, 11, 13, 10, 0)), '2 h late');
    expect(lateBy(day, '08:00', DateTime(2026, 11, 13, 9, 30)), '1 h 30 min late');
    expect(lateBy(day, '08:00', DateTime(2026, 11, 14, 9, 0)), 'a day late');
  });

  group('missed is not skipped', () {
    Medicine drop() => Medicine(
          name: 'Steroid drop',
          createdAt: DateTime(2020),
          schedules: [
            MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['00:00', '23:59']),
          ],
        );

    testWidgets('a past drop with no log reads "not logged", and + offers to log it late', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(app(MemoryStorage()..medicines = [drop()]));
      await tester.pump();
      expect(find.textContaining('Steroid drop · not logged'), findsOneWidget);
      expect(find.textContaining('skipped'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Log a drop or check in'));
      await tester.pumpAndSettle();
      expect(find.text('Log the 00:00 drop'), findsOneWidget);
      await tester.tap(find.text('Log the 00:00 drop'));
      await tester.pumpAndSettle();
      expect(find.textContaining('00:00 · not logged'), findsOneWidget);
      expect(find.text('Hold to log'), findsOneWidget);
    });

    testWidgets('a skipped drop reads "skipped", not "not logged"', (tester) async {
      usePhone(tester);
      final m = drop();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final storage = MemoryStorage()
        ..medicines = [m]
        ..doses = [
          MedicineDose(
            medicineId: m.id,
            medicineName: m.name,
            eye: Eye.both,
            status: DoseStatus.skipped,
            recordedAt: today,
            scheduledDate: today,
            scheduledTime: '00:00',
          ),
        ];
      await tester.pumpWidget(app(storage));
      await tester.pump();
      expect(find.text('Steroid drop · skipped'), findsOneWidget);
      expect(find.textContaining('not logged'), findsNothing);
    });

    testWidgets('an extra drop can become the missed scheduled one', (tester) async {
      usePhone(tester);
      final m = drop();
      final now = DateTime.now();
      final extra = MedicineDose(
        medicineId: m.id,
        medicineName: m.name,
        eye: Eye.both,
        status: DoseStatus.taken,
        recordedAt: now,
        takenAt: now,
      );
      final storage = MemoryStorage()
        ..medicines = [m]
        ..doses = [extra];
      await tester.pumpWidget(app(storage));
      await tester.pump();
      await tester.tap(find.textContaining('Extra Steroid drop'));
      await tester.pumpAndSettle();
      expect(find.byType(UnscheduledDoseDialog), findsOneWidget);
      await tester.tap(find.text('This was my 00:00 drop'));
      await tester.pumpAndSettle();
      expect(storage.doses, hasLength(1));
      expect(storage.doses.single.scheduledTime, '00:00');
      expect(storage.doses.single.status, DoseStatus.taken);
      expect(find.textContaining('Steroid drop · taken'), findsOneWidget);
    });
  

    testWidgets('Journey lists drops not logged and extras, and both can be acted on', (tester) async {
      usePhone(tester);
      final now = DateTime.now();
      // Added today, so only today's 00:00 counts as not logged.
      final m = Medicine(
        name: 'Steroid drop',
        createdAt: DateTime(now.year, now.month, now.day),
        schedules: [
          MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['00:00', '23:59']),
        ],
      );
      final storage = MemoryStorage()
        ..medicines = [m]
        ..doses = [
          MedicineDose(
            medicineId: m.id,
            medicineName: m.name,
            eye: Eye.left,
            status: DoseStatus.taken,
            recordedAt: now,
            takenAt: now,
          ),
        ];
      await tester.pumpWidget(app(storage));
      await tester.pump();
      await tester.tap(find.text('Journey'));
      await tester.pumpAndSettle();
      final list = find.descendant(of: find.byType(JourneyScreen), matching: find.byType(Scrollable)).first;

      await tester.scrollUntilVisible(find.text('DROPS NOT LOGGED · 1'), 200, scrollable: list);
      await tester.scrollUntilVisible(find.textContaining('· 00:00 · not logged'), 200, scrollable: list);
      await tester.drag(list, const Offset(0, -250)); // clear of the floating tab bar
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('· 00:00 · not logged'));
      await tester.pumpAndSettle();
      expect(find.text('Hold to log'), findsOneWidget);
      expect(find.text('Skip this one'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20)); // close the sheet
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('EXTRA DROPS · 1'), 200, scrollable: list);
      await tester.scrollUntilVisible(find.textContaining('tap to edit or remove'), 200, scrollable: list);
      await tester.drag(list, const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('tap to edit or remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(storage.doses, isEmpty);
      expect(find.text('Removed extra Steroid drop'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(storage.doses, hasLength(1));
    });

    testWidgets('Skip this one marks a missed drop skipped without an error', (tester) async {
      usePhone(tester);
      final now = DateTime.now();
      final m = Medicine(
        name: 'Steroid drop',
        createdAt: DateTime(now.year, now.month, now.day),
        schedules: [
          MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['00:00', '23:59']),
        ],
      );
      final storage = MemoryStorage()..medicines = [m];
      await tester.pumpWidget(app(storage));
      await tester.pump();
      await tester.tap(find.textContaining('Steroid drop · not logged'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip this one'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining("Couldn't save"), findsNothing);
      expect(storage.doses, hasLength(1));
      expect(storage.doses.single.status, DoseStatus.skipped);
      expect(find.text('Steroid drop · skipped'), findsOneWidget);
    });
  });
}
