class AppointmentNote {
  final String id;
  final DateTime date;
  final String doctorOffice;
  final String notes;
  final String? calendarEventId;

  AppointmentNote({
    required this.id,
    required this.date,
    required this.doctorOffice,
    required this.notes,
    this.calendarEventId,
  });

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

  factory AppointmentNote.fromJson(Map<String, dynamic> json) {
    // Safely parse calendarEventId (backward compatibility with addedToCalendar)
    String? calendarEventId;
    if (json.containsKey('calendarEventId')) {
      final value = json['calendarEventId'];
      if (value is String && value.isNotEmpty) {
        calendarEventId = value;
      }
    } else if (json.containsKey('addedToCalendar')) {
      // Backward compatibility: if old data has addedToCalendar=true, generate event ID
      final added = json['addedToCalendar'];
      if (added is bool && added == true) {
        // Generate event ID from appointment ID for backward compatibility
        calendarEventId = 'thygeson_appt_${json['id']}';
      }
    }
    
    return AppointmentNote(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      doctorOffice: json['doctorOffice'] as String,
      notes: json['notes'] as String,
      calendarEventId: calendarEventId,
    );
  }
}
