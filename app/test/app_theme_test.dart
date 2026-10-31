import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_iptv/core/config/app_config.dart';
import 'package:re_iptv/core/theme/app_theme.dart';

/// What a theme is allowed to change.
///
/// Choosing a theme used to swap the picture behind an unchanged window: the
/// headings stayed gold and the panels stayed navy. The palette is the part of
/// the theme a screen paints with, so these tests pin it to the accent the
/// provider shipped rather than to a constant.
void main() {
  const blue = ThemeSpec(
    id: 'main',
    name: 'Background Main',
    background: '',
    accent: 0xFF2C6FBB,
  );
  const gold = ThemeSpec(
    id: 'honor',
    name: 'Gold Honor',
    background: '',
    accent: 0xFFE0A83C,
  );

  test('the theme carries its accent to whatever asks for a palette', () {
    final theme = AppTheme.build(blue);
    expect(theme.extension<AppPalette>()!.accent, const Color(0xFF2C6FBB));
  });

  test('labels take a lighter shade of the accent, gradients a darker one', () {
    final palette = AppPalette.from(blue);
    expect(palette.accentBright.computeLuminance(), greaterThan(palette.accent.computeLuminance()));
    expect(palette.accentDeep.computeLuminance(), lessThan(palette.accent.computeLuminance()));
  });

  test('the panels are tinted by the accent instead of being one navy', () {
    final cold = AppPalette.from(blue);
    final warm = AppPalette.from(gold);
    expect(cold.panel, isNot(warm.panel));
    expect(cold.sidebar, isNot(warm.sidebar));
    expect(cold.panelAlt, isNot(AppColors.panelAlt));
  });

  test('a palette blends into another so a theme change does not snap', () {
    final cold = AppPalette.from(blue);
    final warm = AppPalette.from(gold);
    expect(cold.lerp(warm, 1).accent, warm.accent);
    expect(cold.lerp(warm, 0).accent, cold.accent);
  });
}
