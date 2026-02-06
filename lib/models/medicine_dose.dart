import 'medicine.dart';

enum DoseStatus { taken, skipped }

class MedicineDose {
  final String id;
  final String medicineId;
  final Eye eye;
  final DoseStatus status;
  final DateTime recordedAt;
  final DateTime? scheduledDate;
  final String? scheduledTime; // "HH:mm"
  final DateTime? takenAt;

  MedicineDose({
    required this.id,
    required this.medicineId,
    required this.eye,
    required this.status,
    required this.recordedAt,
    this.scheduledDate,
    this.scheduledTime,
    this.takenAt,
  });

  MedicineDose copyWith({
    String? id,
    String? medicineId,
    Eye? eye,
    DoseStatus? status,
    DateTime? recordedAt,
    DateTime? scheduledDate,
    String? scheduledTime,
    DateTime? takenAt,
  }) {
    return MedicineDose(
      id: id ?? this.id,
      medicineId: medicineId ?? this.medicineId,
      eye: eye ?? this.eye,
      status: status ?? this.status,
      recordedAt: recordedAt ?? this.recordedAt,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      takenAt: takenAt ?? this.takenAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineId': medicineId,
        'eye': eye.name,
        'status': status.name,
        'recordedAt': recordedAt.toIso8601String(),
        'scheduledDate': scheduledDate?.toIso8601String(),
        'scheduledTime': scheduledTime,
        'takenAt': takenAt?.toIso8601String(),
      };

  factory MedicineDose.fromJson(Map<String, dynamic> json) => MedicineDose(
        id: json['id'] as String,
        medicineId: json['medicineId'] as String,
        eye: Eye.values.firstWhere(
          (e) => e.name == json['eye'],
          orElse: () => Eye.both,
        ),
        status: DoseStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DoseStatus.taken,
        ),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        scheduledDate: json['scheduledDate'] != null
            ? DateTime.parse(json['scheduledDate'] as String)
            : null,
        scheduledTime: json['scheduledTime'] as String?,
        takenAt: json['takenAt'] != null
            ? DateTime.parse(json['takenAt'] as String)
            : null,
      );
}
