import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';

/// Displays artwork from any supported source (asset, file or network) and
/// degrades to a neutral placeholder on error.
class SmartImage extends StatelessWidget {
  const SmartImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.fallbackText,
    this.borderRadius = 6,
    this.showBorder = false,
  });

  final String path;
  final BoxFit fit;
  final String? fallbackText;
  final double borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (path.isEmpty) {
      child = _placeholder();
    } else if (isRemote(path)) {
      child = CachedNetworkImage(
        imageUrl: path,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
    } else {
      final provider = resolveImage(path);
      child = provider == null
          ? _placeholder()
          : Image(image: provider, fit: fit, errorBuilder: (_, __, ___) => _placeholder());
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: showBorder ? Border.all(color: AppColors.divider) : null,
        ),
        child: child,
      ),
    );
  }

  Widget _placeholder() {
    final letter = (fallbackText ?? '?').trim();
    return ColoredBox(
      color: const Color(0xFF0D1B2C),
      child: Center(
        child: Text(
          letter.isEmpty ? '?' : letter.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
