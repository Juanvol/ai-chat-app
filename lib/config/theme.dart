// Flutter 3.24 / Dart 3.5 — 糯糯 Claymorphism 暖橙主题
// 参考：Duolingo (温馨) + Replika (温暖AI伴侣) + Claymorphism (软3D)
import 'package:flutter/material.dart';

class C {
  C._();

  // ═══════════════════════════════════════════
  // 糯糯 Claymorphism 浅色主题
  // ═══════════════════════════════════════════
  static const _bg = Color(0xFFFFF7ED);        // 暖白背景
  static const _surface = Color(0xFFFFFFFF);    // 纯白卡片面
  static const _card = Color(0xFFFFF0E5);       // 暖橙卡片
  static const _border = Color(0xFFFED7B0);     // 浅橙边框

  static const _accent = Color(0xFFF97316);     // 活力橙主色
  static const _accent2 = Color(0xFFFB923C);    // 浅橙辅色

  static const _text = Color(0xFF5D2E0C);       // 深棕文字
  static const _text2 = Color(0xFF9A7B5C);      // 中棕辅文
  static const _text3 = Color(0xFFC4A890);      // 浅棕 placeholder

  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: _accent,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFEDD5),
    onPrimaryContainer: Color(0xFF7C2D12),
    secondary: _accent2,
    onSecondary: Color(0xFFFFFFFF),
    surface: _surface,
    onSurface: _text,
    surfaceContainerHighest: _card,
    onSurfaceVariant: _text2,
    outline: _border,
    outlineVariant: Color(0xFFFED7B0),
    error: Color(0xFFE5484D),
    onError: Color(0xFFFFFFFF),
  );

  // 间距：4dp 基准
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s20 = 20.0, s24 = 24.0, s32 = 32.0;
  // Claymorphism 圆角：偏大（16-24dp）
  static const r6 = 6.0, r8 = 8.0, r10 = 10.0, r12 = 12.0, r16 = 16.0, r20 = 20.0, r24 = 24.0;

  // 排版 — 保持 YaHei 兼容中文，加粗模拟 Fredoka 可爱感
  static const _f = 'YaHei';
  static TextStyle get h1 => const TextStyle(fontFamily: _f, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: _text, height: 1.35);
  static TextStyle get h2 => const TextStyle(fontFamily: _f, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: _text, height: 1.4);
  static TextStyle get title => const TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: _text, height: 1.45);
  static TextStyle get body => const TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.1, color: _text, height: 1.6);
  static TextStyle get caption => const TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.0, color: _text2, height: 1.5);
  static TextStyle get label => const TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: _text3);

  // ═══════════════════════════════════════════
  // 糯糯 Claymorphism 深色主题
  // ═══════════════════════════════════════════
  static const _dBg = Color(0xFF1F1410);        // 暖黑背景
  static const _dSurface = Color(0xFF2D1F1A);   // 深棕表面
  static const _dCard = Color(0xFF3D2B24);      // 深棕卡片
  static const _dBorder = Color(0xFF5D4A40);    // 深棕边框

  static const _dAccent = Color(0xFFFB923C);    // 浅橙主色（深色模式更亮）
  static const _dAccent2 = Color(0xFFF97316);   // 活力橙辅色

  static const _dText = Color(0xFFFFF0E5);      // 暖白文字
  static const _dText2 = Color(0xFFC4A890);     // 浅棕辅文
  static const _dText3 = Color(0xFF8B6F5C);     // 暗棕 placeholder

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _dAccent,
    onPrimary: Color(0xFF1F1410),
    primaryContainer: Color(0xFF4A2A1A),
    onPrimaryContainer: Color(0xFFFFF0E5),
    secondary: _dAccent2,
    onSecondary: Color(0xFF1F1410),
    surface: _dSurface,
    onSurface: _dText,
    surfaceContainerHighest: _dCard,
    onSurfaceVariant: _dText2,
    outline: _dBorder,
    outlineVariant: Color(0xFF5D4A40),
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF1F1410),
  );

  // ═══════════════════════════════════════════
  // Light Theme
  // ═══════════════════════════════════════════
  static ThemeData get theme => ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: _bg,
    fontFamily: _f,
    visualDensity: VisualDensity.standard,

    appBarTheme: const AppBarTheme(
      backgroundColor: _surface,
      elevation: 0, scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: _text),
      iconTheme: IconThemeData(color: _text2, size: 22),
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: _surface),

    dividerTheme: const DividerThemeData(color: _border, thickness: 1, space: 0),

    // Claymorphism 卡片：大圆角 + 厚边框 + 阴影
    cardTheme: CardThemeData(
      color: _surface,
      elevation: 2,
      shadowColor: _accent.withAlpha(30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r20),
        side: const BorderSide(color: _border, width: 2),
      ),
    ),

    // Claymorphism 输入框：大圆角 + 内阴影感
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r16), borderSide: const BorderSide(color: _border, width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r16), borderSide: const BorderSide(color: _border, width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r16), borderSide: const BorderSide(color: _accent, width: 2.5)),
      hintStyle: const TextStyle(fontFamily: _f, fontSize: 15, color: _text3),
    ),

    // Claymorphism 按钮：胶囊形 + 厚阴影
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: _accent, foregroundColor: Colors.white, elevation: 3,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
      textStyle: const TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.1),
    )),

    // FAB: 大圆角粘泥风格
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _accent, foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
    ),

    // Chips: 圆角胶囊
    chipTheme: ChipThemeData(
      backgroundColor: _card,
      labelStyle: const TextStyle(fontFamily: _f, fontSize: 13, color: _text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20), side: const BorderSide(color: _border)),
    ),

    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );

  // ═══════════════════════════════════════════
  // Dark Theme
  // ═══════════════════════════════════════════
  static ThemeData get darkTheme => ThemeData(
    colorScheme: darkScheme,
    scaffoldBackgroundColor: _dBg,
    fontFamily: _f,
    visualDensity: VisualDensity.standard,

    appBarTheme: const AppBarTheme(
      backgroundColor: _dSurface,
      elevation: 0, scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: _dText),
      iconTheme: IconThemeData(color: _dText2, size: 22),
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: _dSurface),

    dividerTheme: const DividerThemeData(color: _dBorder, thickness: 1, space: 0),

    cardTheme: CardThemeData(
      color: _dCard,
      elevation: 2,
      shadowColor: _dAccent.withAlpha(30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r20),
        side: const BorderSide(color: _dBorder, width: 2),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: _dCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r16), borderSide: const BorderSide(color: _dBorder, width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r16), borderSide: const BorderSide(color: _dBorder, width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r16), borderSide: const BorderSide(color: _dAccent, width: 2.5)),
      hintStyle: const TextStyle(fontFamily: _f, fontSize: 15, color: _dText3),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: _dAccent, foregroundColor: _dBg, elevation: 3,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
      textStyle: const TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.1),
    )),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _dAccent, foregroundColor: _dBg,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: _dCard,
      labelStyle: const TextStyle(fontFamily: _f, fontSize: 13, color: _dText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20), side: const BorderSide(color: _dBorder)),
    ),

    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
