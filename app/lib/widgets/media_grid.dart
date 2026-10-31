import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'smart_image.dart';

/// Responsive poster/thumbnail grid.
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.children,
    this.maxCrossAxisExtent = 168,
    this.aspectRatio = 0.62,
    this.padding = const EdgeInsets.all(14),
  });

  final List<Widget> children;
  final double maxCrossAxisExtent;
  final double aspectRatio;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      padding: padding,
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        childAspectRatio: aspectRatio,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      itemBuilder: (context, index) => children[index],
    );
  }
}

/// Poster card used for movies and series.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.subtitle,
    this.rating,
    this.favorite = false,
    this.onToggleFavorite,
    this.progress,
    this.watched = false,
    this.trailingLabel,
  });

  final String title;
  final String image;
  final VoidCallback onTap;
  final String? subtitle;
  final double? rating;
  final bool favorite;
  final VoidCallback? onToggleFavorite;
  final double? progress;
  final bool watched;
  final String? trailingLabel;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _hovered ? palette.accent : AppColors.divider,
                    width: _hovered ? 1.6 : 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SmartImage(path: widget.image, fallbackText: widget.title, borderRadius: 5),
                    if (widget.rating != null && widget.rating! > 0)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.star, size: 11, color: palette.accent),
                              const SizedBox(width: 3),
                              Text(
                                widget.rating!.toStringAsFixed(1),
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.onToggleFavorite != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: GestureDetector(
                          onTap: widget.onToggleFavorite,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.favorite ? Icons.favorite : Icons.favorite_border,
                              size: 14,
                              color: widget.favorite ? AppColors.red : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (widget.watched)
                      const Positioned(
                        right: 4,
                        bottom: 4,
                        child: Icon(Icons.check_circle, size: 15, color: AppColors.green),
                      ),
                    if (widget.progress != null && widget.progress! > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: widget.progress!.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                          valueColor: AlwaysStoppedAnimation(palette.accent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact row used for channel lists.
class ChannelRow extends StatefulWidget {
  const ChannelRow({
    super.key,
    required this.name,
    required this.image,
    required this.onTap,
    required this.number,
    this.favorite = false,
    this.onToggleFavorite,
    this.onLongPress,
    this.locked = false,
    this.trailing,
  });

  final String name;
  final String image;
  final VoidCallback onTap;
  final int number;
  final bool favorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onLongPress;
  final bool locked;
  final Widget? trailing;

  @override
  State<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<ChannelRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _hovered ? palette.accent.withValues(alpha: 0.55) : AppColors.divider),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${widget.number}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ),
              SizedBox(
                width: 46,
                height: 30,
                child: SmartImage(path: widget.image, fallbackText: widget.name, borderRadius: 3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
                ),
              ),
              if (widget.locked)
                Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.lock_outline, size: 14, color: palette.accent),
                ),
              if (widget.trailing != null) widget.trailing!,
              if (widget.onToggleFavorite != null)
                IconButton(
                  onPressed: widget.onToggleFavorite,
                  tooltip: widget.favorite ? 'Remove from favourites' : 'Add to favourites',
                  iconSize: 16,
                  icon: Icon(
                    widget.favorite ? Icons.favorite : Icons.favorite_border,
                    color: widget.favorite ? AppColors.red : AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
