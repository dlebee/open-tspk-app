import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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

  final IStorageService _storage;

  Future<void> _load() async {
    try {
      final list = _storage.getMedicines();
      state = AsyncValue.data(list);
      // Reschedule notifications once on initial load (cancel all + recreate).
      if (list.isNotEmpty) {
        debugPrint('[MedicineProvider] Initial load: scheduling notifications for ${list.length} medicine(s)');
        _rescheduleAllNotificationsInBackground(list);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _rescheduleAllNotificationsInBackground(List<Medicine> medicines) {
    debugPrint('[MedicineProvider] Scheduling notifications for ${medicines.length} medicine(s) in background');
    Future.microtask(() async {
      try {
        await NotificationService.rescheduleAllNotifications(
          storage: _storage,
          medicines: medicines,
        );
      } catch (e, stackTrace) {
        debugPrint('[MedicineProvider] ✗ Failed to reschedule notifications on initial load: $e');
        debugPrint('[MedicineProvider] Stack trace: $stackTrace');
      }
      debugPrint('[MedicineProvider] Completed background notification scheduling');
    });
  }

  Future<void> add(Medicine medicine) async {
    final list = state.value ?? [];
    final updated = [...list, medicine];
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    _rescheduleAllNotificationsInBackground(updated);
  }

  /// Check if schedules changed between two medicines
  bool _schedulesChanged(Medicine oldMedicine, Medicine newMedicine) {
    if (oldMedicine.schedules.length != newMedicine.schedules.length) {
      return true;
    }
    
    // Compare each schedule
    for (var i = 0; i < oldMedicine.schedules.length; i++) {
      final oldSchedule = oldMedicine.schedules[i];
      final newSchedule = newMedicine.schedules[i];
      
      if (oldSchedule.eye != newSchedule.eye ||
          oldSchedule.daysOfWeek.length != newSchedule.daysOfWeek.length ||
          oldSchedule.times.length != newSchedule.times.length) {
        return true;
      }
      
      // Check days of week
      final oldDays = List<int>.from(oldSchedule.daysOfWeek)..sort();
      final newDays = List<int>.from(newSchedule.daysOfWeek)..sort();
      if (oldDays.toString() != newDays.toString()) {
        return true;
      }
      
      // Check times
      final oldTimes = List<String>.from(oldSchedule.times)..sort();
      final newTimes = List<String>.from(newSchedule.times)..sort();
      if (oldTimes.toString() != newTimes.toString()) {
        return true;
      }
    }
    
    return false;
  }

  Future<void> update(Medicine medicine) async {
    final list = state.value ?? [];
    final oldMedicine = list.firstWhere((m) => m.id == medicine.id, orElse: () => medicine);
    
    // Check if schedules changed
    final schedulesChanged = _schedulesChanged(oldMedicine, medicine);
    
    // If medicine name changed, update medicineName in all non-orphaned doses
    if (oldMedicine.name != medicine.name) {
      final doses = _storage.getDoses();
      final updatedDoses = doses.map((d) {
        // Only update if dose references this medicine (not orphaned)
        if (d.medicineId == medicine.id) {
          return d.copyWith(medicineName: medicine.name);
        }
        return d;
      }).toList();
      await _storage.saveDoses(updatedDoses);
      // Note: Doses provider will refresh on next access, or can be invalidated by caller
    }
    
    final updated = list.map((m) => m.id == medicine.id ? medicine : m).toList();
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    
    // Only reschedule notifications if schedules actually changed
    if (schedulesChanged) {
      debugPrint('[MedicineProvider] Schedules changed for medicine ${medicine.name}, rescheduling notifications');
      _rescheduleAllNotificationsInBackground(updated);
    } else {
      debugPrint('[MedicineProvider] Schedules unchanged for medicine ${medicine.name}, skipping notification rescheduling');
    }
  }

  Future<void> delete(String id) async {
    final list = state.value ?? [];
    final updated = list.where((m) => m.id != id).toList();
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    Future.microtask(() async {
      try {
        await NotificationService.rescheduleAllNotifications(
          storage: _storage,
          medicines: updated,
        );
      } catch (_) {
        // Notification cancel may fail on some platforms (e.g. macOS)
      }
    });
  }

  Future<void> refresh() => _load();
}
