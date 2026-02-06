import '../../models/appointment_note.dart';
import '../../models/flare_up.dart';
import '../../models/medicine.dart';
import '../../models/medicine_dose.dart';

/// Conflict resolution utilities using last-write-wins strategy
class ConflictResolver {
  /// Merge medicines using last-write-wins based on createdAt timestamp
  static List<Medicine> mergeMedicines(
    List<Medicine> local,
    List<Medicine> remote,
  ) {
    final Map<String, Medicine> merged = {};
    
    // Add all local medicines
    for (final medicine in local) {
      merged[medicine.id] = medicine;
    }
    
    // Merge remote medicines (overwrite if newer)
    for (final medicine in remote) {
      final existing = merged[medicine.id];
      if (existing == null || medicine.createdAt.isAfter(existing.createdAt)) {
        merged[medicine.id] = medicine;
      }
    }
    
    return merged.values.toList();
  }

  /// Merge doses using last-write-wins based on recordedAt timestamp
  static List<MedicineDose> mergeDoses(
    List<MedicineDose> local,
    List<MedicineDose> remote,
  ) {
    final Map<String, MedicineDose> merged = {};
    
    // Add all local doses
    for (final dose in local) {
      merged[dose.id] = dose;
    }
    
    // Merge remote doses (overwrite if newer)
    for (final dose in remote) {
      final existing = merged[dose.id];
      final doseTime = dose.takenAt ?? dose.recordedAt;
      final existingTime = existing?.takenAt ?? existing?.recordedAt;
      
      if (existing == null || 
          (existingTime != null && doseTime.isAfter(existingTime))) {
        merged[dose.id] = dose;
      }
    }
    
    return merged.values.toList();
  }

  /// Merge flare-ups using last-write-wins based on date
  static List<FlareUp> mergeFlareUps(
    List<FlareUp> local,
    List<FlareUp> remote,
  ) {
    final Map<String, FlareUp> merged = {};
    
    // Add all local flare-ups
    for (final flareUp in local) {
      merged[flareUp.id] = flareUp;
    }
    
    // Merge remote flare-ups (overwrite if newer date)
    for (final flareUp in remote) {
      final existing = merged[flareUp.id];
      if (existing == null || flareUp.date.isAfter(existing.date)) {
        merged[flareUp.id] = flareUp;
      }
    }
    
    return merged.values.toList();
  }

  /// Merge appointments using last-write-wins based on date
  static List<AppointmentNote> mergeAppointments(
    List<AppointmentNote> local,
    List<AppointmentNote> remote,
  ) {
    final Map<String, AppointmentNote> merged = {};
    
    // Add all local appointments
    for (final appointment in local) {
      merged[appointment.id] = appointment;
    }
    
    // Merge remote appointments (overwrite if newer date)
    for (final appointment in remote) {
      final existing = merged[appointment.id];
      if (existing == null || appointment.date.isAfter(existing.date)) {
        merged[appointment.id] = appointment;
      }
    }
    
    return merged.values.toList();
  }
}
