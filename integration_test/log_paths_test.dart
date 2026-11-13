// Every way of logging a scheduled drop, on a real device with real storage and
// notifications: skip, take at the scheduled time, undo, from Today and from
// Journey, for today's drops and earlier days'.
//   flutter test integration_test/log_paths_test.dart -d <device>
//
// It wipes the app's local data first, so only run it on test devices.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';

import 'package:thygeson/app.dart';
import 'package:thygeson/models/medicine.dart';
import 'package:thygeson/models/medicine_dose.dart';
import 'package:thygeson/models/medicine_schedule.dart';
import 'package:thygeson/providers/dose_provider.dart';
import 'package:thygeson/providers/medicine_provider.dart';
import 'package:thygeson/providers/storage_provider.dart';
import 'package:thygeson/screens/journey_screen.dart';
import 'package:thygeson/services/notification_service.dart';
import 'package:thygeson/services/storage_service.dart';

Future<void> settle(WidgetTester t, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls [target] into view, then places it 40% down the screen, clear of the
/// floating tab bar, without a gesture that could fling the list past it.
Future<void> reveal(WidgetTester t, Finder target, Finder list) async {
  await t.scrollUntilVisible(target, 250, scrollable: list);
  await Scrollable.ensureVisible(t.element(target), alignment: 0.4);
  await settle(t, 500);
}

/// Fails the test if the app showed its save-error snackbar or threw.
void expectNoError(WidgetTester t, String step) {
  final err = find.textContaining("Couldn't save");
  if (err.evaluate().isNotEmpty) {
    final text = (err.evaluate().first.widget as Text).data;
    debugPrint('[paths] FAIL $step showed an error: $text');
    fail('$step showed an error: $text');
  }
  final e = t.takeException();
  if (e != null) {
    debugPrint('[paths] FAIL $step threw: $e');
    fail('$step threw: $e');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Keep only this test's lines and Flutter's own error reports: the services log
  // so much that the device drops lines, including the ones that explain a failure.
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    final noisy = RegExp(r'^\[(NotificationService|MedicineProvider|StorageService|DoseProvider)\]|^  - ');
    if (!noisy.hasMatch(message)) debugPrintSynchronously(message, wrapWidth: wrapWidth);
  };

  testWidgets('log paths work on device', (t) async {
    await NotificationService.init();
    final storage = LocalStorageService();
    await storage.init();
    await storage.wipeAllData();
    await NotificationService.cancelAll();

    await t.pumpWidget(ProviderScope(
      overrides: [storageServiceProvider.overrideWith((ref) => StorageServiceNotifier.withStorage(storage))],
      child: const ThygesonApp(),
    ));
    await settle(t, 1500);

    // A drop added 3 days ago, due at 00:00 and 23:59: 00:00 is always past.
    final now = DateTime.now();
    final container = ProviderScope.containerOf(t.element(find.byType(MainNavigator)));
    await container.read(medicinesProvider.notifier).add(Medicine(
          name: 'Steroid drop',
          createdAt: DateTime(now.year, now.month, now.day - 3),
          schedules: [
            MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['00:00', '23:59']),
          ],
        ));
    for (final name in ['Lubricant', 'Antibiotic']) {
      await container.read(medicinesProvider.notifier).add(Medicine(
            name: name,
            createdAt: DateTime(now.year, now.month, now.day - 3),
            schedules: [
              MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['09:00', '13:00', '17:00', '21:00']),
            ],
          ));
    }
    await settle(t, 4000);

    List<MedicineDose> doses() => container.read(dosesProvider).value ?? [];

    // 0. Skip, then close the sheet straight away, as an impatient tap would.
    await t.tap(find.textContaining('Steroid drop · not logged'));
    await settle(t);
    await t.tap(find.text('Skip this one'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(const Offset(200, 120)); // the dimmed area above the sheet
    await settle(t, 6000);
    debugPrint('[paths] after skip-then-close: ${doses().map((d) => '${d.status.name} ${d.scheduledTime}').toList()}');
    expectNoError(t, 'Skip then close');
    expect(doses().where((d) => d.status == DoseStatus.skipped), hasLength(1),
        reason: 'the skip should be saved even if the sheet is closed right away');
    debugPrint('[paths] skip then close ok');
    // Undo it so the rest starts clean.
    await t.tap(find.text('Steroid drop · skipped'));
    await settle(t);
    await t.tap(find.text('Undo'));
    await settle(t, 6000);

    // 1. Today: skip today's missed 00:00 drop.
    await t.tap(find.textContaining('Steroid drop · not logged'));
    await settle(t);
    await t.tap(find.text('Skip this one'));
    await settle(t, 1500);
    expectNoError(t, 'Skip from Today');
    expect(doses().where((d) => d.status == DoseStatus.skipped), hasLength(1));
    expect(find.text('Steroid drop · skipped'), findsOneWidget);
    debugPrint('[paths] skip from Today ok');
    await settle(t, 4500);

    // 2. Today: open the skipped drop and undo it.
    await t.tap(find.text('Steroid drop · skipped'));
    await settle(t);
    await t.tap(find.text('Undo'));
    await settle(t, 1500);
    expectNoError(t, 'Undo skip');
    expect(doses(), isEmpty);
    debugPrint('[paths] undo ok');
    await settle(t, 4500);

    // 3. Journey: skip an earlier day's drop from the "Drops not logged" list.
    await t.tap(find.text('Journey'));
    await settle(t, 1500);
    final list = find.descendant(of: find.byType(JourneyScreen), matching: find.byType(Scrollable)).first;
    String day(int back) => DateFormat('EEE d MMM').format(DateTime(now.year, now.month, now.day - back));
    final earlier = find.text('${day(1)} · 23:59 · not logged');
    await reveal(t, earlier, list);
    await t.tap(earlier);
    await settle(t);
    await t.tap(find.text('Skip this one'));
    await settle(t, 1500);
    expectNoError(t, 'Skip from Journey');
    expect(doses().where((d) => d.status == DoseStatus.skipped), hasLength(1));
    debugPrint('[paths] skip from Journey ok');
    await settle(t, 4500);

    // 3b. It shows under "Skipped" and can be changed to taken after all.
    final skippedRow = find.text('${day(1)} · 23:59 · skipped');
    await reveal(t, skippedRow, list);
    await t.tap(skippedRow);
    await settle(t);
    await t.tap(find.text('Took it at 23:59 after all'));
    await settle(t, 1500);
    expectNoError(t, 'Took it after all');
    expect(doses().where((d) => d.status == DoseStatus.skipped), isEmpty);
    expect(doses().where((d) => d.status == DoseStatus.taken), hasLength(1));
    debugPrint('[paths] skipped list and took it after all ok');
    await settle(t, 4500);

    // 4. Journey: log another earlier drop at its scheduled time.
    final another = find.text('${day(1)} · 00:00 · not logged');
    await t.fling(list, const Offset(0, 4000), 4000); // back to the top
    await settle(t, 1200);
    // Only the 5 latest show at first; older ones are behind "Show all".
    final showAll = find.textContaining('Show all');
    await reveal(t, showAll, list);
    await t.tap(showAll);
    await settle(t);
    await t.fling(list, const Offset(0, 4000), 4000);
    await settle(t, 1200);
    await reveal(t, another, list);
    await t.tap(another);
    await settle(t);
    await t.tap(find.text('Took it at 00:00'));
    await settle(t, 1500);
    expectNoError(t, 'Took it at from Journey');
    expect(doses().where((d) => d.status == DoseStatus.taken), hasLength(2));
    debugPrint('[paths] took it at ok');
    await settle(t, 2000);
  });
}
