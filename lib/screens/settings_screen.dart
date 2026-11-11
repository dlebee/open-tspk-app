import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import '../providers/appointment_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/notification_reminder_provider.dart';
import '../models/notification_reminder_preference.dart';
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
import 'debug_screen.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import '../app_version.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _versionTaps = 0;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final highContrast = ref.watch(highContrastProvider);
    final developerMode = ref.watch(developerModeProvider);
    final preference = ref.watch(notificationReminderPreferenceProvider);
    return DuskPage(
      title: 'Settings',
      children: [
        const SectionLabel('Reminders'),
        _Group(children: [
          _Row(
            title: 'Drop reminders',
            value: _getNotificationSummary(preference),
            onTap: () => _showNotificationConfigurationBottomSheet(context, ref),
          ),
        ]),
        const SizedBox(height: 20),
        const SectionLabel('Easy on the eyes'),
        _Group(children: [
          SwitchListTile(
            title: const Text('Extra contrast'),
            subtitle: const Text('Brighter text on the dark background'),
            value: highContrast,
            onChanged: (v) => ref.read(highContrastProvider.notifier).state = v,
          ),
        ]),
        const SizedBox(height: 20),
        const SectionLabel('Backup and sync'),
        _Group(children: [_CloudSyncSection()]),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'Your data is stored on this phone and included in iCloud Backup (iOS) or Google Backup (Android) when those are on.',
            style: TextStyle(fontSize: 13, color: Dusk.textMuted),
          ),
        ),
        const SizedBox(height: 20),
        const SectionLabel('Your data'),
        _Group(children: [
          Builder(
            builder: (tileContext) => _Row(
              title: 'Export everything',
              value: 'JSON',
              onTap: () => _exportData(context, ref, shareOriginContext: tileContext),
            ),
          ),
          _Row(title: 'Import a backup', onTap: () => _importData(context, ref)),
          _Row(
            title: 'Wipe all data',
            danger: true,
            onTap: () => _confirmWipeData(context, ref),
          ),
        ]),
        if (developerMode) ...[
          const SizedBox(height: 20),
          const SectionLabel('Developer'),
          _Group(children: [
            _Row(
              title: 'Debug tools',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugScreen()),
              ),
            ),
            SwitchListTile(
              title: const Text('Developer mode'),
              value: true,
              onChanged: (v) => ref.read(developerModeProvider.notifier).setEnabled(v),
            ),
          ]),
        ],
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () async {
              if (developerMode) return;
              _versionTaps++;
              if (_versionTaps >= 7) {
                await ref.read(developerModeProvider.notifier).setEnabled(true);
                if (context.mounted) showDuskSnack(context, 'Developer mode on');
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Thygeson $appVersionLabel',
                style: const TextStyle(fontSize: 12, color: Dusk.textMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getNotificationSummary(NotificationReminderPreference preference) {
    final parts = <String>[];
    if (preference.isEnabled(0)) parts.add('At scheduled time');
    if (preference.isEnabled(15)) parts.add('15 min before');
    if (preference.isEnabled(10)) parts.add('10 min before');
    if (preference.isEnabled(5)) parts.add('5 min before');
    
    if (parts.isEmpty) return 'No notifications';
    if (parts.length == 4) return 'All notifications enabled';
    return parts.join(', ');
  }

  Future<void> _showNotificationConfigurationBottomSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _NotificationConfigurationSheet(),
    );
  }

  Future<void> _exportData(
    BuildContext context,
    WidgetRef ref, {
    BuildContext? shareOriginContext,
  }) async {
    final medicines = ref.read(medicinesProvider).value ?? [];
    final doses = ref.read(dosesProvider).value ?? [];
    final flareUps = ref.read(flareUpsProvider).value ?? [];
    final appointments = ref.read(appointmentsProvider).value ?? [];

    final exported = ExportService.export(
      medicines: medicines,
      doses: doses,
      flareUps: flareUps,
      appointments: appointments,
    );

    Rect? shareOrigin;
    if (shareOriginContext != null) {
      final box =
          shareOriginContext.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final pos = box.localToGlobal(Offset.zero);
        shareOrigin = Rect.fromLTWH(
          pos.dx,
          pos.dy,
          box.size.width,
          box.size.height,
        );
      }
    }

    try {
      await ExportService.share(
        exported,
        sharePositionOrigin: shareOrigin,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data exported')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    try {
      final importData = await ExportService.pickAndParseImport();
      if (importData == null) return; // User cancelled

      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import data'),
          content: Text(
            'This will replace all current data with the imported file.\n\n'
            'Import: ${importData.medicines.length} medicines, '
            '${importData.doses.length} doses, '
            '${importData.flareUps.length} flare-ups, '
            '${importData.appointments.length} appointments.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;

      await NotificationService.cancelAll();
      final storage = ref.read(storageServiceProvider);
      await storage.saveMedicines(importData.medicines);
      await storage.saveDoses(importData.doses);
      await storage.saveFlareUps(importData.flareUps);
      await storage.saveAppointments(importData.appointments);

      ref.invalidate(medicinesProvider);
      ref.invalidate(dosesProvider);
      ref.invalidate(flareUpsProvider);
      ref.invalidate(appointmentsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data imported successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      ref.invalidate(notificationReminderPreferenceProvider);

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
            ? storage.localStorage
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

class _NotificationConfigurationSheet extends ConsumerStatefulWidget {
  const _NotificationConfigurationSheet();

  @override
  ConsumerState<_NotificationConfigurationSheet> createState() => _NotificationConfigurationSheetState();
}

class _NotificationConfigurationSheetState extends ConsumerState<_NotificationConfigurationSheet> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(notificationReminderPreferenceProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active),
                    const SizedBox(width: 8),
                    const Text(
                      'Notification Configuration',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.access_time),
                      title: const Text('At scheduled time'),
                      subtitle: const Text('Notify when it\'s time to take your medicine'),
                      value: preference.isEnabled(0),
                      onChanged: _isSaving ? null : (enabled) => _toggleReminder(0),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.timer),
                      title: const Text('15 minutes before'),
                      subtitle: const Text('Remind 15 minutes before scheduled time'),
                      value: preference.isEnabled(15),
                      onChanged: _isSaving ? null : (enabled) => _toggleReminder(15),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.timer),
                      title: const Text('10 minutes before'),
                      subtitle: const Text('Remind 10 minutes before scheduled time'),
                      value: preference.isEnabled(10),
                      onChanged: _isSaving ? null : (enabled) => _toggleReminder(10),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.timer),
                      title: const Text('5 minutes before'),
                      subtitle: const Text('Remind 5 minutes before scheduled time'),
                      value: preference.isEnabled(5),
                      onChanged: _isSaving ? null : (enabled) => _toggleReminder(5),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleReminder(int minutes) async {
    setState(() => _isSaving = true);
    try {
      await ref.read(notificationReminderPreferenceProvider.notifier).toggleReminder(minutes);
      // Small delay to ensure storage is written
      await Future.delayed(const Duration(milliseconds: 100));
      // Use current storage from provider to ensure we have the latest medicines
      final storage = ref.read(storageServiceProvider);
      await NotificationService.rescheduleAllNotifications(storage: storage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Dusk.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.value, this.onTap, this.danger = false});

  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final long = (value?.length ?? 0) > 12;
    return ListTile(
      shape: const RoundedRectangleBorder(),
      title: Text(title, style: TextStyle(color: danger ? Dusk.rose : Dusk.text)),
      subtitle: long ? Text(value!, style: const TextStyle(color: Dusk.textMuted)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && !long)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(value!, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Dusk.textMuted)),
            ),
          if (!danger) const Icon(Icons.chevron_right, color: Dusk.textMuted),
        ],
      ),
      onTap: onTap,
    );
  }
}
