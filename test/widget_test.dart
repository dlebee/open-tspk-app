import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thygeson/app.dart';
import 'package:thygeson/providers/storage_provider.dart';
import 'package:thygeson/services/storage_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final storage = StorageService();
    await storage.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const ThygesonApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Thygeson'), findsOneWidget);
  });
}
