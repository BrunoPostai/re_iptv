import 'package:flutter_test/flutter_test.dart';
import 'package:re_iptv/data/models/models.dart';

void main() {
  group('Playlist model', () {
    test('round-trips through JSON', () {
      const playlist = Playlist(
        id: 'abc',
        name: 'My playlist',
        url: 'http://example.com:8080',
        username: 'user',
        password: 'pass',
      );

      final restored = Playlist.fromJson(playlist.toJson());

      expect(restored.id, playlist.id);
      expect(restored.name, playlist.name);
      expect(restored.host, 'http://example.com:8080');
      expect(restored.type, PlaylistType.xc);
    });

    test('host strips any path', () {
      const playlist = Playlist(
        id: 'abc',
        name: 'x',
        url: 'http://example.com:8080/player_api.php',
        username: 'u',
        password: 'p',
      );
      expect(playlist.host, 'http://example.com:8080');
    });
  });

  group('Movie model', () {
    test('parses an Xtream payload', () {
      final movie = Movie.fromJson(const {
        'num': 1,
        'name': 'Example',
        'stream_id': 42,
        'stream_icon': 'http://example.com/poster.jpg',
        'rating_5based': '4.2',
        'category_id': '7',
        'container_extension': 'mkv',
      });

      expect(movie.streamId, 42);
      expect(movie.name, 'Example');
      expect(movie.rating5Based, 4.2);
      expect(movie.containerExtension, 'mkv');
    });
  });

  group('WatchProgress', () {
    test('computes completion percentage', () {
      final progress = WatchProgress(
        id: '1',
        kind: 'movie',
        title: 'Example',
        position: const Duration(minutes: 30),
        duration: const Duration(minutes: 60),
        updatedAt: DateTime(2024),
      );

      expect(progress.percent, 0.5);
    });
  });
}
