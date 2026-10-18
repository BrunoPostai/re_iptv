import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Palette used by the recreation. Mirrors the dark, gold-accented look of the
/// original application while remaining fully themeable.
class AppColors {
  static const gold = Color(0xFFE0A83C);
  static const orange = Color(0xFFF5821F);
  static const blue = Color(0xFF2C6FBB);
  static const blueDark = Color(0xFF1B4C86);
  static const blueTile = Color(0xFF1F5FA8);
  static const panel = Color(0xE60B1626);
  static const panelAlt = Color(0xF2152740);
  static const sidebar = Color(0xCC0A1420);
  static const divider = Color(0x33FFFFFF);
  static const textPrimary = Color(0xFFE8EFF7);
  static const textMuted = Color(0xFF93A7BE);
  static const red = Color(0xFFD9534F);
  static const green = Color(0xFF3FA25B);
  static const pendant = Color(0xFF00C853);
}

class AppTheme {
  /// Builds the Material theme for the selected [ThemeSpec].
  static ThemeData build(ThemeSpec spec) {
    final accent = Color(spec.accent);
    final base = spec.dark ? ThemeData.dark(useMaterial3: false) : ThemeData.light(useMaterial3: false);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      primaryColor: accent,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: AppColors.gold,
        surface: AppColors.panel,
      ),
      dividerColor: AppColors.divider,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamily: 'Segoe UI',
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.35),
        selectionHandleColor: accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.25)),
        thickness: const WidgetStatePropertyAll(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.panelAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.divider),
        ),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.25),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: accent),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.panelAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.panelAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      ),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.compact,
    );
  }

  /// Window background colour used by `window_manager` before Flutter paints.
  static const windowBackground = Color(0xFF07101C);
}

/// Standard paddings used across screens.
class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}
