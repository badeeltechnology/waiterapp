import 'package:flutter/material.dart';

/// Nami design tokens, shared with the desktop till.
class Nami {
  Nami._();

  static const deep = Color(0xFF0B3B49);
  static const rail = Color(0xFF0E4A5B);
  static const cream = Color(0xFFF4EFE6);
  static const amber = Color(0xFFF4A52A);
  static const amberText = Color(0xFF6B4300);
  static const teal = Color(0xFF0E6E86);
  static const red = Color(0xFFC83E2E);
  static const green = Color(0xFF1F7A47);
  static const line = Color(0xFFE6E1D6);
  static const lineStrong = Color(0xFFCBC5B8);
  static const muted = Color(0xFF5C6167);
  static const ink = Color(0xFF1B1F24);
  static const onDeepMuted = Color(0xFF9DBAC3);
  static const onDeep = Color(0xFFD8E6EA);
  static const white = Color(0xFFFFFFFF);
  static const purple = Color(0xFF7C5CBF);

  static const bodyFont = 'Readex Pro';
  static const numFont = 'Barlow Condensed';

  static const radius = 6.0;
  static const tapMin = 48.0;

  static const cardShadow = [BoxShadow(color: Color(0x1F3C2D14), blurRadius: 2, offset: Offset(0, 1))];

  /// Condensed numeric / heading style.
  static TextStyle num(double size, {FontWeight weight = FontWeight.w700, Color? color}) => TextStyle(
    fontFamily: numFont,
    // Barlow has no Arabic glyphs: Arabic words fall back to Readex Pro.
    fontFamilyFallback: const [bodyFont],
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
    height: 1.1,
  );

  /// Small uppercase caption used for section labels.
  static const cap = TextStyle(fontFamily: bodyFont, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: muted);

  static ThemeData theme() {
    final scheme = const ColorScheme.light(
      primary: deep,
      onPrimary: white,
      secondary: amber,
      onSecondary: ink,
      tertiary: teal,
      error: red,
      surface: white,
      onSurface: ink,
      surfaceContainerHighest: cream,
      outline: lineStrong,
      outlineVariant: line,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: bodyFont,
      scaffoldBackgroundColor: cream,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            bodyMedium: const TextStyle(fontSize: 15, color: ink),
            bodyLarge: const TextStyle(fontSize: 16, color: ink),
            titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
            labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          )
          .apply(fontFamily: bodyFont),
      appBarTheme: const AppBarTheme(
        backgroundColor: deep,
        foregroundColor: white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: numFont, fontFamilyFallback: [bodyFont], fontSize: 24, fontWeight: FontWeight.w700, color: white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: ink,
          disabledBackgroundColor: line,
          minimumSize: const Size(tapMin, 56),
          shape: shape,
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(tapMin, 52),
          side: const BorderSide(color: lineStrong, width: 1.5),
          shape: shape,
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: teal,
          minimumSize: const Size(tapMin, tapMin),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: teal, width: 2),
        ),
        labelStyle: const TextStyle(color: muted),
      ),
      cardTheme: CardThemeData(color: white, elevation: 0, margin: EdgeInsets.zero, shape: shape),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: deep,
        indicatorColor: rail,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: s.contains(WidgetState.selected) ? white : onDeepMuted),
        ),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? amber : onDeepMuted, size: 26)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(fontFamily: bodyFont, fontSize: 15, color: white),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cream,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      ),
      dialogTheme: DialogThemeData(backgroundColor: white, shape: shape),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? teal : null),
      ),
    );
  }
}
