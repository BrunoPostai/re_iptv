import 'package:media_kit/media_kit.dart';

import '../config/app_config.dart';

/// Applies the opt-in libmpv settings from [LiveTuning] to [player].
///
/// Called just before a live stream is opened, because stream options such as
/// `user-agent` and `stream-lavf-o` only affect the connection that happens at
/// open time. `media_kit` has already set `hwdec`, `cache`, `cache-on-disk` and
/// a network timeout by then, so only the configured extras are sent here and
/// everything else is left alone.
///
/// An option this libmpv build does not know is ignored rather than raised,
/// which is why this is best-effort: the point is to let a provider be tested
/// from `app_config.json`, not to make playback depend on it.
Future<void> applyLiveTuning(Player player, LiveTuning tuning) async {
  if (tuning.isEmpty) return;

  final platform = player.platform;
  // Only the native backend keeps an mpv instance to set options on.
  if (platform is! NativePlayer) return;

  if (tuning.reconnect) {
    await _set(
      platform,
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,'
      'reconnect_delay_max=${tuning.reconnectDelayMax}',
    );
  }
  if (tuning.cacheOnDisk != null) {
    await _set(platform, 'cache-on-disk', tuning.cacheOnDisk! ? 'yes' : 'no');
  }
  if (tuning.userAgent.isNotEmpty) {
    await _set(platform, 'user-agent', tuning.userAgent);
  }
  for (final entry in tuning.properties.entries) {
    await _set(platform, entry.key, entry.value);
  }
}

Future<void> _set(NativePlayer platform, String property, String value) async {
  try {
    await platform.setProperty(property, value);
  } catch (_) {
    // Unknown option, or the player is already gone. Neither is worth
    // interrupting playback for.
  }
}
