class AppointmentNote {
  final String id;
  final DateTime date;
  final String doctorOffice;
  final String notes;

  AppointmentNote({
    required this.id,
    required this.date,
    required this.doctorOffice,
    required this.notes,
  });

  AppointmentNote copyWith({
    String? id,
    DateTime? date,
    String? doctorOffice,
    String? notes,
  }) {
    return AppointmentNote(
      id: id ?? this.id,
      date: date ?? this.date,
      doctorOffice: doctorOffice ?? this.doctorOffice,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'doctorOffice': doctorOffice,
        'notes': notes,
      };

  factory AppointmentNote.fromJson(Map<String, dynamic> json) =>
      AppointmentNote(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        doctorOffice: json['doctorOffice'] as String,
        notes: json['notes'] as String,
      );
}
