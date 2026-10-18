import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibo_player/data/models/models.dart';
import 'package:ibo_player/data/sources/playlist_source.dart';

/// Serves a canned body for every request, so the sources can be exercised
/// without a network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.json = false});

  final String body;

  /// When true the body is served as `application/json`, which is what Dio's
  /// default transformer keys off when deciding to decode.
  final bool json;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [
            json ? Headers.jsonContentType : Headers.textPlainContentType,
          ],
        },
      );
}

const _xtream = Playlist(
  id: 'p1',
  name: 'Provider',
  url: 'http://example.com:8080/',
  username: 'user',
  password: 'pass',
);

const _m3uBody = '''
#EXTM3U
#EXTINF:-1 tvg-id="news" tvg-name="News" tvg-logo="http://logo/news.png" group-title="News",News HD
http://example.com/live/user/pass/101.ts
#EXTINF:-1 tvg-id="sport" tvg-name="Sport" tvg-logo="http://logo/sport.png" group-title="Sport",Sport 1
http://example.com/live/user/pass/102.ts
#EXTINF:-1 tvg-id="sport2" tvg-name="Sport 2" tvg-logo="http://logo/sport2.png" group-title="Sport",Sport 2
http://example.com/live/user/pass/103.m3u8
''';

void main() {
  group('XtreamSource stream URLs', () {
    test('builds live, movie and episode URLs from the account', () {
      final source = XtreamSource(_xtream);

      final live = source.liveUrl(const Channel(num: 1, name: 'News', streamId: 42));
      expect(live, 'http://example.com:8080/live/user/pass/42.ts');

      final movie = source.movieUrl(
        const Movie(num: 1, name: 'Film', streamId: 7, containerExtension: 'mkv'),
      );
      expect(movie, 'http://example.com:8080/movie/user/pass/7.mkv');

      // The episode id carries the provider's own extension.
      final episode = source.episodeUrl(const Episode(
        id: '99',
        episodeNum: 1,
        season: 1,
        containerExtension: 'mp4',
      ));
      expect(episode, 'http://example.com:8080/series/user/pass/99.mp4');
    });

    test('honours the stream format setting', () {
      final hls = XtreamSource(_xtream, format: 'm3u8');
      expect(hls.liveUrl(const Channel(num: 1, name: 'x', streamId: 1)), endsWith('.m3u8'));

      final ts = XtreamSource(_xtream, format: 'ts');
      expect(ts.liveUrl(const Channel(num: 1, name: 'x', streamId: 1)), endsWith('.ts'));
    });

    test('falls back to m3u8 for protected providers when no format is forced', () {
      const protected = Playlist(
        id: 'p2',
        name: 'Protected',
        url: 'http://example.com:8080',
        username: 'u',
        password: 'p',
        isProtected: true,
      );
      final source = XtreamSource(protected);
      expect(source.liveUrl(const Channel(num: 1, name: 'x', streamId: 5)), endsWith('.m3u8'));
    });

    test('formats the catch-up window as timeshift.php expects', () {
      final source = XtreamSource(_xtream);
      final url = source.timeshiftUrl(
        const Channel(num: 1, name: 'News', streamId: 42),
        DateTime(2024, 3, 7, 21, 5),
        90,
      );

      expect(url, isNotNull);
      expect(url, contains('/streaming/timeshift.php'));
      expect(url, contains('stream=42'));
      expect(url, contains('start=2024-03-07:21-05'));
      expect(url, contains('duration=90'));
    });
  });

  group('M3uSource parsing', () {
    test('groups channels by group-title and keeps stream URLs', () async {
      final source = M3uSource(
        const Playlist(id: 'm1', name: 'List', url: 'http://example.com/list.m3u', type: PlaylistType.m3u),
        dio: Dio()..httpClientAdapter = _FakeAdapter(_m3uBody),
      );

      await source.authenticate();

      final categories = await source.categories(ContentKind.live);
      expect(categories.map((c) => c.name), containsAll(['News', 'Sport']));

      final channels = await source.channels();
      expect(channels, hasLength(3));
      expect(channels.first.name, 'News HD');
      expect(channels.first.icon, 'http://logo/news.png');

      // Playback resolves through the parsed URL table.
      final sport = channels.firstWhere((c) => c.name == 'Sport 2');
      expect(source.liveUrl(sport), 'http://example.com/live/user/pass/103.m3u8');
    });

    test('returns nothing for an empty playlist', () async {
      final source = M3uSource(
        const Playlist(id: 'm2', name: 'Empty', url: 'http://example.com/empty.m3u', type: PlaylistType.m3u),
        dio: Dio()..httpClientAdapter = _FakeAdapter('#EXTM3U\n'),
      );

      await source.authenticate();
      expect(await source.channels(), isEmpty);
    });
  });

  group('ContentKind', () {
    test('exposes a stable key used by storage and API actions', () {
      expect(ContentKind.live.key, 'live');
      expect(ContentKind.movie.key, 'movie');
      expect(ContentKind.series.key, 'series');
    });
  });

  group('XtreamSource authentication', () {
    test('reads the account envelope', () async {
      final source = XtreamSource(
        _xtream,
        dio: Dio()
          ..httpClientAdapter = _FakeAdapter(json: true, '''
        {
          "user_info": {
            "auth": 1, "status": "Active", "exp_date": "1735689600",
            "is_trial": "0", "max_connections": "2",
            "allowed_output_formats": ["m3u8", "ts"]
          },
          "server_info": { "url": "example.com", "port": "8080", "timezone": "UTC" }
        }
      '''),
      );

      final auth = await source.authenticate();

      expect(auth.ok, isTrue);
      expect(auth.expiryDateTime, isNotNull);
      expect(auth.maxConnections, 2);
      expect(auth.isTrial, isFalse);
    });

    test('rejects an inactive account', () async {
      final source = XtreamSource(
        _xtream,
        dio: Dio()
          ..httpClientAdapter = _FakeAdapter(json: true, '''
        { "user_info": { "auth": 0, "status": "Expired", "max_connections": "1" } }
      '''),
      );

      final auth = await source.authenticate();

      expect(auth.ok, isFalse);
      expect(auth.status, 'Expired');
    });
  });
}
