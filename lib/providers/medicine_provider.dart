import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../models/medicine_dose.dart';
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
      // Schedule notifications for all medicines when loading
      // This is necessary on initial load to ensure notifications are set up
      if (list.isNotEmpty) {
        print('[MedicineProvider] Initial load: scheduling notifications for ${list.length} medicine(s)');
        _scheduleAllNotificationsInBackground(list);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _scheduleAllNotificationsInBackground(List<Medicine> medicines) {
    print('[MedicineProvider] Scheduling notifications for ${medicines.length} medicine(s) in background');
    Future.microtask(() async {
      for (final medicine in medicines) {
        try {
          await NotificationService.scheduleForMedicine(medicine);
        } catch (e, stackTrace) {
          // Log error but continue with other medicines
          print('[MedicineProvider] ✗ Failed to schedule notifications for medicine ${medicine.id}: $e');
          print('[MedicineProvider] Stack trace: $stackTrace');
        }
      }
      print('[MedicineProvider] Completed background notification scheduling');
    });
  }

  Future<void> add(Medicine medicine) async {
    final list = state.valueOrNull ?? [];
    final updated = [...list, medicine];
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    _scheduleNotificationsInBackground(medicine);
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
    final list = state.valueOrNull ?? [];
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
      print('[MedicineProvider] Schedules changed for medicine ${medicine.name}, rescheduling notifications');
      _scheduleNotificationsInBackground(medicine);
    } else {
      print('[MedicineProvider] Schedules unchanged for medicine ${medicine.name}, skipping notification rescheduling');
    }
  }

  void _scheduleNotificationsInBackground(Medicine medicine) {
    print('[MedicineProvider] Scheduling notifications for medicine: ${medicine.name} (ID: ${medicine.id})');
    Future.microtask(() async {
      try {
        await NotificationService.scheduleForMedicine(medicine);
      } catch (e, stackTrace) {
        // Log error for debugging - notifications may fail on some platforms (e.g. macOS)
        print('[MedicineProvider] ✗ Failed to schedule notifications for medicine ${medicine.id}: $e');
        print('[MedicineProvider] Stack trace: $stackTrace');
      }
    });
  }

  Future<void> delete(String id) async {
    final list = state.valueOrNull ?? [];
    // Get the medicine before deleting it so we can cancel its notifications efficiently
    final medicine = list.firstWhere((m) => m.id == id, orElse: () => Medicine(id: '', name: '', schedules: [], createdAt: DateTime.now()));
    final updated = list.where((m) => m.id != id).toList();
    await _storage.saveMedicines(updated);
    state = AsyncValue.data(updated);
    Future.microtask(() async {
      try {
        // Pass the medicine object if we found it, so cancellation is more efficient
        if (medicine.id.isNotEmpty) {
          await NotificationService.cancelForMedicine(id, medicine: medicine);
        } else {
          await NotificationService.cancelForMedicine(id);
        }
      } catch (_) {
        // Notification cancel may fail on some platforms (e.g. macOS)
      }
    });
  }

  Future<void> refresh() => _load();
}
