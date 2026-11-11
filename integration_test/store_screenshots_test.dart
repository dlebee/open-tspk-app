// Walks the app with demo data and pauses on each store screenshot.
// The host captures the device screen whenever a "[shot] <name>" line prints:
//   tool/store_screenshots.sh ios <udid>   |   tool/store_screenshots.sh android <serial>
//
// It wipes the app's local data first, so only run it on test devices.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:thygeson/app.dart';
import 'package:thygeson/dev/demo_data.dart';
import 'package:thygeson/models/flare_up.dart';
import 'package:thygeson/providers/flare_up_provider.dart';
import 'package:thygeson/ui/dusk_ui.dart';
import 'package:thygeson/providers/storage_provider.dart';
import 'package:thygeson/services/notification_service.dart';
import 'package:thygeson/services/storage_service.dart';

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Signals the host, then holds the frame still long enough for it to capture.
/// iOS buffers test logs, so the signal is also a file in the app's Documents
/// folder (shot_marker.txt) that the host polls; Android reads the log line.
Future<void> shot(WidgetTester t, String name) async {
  await settle(t, 1200);
  final dir = await t.runAsync(getApplicationDocumentsDirectory);
  File('${dir!.path}/shot_marker.txt').writeAsStringSync(name);
  debugPrint('[shot] $name');
  await settle(t, 6000);
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).last);
  }
  await t.ensureVisible(f.first);
  await settle(t, 300);
  await t.tap(f.first);
  await settle(t, 900);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (t) async {
    await NotificationService.init();
    final storage = LocalStorageService();
    await storage.init();
    await storage.wipeAllData();
    await NotificationService.cancelAll();

    await t.pumpWidget(ProviderScope(
      overrides: [storageServiceProvider.overrideWith((ref) => StorageServiceNotifier.withStorage(storage))],
      child: const ThygesonApp(),
    ));
    await settle(t, 2500);
    await shot(t, '01-welcome');

    final container = ProviderScope.containerOf(t.element(find.byType(MainNavigator)));
    await seedDemoData(container.read, logToday: true);
    // A recent flare so this month's Journey shows one.
    final now = DateTime.now();
    for (final (days, feel) in [(4, EyeFeel.sore), (3, EyeFeel.flaring), (2, EyeFeel.gritty)]) {
      await container.read(flareUpsProvider.notifier).add(FlareUp(
            date: DateTime(now.year, now.month, now.day - days, 19, 20),
            leftEye: false,
            rightEye: true,
            rightPainLevel: feel.painLevel,
            reason: feel == EyeFeel.gritty ? null : 'Light hurts, Watery',
          ));
    }
    await settle(t, 3000);
    await shot(t, '02-today');

    // Check-in with a sore right eye.
    await t.tap(find.bySemanticsLabel('Log a drop or check in'));
    await settle(t, 900);
    await tapText(t, 'Check in on my eyes');
    await t.tap(find.text('Sore').last);
    await settle(t);
    await tapText(t, 'Light hurts');
    await t.ensureVisible(find.text('How do your\neyes feel?'));
    await shot(t, '03-check-in');
    await t.pageBack();
    await settle(t, 900);

    // Journey month.
    await tapText(t, 'Journey');
    await shot(t, '04-journey');

    // A flare day.
    await tapText(t, 'Right eye flaring');
    await shot(t, '05-day');
    await t.pageBack();
    await settle(t, 900);

    // Doctor visits and the summary.
    await tapText(t, 'Doctor visits');
    await shot(t, '06-visits');
    await t.pageBack();
    await settle(t, 900);

    // Your drops.
    await tapText(t, 'Today');
    await t.tap(find.byTooltip('Your drops'));
    await settle(t, 900);
    await shot(t, '07-drops');
  });
}
