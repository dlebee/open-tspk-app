import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class AppointmentNote {
  final String id;
  final DateTime date;
  final String doctorOffice;
  final String notes;
  final String? calendarEventId;

  AppointmentNote({
    String? id,
    required this.date,
    required this.doctorOffice,
    required this.notes,
    this.calendarEventId,
  }) : id = id ?? _uuid.v4();

  AppointmentNote copyWith({
    String? id,
    DateTime? date,
    String? doctorOffice,
    String? notes,
    String? calendarEventId,
  }) {
    return AppointmentNote(
      id: id ?? this.id,
      date: date ?? this.date,
      doctorOffice: doctorOffice ?? this.doctorOffice,
      notes: notes ?? this.notes,
      calendarEventId: calendarEventId ?? this.calendarEventId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'doctorOffice': doctorOffice,
        'notes': notes,
        if (calendarEventId != null) 'calendarEventId': calendarEventId,
      };

  factory AppointmentNote.fromJson(Map<String, dynamic> json) => AppointmentNote(
        id: json['id'] as String? ?? _uuid.v4(),
        date: DateTime.parse(json['date'] as String),
        doctorOffice: json['doctorOffice'] as String,
        notes: json['notes'] as String,
        calendarEventId: json['calendarEventId'] as String?,
      );
}
