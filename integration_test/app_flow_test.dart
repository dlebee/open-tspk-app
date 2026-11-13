// End-to-end walk through the redesigned app on a real simulator/emulator.
// Run: flutter test integration_test/app_flow_test.dart -d <device>
//
// It wipes the app's local data first, so only run it on test devices.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:thygeson/app.dart';
import 'package:thygeson/providers/storage_provider.dart';
import 'package:thygeson/services/notification_service.dart';
import 'package:thygeson/services/storage_service.dart';
import 'package:thygeson/widgets/hold_button.dart';

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    // Lazily built list item further down: scroll the top-most page to it.
    await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).last);
  }
  await t.ensureVisible(f.first);
  await settle(t, 300);
  await t.tap(f.first);
  await settle(t);
}

Future<void> hold(WidgetTester t) async {
  final g = await t.startGesture(t.getCenter(find.byType(HoldButton)));
  await settle(t, 1300);
  await g.up();
  await settle(t, 1200);
}

Future<void> openPlus(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Log a drop or check in'));
  await settle(t, 800);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full app walk-through', (t) async {
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

    // 1. First run → add a drop.
    expect(find.text('Add my first drop'), findsOneWidget);
    await tapText(t, 'Add my first drop');
    expect(find.text('Add a drop'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Steroid drop');
    await settle(t);
    await tapText(t, 'Save');
    await settle(t, 1500);

    // 2. Today timeline with the new drop, and its reminders are scheduled.
    expect(find.text('NOW'), findsOneWidget);
    expect(find.textContaining('Steroid drop'), findsWidgets);
    await settle(t, 3000);
    final pending = await NotificationService.getPendingNotifications();
    debugPrint('[e2e] pending notifications after adding drop: ${pending.length}');
    expect(pending, isNotEmpty);

    // 3. + → log the drop by holding the button.
    await openPlus(t);
    expect(find.textContaining('drop'), findsWidgets);
    await t.tap(find.textContaining('Log the ').first);
    await settle(t, 800);
    expect(find.byType(HoldButton), findsOneWidget);
    await hold(t);
    expect(find.textContaining('Logged'), findsOneWidget);
    await settle(t, 4500); // let the snackbar go

    // 4. + → check-in with a sore right eye.
    await openPlus(t);
    await tapText(t, 'Check in on my eyes');
    expect(find.text('How do your\neyes feel?'), findsOneWidget);
    await t.tap(find.text('Sore').last);
    await settle(t);
    await tapText(t, 'Light hurts');
    await tapText(t, 'Save check-in');
    await settle(t, 1000);
    expect(find.text('R · sore'), findsOneWidget);
    await settle(t, 4500);

    // 5. + → extra drop.
    await openPlus(t);
    await tapText(t, 'Extra drop');
    await hold(t);
    expect(find.textContaining('Logged extra'), findsOneWidget);
    await settle(t, 4500);

    // 6. Journey → flare-up → day detail.
    await tapText(t, 'Journey');
    expect(find.text('Each day: left eye | right eye'), findsOneWidget);
    await tapText(t, 'Right eye sore');
    expect(find.text('Check-in'), findsOneWidget);
    expect(find.textContaining('Extra Steroid drop'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    // 7. Doctor visits screen.
    await tapText(t, 'Doctor visits');
    expect(find.text('Share summary with doctor'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    // 8. Your drops → edit.
    await tapText(t, 'Today');
    await t.tap(find.byTooltip('Your drops'));
    await settle(t);
    expect(find.text('Your drops'), findsOneWidget);
    await tapText(t, 'Steroid drop');
    expect(find.text('Edit drop'), findsOneWidget);
    await t.pageBack();
    await settle(t);
    await t.pageBack();
    await settle(t);

    // 9. Settings → developer mode → explorers and debug tools.
    await t.tap(find.byTooltip('Settings'));
    await settle(t);
    final devSwitch = find.widgetWithText(SwitchListTile, 'Developer mode');
    await t.scrollUntilVisible(devSwitch, 300, scrollable: find.byType(Scrollable).last);
    await settle(t, 300);
    await t.tap(devSwitch);
    await settle(t, 1000);
    expect(find.text('Notification explorer'), findsOneWidget);
    expect(find.text('Storage explorer'), findsOneWidget);
    await tapText(t, 'Debug tools');
    expect(find.text('Debug tools'), findsWidgets);
    await settle(t, 1500);
    expect(find.textContaining('Notifications: allowed'), findsOneWidget);

    await tapText(t, 'Add demo data');
    await settle(t, 3000);
    expect(find.textContaining('demo data'), findsWidgets);

    // 10. Real notification: fires in 5 s while the app is open (banner shows in foreground).
    await tapText(t, 'Send test in 5 seconds');
    final testPending = (await NotificationService.getPendingNotifications()).where((p) => p.id == 999999);
    expect(testPending, isNotEmpty);
    debugPrint('[e2e] test notification scheduled; waiting for it to fire');
    await settle(t, 9000);
    final stillPending = (await NotificationService.getPendingNotifications()).where((p) => p.id == 999999);
    debugPrint('[e2e] test notification still pending after 9 s: ${stillPending.length}');
    expect(stillPending, isEmpty);

    // Leave the app on Journey with demo data for screenshots.
    await t.pageBack();
    await settle(t);
    await t.pageBack();
    await settle(t);
    await tapText(t, 'Journey');
    await settle(t, 2000);
  });
}
