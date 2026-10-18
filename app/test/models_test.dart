import 'dart:convert';

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

  group('EpgProgram', () {
    test('decodes base64 titles and descriptions', () {
      final program = EpgProgram.fromJson({
        'title': base64.encode(utf8.encode('Morning News')),
        'description': base64.encode(utf8.encode('Headlines and weather')),
        'start_timestamp': '1770000000',
        'stop_timestamp': '1770003600',
      });

      expect(program.title, 'Morning News');
      expect(program.description, 'Headlines and weather');
      expect(program.hasUsableTime, isTrue);
    });

    test('keeps plain-text titles that merely look like base64', () {
      expect(EpgProgram.fromJson(const {'title': 'News'}).title, 'News');
      expect(EpgProgram.fromJson(const {'title': 'Film'}).title, 'Film');
    });

    test('falls back to the UTC start/stop strings', () {
      final program = EpgProgram.fromJson(const {
        'title': 'Late Show',
        'start': '2026-03-01 20:00:00',
        'end': '2026-03-01 21:30:00',
      });

      expect(program.hasUsableTime, isTrue);
      expect(program.end.difference(program.start), const Duration(minutes: 90));
      // Providers send UTC; the app renders the viewer's local time.
      expect(program.start.toUtc(), DateTime.utc(2026, 3, 1, 20));
    });

    test('reports unusable times instead of inventing 1970', () {
      final program = EpgProgram.fromJson(const {'title': 'Unknown'});
      expect(program.hasUsableTime, isFalse);
      expect(program.isNow, isFalse);
    });

    test('prefers timestamps when both shapes are present', () {
      final program = EpgProgram.fromJson(const {
        'title': 'Both',
        'start_timestamp': '1770000000',
        'start': '2026-03-01 20:00:00',
      });
      expect(program.start.millisecondsSinceEpoch, 1770000000 * 1000);
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
