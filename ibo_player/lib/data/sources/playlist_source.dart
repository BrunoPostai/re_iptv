import 'package:dio/dio.dart';

import '../models/models.dart';

enum ContentKind { live, movie, series }

extension ContentKindX on ContentKind {
  String get key => switch (this) {
        ContentKind.live => 'live',
        ContentKind.movie => 'movie',
        ContentKind.series => 'series',
      };
}

class PlaylistAuth {
  final bool ok;
  final String? message;
  final bool isTrial;
  final String status;
  final String expiryDate;
  final int maxConnections;
  final String serverVersion;

  const PlaylistAuth({
    required this.ok,
    this.message,
    this.isTrial = false,
    this.status = '',
    this.expiryDate = '',
    this.maxConnections = 1,
    this.serverVersion = '',
  });

  bool get expired {
    if (expiryDate.isEmpty) return false;
    final ts = int.tryParse(expiryDate);
    if (ts == null || ts == 0) return false;
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000).isBefore(DateTime.now());
  }

  DateTime? get expiryDateTime {
    final ts = int.tryParse(expiryDate);
    if (ts == null || ts == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  }
}

/// A source of channels/movies/series for one playlist.
///
/// Implement this interface to plug in a new backend (see `docs/EXTENDING.md`).
abstract class PlaylistSource {
  Playlist get playlist;

  Future<PlaylistAuth> authenticate();

  Future<List<Category>> categories(ContentKind kind);

  Future<List<Channel>> channels({String? categoryId});

  Future<List<Movie>> movies({String? categoryId});

  Future<List<Series>> series({String? categoryId});

  Future<SeriesInfo> seriesInfo(int seriesId);

  Future<Movie> movieInfo(int vodId);

  Future<List<EpgProgram>> shortEpg(int streamId);

  String liveUrl(Channel channel);

  String movieUrl(Movie movie);

  String episodeUrl(Episode episode);

  String? timeshiftUrl(Channel channel, DateTime start, int durationMinutes);
}

/// Xtream Codes / XUI compatible source.
class XtreamSource implements PlaylistSource {
  @override
  final Playlist playlist;
  final Dio _dio;
  final String userAgent;

  /// `default` | `m3u8` | `ts` — see the stream format setting.
  final String format;
  PlaylistAuth? lastAuth;

  XtreamSource(
    this.playlist, {
    Dio? dio,
    this.userAgent = 'IPTVPlayer/1.0',
    this.format = 'default',
  }) : _dio = dio ?? Dio();

  String get _host => playlist.host.replaceAll(RegExp(r'/+$'), '');

  Future<Map<String, dynamic>> _api(Map<String, String> extra) async {
    final uri = Uri.parse('$_host/player_api.php').replace(queryParameters: {
      'username': playlist.username,
      'password': playlist.password,
      ...extra,
    });
    final res = await _dio.getUri<dynamic>(
      uri,
      options: Options(responseType: ResponseType.json, headers: {'User-Agent': userAgent}),
    );
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<List<dynamic>> _apiList(Map<String, String> extra) async {
    final uri = Uri.parse('$_host/player_api.php').replace(queryParameters: {
      'username': playlist.username,
      'password': playlist.password,
      ...extra,
    });
    final res = await _dio.getUri<dynamic>(
      uri,
      options: Options(responseType: ResponseType.json, headers: {'User-Agent': userAgent}),
    );
    final data = res.data;
    if (data is List) return data;
    return const [];
  }

  @override
  Future<PlaylistAuth> authenticate() async {
    final json = await _api(const {});
    final userInfo = Map<String, dynamic>.from((json['user_info'] as Map?) ?? const {});
    final serverInfo = Map<String, dynamic>.from((json['server_info'] as Map?) ?? const {});
    final status = (userInfo['status'] ?? '').toString();
    final auth = PlaylistAuth(
      ok: status.toLowerCase() == 'active' || (userInfo['auth']?.toString() == '1'),
      status: status,
      isTrial: userInfo['is_trial']?.toString() == '1',
      expiryDate: (userInfo['exp_date'] ?? '').toString(),
      maxConnections: int.tryParse((userInfo['max_connections'] ?? '1').toString()) ?? 1,
      serverVersion: (serverInfo['version'] ?? '').toString(),
      message: userInfo.isEmpty ? 'Unknown response' : null,
    );
    lastAuth = auth;
    return auth;
  }

  @override
  Future<List<Category>> categories(ContentKind kind) async {
    final action = switch (kind) {
      ContentKind.live => 'get_live_categories',
      ContentKind.movie => 'get_vod_categories',
      ContentKind.series => 'get_series_categories',
    };
    final raw = await _apiList({'action': action});
    return raw.whereType<Map>().map((e) => Category.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<List<Channel>> channels({String? categoryId}) async {
    final raw = await _apiList({
      'action': 'get_live_streams',
      if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
    });
    return raw.whereType<Map>().map((e) => Channel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<List<Movie>> movies({String? categoryId}) async {
    final raw = await _apiList({
      'action': 'get_vod_streams',
      if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
    });
    return raw.whereType<Map>().map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<List<Series>> series({String? categoryId}) async {
    final raw = await _apiList({
      'action': 'get_series',
      if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
    });
    return raw.whereType<Map>().map((e) => Series.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<Movie> movieInfo(int vodId) async {
    final json = await _api({'action': 'get_vod_info', 'vod_id': '$vodId'});
    final info = Map<String, dynamic>.from((json['info'] as Map?) ?? const {});
    final movieData = Map<String, dynamic>.from((json['movie_data'] as Map?) ?? const {});
    final base = Movie.fromJson(movieData);
    return base.copyWith(
      plot: (info['plot'] ?? info['description'] ?? '').toString(),
      cast: (info['cast'] ?? '').toString(),
      director: (info['director'] ?? '').toString(),
      genre: (info['genre'] ?? '').toString(),
      releaseDate: (info['releasedate'] ?? info['release_date'] ?? '').toString(),
      duration: (info['duration'] ?? '').toString(),
      youtubeTrailer: (info['youtube_trailer'] ?? '').toString(),
      backdropPath: info['backdrop_path']?.toString() ?? '',
      icon: (info['movie_image'] ?? base.icon).toString(),
      rating5Based: double.tryParse((info['rating'] ?? '0').toString()) ?? base.rating5Based,
    );
  }

  @override
  Future<SeriesInfo> seriesInfo(int seriesId) async {
    final json = await _api({'action': 'get_series_info', 'series_id': '$seriesId'});
    final info = Map<String, dynamic>.from((json['info'] as Map?) ?? const {});
    final episodesRaw = Map<String, dynamic>.from((json['episodes'] as Map?) ?? const {});
    final episodes = <int, List<Episode>>{};
    for (final entry in episodesRaw.entries) {
      final season = int.tryParse(entry.key) ?? 0;
      final list = (entry.value as List?)
              ?.whereType<Map>()
              .map((e) => Episode.fromJson(Map<String, dynamic>.from(e), season: season))
              .toList() ??
          const <Episode>[];
      episodes[season] = list;
    }
    final series = Series(
      seriesId: seriesId,
      name: (info['name'] ?? '').toString(),
      cover: (info['cover'] ?? '').toString(),
      plot: (info['plot'] ?? '').toString(),
      cast: (info['cast'] ?? '').toString(),
      director: (info['director'] ?? '').toString(),
      genre: (info['genre'] ?? '').toString(),
      releaseDate: (info['releaseDate'] ?? info['release_date'] ?? '').toString(),
      rating: (info['rating'] ?? '').toString(),
      rating5Based: double.tryParse((info['rating_5based'] ?? '0').toString()) ?? 0,
      backdropPath: info['backdrop_path']?.toString() ?? '',
      youtubeTrailer: (info['youtube_trailer'] ?? '').toString(),
      episodeRunTime: (info['episode_run_time'] ?? '0').toString(),
    );
    final seasons = episodes.keys.toList()..sort();
    return SeriesInfo(series: series, seasons: seasons, episodes: episodes);
  }

  @override
  Future<List<EpgProgram>> shortEpg(int streamId) async {
    final json = await _api({'action': 'get_short_epg', 'stream_id': '$streamId'});
    final listings = (json['epg_listings'] as List?) ?? const [];
    return listings
        .whereType<Map>()
        .map((e) => EpgProgram.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  String liveUrl(Channel channel) {
    final ext = switch (format) {
      'm3u8' => 'm3u8',
      'ts' => 'ts',
      _ => playlist.isProtected ? 'm3u8' : 'ts',
    };
    return '$_host/live/${playlist.username}/${playlist.password}/${channel.streamId}.$ext';
  }

  @override
  String movieUrl(Movie movie) =>
      '$_host/movie/${playlist.username}/${playlist.password}/${movie.streamId}.${movie.containerExtension}';

  @override
  String episodeUrl(Episode episode) =>
      '$_host/series/${playlist.username}/${playlist.password}/${episode.id}.${episode.containerExtension}';

  @override
  /// Catch-up for the picked programme.
  ///
  /// The date/time is sent as the wall-clock value the user selected: Xtream
  /// providers expect the value in *their* guide's timezone, and the guide the
  /// user picks from is already rendered in that timezone. Converting to UTC
  /// here would shift the request by the client's offset and miss the
  /// programme.
  String? timeshiftUrl(Channel channel, DateTime start, int durationMinutes) {
    final formatted =
        '${start.year}-${two(start.month)}-${two(start.day)}:${two(start.hour)}-${two(start.minute)}';
    return '$_host/streaming/timeshift.php?username=${playlist.username}'
        '&password=${playlist.password}&stream=${channel.streamId}'
        '&start=$formatted&duration=$durationMinutes';
  }

  /// Full M3U export, useful for importing into another player.
  String m3uExportUrl({String output = 'ts'}) =>
      '$_host/get.php?username=${playlist.username}&password=${playlist.password}'
          '&type=m3u_plus&output=$output';

  static String two(int v) => v.toString().padLeft(2, '0');
}

/// Plain M3U / M3U8 playlist source.
class M3uSource implements PlaylistSource {
  @override
  final Playlist playlist;
  final Dio _dio;
  final String userAgent;

  List<Channel> _channels = const [];
  List<Movie> _movies = const [];
  final Map<int, Series> _series = {};
  final Map<int, List<Episode>> _episodes = {};
  final Set<String> _liveGroups = {};
  final Set<String> _vodGroups = {};
  final Set<String> _seriesGroups = {};

  M3uSource(this.playlist, {Dio? dio, this.userAgent = 'IPTVPlayer/1.0'}) : _dio = dio ?? Dio();

  @override
  Future<PlaylistAuth> authenticate() async {
    final res = await _dio.getUri<String>(
      Uri.parse(playlist.url),
      options: Options(responseType: ResponseType.plain, headers: {'User-Agent': userAgent}),
    );
    final body = res.data ?? '';
    if (!body.contains('#EXTM3U')) {
      return const PlaylistAuth(ok: false, message: 'Not a valid M3U playlist');
    }
    _parse(body);
    return const PlaylistAuth(ok: true, status: 'active');
  }

  void _parse(String body) {
    final channels = <Channel>[];
    final movies = <Movie>[];
    final series = <int, Series>{};
    final episodes = <int, List<Episode>>{};
    var pending = <String, String>{};
    var pendingName = '';
    var index = 0;
    Duration? pendingDuration;

    for (final line in body.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#EXTINF')) {
        pending = _attributes(trimmed);
        pendingName = trimmed.contains(',') ? trimmed.split(',').last.trim() : '';
        pendingDuration = _duration(trimmed);
        continue;
      }
      if (trimmed.startsWith('#')) continue;

      index++;
      final group = pending['group-title'] ?? '';
      final logo = pending['tvg-logo'] ?? '';
      final tvgId = pending['tvg-id'];
      final name = pendingName.isEmpty ? 'Channel $index' : pendingName;
      final ext = _extension(trimmed);

      if (_looksLikeEpisode(trimmed, name)) {
        final seriesId = _stableId(pending['tvg-id'] ?? name);
        final s = series.putIfAbsent(
          seriesId,
          () => Series(
            seriesId: seriesId,
            name: _seriesTitle(name),
            cover: logo,
            categoryId: group,
          ),
        );
        episodes.putIfAbsent(seriesId, () => []).add(
              Episode(
                id: trimmed,
                episodeNum: (episodes[seriesId]?.length ?? 0) + 1,
                season: 1,
                title: name,
                containerExtension: ext,
                image: s.cover,
              ),
            );
      } else if (_isVodGroup(group) || _isVodExtension(ext)) {
        _vodGroups.add(group);
        movies.add(Movie(
          num: index,
          streamId: _stableId(trimmed),
          name: name,
          icon: logo,
          categoryId: group,
          containerExtension: ext,
          duration: pendingDuration?.inMinutes.toString() ?? '',
        ));
      } else {
        _liveGroups.add(group);
        channels.add(Channel(
          num: index,
          name: name,
          streamId: _stableId(trimmed),
          icon: logo,
          epgChannelId: tvgId,
          categoryId: group,
        ));
      }
      pending = {};
      pendingName = '';
    }

    for (final e in episodes.entries) {
      _seriesGroups.add(series[e.key]?.categoryId ?? '');
    }
    _channels = channels;
    _movies = movies;
    _series
      ..clear()
      ..addAll(series);
    _episodes
      ..clear()
      ..addAll(episodes);
    _urls.clear();
    // Rebuild index -> url mapping.
    _rebuildUrls(body);
  }

  final Map<int, String> _urls = {};

  void _rebuildUrls(String body) {
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#') && !trimmed.startsWith('#EXTINF')) continue;
      if (!trimmed.startsWith('#')) {
        _urls[_stableId(trimmed)] = trimmed;
      }
    }
  }

  static Map<String, String> _attributes(String line) {
    final map = <String, String>{};
    for (final match in RegExp(r'([\w-]+)="([^"]*)"').allMatches(line)) {
      map[match.group(1)!.toLowerCase()] = match.group(2)!;
    }
    return map;
  }

  static Duration? _duration(String line) {
    final match = RegExp(r'#EXTINF:(-?\d+)').firstMatch(line);
    if (match == null) return null;
    final seconds = int.tryParse(match.group(1)!) ?? 0;
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }

  static String _extension(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot <= 0 || clean.length - dot > 5) return 'mp4';
    return clean.substring(dot + 1).toLowerCase();
  }

  static bool _isVodExtension(String ext) =>
      const {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg'}.contains(ext);

  static bool _isVodGroup(String group) {
    final g = group.toLowerCase();
    return g.contains('vod') || g.contains('movie') || g.contains('film') || g.contains('cinema');
  }

  static bool _looksLikeEpisode(String url, String name) {
    final ext = _extension(url);
    if (!_isVodExtension(ext)) return false;
    return RegExp(r'(s\d{1,2}\s?e\d{1,3})', caseSensitive: false).hasMatch(name) ||
        RegExp(r'(season\s?\d+)', caseSensitive: false).hasMatch(name);
  }

  static String _seriesTitle(String name) {
    final match = RegExp(r'^(.*?)\s*[sS]\d{1,2}\s?[eE]\d{1,3}').firstMatch(name);
    return (match?.group(1) ?? name).trim();
  }

  static int _stableId(String value) => value.hashCode & 0x7fffffff;

  @override
  Future<List<Category>> categories(ContentKind kind) async {
    final groups = switch (kind) {
      ContentKind.live => _liveGroups,
      ContentKind.movie => _vodGroups,
      ContentKind.series => _seriesGroups,
    };
    final list = groups.toList()..sort();
    return [for (final g in list) Category(id: g, name: g.isEmpty ? 'Ungrouped' : g)];
  }

  @override
  Future<List<Channel>> channels({String? categoryId}) async => _channels
      .where((c) => categoryId == null || categoryId.isEmpty || c.categoryId == categoryId)
      .toList();

  @override
  Future<List<Movie>> movies({String? categoryId}) async => _movies
      .where((m) => categoryId == null || categoryId.isEmpty || m.categoryId == categoryId)
      .toList();

  @override
  Future<List<Series>> series({String? categoryId}) async => _series.values
      .where((s) => categoryId == null || categoryId.isEmpty || s.categoryId == categoryId)
      .toList();

  @override
  Future<SeriesInfo> seriesInfo(int seriesId) async {
    final s = _series[seriesId] ??
        Series(seriesId: seriesId, name: 'Series', categoryId: '');
    return SeriesInfo(series: s, seasons: const [1], episodes: {1: _episodes[seriesId] ?? const []});
  }

  @override
  Future<Movie> movieInfo(int vodId) async => _movies.firstWhere(
        (m) => m.streamId == vodId,
        orElse: () => Movie(streamId: vodId, name: 'Movie'),
      );

  @override
  Future<List<EpgProgram>> shortEpg(int streamId) async => const [];

  @override
  String liveUrl(Channel channel) => _urls[channel.streamId] ?? '';

  @override
  String movieUrl(Movie movie) => _urls[movie.streamId] ?? '';

  @override
  String episodeUrl(Episode episode) =>
      episode.id.startsWith('http') ? episode.id : (_urls[int.tryParse(episode.id) ?? 0] ?? '');

  @override
  String? timeshiftUrl(Channel channel, DateTime start, int durationMinutes) => null;
}
