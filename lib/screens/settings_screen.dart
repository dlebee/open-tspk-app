import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/appointment_provider.dart';
import '../providers/theme_provider.dart';
import '../services/export_service.dart';
import '../providers/dose_provider.dart';
import '../providers/flare_up_provider.dart';
import '../providers/medicine_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open menu',
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Consumer(
            builder: (context, ref, _) {
              final highContrast = ref.watch(highContrastProvider);
              return Semantics(
                label: 'High contrast mode',
                child: SwitchListTile(
                  secondary: const Icon(Icons.contrast),
                  title: const Text('High contrast'),
                  subtitle: const Text('Improve visibility'),
                  value: highContrast,
                  onChanged: (v) =>
                      ref.read(highContrastProvider.notifier).state = v,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export data'),
            subtitle: const Text('Export all data as JSON'),
            onTap: () => _exportData(context, ref),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.cloud),
            title: Text('Backup'),
            subtitle: Text(
              'Your data is stored locally and included in iCloud Backup (iOS) or Google Backup (Android) when enabled in device settings.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final medicines = ref.read(medicinesProvider).valueOrNull ?? [];
    final doses = ref.read(dosesProvider).valueOrNull ?? [];
    final flareUps = ref.read(flareUpsProvider).valueOrNull ?? [];
    final appointments = ref.read(appointmentsProvider).valueOrNull ?? [];

    final exported = ExportService.export(
      medicines: medicines,
      doses: doses,
      flareUps: flareUps,
      appointments: appointments,
    );

    await ExportService.share(exported);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data exported')),
      );
    }
  }
}
