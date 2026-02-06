import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_sync/cloud_sync_adapter.dart';
import '../services/cloud_sync/cloud_sync_service.dart';
import '../services/cloud_sync_storage_service.dart';
import '../services/storage_service.dart';

/// Provider for storage service that switches between local and cloud sync
final storageServiceProvider = StateNotifierProvider<StorageServiceNotifier, IStorageService>((ref) {
  return StorageServiceNotifier();
});

class StorageServiceNotifier extends StateNotifier<IStorageService> {
  StorageServiceNotifier() : super(LocalStorageService()) {
    _initialize();
  }

  Future<void> _initialize() async {
    final localStorage = LocalStorageService();
    await localStorage.init();
    
    if (localStorage.getCloudSyncEnabled()) {
      try {
        final cloudAdapter = CloudSyncService.createAdapter();
        await cloudAdapter.init();
        
        if (await cloudAdapter.isSignedIn() || await cloudAdapter.isAvailable()) {
          state = CloudSyncStorageService(localStorage, cloudAdapter);
          await state.init();
          return;
        }
      } catch (_) {
        // Fall through to local storage
      }
    }
    
    state = localStorage;
  }

  void updateStorage(IStorageService newStorage) {
    state = newStorage;
  }
}

/// Provider for cloud sync adapter (for sign-in/sign-out operations)
final cloudSyncAdapterProvider = Provider<ICloudSyncAdapter?>((ref) {
  final storage = ref.watch(storageServiceProvider);
  if (storage is CloudSyncStorageService) {
    return storage.cloudAdapter;
  }
  return null;
});
