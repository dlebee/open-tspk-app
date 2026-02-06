import 'medicine.dart';

class MedicineSchedule {
  final Eye eye;
  final List<int> daysOfWeek; // 1=Mon, 7=Sun
  final List<String> times; // "HH:mm"

  MedicineSchedule({
    required this.eye,
    required this.daysOfWeek,
    required this.times,
  });

  MedicineSchedule copyWith({
    Eye? eye,
    List<int>? daysOfWeek,
    List<String>? times,
  }) {
    return MedicineSchedule(
      eye: eye ?? this.eye,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      times: times ?? this.times,
    );
  }

  Map<String, dynamic> toJson() => {
        'eye': eye.name,
        'daysOfWeek': daysOfWeek,
        'times': times,
      };

  factory MedicineSchedule.fromJson(Map<String, dynamic> json) =>
      MedicineSchedule(
        eye: Eye.values.firstWhere(
          (e) => e.name == json['eye'],
          orElse: () => Eye.both,
        ),
        daysOfWeek: List<int>.from(json['daysOfWeek'] as List),
        times: List<String>.from(json['times'] as List),
      );
}
