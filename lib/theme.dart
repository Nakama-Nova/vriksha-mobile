import 'package:flutter/material.dart';

/// Colours come from the shared brand tokens (docs/brand/design-tokens.json in the
/// backend repo). Gold is for accents only; body text is brown on a warm surface.
const brandBrown = Color(0xFF5A2A06);
const brandGold = Color(0xFFBF830B);
const surfaceWarm = Color(0xFFFBF6EC);
const textBrown = Color(0xFF3A1B04);
const textMuted = Color(0xFF7A5A3C);

ThemeData brandTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandBrown,
    primary: brandBrown,
    secondary: brandGold,
    surface: surfaceWarm,
    onSurface: textBrown,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surfaceWarm,
    appBarTheme: const AppBarTheme(
      backgroundColor: brandBrown,
      foregroundColor: Colors.white,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: brandBrown,
      foregroundColor: Colors.white,
    ),
  );
}
