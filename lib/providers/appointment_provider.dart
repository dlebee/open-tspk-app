import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_note.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

final appointmentsProvider = StateNotifierProvider<AppointmentsNotifier, AsyncValue<List<AppointmentNote>>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return AppointmentsNotifier(storage);
});

class AppointmentsNotifier extends StateNotifier<AsyncValue<List<AppointmentNote>>> {
  AppointmentsNotifier(this._storage) : super(const AsyncValue.loading()) {
    _load();
  }

  final StorageService _storage;

  Future<void> _load() async {
    try {
      final list = _storage.getAppointments();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(AppointmentNote note) async {
    final list = state.valueOrNull ?? [];
    final updated = [...list, note];
    await _storage.saveAppointments(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> update(AppointmentNote note) async {
    final list = state.valueOrNull ?? [];
    final updated = list.map((a) => a.id == note.id ? note : a).toList();
    await _storage.saveAppointments(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> delete(String id) async {
    final list = state.valueOrNull ?? [];
    final updated = list.where((a) => a.id != id).toList();
    await _storage.saveAppointments(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> refresh() => _load();
}
