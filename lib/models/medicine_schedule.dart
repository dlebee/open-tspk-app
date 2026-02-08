import 'package:uuid/uuid.dart';

import 'medicine.dart';

const _uuid = Uuid();

class MedicineSchedule {
  final String id;
  final Eye eye;
  final List<int> daysOfWeek; // 1=Mon, 7=Sun
  final List<String> times; // "HH:mm"

  MedicineSchedule({
    String? id,
    required this.eye,
    required this.daysOfWeek,
    required this.times,
  }) : id = id ?? _uuid.v4();

  MedicineSchedule copyWith({
    String? id,
    Eye? eye,
    List<int>? daysOfWeek,
    List<String>? times,
  }) {
    return MedicineSchedule(
      id: id ?? this.id,
      eye: eye ?? this.eye,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      times: times ?? this.times,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'eye': eye.name,
        'daysOfWeek': daysOfWeek,
        'times': times,
      };

  factory MedicineSchedule.fromJson(Map<String, dynamic> json) =>
      MedicineSchedule(
        id: json['id'] as String? ?? _uuid.v4(),
        eye: Eye.values.firstWhere(
          (e) => e.name == json['eye'],
          orElse: () => Eye.both,
        ),
        daysOfWeek: List<int>.from(json['daysOfWeek'] as List),
        times: List<String>.from(json['times'] as List),
      );
}
