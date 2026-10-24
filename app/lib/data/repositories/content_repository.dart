import 'dart:collection';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../../core/constants.dart';
import '../models/models.dart';
import '../sources/playlist_source.dart';
import '../storage/app_storage.dart';
import 'playlist_repository.dart';

/// Loads, caches and queries playlist content.
class ContentRepository {
  ContentRepository(this._storage, this._playlists);

  final AppStorage _storage;
  final PlaylistRepository _playlists;

  Future<Box<dynamic>> _box(Playlist playlist) => _storage.openContentBox(playlist.id);

  /// The decoded catalogue, held for the playlist in use.
  ///
  /// Reading a catalogue back out of its box costs a JSON parse plus a model per
  /// entry in a background isolate, and then a copy of every object back onto the
  /// UI isolate. Without this, moving between Live, Films and Series paid that
  /// again every time — and so did every search, which reads all three kinds out
  /// in full. Only one playlist is kept: a large catalogue runs to tens of
  /// megabytes, and another playlist's can be read when the user switches to it.
  final Map<String, _Catalogue> _catalogues = {};

  _Catalogue _catalogueFor(Playlist playlist) {
    final cached = _catalogues[playlist.id];
    if (cached != null) return cached;
    _catalogues.clear();
    return _catalogues[playlist.id] = _Catalogue();
  }

  static ContentKindKey kindKey(ContentKind kind) => switch (kind) {
        ContentKind.live => ContentKindKey.live,
        ContentKind.movie => ContentKindKey.movie,
        ContentKind.series => ContentKindKey.series,
      };

  static String favoriteKey(ContentKind kind) => switch (kind) {
        ContentKind.live => ContentKeys.favoriteChannels,
        ContentKind.movie => ContentKeys.favoriteMovies,
        ContentKind.series => ContentKeys.favoriteSeries,
      };

  static String watchedKey(ContentKind kind) => switch (kind) {
        ContentKind.live => ContentKeys.watchedChannels,
        ContentKind.movie => ContentKeys.watchedMovies,
        ContentKind.series => ContentKeys.watchedSeries,
      };

  // ------------------------------------------------------------------- load

  Future<List<Category>> categories(Playlist playlist, ContentKind kind) async {
    final catalogue = _catalogueFor(playlist);
    final cached = catalogue.categories[kind];
    if (cached != null) return cached;
    final box = await _box(playlist);
    final loaded = await _storage.categories(box, kindKey(kind));
    return catalogue.categories[kind] = UnmodifiableListView(loaded);
  }

  Future<List<Channel>> channels(Playlist playlist) async {
    final catalogue = _catalogueFor(playlist);
    final cached = catalogue.channels;
    if (cached != null) return cached;
    final box = await _box(playlist);
    return catalogue.channels = UnmodifiableListView(await _storage.channels(box));
  }

  Future<List<Movie>> movies(Playlist playlist) async {
    final catalogue = _catalogueFor(playlist);
    final cached = catalogue.movies;
    if (cached != null) return cached;
    final box = await _box(playlist);
    return catalogue.movies = UnmodifiableListView(await _storage.movies(box));
  }

  Future<List<Series>> series(Playlist playlist) async {
    final catalogue = _catalogueFor(playlist);
    final cached = catalogue.series;
    if (cached != null) return cached;
    final box = await _box(playlist);
    return catalogue.series = UnmodifiableListView(await _storage.series(box));
  }

  bool get hasCache => false;

  Future<DateTime?> lastSync(Playlist playlist) async {
    final raw = _storage.readSetting<String>(StoreKeys.contentUpdateDate, '');
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Pulls the full catalogue from the source and stores it.
  Future<void> sync(
    Playlist playlist, {
    void Function(String stage, double progress)? onProgress,
  }) async {
    // Dropped before anything is written, not after: a sync that fails halfway
    // has still changed the store, and the cache must not outlive that.
    _catalogues.remove(playlist.id);
    final source = _playlists.sourceFor(playlist);
    final box = await _box(playlist);
    onProgress?.call('authenticating', 0.05);
    await source.authenticate();

    onProgress?.call('live', 0.15);
    final liveCategories = await source.categories(ContentKind.live);
    await _storage.saveCategories(box, ContentKindKey.live, liveCategories);
    final channelList = await source.channels();
    await _storage.saveChannels(box, channelList);

    onProgress?.call('movies', 0.45);
    final movieCategories = await source.categories(ContentKind.movie);
    await _storage.saveCategories(box, ContentKindKey.movie, movieCategories);
    final movieList = await source.movies();
    await _storage.saveMovies(box, movieList);

    onProgress?.call('series', 0.75);
    final seriesCategories = await source.categories(ContentKind.series);
    await _storage.saveCategories(box, ContentKindKey.series, seriesCategories);
    final seriesList = await source.series();
    await _storage.saveSeries(box, seriesList);

    await _storage.writeSetting(
      StoreKeys.contentUpdateDate,
      DateTime.now().toIso8601String(),
    );
    onProgress?.call('ready', 1);
  }

  Future<SeriesInfo> seriesInfo(Playlist playlist, int seriesId) async {
    final cached = await _cachedSeriesInfo(playlist, seriesId);
    if (cached != null) return cached;
    final info = await _playlists.sourceFor(playlist).seriesInfo(seriesId);
    final box = await _box(playlist);
    await box.put('series-info-$seriesId', json.encode({
      'series': info.series.toJson(),
      'seasons': info.seasons,
      'episodes': {
        for (final e in info.episodes.entries) '${e.key}': e.value.map((x) => x.toJson()).toList(),
      },
    }));
    return info;
  }

  Future<SeriesInfo?> _cachedSeriesInfo(Playlist playlist, int seriesId) async {
    final box = await _box(playlist);
    final raw = box.get('series-info-$seriesId');
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = Map<String, dynamic>.from(json.decode(raw) as Map);
      final episodesRaw = Map<String, dynamic>.from((decoded['episodes'] as Map?) ?? const {});
      return SeriesInfo(
        series: Series.fromJson(Map<String, dynamic>.from(decoded['series'] as Map)),
        seasons: ((decoded['seasons'] as List?) ?? const []).map((e) => e as int).toList(),
        episodes: {
          for (final e in episodesRaw.entries)
            int.parse(e.key): (e.value as List)
                .whereType<Map>()
                .map((x) => Episode.fromJson(Map<String, dynamic>.from(x), season: int.parse(e.key)))
                .toList(),
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<Movie> movieInfo(Playlist playlist, Movie movie) async {
    try {
      return await _playlists.sourceFor(playlist).movieInfo(movie.streamId);
    } catch (_) {
      return movie;
    }
  }

  /// Programme guide for one channel, kept for the day it was fetched for.
  ///
  /// Every channel switch used to cost a request to the panel — the slowest part
  /// of picking a channel, asking again for the same day's listings. A channel is
  /// fetched once per day now: repeats are answered from memory, and two lookups
  /// of one channel at the same time share a single request.
  Future<List<EpgProgram>> shortEpg(Playlist playlist, int streamId) {
    final catalogue = _catalogueFor(playlist);
    final cached = catalogue.epg[streamId];
    if (cached != null && cached.isCurrent) return Future.value(cached.programs);
    final pending = catalogue.epgPending[streamId];
    if (pending != null) return pending;
    final request = _fetchEpg(playlist, streamId);
    catalogue.epgPending[streamId] = request;
    return request.whenComplete(() => catalogue.epgPending.remove(streamId));
  }

  Future<List<EpgProgram>> _fetchEpg(Playlist playlist, int streamId) async {
    var programs = const <EpgProgram>[];
    try {
      programs = await _playlists.sourceFor(playlist).shortEpg(streamId);
    } catch (_) {
      // A channel whose panel will not answer still plays; the guide is a nicety.
    }
    final cache = _catalogueFor(playlist).epg;
    // Re-inserted so that the oldest entry is the one dropped when the cache is
    // full, rather than whichever channel was looked at first.
    cache
      ..remove(streamId)
      ..[streamId] = _EpgListings(programs);
    if (cache.length > epgCacheLimit) cache.remove(cache.keys.first);
    return programs;
  }

  // -------------------------------------------------------------- watch state

  Future<List<String>> favorites(Playlist playlist, ContentKind kind) async =>
      _storage.idList(await _box(playlist), favoriteKey(kind));

  Future<bool> isFavorite(Playlist playlist, ContentKind kind, int id) async =>
      (await favorites(playlist, kind)).contains('$id');

  Future<bool> toggleFavorite(Playlist playlist, ContentKind kind, int id) async {
    final box = await _box(playlist);
    final ids = _storage.idList(box, favoriteKey(kind)).toList();
    final value = '$id';
    final added = !ids.remove(value);
    if (added) ids.add(value);
    await _storage.saveIdList(box, favoriteKey(kind), ids);
    return added;
  }

  /// Which list a watched item belongs in, and under which id.
  ///
  /// An episode is watched as part of its series, so it marks the series under
  /// the series id — not a film of its own under the episode's id, which lit a
  /// watched check on a poster that was never played.
  static (ContentKind kind, int id) watchedEntry(String kind, int streamId, int parentId) =>
      switch (kind) {
        'episode' => (ContentKind.series, parentId),
        'live' => (ContentKind.live, streamId),
        _ => (ContentKind.movie, streamId),
      };

  /// The id an episode's resume position is filed and looked up under.
  ///
  /// Both halves come from the item the player opened — the series it belongs to
  /// and the stream id it was played by (`Episode.streamId`) — so the series page
  /// has to derive it the same way. Building it from the provider's raw episode id
  /// instead looked identical for every panel that numbers its episodes plainly,
  /// and found nothing at all for the ones that do not.
  static String episodeProgressId(int seriesId, int streamId) => '$seriesId:$streamId';

  Future<List<String>> watched(Playlist playlist, ContentKind kind) async =>
      _storage.idList(await _box(playlist), watchedKey(kind));

  Future<void> markWatched(Playlist playlist, ContentKind kind, int id) async {
    final box = await _box(playlist);
    final ids = _storage.idList(box, watchedKey(kind)).toList();
    final value = '$id';
    ids.remove(value);
    ids.insert(0, value);
    await _storage.saveIdList(box, watchedKey(kind), ids.take(100).toList());
  }

  Future<List<WatchProgress>> continueWatching(Playlist playlist, ContentKind kind) async {
    final box = await _box(playlist);
    final key = kind == ContentKind.series ? ContentKeys.continueSeries : ContentKeys.continueMovies;
    final list = _storage.progressList(box, key).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Which list a resume entry belongs in: an episode is watched as part of its
  /// series, not alongside the films.
  static String progressKey(String kind) =>
      kind == 'episode' ? ContentKeys.continueSeries : ContentKeys.continueMovies;

  Future<void> saveProgress(Playlist playlist, WatchProgress progress) async {
    final box = await _box(playlist);
    final key = progressKey(progress.kind);
    final list = _storage.progressList(box, key).toList()
      ..removeWhere((e) => e.id == progress.id)
      ..insert(0, progress);
    await _storage.saveProgressList(box, key, list.take(50).toList());
  }

  /// Drops one resume entry and leaves the rest of the list alone, so that an
  /// item watched to the end starts over instead of resuming on its last minute.
  Future<void> clearProgress(Playlist playlist, WatchProgress progress) async {
    final box = await _box(playlist);
    final key = progressKey(progress.kind);
    final list = _storage.progressList(box, key).toList()
      ..removeWhere((e) => e.id == progress.id);
    await _storage.saveProgressList(box, key, list);
  }

  Future<void> clearWatchLists(Playlist playlist) async {
    final box = await _box(playlist);
    for (final key in [
      ContentKeys.watchedChannels,
      ContentKeys.watchedMovies,
      ContentKeys.watchedSeries,
      ContentKeys.continueMovies,
      ContentKeys.continueSeries,
    ]) {
      await box.delete(key);
    }
  }

  /// Removes configuration, cached content and watch state for one playlist.
  Future<void> clearPlaylistCache(Playlist playlist) async {
    _catalogues.remove(playlist.id);
    final box = await _box(playlist);
    await box.clear();
  }

  /// Removes every cached box and the global settings box.
  Future<void> clearEverything() async {
    _catalogues.clear();
    await _storage.clearAll();
  }

  // ------------------------------------------------------------------ search

  Future<List<Channel>> searchChannels(Playlist playlist, String query) async {
    final q = query.toLowerCase();
    final all = await channels(playlist);
    return all.where((c) => c.name.toLowerCase().contains(q)).take(300).toList();
  }

  Future<List<Movie>> searchMovies(Playlist playlist, String query) async {
    final q = query.toLowerCase();
    final all = await movies(playlist);
    return all.where((m) => m.name.toLowerCase().contains(q)).take(300).toList();
  }

  Future<List<Series>> searchSeries(Playlist playlist, String query) async {
    final q = query.toLowerCase();
    final all = await series(playlist);
    return all.where((s) => s.name.toLowerCase().contains(q)).take(300).toList();
  }
}

/// One playlist's decoded content, filled in as each kind is asked for.
///
/// These lists go straight out to callers, so they are wrapped unmodifiable: code
/// that sorted or trimmed one in place would otherwise corrupt the cache for every
/// later read, and would do it silently.
class _Catalogue {
  final Map<ContentKind, List<Category>> categories = {};
  List<Channel>? channels;
  List<Movie>? movies;
  List<Series>? series;

  /// Guide listings per channel, and the requests still in flight, so that two
  /// selections of one channel make a single request.
  final Map<int, _EpgListings> epg = {};
  final Map<int, Future<List<EpgProgram>>> epgPending = {};
}

/// One channel's guide listings, and when the panel answered with them.
class _EpgListings {
  _EpgListings(this.programs) : fetchedAt = DateTime.now();

  final List<EpgProgram> programs;
  final DateTime fetchedAt;

  /// The day's listings do not change once fetched, so they are kept until the
  /// day does. An empty answer is not held for nearly as long: it is as likely to
  /// be a request that failed as a channel with no guide at all.
  bool get isCurrent {
    final now = DateTime.now();
    if (programs.isEmpty && now.difference(fetchedAt) >= epgEmptyRetry) return false;
    return fetchedAt.year == now.year && fetchedAt.month == now.month && fetchedAt.day == now.day;
  }
}
