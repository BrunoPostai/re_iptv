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

/// The colours a screen actually paints with, taken from the selected theme.
///
/// The original draws everything in one accent — gold headings, orange labels,
/// blue buttons — and every one of those was a constant, so choosing a theme
/// changed the picture behind an otherwise unchanged window. Here they are one
/// accent and the two shades either side of it, and the surfaces are that accent
/// mixed a little way into the dark backdrop, which is what keeps a blue theme
/// cold and a gold one warm.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accent,
    required this.accentBright,
    required this.accentDeep,
    required this.panel,
    required this.panelAlt,
    required this.sidebar,
  });

  factory AppPalette.from(ThemeSpec spec) {
    final accent = Color(spec.accent);
    Color surface(Color base, double tint, double alpha) => Color.alphaBlend(
          accent.withValues(alpha: tint),
          base,
        ).withValues(alpha: alpha);
    return AppPalette(
      accent: accent,
      accentBright: Color.lerp(accent, Colors.white, 0.38)!,
      accentDeep: Color.lerp(accent, Colors.black, 0.45)!,
      panel: surface(const Color(0xFF0B1626), 0.18, 0.90),
      panelAlt: surface(const Color(0xFF152740), 0.18, 0.95),
      sidebar: surface(const Color(0xFF0A1420), 0.16, 0.80),
    );
  }

  /// Used by anything drawn outside a `Theme` — the splash before the first
  /// frame, and tests — so a missing extension never means a missing colour.
  static const fallback = AppPalette(
    accent: AppColors.gold,
    accentBright: AppColors.orange,
    accentDeep: AppColors.blueDark,
    panel: AppColors.panel,
    panelAlt: AppColors.panelAlt,
    sidebar: AppColors.sidebar,
  );

  /// Headings, favourite stars, selection and hover: what the original painted
  /// gold.
  final Color accent;

  /// One step lighter, for labels and gradients: what it painted orange.
  final Color accentBright;

  /// One step darker, for the far end of a gradient or a pressed state.
  final Color accentDeep;

  final Color panel;
  final Color panelAlt;
  final Color sidebar;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? fallback;

  @override
  AppPalette copyWith({
    Color? accent,
    Color? accentBright,
    Color? accentDeep,
    Color? panel,
    Color? panelAlt,
    Color? sidebar,
  }) {
    return AppPalette(
      accent: accent ?? this.accent,
      accentBright: accentBright ?? this.accentBright,
      accentDeep: accentDeep ?? this.accentDeep,
      panel: panel ?? this.panel,
      panelAlt: panelAlt ?? this.panelAlt,
      sidebar: sidebar ?? this.sidebar,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      accentBright: Color.lerp(accentBright, other.accentBright, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelAlt: Color.lerp(panelAlt, other.panelAlt, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
    );
  }
}

/// `context.palette` reads better than a static call at ninety call sites.
extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(this);
}

/// Lettering that reads on [fill]: a pale accent — the gold theme is one —
/// needs dark ink, a deep one, like the blue, needs white.
///
/// White wins up to a luminance of about 0.18; above that black's ratio is the
/// larger of the two, and the gold accent sits well above it.
Color inkOn(Color fill) =>
    fill.computeLuminance() < 0.18 ? Colors.white : Colors.black87;

class AppTheme {
  /// Builds the Material theme for the selected [ThemeSpec].
  static ThemeData build(ThemeSpec spec) {
    final palette = AppPalette.from(spec);
    final accent = palette.accent;
    final base = spec.dark ? ThemeData.dark(useMaterial3: false) : ThemeData.light(useMaterial3: false);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      primaryColor: accent,
      extensions: [palette],
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: palette.accentBright,
        surface: palette.panel,
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
          color: palette.panelAlt,
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
        backgroundColor: palette.panelAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.panelAlt,
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
