import 'medicine_schedule.dart';

enum Eye { left, right, both, other }

class Medicine {
  final String id;
  final String name;
  final List<MedicineSchedule> schedules;
  final DateTime createdAt;

  Medicine({
    required this.id,
    required this.name,
    required this.schedules,
    required this.createdAt,
  });

  Medicine copyWith({
    String? id,
    String? name,
    List<MedicineSchedule>? schedules,
    DateTime? createdAt,
  }) {
    return Medicine(
      id: id ?? this.id,
      name: name ?? this.name,
      schedules: schedules ?? this.schedules,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'schedules': schedules.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine(
        id: json['id'] as String,
        name: json['name'] as String,
        schedules: (json['schedules'] as List)
            .map((s) => MedicineSchedule.fromJson(s as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
