import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/theme/app_theme.dart';

/// A snapshot of what libmpv is doing with the playing stream.
///
/// [PlayerState] carries position, volume and tracks, but nothing about whether
/// decoding is keeping up. These are read straight from mpv properties, which
/// is the difference between "the stream stutters" and knowing *why*: whether
/// hardware decoding actually engaged, whether frames are being dropped, and
/// how much of the stream is buffered.
class PlayerStats {
  const PlayerStats(this.rows);

  /// Labelled values, in the order mpv was asked for them.
  final List<(String, String)> rows;

  bool get isEmpty => rows.isEmpty;

  /// mpv properties to read, as `(property, label)`.
  ///
  /// Anything a given mpv build does not expose is left out rather than shown
  /// as zero. Resolution is read separately so it can be shown on one line.
  static const _watched = <(String, String)>[
    ('hwdec-current', 'Decoder'),
    ('video-codec', 'Codec'),
    ('estimated-vf-fps', 'FPS'),
    ('decoder-frame-drop-count', 'Dropped (decode)'),
    ('frame-drop-count', 'Dropped (output)'),
    ('mistimed-frame-count', 'Mistimed'),
    ('demuxer-cache-time', 'Buffered'),
    ('cache-buffering-state', 'Cache fill'),
    ('cache-speed', 'Cache rate'),
    ('avsync', 'A/V sync'),
    // Why playback stopped moving: mpv calls itself idle both at the end of a
    // file and while it waits for data, and `eof-reached` is what tells the two
    // apart. `media_kit` reports idle as buffering, which is the spinner.
    ('eof-reached', 'End of file'),
    ('core-idle', 'Core idle'),
    ('paused-for-cache', 'Waiting for data'),
  ];

  /// Reads [player]'s diagnostics.
  static Future<PlayerStats> read(Player player) async {
    final platform = player.platform;
    // Only the native backend keeps an mpv instance to query.
    if (platform is! NativePlayer) return const PlayerStats([]);

    final rows = <(String, String)>[];

    final width = int.tryParse(await _read(platform, 'width') ?? '');
    final height = int.tryParse(await _read(platform, 'height') ?? '');
    if (width != null && height != null && width > 0 && height > 0) {
      rows.add(('Resolution', '$width x $height'));
    }

    for (final (property, label) in _watched) {
      final raw = await _read(platform, property);
      final value = raw == null ? null : _format(property, raw);
      if (value != null) rows.add((label, value));
    }
    return PlayerStats(rows);
  }

  static Future<String?> _read(NativePlayer platform, String property) async {
    try {
      final raw = await platform.getProperty(property, waitForInitialization: false);
      final value = raw.trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      // Property unknown to this build, or the player is being disposed.
      return null;
    }
  }

  static String? _format(String property, String raw) {
    switch (property) {
      case 'estimated-vf-fps':
        final fps = double.tryParse(raw);
        return fps == null ? raw : fps.toStringAsFixed(1);
      case 'demuxer-cache-time':
        final seconds = double.tryParse(raw);
        return seconds == null ? raw : '${seconds.toStringAsFixed(1)} s';
      case 'cache-buffering-state':
        final percent = double.tryParse(raw);
        return percent == null ? raw : '${percent.round()}%';
      case 'cache-speed':
        return _rate(double.tryParse(raw));
      case 'avsync':
        final sync = double.tryParse(raw);
        return sync == null ? raw : '${sync >= 0 ? '+' : ''}${sync.toStringAsFixed(3)} s';
      default:
        return raw;
    }
  }

  static String _rate(double? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) return '0';
    const units = ['B/s', 'kB/s', 'MB/s', 'GB/s'];
    var value = bytesPerSecond;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

/// Read-out of [PlayerStats], refreshed once a second while it is on screen.
class PlayerStatsOverlay extends StatefulWidget {
  const PlayerStatsOverlay({super.key, required this.player});

  final Player player;

  @override
  State<PlayerStatsOverlay> createState() => _PlayerStatsOverlayState();
}

class _PlayerStatsOverlayState extends State<PlayerStatsOverlay> {
  static const _interval = Duration(seconds: 1);

  PlayerStats _stats = const PlayerStats([]);
  Timer? _timer;

  /// Guards against a slow read overlapping the next tick.
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_interval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final stats = await PlayerStats.read(widget.player);
      if (mounted) setState(() => _stats = stats);
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stats.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in _stats.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(
                        label,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
