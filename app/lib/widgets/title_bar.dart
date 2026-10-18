import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/app_theme.dart';

/// Frameless window title bar (drag, minimise, maximise, close).
class AppTitleBar extends StatefulWidget implements PreferredSizeWidget {
  const AppTitleBar({
    super.key,
    this.title,
    this.actions = const [],
    this.onBack,
    this.onSettings,
    this.showAccount = false,
    this.logo,
  });

  final String? title;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final bool showAccount;
  final String? logo;

  @override
  Size get preferredSize => const Size.fromHeight(38);

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _sync();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _sync() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _maximized) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 38,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF20A1A2E), Color(0xF20E2138)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            if (widget.onBack != null)
              _BarButton(
                icon: Icons.arrow_back_ios_new,
                onTap: () => widget.onBack?.call(),
                tooltip: 'Back',
              ),
            if (widget.logo != null && widget.logo!.isNotEmpty) ...[
              const SizedBox(width: 4),
              Image.asset(
                widget.logo!,
                height: 22,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            ...widget.actions,
            _BarButton(
              icon: Icons.vertical_align_bottom,
              tooltip: 'Minimise',
              onTap: windowManager.minimize,
            ),
            _BarButton(
              icon: _maximized ? Icons.fullscreen_exit : Icons.fullscreen,
              tooltip: _maximized ? 'Restore' : 'Maximise',
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _BarButton(
              icon: Icons.close,
              tooltip: 'Close',
              hoverColor: AppColors.red,
              onTap: windowManager.close,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.hoverColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? hoverColor;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 42,
          height: 38,
          alignment: Alignment.center,
          color: _hovered
              ? (widget.hoverColor ?? Colors.white).withValues(alpha: 0.18)
              : Colors.transparent,
          child: Icon(widget.icon, size: 15, color: AppColors.textPrimary),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}
