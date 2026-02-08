import 'package:uuid/uuid.dart';

import 'medicine_schedule.dart';

const _uuid = Uuid();

enum Eye { left, right, both, other }

class Medicine {
  final String id;
  final String name;
  final List<MedicineSchedule> schedules;
  final DateTime createdAt;

  Medicine({
    String? id,
    required this.name,
    required this.schedules,
    required this.createdAt,
  }) : id = id ?? _uuid.v4();

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
        id: json['id'] as String? ?? _uuid.v4(),
        name: json['name'] as String,
        schedules: (json['schedules'] as List)
            .map((s) => MedicineSchedule.fromJson(s as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
