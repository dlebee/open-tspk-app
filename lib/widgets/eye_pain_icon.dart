import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/flare_up.dart';

/// Single eye icon with color indicating pain level. Use [flip] for left eye.
class EyePainIcon extends StatelessWidget {
  const EyePainIcon({
    super.key,
    required this.level,
    this.size = 28,
    this.flip = false,
  });

  final PainLevel? level;
  final double size;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    final color = painLevelColor(level);
    final opacity = level == null ? 0.25 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(flip ? -1.0 : 1.0, 1.0),
        child: SvgPicture.asset(
          'assets/icons/eye.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}
