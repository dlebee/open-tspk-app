import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine_dose.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

final dosesProvider = StateNotifierProvider<DosesNotifier, AsyncValue<List<MedicineDose>>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return DosesNotifier(storage);
});

class DosesNotifier extends StateNotifier<AsyncValue<List<MedicineDose>>> {
  DosesNotifier(this._storage) : super(const AsyncValue.loading()) {
    _load();
  }

  final IStorageService _storage;

  Future<void> _load() async {
    try {
      final list = _storage.getDoses();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(MedicineDose dose) async {
    final list = state.valueOrNull ?? [];
    final updated = [...list, dose];
    await _storage.saveDoses(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> delete(String id) async {
    final list = state.valueOrNull ?? [];
    final updated = list.where((d) => d.id != id).toList();
    await _storage.saveDoses(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> refresh() => _load();
}
