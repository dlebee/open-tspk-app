import 'package:flutter/material.dart';

import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../theme/dusk_theme.dart';

/// How an eye feels, as shown in the check-in. Maps onto the stored [PainLevel].
enum EyeFeel { calm, gritty, sore, flaring }

extension EyeFeelX on EyeFeel {
  String get label => switch (this) {
        EyeFeel.calm => 'Calm',
        EyeFeel.gritty => 'Gritty',
        EyeFeel.sore => 'Sore',
        EyeFeel.flaring => 'Flaring',
      };

  /// Fill used on the Journey month grid.
  Color get tone => switch (this) {
        EyeFeel.calm => const Color(0xFF3A4535),
        EyeFeel.gritty => const Color(0xFF5E4C30),
        EyeFeel.sore => const Color(0xFFB88A4C),
        EyeFeel.flaring => const Color(0xFFE08A7C),
      };

  /// Foreground for pills and selected buttons.
  Color get fg => switch (this) {
        EyeFeel.calm => Dusk.sage,
        EyeFeel.gritty => const Color(0xFFC9A774),
        EyeFeel.sore => Dusk.amber,
        EyeFeel.flaring => Dusk.rose,
      };

  Color get bg => switch (this) {
        EyeFeel.calm => Dusk.sageSoft,
        EyeFeel.gritty => const Color(0xFF332C22),
        EyeFeel.sore => Dusk.amberSoft,
        EyeFeel.flaring => Dusk.roseSoft,
      };

  PainLevel? get painLevel => switch (this) {
        EyeFeel.calm => null,
        EyeFeel.gritty => PainLevel.low,
        EyeFeel.sore => PainLevel.medium,
        EyeFeel.flaring => PainLevel.bad,
      };

  bool get isFlare => index >= EyeFeel.sore.index;
}

EyeFeel feelFromPain(bool affected, PainLevel? level) {
  if (!affected) return EyeFeel.calm;
  return switch (level) {
    null || PainLevel.low => EyeFeel.gritty,
    PainLevel.medium => EyeFeel.sore,
    PainLevel.bad || PainLevel.terrible => EyeFeel.flaring,
  };
}

extension FlareUpFeel on FlareUp {
  EyeFeel get leftFeel => feelFromPain(leftEye, leftPainLevel);
  EyeFeel get rightFeel => feelFromPain(rightEye, rightPainLevel);
  bool get isFlare => leftFeel.isFlare || rightFeel.isFlare;
}

EyeFeel worse(EyeFeel a, EyeFeel b) => a.index >= b.index ? a : b;

String eyeLabel(Eye eye) => switch (eye) {
      Eye.left => 'Left eye',
      Eye.right => 'Right eye',
      Eye.both => 'Both eyes',
      Eye.other => 'Pill / other',
    };

String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// How long ago a scheduled time was, for a drop that hasn't been logged yet:
/// "5 min late", "2 h late", "2 h 10 min late". Missing the time is not skipping.
String lateBy(DateTime day, String hhmm, [DateTime? now]) {
  final mins = (now ?? DateTime.now()).difference(atTime(day, hhmm)).inMinutes;
  if (mins < 60) return '${mins < 1 ? 1 : mins} min late';
  final h = mins ~/ 60, m = mins % 60;
  if (h >= 24) return h >= 48 ? '${h ~/ 24} days late' : 'a day late';
  return m == 0 || h >= 3 ? '$h h late' : '$h h $m min late';
}

DateTime atTime(DateTime day, String hhmm) {
  final p = hhmm.split(':');
  return DateTime(
    day.year,
    day.month,
    day.day,
    int.tryParse(p[0]) ?? 0,
    p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
  );
}

const headingFont = TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.6);

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: Dusk.textSecondary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A rounded tappable surface used for cards and rows.
class DuskTile extends StatelessWidget {
  const DuskTile({
    super.key,
    required this.child,
    this.onTap,
    this.color = Dusk.surface,
    this.border,
    this.radius = 16,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Color? border;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border == null ? BorderSide.none : BorderSide(color: border!),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Dusk.surface,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 20, color: Dusk.textSecondary),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.fg, required this.bg});

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Full-width primary button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Screen scaffold with a back button and a big title.
class DuskPage extends StatelessWidget {
  const DuskPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.leadingIcon = Icons.arrow_back_ios_new,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? bottom;
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  RoundIconButton(
                    icon: leadingIcon,
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  ...actions,
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(title, style: headingFont.copyWith(fontSize: 32, color: Dusk.text)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: const TextStyle(fontSize: 15, color: Dusk.textSecondary)),
                  ],
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
            if (bottom != null)
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: bottom),
          ],
        ),
      ),
    );
  }
}

void showDuskSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
