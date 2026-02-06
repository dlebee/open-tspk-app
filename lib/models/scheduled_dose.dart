import 'medicine.dart';
import 'medicine_dose.dart';

enum ScheduledDoseStatus { taken, skipped, missed, scheduled }

class ScheduledDose {
  final String medicineId;
  final String medicineName;
  final Eye eye;
  final DateTime scheduledDate;
  final String scheduledTime; // "HH:mm"
  final ScheduledDoseStatus status;
  final DateTime? takenAt;
  final MedicineDose? dose;

  ScheduledDose({
    required this.medicineId,
    required this.medicineName,
    required this.eye,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.status,
    this.takenAt,
    this.dose,
  });
}
