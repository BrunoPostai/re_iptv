import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/artwork.dart';
import '../core/utils/formatters.dart';

/// Displays artwork from any supported source (asset, file or network) and
/// degrades to a neutral placeholder on error.
class SmartImage extends StatefulWidget {
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
  State<SmartImage> createState() => _SmartImageState();
}

class _SmartImageState extends State<SmartImage> {
  /// The URL being asked for: the playlist's own at first, the panel's after
  /// that, and nothing but the placeholder once both have failed.
  late String _url = widget.path;
  bool _mirrored = false;

  @override
  void didUpdateWidget(SmartImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _url = widget.path;
      _mirrored = false;
    }
  }

  /// A provider's logo host can refuse the request while its panel serves the
  /// same path perfectly well, so ask the panel once before giving up.
  void _retryThroughPanel() {
    if (_mirrored) return;
    final mirror = Artwork.mirror(_url);
    if (mirror == null) return;
    _mirrored = true;
    // This runs while the failed image is being built; swapping its URL under
    // it in the same frame would rebuild the tree in the middle of a pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _url = mirror);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (widget.path.isEmpty) {
      child = _placeholder();
    } else if (isRemote(_url)) {
      child = CachedNetworkImage(
        imageUrl: _url,
        fit: widget.fit,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) {
          _retryThroughPanel();
          return _placeholder();
        },
      );
    } else {
      final provider = resolveImage(_url);
      child = provider == null
          ? _placeholder()
          : Image(
              image: provider,
              fit: widget.fit,
              errorBuilder: (_, __, ___) => _placeholder(),
            );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: widget.showBorder ? Border.all(color: AppColors.divider) : null,
        ),
        child: child,
      ),
    );
  }

  Widget _placeholder() {
    final letter = (widget.fallbackText ?? '?').trim();
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
