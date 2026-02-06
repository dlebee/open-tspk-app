import 'package:flutter/material.dart';

enum PainLevel { terrible, bad, medium, low }

/// Color for each pain level (worse = more intense). null = no pain.
Color painLevelColor(PainLevel? level) {
  return switch (level) {
    null => Colors.grey,
    PainLevel.low => Colors.green,
    PainLevel.medium => Colors.amber,
    PainLevel.bad => Colors.deepOrange,
    PainLevel.terrible => Colors.red.shade800,
  };
}

extension FlareUpPainLevels on FlareUp {
  PainLevel? get leftLevel => leftEye ? (leftPainLevel ?? PainLevel.low) : null;
  PainLevel? get rightLevel => rightEye ? (rightPainLevel ?? PainLevel.low) : null;
  bool get leftHasPain => leftEye;
  bool get rightHasPain => rightEye;
}

class FlareUp {
  final String id;
  final DateTime date;
  final bool leftEye;
  final bool rightEye;
  final PainLevel? leftPainLevel;
  final PainLevel? rightPainLevel;
  final String? reason;
  final String? comment;

  FlareUp({
    required this.id,
    required this.date,
    required this.leftEye,
    required this.rightEye,
    this.leftPainLevel,
    this.rightPainLevel,
    this.reason,
    this.comment,
  });

  FlareUp copyWith({
    String? id,
    DateTime? date,
    bool? leftEye,
    bool? rightEye,
    PainLevel? leftPainLevel,
    PainLevel? rightPainLevel,
    String? reason,
    String? comment,
  }) {
    return FlareUp(
      id: id ?? this.id,
      date: date ?? this.date,
      leftEye: leftEye ?? this.leftEye,
      rightEye: rightEye ?? this.rightEye,
      leftPainLevel: leftPainLevel ?? this.leftPainLevel,
      rightPainLevel: rightPainLevel ?? this.rightPainLevel,
      reason: reason ?? this.reason,
      comment: comment ?? this.comment,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'leftEye': leftEye,
        'rightEye': rightEye,
        'leftPainLevel': leftPainLevel?.name,
        'rightPainLevel': rightPainLevel?.name,
        'reason': reason,
        'comment': comment,
      };

  factory FlareUp.fromJson(Map<String, dynamic> json) => FlareUp(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        leftEye: json['leftEye'] as bool,
        rightEye: json['rightEye'] as bool,
        leftPainLevel: json['leftPainLevel'] != null
            ? PainLevel.values.firstWhere(
                (e) => e.name == json['leftPainLevel'],
                orElse: () => PainLevel.medium,
              )
            : null,
        rightPainLevel: json['rightPainLevel'] != null
            ? PainLevel.values.firstWhere(
                (e) => e.name == json['rightPainLevel'],
                orElse: () => PainLevel.medium,
              )
            : null,
        reason: json['reason'] as String?,
        comment: json['comment'] as String?,
      );
}
