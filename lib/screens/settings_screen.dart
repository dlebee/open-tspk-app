import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import '../providers/appointment_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/theme_provider.dart';
import '../services/cloud_sync/cloud_sync_adapter.dart';
import '../services/cloud_sync/cloud_sync_service.dart';
import '../services/cloud_sync_storage_service.dart';
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
          _CloudSyncSection(),
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
      
      // Update notification service if storage changed
      NotificationService.setStorage(storage);

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

class _CloudSyncSection extends ConsumerStatefulWidget {
  const _CloudSyncSection();

  @override
  ConsumerState<_CloudSyncSection> createState() => _CloudSyncSectionState();
}

class _CloudSyncSectionState extends ConsumerState<_CloudSyncSection> {
  bool _isInitializing = false;

  @override
  Widget build(BuildContext context) {
    final syncEnabled = ref.watch(syncEnabledProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final storage = ref.watch(storageServiceProvider);
    final cloudAdapter = ref.watch(cloudSyncAdapterProvider);

    final platformName = Platform.isIOS ? 'iCloud Drive' : 'Google Drive';
    final platformIcon = Platform.isIOS ? Icons.cloud : Icons.cloud_queue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: Icon(platformIcon),
          title: Text('Sync with $platformName'),
          subtitle: Text(
            syncEnabled
                ? 'Your data syncs across devices'
                : 'Enable to sync your data across devices',
          ),
          value: syncEnabled,
          onChanged: _isInitializing
              ? null
              : (value) async {
                  await _handleSyncToggle(context, ref, value, storage);
                },
        ),
        if (syncEnabled) ...[
          const SizedBox(height: 8),
          if (cloudAdapter != null) ...[
            FutureBuilder<bool>(
              future: cloudAdapter.isSignedIn(),
              builder: (context, snapshot) {
                if (snapshot.data == false) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (Platform.isAndroid)
                          FilledButton.icon(
                            onPressed: _isInitializing
                                ? null
                                : () async {
                                    await _handleSignIn(context, ref, cloudAdapter);
                                  },
                            icon: const Icon(Icons.login),
                            label: const Text('Sign in to Google Drive'),
                          ),
                        if (Platform.isIOS)
                          Text(
                            'Sign in to iCloud in Settings to enable sync',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
          if (syncStatus == SyncStatus.syncing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Syncing...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (syncStatus == SyncStatus.error)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Sync error. Please try again.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _handleSyncToggle(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
    IStorageService storage,
  ) async {
    setState(() => _isInitializing = true);
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      await storage.setCloudSyncEnabled(enabled);

      if (enabled) {
        // Initialize cloud sync
        try {
          final cloudAdapter = CloudSyncService.createAdapter();
          await cloudAdapter.init();

          // Check if signed in (for Android) or available (for iOS)
          final isSignedIn = await cloudAdapter.isSignedIn();
          final isAvailable = await cloudAdapter.isAvailable();

          if (!isSignedIn && !isAvailable) {
            // Need to sign in
            if (Platform.isAndroid) {
              await cloudAdapter.signIn();
            } else {
              // iOS - user needs to sign in via Settings
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please sign in to iCloud in Settings to enable sync',
                    ),
                  ),
                );
              }
            }
          }

          // Create cloud sync storage service
          final localStorage = storage as LocalStorageService;
          final cloudSyncStorage = CloudSyncStorageService(
            localStorage,
            cloudAdapter,
          );
          await cloudSyncStorage.init();

          // Update provider
          ref.read(storageServiceProvider.notifier).updateStorage(cloudSyncStorage);
          
          // Update notification service
          NotificationService.setStorage(cloudSyncStorage);

          ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        } catch (e) {
          // Failed to initialize cloud sync
          await storage.setCloudSyncEnabled(false);
          ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to enable sync: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Disable sync - sign out from cloud
        final cloudAdapter = ref.read(cloudSyncAdapterProvider);
        if (cloudAdapter != null) {
          try {
            await cloudAdapter.signOut();
          } catch (_) {
            // Ignore sign-out errors
          }
        }

        // Switch back to local storage
        final localStorage = storage is CloudSyncStorageService
            ? (storage as CloudSyncStorageService).localStorage
            : storage as LocalStorageService;

        ref.read(storageServiceProvider.notifier).updateStorage(localStorage);
        
        // Update notification service
        NotificationService.setStorage(localStorage);
        
        ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
      }
    } catch (e) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _handleSignIn(
    BuildContext context,
    WidgetRef ref,
    ICloudSyncAdapter adapter,
  ) async {
    setState(() => _isInitializing = true);
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      await adapter.signIn();
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully')),
        );
      }

      // Refresh the storage service to use cloud sync
      final storage = ref.read(storageServiceProvider);
      if (storage is LocalStorageService) {
        final cloudSyncStorage = CloudSyncStorageService(
          storage,
          adapter,
        );
        await cloudSyncStorage.init();
        ref.read(storageServiceProvider.notifier).updateStorage(cloudSyncStorage);
        
        // Update notification service
        NotificationService.setStorage(cloudSyncStorage);
      }
    } catch (e) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign-in failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isInitializing = false);
    }
  }
}
