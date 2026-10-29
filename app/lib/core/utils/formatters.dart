import 'dart:io';

import 'package:flutter/material.dart';

/// Formats a credential expiry timestamp (Xtream sends unix seconds as string).
String formatExpiry(String raw) {
  if (raw.isEmpty) return '—';
  final ts = int.tryParse(raw);
  if (ts == null || ts <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
}

String formatDate(DateTime date) => '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';

String formatClock(DateTime date) =>
    '${twoDigits(date.hour)}:${twoDigits(date.minute)}:${twoDigits(date.second)}';

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  return '${twoDigits(minutes)}:${twoDigits(seconds)}';
}

String formatMinutes(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m';

String twoDigits(int value) => value.toString().padLeft(2, '0');

/// When the build the app is running was made, as the time its `data/app.so`
/// was written.
///
/// `re_iptv.exe` is only the C++ shell and keeps the date it was first built, so
/// its timestamp says nothing about which version is running; every line of Dart
/// ships in `data/app.so` next to it, and that file is rewritten by every build.
/// That trick only applies to the Windows layout. Android and iOS fold the
/// snapshot into the app binary, where the only nearby dates belong to the
/// system, so they report no stamp rather than a misleading one.
String buildStamp() {
  if (!Platform.isWindows) return 'unknown';
  try {
    final exe = File(Platform.resolvedExecutable);
    final separator = Platform.pathSeparator;
    final snapshot = File('${exe.parent.path}${separator}data${separator}app.so');
    final file = snapshot.existsSync() ? snapshot : exe;
    final modified = file.statSync().modified;
    return '${formatDate(modified)} ${formatClock(modified)}';
  } catch (_) {
    return 'unknown';
  }
}

/// Resolves an image path that may be a bundled asset, an absolute file path or
/// a network URL. Keeps personalisation simple: point the config at a local
/// file and it just works.
ImageProvider? resolveImage(String path) {
  if (path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(path);
  }
  if (path.startsWith('assets/')) return AssetImage(path);
  final file = File(path);
  if (file.existsSync()) return FileImage(file);
  return null;
}

bool isRemote(String path) => path.startsWith('http://') || path.startsWith('https://');
