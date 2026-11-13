// Opens the app on a test device with 3 weeks of demo data (some drops not logged,
// some skipped, a few extras) and keeps it running and tappable for a while, for
// demos and manual checks:
//   flutter test integration_test/demo_seed_test.dart -d <device> --dart-define=DEMO_MINUTES=20
//
// It wipes the app's local data first, so only run it on test devices.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:thygeson/app.dart';
import 'package:thygeson/dev/demo_data.dart';
import 'package:thygeson/providers/storage_provider.dart';
import 'package:thygeson/services/notification_service.dart';
import 'package:thygeson/services/storage_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const minutes = int.fromEnvironment('DEMO_MINUTES', defaultValue: 0);

  testWidgets('seed demo data', (t) async {
    await NotificationService.init();
    final storage = LocalStorageService();
    await storage.init();
    await storage.wipeAllData();
    await NotificationService.cancelAll();

    await t.pumpWidget(ProviderScope(
      overrides: [storageServiceProvider.overrideWith((ref) => StorageServiceNotifier.withStorage(storage))],
      child: const ThygesonApp(),
    ));
    await t.pump(const Duration(seconds: 2));
    final container = ProviderScope.containerOf(t.element(find.byType(MainNavigator)));
    await seedDemoData(container.read);
    await t.pump(const Duration(seconds: 3));
    debugPrint('[demo] seeded');

    if (minutes > 0) {
      // Hand the app to real touches until time runs out.
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      binding.shouldPropagateDevicePointerEvents = true;
      debugPrint('[demo] live for $minutes min');
      final end = DateTime.now().add(const Duration(minutes: minutes));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
  }, timeout: const Timeout(Duration(minutes: minutes + 5)));
}
