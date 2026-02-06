import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

final medicinesProvider = StateNotifierProvider<MedicinesNotifier, AsyncValue<List<Medicine>>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return MedicinesNotifier(storage);
});

class MedicinesNotifier extends StateNotifier<AsyncValue<List<Medicine>>> {
  MedicinesNotifier(this._storage) : super(const AsyncValue.loading()) {
    _load();
  }

  final StorageService _storage;

  Future<void> _load() async {
    try {
      final list = _storage.getMedicines();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(Medicine medicine) async {
    final list = state.valueOrNull ?? [];
    final updated = [...list, medicine];
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    _scheduleNotificationsInBackground(medicine);
  }

  Future<void> update(Medicine medicine) async {
    final list = state.valueOrNull ?? [];
    final updated = list.map((m) => m.id == medicine.id ? medicine : m).toList();
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    _scheduleNotificationsInBackground(medicine);
  }

  void _scheduleNotificationsInBackground(Medicine medicine) {
    Future.microtask(() async {
      try {
        await NotificationService.scheduleForMedicine(medicine);
      } catch (_) {
        // Notifications may fail on some platforms (e.g. macOS)
      }
    });
  }

  Future<void> delete(String id) async {
    final list = state.valueOrNull ?? [];
    final updated = list.where((m) => m.id != id).toList();
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    Future.microtask(() async {
      try {
        await NotificationService.cancelForMedicine(id);
      } catch (_) {
        // Notification cancel may fail on some platforms (e.g. macOS)
      }
    });
  }

  Future<void> refresh() => _load();
}
