import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/dusk_theme.dart';

/// A round button that has to be held down to confirm. A progress ring fills
/// while holding; letting go early cancels. Screen readers get a plain tap.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.onConfirmed,
    this.label = 'Hold to log',
    this.icon = Icons.water_drop_outlined,
    this.size = 168,
    this.duration = const Duration(milliseconds: 900),
  });

  final VoidCallback onConfirmed;
  final String label;
  final IconData icon;
  final double size;
  final Duration duration;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.mediumImpact();
        widget.onConfirmed();
      }
    });

  void _start() {
    HapticFeedback.selectionClick();
    _c.forward();
  }

  void _cancel() {
    if (_c.status != AnimationStatus.completed) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inner = widget.size - 36;
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onConfirmed,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _start(),
        onTapUp: (_) => _cancel(),
        onTapCancel: _cancel,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: widget.size - 8,
                  height: widget.size - 8,
                  child: CircularProgressIndicator(
                    value: _c.value,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    color: Dusk.amber,
                    backgroundColor: Dusk.border,
                  ),
                ),
                Transform.scale(
                  scale: 1 - _c.value * 0.06,
                  child: Container(
                    width: inner,
                    height: inner,
                    decoration: const BoxDecoration(color: Dusk.amber, shape: BoxShape.circle),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.icon, size: 30, color: Dusk.onAmber),
                        const SizedBox(height: 4),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Dusk.onAmber,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
