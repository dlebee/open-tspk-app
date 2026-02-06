import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';
import 'storage_provider.dart';

final highContrastProvider = StateProvider<bool>((ref) => false);

final developerModeProvider = StateNotifierProvider<DeveloperModeNotifier, bool>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return DeveloperModeNotifier(storage);
});

class DeveloperModeNotifier extends StateNotifier<bool> {
  DeveloperModeNotifier(this._storage) : super(_storage.getDeveloperMode()) {
    _load();
  }

  final StorageService _storage;

  Future<void> _load() async {
    state = _storage.getDeveloperMode();
  }

  Future<void> setEnabled(bool enabled) async {
    await _storage.setDeveloperMode(enabled);
    state = enabled;
  }
}
