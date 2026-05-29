// Flutter 3.24 / Dart 3.5 — Chatbox 浅色蓝调主题
import 'package:flutter/material.dart';

class C {
  C._();

  // —— Chatbox 浅色蓝调 ——
  static const _bg = Color(0xFFF8F8FA);
  static const _surface = Color(0xFFFFFFFF);
  static const _card = Color(0xFFF0F0F5);
  static const _border = Color(0xFFE5E5EC);

  static const _accent = Color(0xFF4A90D9);

  static const _text = Color(0xFF1A1A1F);
  static const _text2 = Color(0xFF6B6B75);
  static const _text3 = Color(0xFFA0A0AB);

  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: _accent,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD6E8FB),
    onPrimaryContainer: Color(0xFF0D2847),
    secondary: Color(0xFFF0F0F5),
    onSecondary: Color(0xFF1A1A1F),
    surface: _surface,
    onSurface: _text,
    surfaceContainerHighest: _card,
    onSurfaceVariant: _text2,
    outline: _border,
    outlineVariant: Color(0xFFE5E5EC),
    error: Color(0xFFE53E3E),
    onError: Color(0xFFFFFFFF),
  );

  // 间距：4dp 基准
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s20 = 20.0, s24 = 24.0, s32 = 32.0;
  // 圆角
  static const r6 = 6.0, r8 = 8.0, r10 = 10.0, r12 = 12.0, r16 = 16.0, r20 = 20.0;

  // 排版
  static const _f = 'YaHei';
  static TextStyle get h1 => const TextStyle(fontFamily: _f, fontSize: 25, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: _text, height: 1.35);
  static TextStyle get h2 => const TextStyle(fontFamily: _f, fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: _text, height: 1.4);
  static TextStyle get title => const TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: _text, height: 1.45);
  static TextStyle get body => const TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.1, color: _text, height: 1.6);
  static TextStyle get caption => const TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.0, color: _text2, height: 1.5);
  static TextStyle get label => const TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.3, color: _text3);

  // —— Chatbox 深色蓝调 ——
  static const _dBg = Color(0xFF1E1E2E);
  static const _dSurface = Color(0xFF313244);
  static const _dCard = Color(0xFF45475A);
  static const _dBorder = Color(0xFF585B70);

  static const _dAccent = Color(0xFF89B4FA);

  static const _dText = Color(0xFFCDD6F4);
  static const _dText2 = Color(0xFFA6ADC8);
  static const _dText3 = Color(0xFF6C7086);

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _dAccent,
    onPrimary: Color(0xFF1E1E2E),
    primaryContainer: Color(0xFF1E3A5F),
    onPrimaryContainer: Color(0xFFCDD6F4),
    secondary: _dCard,
    onSecondary: _dText,
    surface: _dSurface,
    onSurface: _dText,
    surfaceContainerHighest: _dCard,
    onSurfaceVariant: _dText2,
    outline: _dBorder,
    outlineVariant: Color(0xFF585B70),
    error: Color(0xFFF38BA8),
    onError: Color(0xFF1E1E2E),
  );

  static ThemeData get theme => ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: _bg,
    fontFamily: _f,
    visualDensity: VisualDensity.standard,

    appBarTheme: const AppBarTheme(
      backgroundColor: _surface,
      elevation: 0, scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: _text),
      iconTheme: IconThemeData(color: _text2, size: 22),
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: _surface),

    dividerTheme: const DividerThemeData(color: _border, thickness: 1, space: 0),

    cardTheme: CardThemeData(color: _card, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r10))),

    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: _card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r10), borderSide: const BorderSide(color: _border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r10), borderSide: const BorderSide(color: _border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r10), borderSide: const BorderSide(color: _accent)),
      hintStyle: const TextStyle(fontFamily: _f, fontSize: 15, color: _text3),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r10)),
      textStyle: const TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.1),
    )),

    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );

  static ThemeData get darkTheme => ThemeData(
    colorScheme: darkScheme,
    scaffoldBackgroundColor: _dBg,
    fontFamily: _f,
    visualDensity: VisualDensity.standard,

    appBarTheme: const AppBarTheme(
      backgroundColor: _dSurface,
      elevation: 0, scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: _dText),
      iconTheme: IconThemeData(color: _dText2, size: 22),
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: _dSurface),

    dividerTheme: const DividerThemeData(color: _dBorder, thickness: 1, space: 0),

    cardTheme: CardThemeData(color: _dCard, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r10))),

    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: _dCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r10), borderSide: const BorderSide(color: _dBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r10), borderSide: const BorderSide(color: _dBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r10), borderSide: const BorderSide(color: _dAccent)),
      hintStyle: const TextStyle(fontFamily: _f, fontSize: 15, color: _dText3),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: _dAccent, foregroundColor: _dBg, elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r10)),
      textStyle: const TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.1),
    )),

    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
