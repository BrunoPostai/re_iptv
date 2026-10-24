import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:re_iptv/core/constants.dart';
import 'package:re_iptv/data/models/models.dart';
import 'package:re_iptv/data/storage/app_storage.dart';

/// The catalogue is decoded in a background isolate, which means every entry has
/// to survive being copied across that boundary. These tests round-trip the four
/// shapes through a real box to prove it does, and that a corrupt store is still
/// swallowed rather than thrown.
void main() {
  final storage = AppStorage();
  late Directory dir;
  late Box<dynamic> box;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('re_iptv_storage');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('content');
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('the catalogue survives the trip through the background isolate', () async {
    final channels = [
      const Channel(streamId: 1, name: 'One', num: 1, icon: 'one.png', categoryId: 'sports'),
      const Channel(streamId: 2, name: 'Two', categoryId: 'news'),
    ];
    final movies = [
      const Movie(streamId: 11, name: 'A Film', categoryId: 'action', plot: 'Plot'),
    ];
    final series = [
      const Series(seriesId: 21, name: 'A Show', cover: 'cover.jpg', categoryId: 'drama'),
    ];
    const categories = [Category(id: 'sports', name: 'Sports'), Category(id: 'news', name: 'News')];

    await storage.saveChannels(box, channels);
    await storage.saveMovies(box, movies);
    await storage.saveSeries(box, series);
    await storage.saveCategories(box, ContentKindKey.live, categories);

    expect(await storage.channels(box), channels);
    expect(await storage.movies(box), movies);
    expect(await storage.series(box), series);
    expect(await storage.categories(box, ContentKindKey.live), categories);
  });

  test('an empty store yields an empty list', () async {
    expect(await storage.channels(box), isEmpty);
    expect(await storage.categories(box, ContentKindKey.movie), isEmpty);
  });

  test('an unreadable store yields an empty list instead of throwing', () async {
    await box.put(ContentKeys.channels, '{not json');
    expect(await storage.channels(box), isEmpty);

    await box.put(ContentKeys.movies, json.encode({'not': 'a list'}));
    expect(await storage.movies(box), isEmpty);
  });
}
