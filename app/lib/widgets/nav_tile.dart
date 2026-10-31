import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Tile used by the home navigation row.
class NavTile extends StatefulWidget {
  const NavTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = AppColors.orange,
    this.iconColor = Colors.white,
    this.badge,
    this.size = 132,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;
  final Color iconColor;
  final String? badge;

  /// The tile is square; a phone gives it more of the width than the desktop
  /// does, so the grid fills the screen instead of leaving a stripe of empty
  /// background down each side.
  final double size;

  @override
  State<NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered
                  ? [AppColors.blueTile, AppColors.blueDark]
                  : [const Color(0xCC12365F), const Color(0xCC0B1F38)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered ? widget.accent : AppColors.divider,
              width: _hovered ? 1.6 : 1,
            ),
            boxShadow: _hovered
                ? [BoxShadow(color: widget.accent.withValues(alpha: 0.25), blurRadius: 14)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.icon, size: widget.size * 0.32, color: widget.iconColor),
                  if (widget.badge != null)
                    Positioned(
                      right: -14,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.badge!,
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact square tile used by the settings grid.
class SettingsTile extends StatefulWidget {
  const SettingsTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.value,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final String? value;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered && widget.enabled
                  ? [const Color(0xFF2A6DBC), const Color(0xFF17406E)]
                  : [const Color(0xE61B4C86), const Color(0xE60E2A4C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _hovered && widget.enabled ? AppColors.gold : AppColors.divider),
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.45,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 30, color: Colors.white),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.value != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
