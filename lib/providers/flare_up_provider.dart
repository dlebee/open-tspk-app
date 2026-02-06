import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/flare_up.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

final flareUpsProvider = StateNotifierProvider<FlareUpsNotifier, AsyncValue<List<FlareUp>>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return FlareUpsNotifier(storage);
});

class FlareUpsNotifier extends StateNotifier<AsyncValue<List<FlareUp>>> {
  FlareUpsNotifier(this._storage) : super(const AsyncValue.loading()) {
    _load();
  }

  final IStorageService _storage;

  Future<void> _load() async {
    try {
      final list = _storage.getFlareUps();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(FlareUp flareUp) async {
    final list = state.valueOrNull ?? [];
    final updated = [...list, flareUp];
    await _storage.saveFlareUps(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> update(FlareUp flareUp) async {
    final list = state.valueOrNull ?? [];
    final updated = list.map((f) => f.id == flareUp.id ? flareUp : f).toList();
    await _storage.saveFlareUps(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> delete(String id) async {
    final list = state.valueOrNull ?? [];
    final updated = list.where((f) => f.id != id).toList();
    await _storage.saveFlareUps(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> refresh() => _load();
}
