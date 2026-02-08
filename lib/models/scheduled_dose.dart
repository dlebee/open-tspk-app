import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'medicine.dart';
import 'medicine_dose.dart';

enum ScheduledDoseStatus { taken, skipped, missed, scheduled }

class ScheduledDose {
  final String id; // Deterministic hash of unique properties
  final String medicineId;
  final String medicineName;
  final Eye eye;
  final DateTime scheduledDate;
  final String scheduledTime; // "HH:mm"
  final ScheduledDoseStatus status;
  final DateTime? takenAt;
  final MedicineDose? dose;

  ScheduledDose({
    String? id,
    required this.medicineId,
    required this.medicineName,
    required this.eye,
    required List<int> daysOfWeek,
    required List<String> times,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.status,
    this.takenAt,
    this.dose,
  }) : id = id ?? _generateId(medicineId, scheduledDate, scheduledTime);

  /// Generate a deterministic hash ID from the unique properties
  static String _generateId(String medicineId, DateTime scheduledDate, String scheduledTime) {
    // Format date as YYYY-MM-DD for consistency
    final dateStr = '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}';
    // Create a unique string from medicineId, date, and time
    final uniqueString = '$medicineId|$dateStr|$scheduledTime';
    // Use full SHA256 hash (64 hex characters)
    final bytes = utf8.encode(uniqueString);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'eye': eye.name,
        'scheduledDate': scheduledDate.toIso8601String(),
        'scheduledTime': scheduledTime,
        'status': status.name,
        if (takenAt != null) 'takenAt': takenAt!.toIso8601String(),
        if (dose != null) 'doseId': dose!.id,
      };
}
