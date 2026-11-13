import 'package:flutter/material.dart';

/// "Dusk" palette: warm, low-glare dark UI for light-sensitive eyes.
/// No pure white and no pure black; one warm amber accent.
class Dusk {
  Dusk._();

  static const bg = Color(0xFF1C1B19);
  static const surface = Color(0xFF262420);
  static const surfaceHigh = Color(0xFF2E2C28);
  static const border = Color(0xFF3A3731);

  static const text = Color(0xFFEDE8DC);
  static const textSecondary = Color(0xFFA39E92);
  static const textMuted = Color(0xFF7A756B);

  static const amber = Color(0xFFD9A35B);
  static const amberSoft = Color(0xFF3B3328);
  static const amberBorder = Color(0xFF6B5432);
  static const onAmber = Color(0xFF1C1B19);

  static const rose = Color(0xFFD9776A);
  static const roseSoft = Color(0xFF3A2724);
  static const sage = Color(0xFF9DB58F);
  static const sageSoft = Color(0xFF2A3026);
}

ThemeData buildDuskTheme({bool highContrast = false}) {
  final text = highContrast ? const Color(0xFFF7F3EA) : Dusk.text;
  final textSecondary = highContrast ? const Color(0xFFCFC9BC) : Dusk.textSecondary;
  final border = highContrast ? const Color(0xFF5A564D) : Dusk.border;

  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Dusk.amber,
    onPrimary: Dusk.onAmber,
    primaryContainer: Dusk.amberSoft,
    onPrimaryContainer: Dusk.amber,
    secondary: Dusk.sage,
    onSecondary: Dusk.onAmber,
    secondaryContainer: Dusk.sageSoft,
    onSecondaryContainer: Dusk.sage,
    tertiary: Dusk.rose,
    onTertiary: Dusk.onAmber,
    error: Dusk.rose,
    onError: Dusk.onAmber,
    errorContainer: Dusk.roseSoft,
    onErrorContainer: Dusk.rose,
    surface: Dusk.bg,
    onSurface: text,
    onSurfaceVariant: textSecondary,
    surfaceContainerLowest: Dusk.bg,
    surfaceContainerLow: Dusk.surface,
    surfaceContainer: Dusk.surface,
    surfaceContainerHigh: Dusk.surfaceHigh,
    surfaceContainerHighest: Dusk.surfaceHigh,
    outline: border,
    outlineVariant: border,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  final textTheme = base.textTheme.apply(bodyColor: text, displayColor: text).copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: text,
          letterSpacing: -0.5,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: text),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: text),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: textSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  return base.copyWith(
    scaffoldBackgroundColor: Dusk.bg,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Dusk.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: Dusk.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: rounded,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: textSecondary,
      textColor: text,
      shape: rounded,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 0.5, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: Dusk.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Dusk.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Dusk.textMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Dusk.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Dusk.amberSoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Dusk.amber : Dusk.textMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? Dusk.amber : Dusk.textMuted,
          )),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Dusk.amber,
      foregroundColor: Dusk.onAmber,
      elevation: 0,
      highlightElevation: 0,
      shape: CircleBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Dusk.amber,
        foregroundColor: Dusk.onAmber,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Dusk.amber),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Dusk.surfaceHigh,
      side: BorderSide(color: border),
      labelStyle: TextStyle(color: text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Dusk.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Dusk.amber),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Dusk.surfaceHigh,
      contentTextStyle: TextStyle(color: text),
      actionTextColor: Dusk.amber,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
