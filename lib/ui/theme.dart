import 'package:flutter/material.dart';

/// F-Locker colors (dark theme, teal accent).
class C {
  static const bg = Color(0xFF0F1115);
  static const surface = Color(0xFF191C22);
  static const surface2 = Color(0xFF1F2430);
  static const border = Color(0xFF2E333C);
  static const text = Color(0xFFECEEF2);
  static const muted = Color(0xFF9AA1AD);
  static const muted2 = Color(0xFFC9CED6);
  static const accent = Color(0xFF3DD6B5);
  static const accentBg = Color(0xFF16302B);
  static const accentText = Color(0xFFBDF3E6);
  static const warnBg = Color(0xFF3A2A16);
  static const warnText = Color(0xFFF6D3A8);
  static const danger = Color(0xFFFF8A80);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.accent,
    onPrimary: C.bg,
    secondary: C.accent,
    onSecondary: C.bg,
    surface: C.surface,
    onSurface: C.text,
    error: C.danger,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    appBarTheme: const AppBarTheme(
        backgroundColor: C.bg,
        foregroundColor: C.text,
        elevation: 0,
        scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      labelStyle: const TextStyle(color: C.muted),
      border: border(C.border),
      enabledBorder: border(C.border),
      focusedBorder: border(C.accent, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        minimumSize: const Size(64, 46),
        side: const BorderSide(color: C.border),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
