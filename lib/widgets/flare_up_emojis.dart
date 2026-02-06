import 'package:flutter/material.dart';

import '../models/flare_up.dart';
import 'eye_pain_icon.dart';

/// Displays left and right eye icons with colors indicating pain level.
class FlareUpEyes extends StatelessWidget {
  const FlareUpEyes({super.key, required this.flareUp, this.size = 24});

  final FlareUp flareUp;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EyePainIcon(
          level: flareUp.leftLevel,
          size: size,
          flip: true,
        ),
        SizedBox(width: size > 22 ? 6 : 4),
        EyePainIcon(
          level: flareUp.rightLevel,
          size: size,
          flip: false,
        ),
      ],
    );
  }
}
