import 'package:equatable/equatable.dart';

/// Tolerant numeric helpers.
///
/// Xtream providers are inconsistent: the same field may arrive as an int, a
/// double or a string. These helpers also avoid the shadowing problem that
/// occurs inside classes that declare a member named `num`.
int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

/// Playlist kinds supported by the app.
enum PlaylistType { xc, m3u, local }

PlaylistType playlistTypeFrom(String? value) {
  switch ((value ?? 'xc').toLowerCase()) {
    case 'm3u':
    case 'm3u8':
      return PlaylistType.m3u;
    case 'local':
      return PlaylistType.local;
    default:
      return PlaylistType.xc;
  }
}

String playlistTypeTo(PlaylistType type) => switch (type) {
      PlaylistType.m3u => 'm3u',
      PlaylistType.local => 'local',
      PlaylistType.xc => 'xc',
    };

class Playlist extends Equatable {
  final String id;
  final String name;
  final String url;
  final String username;
  final String password;
  final PlaylistType type;
  final String epgUrl;
  final bool isProtected;
  final bool isDemo;

  const Playlist({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
    this.type = PlaylistType.xc,
    this.epgUrl = '',
    this.isProtected = false,
    this.isDemo = false,
  });

  String get host {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  String get displayAccount => username.isEmpty ? host : '$username · $host';

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: (j['id'] ?? '').toString(),
        name: (j['playlist_name'] ?? j['name'] ?? 'Playlist').toString(),
        url: (j['url'] ?? j['origin_url'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        type: playlistTypeFrom((j['playlist_type'] ?? j['origin_type']) as String?),
        epgUrl: (j['epg_url'] ?? '').toString(),
        isProtected: (j['is_protected'] as num?)?.toInt() == 1,
        isDemo: j['is_demo'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'playlist_name': name,
        'playlist_type': playlistTypeTo(type),
        // `origin_*` are written for schema parity with the original, which
        // keeps the address the playlist was created from next to the URL in
        // use. For a playlist that has never been redirected the two agree.
        'origin_type': playlistTypeTo(type),
        'origin_url': url,
        'url': url,
        'username': username,
        'password': password,
        'epg_url': epgUrl,
        'is_protected': isProtected ? 1 : 0,
        'is_demo': isDemo,
      };

  Playlist copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    PlaylistType? type,
    String? epgUrl,
    bool? isProtected,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        type: type ?? this.type,
        epgUrl: epgUrl ?? this.epgUrl,
        isProtected: isProtected ?? this.isProtected,
        isDemo: isDemo,
      );

  @override
  List<Object?> get props => [id, name, url, username, password, type, epgUrl, isProtected, isDemo];
}

class Category extends Equatable {
  final String id;
  final String name;
  final int parentId;

  const Category({required this.id, required this.name, this.parentId = 0});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: (j['category_id'] ?? '').toString(),
        name: (j['category_name'] ?? '').toString(),
        parentId: int.tryParse((j['parent_id'] ?? '0').toString()) ?? 0,
      );

  Map<String, dynamic> toJson() => {'category_id': id, 'category_name': name, 'parent_id': parentId};

  @override
  List<Object?> get props => [id, name, parentId];
}

class Channel extends Equatable {
  final int num;
  final String name;
  final int streamId;
  final String icon;
  final String? epgChannelId;
  final String added;
  final String categoryId;
  final bool hasArchive;
  final int archiveDuration;
  final String directSource;

  const Channel({
    required this.streamId,
    required this.name,
    this.num = 0,
    this.icon = '',
    this.epgChannelId,
    this.added = '',
    this.categoryId = '',
    this.hasArchive = false,
    this.archiveDuration = 0,
    this.directSource = '',
  });

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        num: asInt(j['num']),
        name: (j['name'] ?? '').toString(),
        streamId: asInt(j['stream_id']),
        icon: (j['stream_icon'] ?? '').toString(),
        epgChannelId: j['epg_channel_id']?.toString(),
        added: (j['added'] ?? '').toString(),
        categoryId: (j['category_id'] ?? '').toString(),
        hasArchive: asInt(j['tv_archive']) == 1,
        archiveDuration: asInt(j['tv_archive_duration']),
        directSource: (j['direct_source'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'num': num,
        'name': name,
        'stream_type': 'live',
        'stream_id': streamId,
        'stream_icon': icon,
        'epg_channel_id': epgChannelId,
        'added': added,
        'category_id': categoryId,
        'custom_sid': '',
        'tv_archive': hasArchive ? 1 : 0,
        'direct_source': directSource,
        'tv_archive_duration': archiveDuration,
      };

  @override
  List<Object?> get props => [streamId, name, num, icon, epgChannelId, categoryId, hasArchive];
}

class Movie extends Equatable {
  final int num;
  final int streamId;
  final String name;
  final String icon;
  final String rating;
  final double rating5Based;
  final String added;
  final String categoryId;
  final String containerExtension;
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String releaseDate;
  final String duration;
  final String youtubeTrailer;
  final String backdropPath;

  const Movie({
    required this.streamId,
    required this.name,
    this.num = 0,
    this.icon = '',
    this.rating = '',
    this.rating5Based = 0,
    this.added = '',
    this.categoryId = '',
    this.containerExtension = 'mp4',
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.genre = '',
    this.releaseDate = '',
    this.duration = '',
    this.youtubeTrailer = '',
    this.backdropPath = '',
  });

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        num: asInt(j['num']),
        streamId: asInt(j['stream_id']),
        name: (j['name'] ?? '').toString(),
        icon: (j['stream_icon'] ?? '').toString(),
        rating: (j['rating'] ?? '').toString(),
        rating5Based: double.tryParse((j['rating_5based'] ?? '0').toString()) ?? 0,
        added: (j['added'] ?? '').toString(),
        categoryId: (j['category_id'] ?? '').toString(),
        containerExtension: (j['container_extension'] ?? 'mp4').toString(),
        plot: (j['plot'] ?? '').toString(),
        cast: (j['cast'] ?? '').toString(),
        director: (j['director'] ?? '').toString(),
        genre: (j['genre'] ?? '').toString(),
        releaseDate: (j['releaseDate'] ?? j['releasedate'] ?? '').toString(),
        duration: (j['duration'] ?? '').toString(),
        youtubeTrailer: (j['youtube_trailer'] ?? '').toString(),
        backdropPath: (j['backdrop_path']?.toString() ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'num': num,
        'name': name,
        'stream_type': 'movie',
        'stream_id': streamId,
        'stream_icon': icon,
        'rating': rating,
        'rating_5based': rating5Based,
        'added': added,
        'category_id': categoryId,
        'container_extension': containerExtension,
        'plot': plot,
        'cast': cast,
        'director': director,
        'genre': genre,
        'releaseDate': releaseDate,
        'duration': duration,
        'youtube_trailer': youtubeTrailer,
        'backdrop_path': backdropPath,
      };

  Movie copyWith({
    String? plot,
    String? cast,
    String? director,
    String? genre,
    String? releaseDate,
    String? duration,
    String? youtubeTrailer,
    String? backdropPath,
    String? icon,
    double? rating5Based,
  }) =>
      Movie(
        num: num,
        streamId: streamId,
        name: name,
        icon: icon ?? this.icon,
        rating: rating,
        rating5Based: rating5Based ?? this.rating5Based,
        added: added,
        categoryId: categoryId,
        containerExtension: containerExtension,
        plot: plot ?? this.plot,
        cast: cast ?? this.cast,
        director: director ?? this.director,
        genre: genre ?? this.genre,
        releaseDate: releaseDate ?? this.releaseDate,
        duration: duration ?? this.duration,
        youtubeTrailer: youtubeTrailer ?? this.youtubeTrailer,
        backdropPath: backdropPath ?? this.backdropPath,
      );

  @override
  List<Object?> get props => [streamId, name, icon, categoryId, containerExtension, plot];
}

class Series extends Equatable {
  final int num;
  final int seriesId;
  final String name;
  final String cover;
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String releaseDate;
  final String lastModified;
  final String rating;
  final double rating5Based;
  final String backdropPath;
  final String youtubeTrailer;
  final String episodeRunTime;
  final String categoryId;

  const Series({
    required this.seriesId,
    required this.name,
    this.num = 0,
    this.cover = '',
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.genre = '',
    this.releaseDate = '',
    this.lastModified = '',
    this.rating = '',
    this.rating5Based = 0,
    this.backdropPath = '',
    this.youtubeTrailer = '',
    this.episodeRunTime = '0',
    this.categoryId = '',
  });

  factory Series.fromJson(Map<String, dynamic> j) => Series(
        num: asInt(j['num']),
        seriesId: asInt(j['series_id']),
        name: (j['name'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        plot: (j['plot'] ?? '').toString(),
        cast: (j['cast'] ?? '').toString(),
        director: (j['director'] ?? '').toString(),
        genre: (j['genre'] ?? '').toString(),
        releaseDate: (j['releaseDate'] ?? j['release_date'] ?? '').toString(),
        lastModified: (j['last_modified'] ?? '').toString(),
        rating: (j['rating'] ?? '').toString(),
        rating5Based: double.tryParse((j['rating_5based'] ?? '0').toString()) ?? 0,
        backdropPath: (j['backdrop_path'] is List)
            ? (j['backdrop_path'] as List).join(',')
            : (j['backdrop_path'] ?? '').toString(),
        youtubeTrailer: (j['youtube_trailer'] ?? '').toString(),
        episodeRunTime: (j['episode_run_time'] ?? '0').toString(),
        categoryId: (j['category_id'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'num': num,
        'name': name,
        'series_id': seriesId,
        'cover': cover,
        'plot': plot,
        'cast': cast,
        'director': director,
        'genre': genre,
        'releaseDate': releaseDate,
        'last_modified': lastModified,
        'rating': rating,
        'rating_5based': rating5Based,
        'backdrop_path': backdropPath.isEmpty ? <String>[] : [backdropPath],
        'youtube_trailer': youtubeTrailer,
        'episode_run_time': episodeRunTime,
        'category_id': categoryId,
      };

  @override
  List<Object?> get props => [seriesId, name, cover, categoryId, plot];
}

class Episode extends Equatable {
  final String id;
  final int episodeNum;
  final int season;
  final String title;
  final String containerExtension;
  final String plot;
  final String duration;
  final String image;
  final double rating;

  const Episode({
    required this.id,
    required this.episodeNum,
    required this.season,
    this.title = '',
    this.containerExtension = 'mp4',
    this.plot = '',
    this.duration = '',
    this.image = '',
    this.rating = 0,
  });

  factory Episode.fromJson(Map<String, dynamic> j, {required int season}) {
    final info = Map<String, dynamic>.from((j['info'] as Map?) ?? const {});
    return Episode(
      id: (j['id'] ?? '').toString(),
      episodeNum: int.tryParse((j['episode_num'] ?? '0').toString()) ?? 0,
      season: int.tryParse((j['season'] ?? season).toString()) ?? season,
      title: (j['title'] ?? '').toString(),
      containerExtension: (j['container_extension'] ?? 'mp4').toString(),
      plot: (info['plot'] ?? '').toString(),
      duration: (info['duration'] ?? '').toString(),
      image: (info['movie_image'] ?? '').toString(),
      rating: double.tryParse((info['rating'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'episode_num': episodeNum,
        'season': season,
        'title': title,
        'container_extension': containerExtension,
      };

  @override
  List<Object?> get props => [id, episodeNum, season, title, containerExtension];
}

class SeriesInfo extends Equatable {
  final Series series;
  final List<int> seasons;
  final Map<int, List<Episode>> episodes;

  const SeriesInfo({required this.series, this.seasons = const [], this.episodes = const {}});

  @override
  List<Object?> get props => [series, seasons, episodes];
}

class EpgProgram extends Equatable {
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  const EpgProgram({
    required this.title,
    required this.start,
    required this.end,
    this.description = '',
  });

  factory EpgProgram.fromJson(Map<String, dynamic> j) {
    int ts(dynamic v) => int.tryParse((v ?? '0').toString()) ?? 0;
    return EpgProgram(
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      start: DateTime.fromMillisecondsSinceEpoch(ts(j['start_timestamp']) * 1000),
      end: DateTime.fromMillisecondsSinceEpoch(ts(j['stop_timestamp']) * 1000),
    );
  }

  bool get isNow => DateTime.now().isAfter(start) && DateTime.now().isBefore(end);

  @override
  List<Object?> get props => [title, start, end];
}

/// Progress record for "continue watching".
class WatchProgress extends Equatable {
  final String id;
  final String kind; // movie | episode | channel
  final String title;
  final String image;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final int parentId;
  final int season;
  final int episodeNum;
  final String containerExtension;

  const WatchProgress({
    required this.id,
    required this.kind,
    required this.title,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.image = '',
    this.parentId = 0,
    this.season = 0,
    this.episodeNum = 0,
    this.containerExtension = 'mp4',
  });

  double get percent => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  factory WatchProgress.fromJson(Map<String, dynamic> j) => WatchProgress(
        id: (j['id'] ?? '').toString(),
        kind: (j['kind'] ?? 'movie').toString(),
        title: (j['title'] ?? '').toString(),
        image: (j['image'] ?? '').toString(),
        position: Duration(milliseconds: (j['position'] as num?)?.toInt() ?? 0),
        duration: Duration(milliseconds: (j['duration'] as num?)?.toInt() ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((j['updated_at'] as num?)?.toInt() ?? 0),
        parentId: (j['parent_id'] as num?)?.toInt() ?? 0,
        season: (j['season'] as num?)?.toInt() ?? 0,
        episodeNum: (j['episode_num'] as num?)?.toInt() ?? 0,
        containerExtension: (j['container_extension'] ?? 'mp4').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'image': image,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'parent_id': parentId,
        'season': season,
        'episode_num': episodeNum,
        'container_extension': containerExtension,
      };

  @override
  List<Object?> get props => [id, kind, position, duration, updatedAt];
}

/// A resolvable media item handed to the player.
class MediaItem extends Equatable {
  final String title;
  final String url;
  final String? subtitle;
  final String? image;
  final bool isLive;
  final int streamId;
  final String kind;
  final int parentId;
  final int season;
  final int episodeNum;
  final String containerExtension;
  final List<MediaItem> siblings;

  const MediaItem({
    required this.title,
    required this.url,
    this.subtitle,
    this.image,
    this.isLive = false,
    this.streamId = 0,
    this.kind = 'movie',
    this.parentId = 0,
    this.season = 0,
    this.episodeNum = 0,
    this.containerExtension = 'mp4',
    this.siblings = const [],
  });

  @override
  List<Object?> get props => [title, url, isLive, streamId, kind];
}
