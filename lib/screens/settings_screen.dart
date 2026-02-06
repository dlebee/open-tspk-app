import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/appointment_provider.dart';
import '../providers/theme_provider.dart';
import '../services/export_service.dart';
import '../providers/dose_provider.dart';
import '../providers/flare_up_provider.dart';
import '../providers/medicine_provider.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../providers/storage_provider.dart';

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
          Consumer(
            builder: (context, ref, _) {
              final developerMode = ref.watch(developerModeProvider);
              return SwitchListTile(
                secondary: const Icon(Icons.developer_mode),
                title: const Text('Developer mode'),
                subtitle: const Text('Enable advanced features'),
                value: developerMode,
                onChanged: (v) =>
                    ref.read(developerModeProvider.notifier).setEnabled(v),
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
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Wipe all data'),
            subtitle: const Text('Delete all medicines, doses, flare-ups, and appointments'),
            textColor: Colors.red,
            iconColor: Colors.red,
            onTap: () => _confirmWipeData(context, ref),
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

  Future<void> _confirmWipeData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _WipeDataConfirmationDialog(),
    );

    if (confirmed != true) return;

    try {
      // Cancel all notifications
      await NotificationService.cancelAll();

      // Wipe all data from storage
      final storage = ref.read(storageServiceProvider);
      await storage.wipeAllData();

      // Refresh all providers to reflect empty state
      ref.invalidate(medicinesProvider);
      ref.invalidate(dosesProvider);
      ref.invalidate(flareUpsProvider);
      ref.invalidate(appointmentsProvider);
      ref.invalidate(developerModeProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data has been wiped'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to wipe data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _WipeDataConfirmationDialog extends StatefulWidget {
  @override
  State<_WipeDataConfirmationDialog> createState() =>
      _WipeDataConfirmationDialogState();
}

class _WipeDataConfirmationDialogState
    extends State<_WipeDataConfirmationDialog> {
  final _textController = TextEditingController();
  static const _confirmationText = 'i am sure';

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _isConfirmed => _textController.text.trim().toLowerCase() == _confirmationText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Wipe all data?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will permanently delete all medicines, doses, flare-ups, appointments, and preferences. This action cannot be undone.',
            ),
            const SizedBox(height: 16),
            const Text(
              'To confirm, please type "i am sure" below:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'i am sure',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isConfirmed ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Wipe all data'),
        ),
      ],
    );
  }
}
