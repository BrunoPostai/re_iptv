import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../models/models.dart';

/// Local persistence.
///
/// Layout follows the observed original structure under this project's own
/// neutral names:
///  * one settings box: `hive-re-iptv-box`
///  * one content cache box per playlist: `re-iptv-<id>`
///
/// Both live in `<support>/localData`, the same directory shape the original
/// used.
class AppStorage {
  AppStorage();

  late final Box<dynamic> settings;
  final Map<String, Box<dynamic>> _contentBoxes = {};

  Future<void> init() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}localData');
    if (!await dir.exists()) await dir.create(recursive: true);
    Hive.init(dir.path);
    settings = await Hive.openBox<dynamic>(HiveBoxes.settings);
    await _ensureDeviceIdentity();
  }

  Box<dynamic> contentBox(String playlistId) {
    final box = _contentBoxes[playlistId];
    if (box != null && box.isOpen) return box;
    throw StateError('Content box for "$playlistId" is not open. Call openContentBox first.');
  }

  Future<Box<dynamic>> openContentBox(String playlistId) async {
    final existing = _contentBoxes[playlistId];
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(HiveBoxes.content(playlistId));
    _contentBoxes[playlistId] = box;
    return box;
  }

  Future<void> closeContentBox(String playlistId) async {
    final box = _contentBoxes.remove(playlistId);
    await box?.close();
  }

  /// Clears the settings box and every content cache opened by this instance.
  Future<void> clearAll() async {
    for (final box in _contentBoxes.values) {
      if (box.isOpen) await box.clear();
    }
    await settings.clear();
  }

  Future<void> _ensureDeviceIdentity() async {
    if (settings.get(StoreKeys.deviceId) == null) {
      final hex = List.generate(32, (_) => Random().nextInt(16).toRadixString(16)).join();
      await settings.put(StoreKeys.deviceId, 'WINDOWS-${hex.toUpperCase()}');
    }
    if (settings.get(StoreKeys.deviceKey) == null) {
      final key = (Random().nextInt(900000) + 100000).toString();
      await settings.put(StoreKeys.deviceKey, key);
    }
    if (settings.get(StoreKeys.macAddress) == null) {
      final rnd = Random();
      final mac = List.generate(6, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join(':');
      await settings.put(StoreKeys.macAddress, mac);
    }
  }

  String get deviceId => (settings.get(StoreKeys.deviceId) ?? '').toString();
  String get deviceKey => (settings.get(StoreKeys.deviceKey) ?? '').toString();
  String get macAddress => (settings.get(StoreKeys.macAddress) ?? '').toString();

  // ---------------------------------------------------------------- playlists

  List<Playlist> loadPlaylists() {
    final raw = settings.get(StoreKeys.playlists);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    await settings.put(
      StoreKeys.playlists,
      json.encode(playlists.map((e) => e.toJson()).toList()),
    );
  }

  String? get recentPlaylistId => settings.get(StoreKeys.recentPlaylistId) as String?;

  Future<void> setRecentPlaylistId(String id) => settings.put(StoreKeys.recentPlaylistId, id);

  // ---------------------------------------------------------------- settings

  T readSetting<T>(String key, T fallback) {
    final value = settings.get(key);
    return value is T ? value : fallback;
  }

  Future<void> writeSetting(String key, Object? value) => settings.put(key, value);

  List<String> readStringList(String key) {
    final raw = settings.get(key);
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  Future<void> writeStringList(String key, List<String> value) => settings.put(key, value);

  Map<String, dynamic> _decodeMap(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(json.decode(raw) as Map);
      } catch (_) {}
    }
    return const {};
  }

  Map<String, dynamic> readMap(String key) => _decodeMap(settings.get(key));

  Future<void> writeMap(String key, Map<String, dynamic> value) =>
      settings.put(key, json.encode(value));

  // ------------------------------------------------------------ content cache

  /// Decodes one stored JSON list in a background isolate.
  ///
  /// `json.decode` plus a model per entry is the heaviest thing this app does to
  /// a large catalogue — tens of thousands of strings and objects, all of it on
  /// the isolate that draws the frame — so the work is handed to [compute]. The
  /// finished list does still have to be copied back, but that is cheaper than
  /// parsing the JSON here, and an unreadable store degrades to an empty list
  /// exactly as it did before.
  Future<List<T>> _decodeList<T>(
    Box<dynamic> box,
    String key,
    List<T> Function(String raw) parse,
  ) async {
    final raw = box.get(key);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return await compute(parse, raw);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeList(Box<dynamic> box, String key, List<dynamic> values) =>
      box.put(key, json.encode(values));

  Future<List<Channel>> channels(Box<dynamic> box) =>
      _decodeList(box, ContentKeys.channels, _parseChannels);

  Future<void> saveChannels(Box<dynamic> box, List<Channel> values) =>
      _writeList(box, ContentKeys.channels, values.map((e) => e.toJson()).toList());

  Future<List<Movie>> movies(Box<dynamic> box) =>
      _decodeList(box, ContentKeys.movies, _parseMovies);

  Future<void> saveMovies(Box<dynamic> box, List<Movie> values) =>
      _writeList(box, ContentKeys.movies, values.map((e) => e.toJson()).toList());

  Future<List<Series>> series(Box<dynamic> box) =>
      _decodeList(box, ContentKeys.series, _parseSeries);

  Future<void> saveSeries(Box<dynamic> box, List<Series> values) =>
      _writeList(box, ContentKeys.series, values.map((e) => e.toJson()).toList());

  Future<List<Category>> categories(Box<dynamic> box, ContentKindKey key) =>
      _decodeList(box, key.storeKey, _parseCategories);

  Future<void> saveCategories(Box<dynamic> box, ContentKindKey key, List<Category> values) =>
      _writeList(box, key.storeKey, values.map((e) => e.toJson()).toList());

  /// One channel's stored guide listings, or empty when none were kept.
  ///
  /// Decoded on the calling isolate, unlike the catalogue: this is a few dozen
  /// listings for one channel, not tens of thousands of entries.
  List<EpgProgram> epgPrograms(Box<dynamic> box, String key) {
    final raw = box.get(key);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => EpgProgram.fromStoredJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveEpgPrograms(Box<dynamic> box, String key, List<EpgProgram> programs) =>
      _writeList(box, key, programs.map((e) => e.toStoredJson()).toList());

  /// Keys in [box] that begin with [prefix].
  ///
  /// Keys only: a caller that puts the day it stored something under into the key
  /// can tell what has gone stale without reading a single value.
  List<String> keysStartingWith(Box<dynamic> box, String prefix) =>
      box.keys.whereType<String>().where((key) => key.startsWith(prefix)).toList();

  Future<void> deleteKeys(Box<dynamic> box, Iterable<String> keys) => box.deleteAll(keys);

  // ------------------------------------------------------------ watch state

  List<String> idList(Box<dynamic> box, String key) {
    final raw = box.get(key);
    if (raw is String && raw.isNotEmpty) {
      return raw.split(',').where((e) => e.isNotEmpty).toList();
    }
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  Future<void> saveIdList(Box<dynamic> box, String key, List<String> ids) =>
      box.put(key, ids.map((e) => '$e,').join());

  List<WatchProgress> progressList(Box<dynamic> box, String key) {
    final raw = box.get(key);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => WatchProgress.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveProgressList(Box<dynamic> box, String key, List<WatchProgress> values) =>
      _writeList(box, key, values.map((e) => e.toJson()).toList());
}

/// Identifies a category store inside a content box.
enum ContentKindKey {
  live(ContentKeys.channelCategories),
  movie(ContentKeys.movieCategories),
  series(ContentKeys.seriesCategories);

  const ContentKindKey(this.storeKey);
  final String storeKey;
}

// Top-level, so [compute] can run them in a background isolate. Each one is
// handed a raw JSON string and returns finished models.

List<Channel> _parseChannels(String raw) => _parseList(raw, Channel.fromJson);

List<Movie> _parseMovies(String raw) => _parseList(raw, Movie.fromJson);

List<Series> _parseSeries(String raw) => _parseList(raw, Series.fromJson);

List<Category> _parseCategories(String raw) => _parseList(raw, Category.fromJson);

List<T> _parseList<T>(String raw, T Function(Map<String, dynamic>) fromJson) {
  final decoded = json.decode(raw) as List;
  return decoded.whereType<Map>().map((e) => fromJson(Map<String, dynamic>.from(e))).toList();
}
