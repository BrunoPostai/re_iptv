import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/platform/window_class.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';

/// [preferred] pixels, or the room actually available, whichever is smaller.
///
/// Several panels in this app were drawn at a fixed width on a desktop — a 430
/// pixel identity card, a 560 pixel dialog — and a fixed width wider than the
/// screen is an overflow. [inset] is what the surroundings already spend on
/// padding.
double fitWidth(BuildContext context, double preferred, {double inset = 32}) =>
    math.min(preferred, MediaQuery.sizeOf(context).width - inset);

/// Paints the configured background image behind a screen, with a dark scrim so
/// that foreground content stays readable on any artwork.
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.image,
    required this.child,
    this.scrim = 0.45,
  });

  final String image;
  final Widget child;
  final double scrim;

  @override
  Widget build(BuildContext context) {
    final provider = resolveImage(image);
    // Android 15 and later draw the app edge to edge, so the navigation bar sits
    // over the bottom of the page instead of below it. The artwork still wants
    // to reach the edge; the content on top of it must not.
    final safe = MediaQuery.paddingOf(context);
    final content = safe.bottom > 0 || safe.left > 0 || safe.right > 0
        ? Padding(
            padding: EdgeInsets.only(bottom: safe.bottom, left: safe.left, right: safe.right),
            child: child,
          )
        : child;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF04080F)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (provider != null)
            Image(
              image: provider,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _FallbackArtwork(),
            )
          else
            const _FallbackArtwork(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: scrim + 0.15),
                  Colors.black.withValues(alpha: scrim * 0.5),
                  Colors.black.withValues(alpha: scrim + 0.15),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          content,
        ],
      ),
    );
  }
}

/// Used when a configured background cannot be loaded; keeps the dotted
/// world-map feel with a pure gradient.
class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.4,
          colors: [Color(0xFF0E2A4A), Color(0xFF050B14)],
        ),
      ),
    );
  }
}

/// Big gold heading used by the category screens ("Live Channels", "Movies"…).
class ScreenHeading extends StatelessWidget {
  const ScreenHeading({
    super.key,
    required this.title,
    this.color = AppColors.gold,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final Color color;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 24, color: color),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
          ],
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A screen's heading, search box and controls, laid out for the width at hand.
///
/// The desktop puts them on one line. A phone cannot: the search box alone is
/// 250 of a 360 pixel screen, so there the controls ride with the heading and
/// the search box takes the line below — the same arrangement the live screen
/// arrived at by hand.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.heading,
    required this.search,
    this.controls = const [],
  });

  final Widget heading;

  /// Built with a null width to fill the line on a phone, or a fixed one on the
  /// desktop; [SearchField] takes both.
  final Widget search;

  /// Sort order, reload, filters — these stay beside the heading when stacked,
  /// because they are pressed rather than read.
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    final compact = WindowClass.of(context).isCompact;
    final padding = EdgeInsets.fromLTRB(compact ? 14 : 18, 14, compact ? 14 : 18, 10);

    if (!compact) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: heading),
            search,
            for (final control in controls) ...[const SizedBox(width: 10), control],
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: heading),
              for (final control in controls) ...[const SizedBox(width: 6), control],
            ],
          ),
          const SizedBox(height: 10),
          search,
        ],
      ),
    );
  }
}

class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(message!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class EmptyBlock extends StatelessWidget {
  const EmptyBlock({super.key, required this.message, this.icon = Icons.inbox_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 46, color: AppColors.red),
            const SizedBox(height: 12),
            const Text(
              'Could not load content',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              AccentButton(label: 'Retry', icon: Icons.refresh, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color = AppColors.blue,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label, style: TextStyle(fontSize: compact ? 12 : 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.35),
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18, vertical: compact ? 8 : 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class OutlineButtonX extends StatelessWidget {
  const OutlineButtonX({super.key, required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

/// Small pill used to display e.g. "Current Playlist Expired On".
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.value, this.color = AppColors.gold});

  final String label;
  final String? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          children: [
            TextSpan(text: '$label '),
            if (value != null)
              TextSpan(
                text: value,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}

/// Read-only labelled value row (used on the account / playlist screens).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: color ?? AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ticking clock, matching the header of the original home screen.
class LiveClock extends StatefulWidget {
  const LiveClock({super.key, this.style});

  final TextStyle? style;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatClock(_now),
      style: widget.style ??
          const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
    );
  }
}

/// Confirmation dialog helper.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel, style: const TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, elevation: 0),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
