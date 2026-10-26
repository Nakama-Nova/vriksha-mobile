import 'package:flutter/material.dart';

/// Brand tokens (docs/brand/design-tokens.json in the backend repo) and the
/// shared look from the generated mobile design: brown app bars, warm surface,
/// outlined cards and chips, serif headings. Gold is for accents only.
const brandBrown = Color(0xFF5A2A06);
const brandGold = Color(0xFFBF830B);
const surfaceWarm = Color(0xFFFBF6EC);
const textBrown = Color(0xFF3A1B04);
const textMuted = Color(0xFF7A5A3C);
const lineColor = Color(0xFFE8DCC8);
const okGreen = Color(0xFF2F7D4F);
const badRed = Color(0xFFB3261E);

/// Headings use Cormorant Garamond when it is installed in the app's fonts, and
/// the phone's serif font otherwise (add the font files to get the exact look).
TextStyle serif(double size, {Color color = textBrown}) => TextStyle(
      fontFamily: 'Cormorant Garamond',
      fontFamilyFallback: const ['serif'],
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: color,
    );

ThemeData brandTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandBrown,
    primary: brandBrown,
    onPrimary: Colors.white,
    secondary: brandGold,
    surface: Colors.white,
    onSurface: textBrown,
    error: badRed,
    outline: lineColor,
  );
  final shape10 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    textTheme: ThemeData.light().textTheme.apply(bodyColor: textBrown, displayColor: textBrown),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: lineColor),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(14),
      labelStyle: const TextStyle(color: textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: lineColor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: lineColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: brandGold, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brandBrown,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: shape10,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: brandBrown,
        side: const BorderSide(color: brandGold, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: shape10,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: brandGold),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: brandBrown,
        selectedForegroundColor: Colors.white,
        foregroundColor: textBrown,
        side: const BorderSide(color: lineColor),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? brandBrown : textMuted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? brandBrown : textMuted,
          )),
    ),
    dividerTheme: const DividerThemeData(color: lineColor),
  );
}
