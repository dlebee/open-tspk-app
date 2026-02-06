import 'appointment_note.dart';
import 'flare_up.dart';
import 'medicine_dose.dart';

enum ActivityType { dose, flareUp, appointment }

class ActivityItem {
  final ActivityType type;
  final DateTime date;
  final String id;
  final String title;
  final String? subtitle;
  final MedicineDose? dose;
  final FlareUp? flareUp;
  final AppointmentNote? appointment;

  const ActivityItem({
    required this.type,
    required this.date,
    required this.id,
    required this.title,
    this.subtitle,
    this.dose,
    this.flareUp,
    this.appointment,
  });

  factory ActivityItem.fromDose(MedicineDose d, String medicineName) {
    final dt = d.takenAt ?? d.recordedAt;
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final isScheduled = d.scheduledDate != null && d.scheduledTime != null;
    final sub = isScheduled
        ? 'Scheduled • Taken at $timeStr'
        : 'Ad-hoc • $timeStr';
    return ActivityItem(
      type: ActivityType.dose,
      date: dt,
      id: d.id,
      title: '$medicineName - ${d.eye.name}',
      subtitle: sub,
      dose: d,
    );
  }

  factory ActivityItem.fromFlareUp(FlareUp f) {
    final eyes = <String>[];
    if (f.leftEye) eyes.add('Left');
    if (f.rightEye) eyes.add('Right');
    final eyeStr = eyes.join(', ');
    return ActivityItem(
      type: ActivityType.flareUp,
      date: f.date,
      id: f.id,
      title: 'Flare-up',
      subtitle: eyeStr.isNotEmpty ? eyeStr : null,
      flareUp: f,
    );
  }

  factory ActivityItem.fromAppointment(AppointmentNote a) {
    return ActivityItem(
      type: ActivityType.appointment,
      date: a.date,
      id: a.id,
      title: a.doctorOffice,
      subtitle: a.notes,
      appointment: a,
    );
  }
}
