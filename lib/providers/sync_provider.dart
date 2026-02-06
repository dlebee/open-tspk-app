import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';
import 'storage_provider.dart';

enum SyncStatus {
  idle,
  syncing,
  error,
  signedOut,
  unavailable,
}

/// Provider for cloud sync enabled state
final syncEnabledProvider = Provider<bool>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.getCloudSyncEnabled();
});

/// Provider for sync status
final syncStatusProvider = StateProvider<SyncStatus>((ref) {
  return SyncStatus.idle;
});

/// Provider for last sync time
final lastSyncTimeProvider = StateProvider<DateTime?>((ref) {
  return null;
});
