// Flutter 3.24 / Dart 3.5 — 高级暗调主题
// 参考：Nothing Phone × Linear × 高端腕表App
// 克制、精致、毛玻璃质感、哑铜金点缀
import 'package:flutter/material.dart';

class C {
  C._();

  // ═══════════════════════════════════════════
  // Light — 暖灰白底
  // ═══════════════════════════════════════════
  static const _bg      = Color(0xFFF5F4F1);  // 暖灰白
  static const _surface = Color(0xFFFFFFFF);  // 纯白卡面
  static const _card    = Color(0xFFF8F7F5);  // 微暖卡底
  static const _border  = Color(0xFFE5E3DE);  // 极淡暖灰线
  static const _borderStrong = Color(0xFFD5D2CC);

  static const _accent  = Color(0xFFB8935D);  // 哑铜金（点缀色）
  static const _accentDim = Color(0xFFD4C4A8); // 浅金（hover态）

  static const _text   = Color(0xFF1C1B1F);  // 近黑
  static const _text2  = Color(0xFF6B6760);  // 暖灰辅文
  static const _text3  = Color(0xFF9B968F);  // 浅灰 placeholder

  static const _error  = Color(0xFFD95555);  // 柔红

  // 兼容旧代码：scheme 返回亮色方案，新代码用 schemeOf(context)
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: _accent,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF5EFE5),
    onPrimaryContainer: Color(0xFF3D2E1A),
    secondary: Color(0xFFF5F4F1),
    onSecondary: _text,
    surface: _surface,
    onSurface: _text,
    surfaceContainerHighest: _card,
    onSurfaceVariant: _text2,
    outline: _border,
    outlineVariant: _borderStrong,
    error: _error,
    onError: Color(0xFFFFFFFF),
  );

  // 间距
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s20 = 20.0, s24 = 24.0, s32 = 32.0;
  // 圆角 — 克制（6-14dp，不做大圆角可爱风）
  static const r4 = 4.0, r6 = 6.0, r8 = 8.0, r10 = 10.0, r12 = 12.0, r14 = 14.0, r16 = 16.0;

  // ═══════════════════════════════════════════
  // 排版 — 上下文感知（自动适配亮/暗色主题）
  // ═══════════════════════════════════════════
  static const _f = 'YaHei';

  static ColorScheme schemeOf(BuildContext context) => Theme.of(context).colorScheme;

  static TextStyle h1(BuildContext context) => TextStyle(fontFamily: _f, fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: Theme.of(context).colorScheme.onSurface, height: 1.3);
  static TextStyle h2(BuildContext context) => TextStyle(fontFamily: _f, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: Theme.of(context).colorScheme.onSurface, height: 1.35);
  static TextStyle title(BuildContext context) => TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: Theme.of(context).colorScheme.onSurface, height: 1.4);
  static TextStyle body(BuildContext context) => TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.1, color: Theme.of(context).colorScheme.onSurface, height: 1.55);
  static TextStyle caption(BuildContext context) => TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.0, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45);
  static TextStyle label(BuildContext context) => TextStyle(fontFamily: _f, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.3, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6));

  // ═══════════════════════════════════════════
  // Dark — 深炭灰底（默认）
  // ═══════════════════════════════════════════
  static const _dBg      = Color(0xFF212124);  // 深炭灰（比纯黑舒适）
  static const _dSurface = Color(0xFF28282C);  // 微亮面
  static const _dCard    = Color(0xFF2E2E32);  // 卡片
  static const _dBorder  = Color(0xFF3A3A3E);  // 隐线
  static const _dBorderStrong = Color(0xFF4A4A4E);

  static const _dAccent  = Color(0xFFB8935D);  // 哑铜金
  static const _dAccentDim = Color(0xFF9A7B4A); // 暗金

  static const _dText  = Color(0xFFE4DFD8);  // 暖白（~12:1 对比度）
  static const _dText2 = Color(0xFF8B857D);  // 暖灰辅文（~5:1）
  static const _dText3 = Color(0xFF5E5A54);  // 暗灰 placeholder

  static const _dError = Color(0xFFE05555);  // 柔红

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _dAccent,
    onPrimary: Color(0xFF212124),
    primaryContainer: Color(0xFF3D2E1A),
    onPrimaryContainer: Color(0xFFE4DFD8),
    secondary: Color(0xFF2E2E32),
    onSecondary: _dText,
    surface: _dSurface,
    onSurface: _dText,
    surfaceContainerHighest: _dCard,
    onSurfaceVariant: _dText2,
    outline: _dBorder,
    outlineVariant: _dBorderStrong,
    error: _dError,
    onError: Color(0xFF212124),
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
      elevation: 0, scrolledUnderElevation: 0.5,
      titleTextStyle: TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: _text),
      iconTheme: IconThemeData(color: _text2, size: 22),
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: _surface),
    dividerTheme: const DividerThemeData(color: _border, thickness: 1, space: 0),

    // 卡片：极细边框 + 微阴影（克制）
    cardTheme: CardThemeData(
      color: _surface,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r8),
        side: const BorderSide(color: _border, width: 1),
      ),
    ),

    // 输入框：细线框
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r8), borderSide: const BorderSide(color: _border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r8), borderSide: const BorderSide(color: _border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r8), borderSide: const BorderSide(color: _accent, width: 1.5)),
      hintStyle: const TextStyle(fontFamily: _f, fontSize: 15, color: _text3),
    ),

    // 按钮：克制金
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r8)),
      textStyle: const TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.1),
    )),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _accent, foregroundColor: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r8)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: _card,
      labelStyle: const TextStyle(fontFamily: _f, fontSize: 13, color: _text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r8), side: const BorderSide(color: _border)),
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
      elevation: 0, scrolledUnderElevation: 0.5,
      titleTextStyle: TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: _dText),
      iconTheme: IconThemeData(color: _dText2, size: 22),
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: _dSurface),
    dividerTheme: const DividerThemeData(color: _dBorder, thickness: 1, space: 0),

    cardTheme: CardThemeData(
      color: _dCard,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r8),
        side: const BorderSide(color: _dBorder, width: 1),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: _dCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r8), borderSide: const BorderSide(color: _dBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r8), borderSide: const BorderSide(color: _dBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r8), borderSide: const BorderSide(color: _dAccent, width: 1.5)),
      hintStyle: const TextStyle(fontFamily: _f, fontSize: 15, color: _dText3),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      backgroundColor: _dAccent, foregroundColor: Colors.black, elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r8)),
      textStyle: const TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.1),
    )),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _dAccent, foregroundColor: Colors.black,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r8)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: _dCard,
      labelStyle: const TextStyle(fontFamily: _f, fontSize: 13, color: _dText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r8), side: const BorderSide(color: _dBorder)),
    ),

    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
