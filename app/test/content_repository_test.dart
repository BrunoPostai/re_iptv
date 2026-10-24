import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:re_iptv/core/config/app_config.dart';
import 'package:re_iptv/data/models/models.dart';
import 'package:re_iptv/data/repositories/content_repository.dart';
import 'package:re_iptv/data/repositories/playlist_repository.dart';
import 'package:re_iptv/data/sources/playlist_source.dart';
import 'package:re_iptv/data/storage/app_storage.dart';

/// `ContentRepository` keeps the decoded catalogue for the playlist in use. These
/// tests pin the two things that make that safe — a catalogue is only read once,
/// and anything that writes to the store drops what was cached — plus the resume
/// progress the player writes and the detail screens read back.
void main() {
  const playlist =
      Playlist(id: 'p1', name: 'One', url: 'http://playlist.invalid', type: PlaylistType.m3u);

  late Directory dir;
  late AppStorage storage;
  late ContentRepository content;
  late Box<dynamic> box;

  Future<Box<dynamic>> boxFor(String playlistId) => storage.openContentBox(playlistId);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('re_iptv_content');
    Hive.init(dir.path);
    storage = AppStorage();
    content = ContentRepository(storage, PlaylistRepository(storage, AppConfig.fromJson(const {})));
    box = await boxFor(playlist.id);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  WatchProgress film({Duration position = const Duration(minutes: 1)}) => WatchProgress(
        id: '7',
        kind: 'movie',
        title: 'A Film',
        position: position,
        duration: const Duration(minutes: 100),
        updatedAt: DateTime(2026, 1, 1),
      );

  WatchProgress episode() => WatchProgress(
        id: '3:9',
        kind: 'episode',
        title: 'An Episode',
        position: const Duration(minutes: 2),
        duration: const Duration(minutes: 45),
        updatedAt: DateTime(2026, 1, 2),
        parentId: 3,
        season: 1,
        episodeNum: 9,
      );

  test('a film resumes where it was left', () async {
    await content.saveProgress(playlist, film(position: const Duration(minutes: 12)));

    final saved = await content.continueWatching(playlist, ContentKind.movie);

    // The player files a film under this id and the detail screen looks it up
    // under the same one: were the two ever to disagree, the film would start
    // again from the beginning instead of resuming.
    expect(saved.single.id, '7');
    expect(saved.single.position, const Duration(minutes: 12));
  });

  test('an episode is not filed with the films', () async {
    await content.saveProgress(playlist, film());
    await content.saveProgress(playlist, episode());

    expect((await content.continueWatching(playlist, ContentKind.movie)).map((p) => p.id), ['7']);
    expect((await content.continueWatching(playlist, ContentKind.series)).map((p) => p.id), ['3:9']);
  });

  test('re-watching moves an entry to the front instead of adding another', () async {
    await content.saveProgress(playlist, film(position: const Duration(minutes: 5)));
    await content.saveProgress(playlist, episode());
    await content.saveProgress(playlist, film(position: const Duration(minutes: 40)));

    final films = await content.continueWatching(playlist, ContentKind.movie);

    expect(films.length, 1);
    expect(films.single.position, const Duration(minutes: 40));
  });

  test('clearing one entry leaves the rest of the list alone', () async {
    await content.saveProgress(playlist, film(position: const Duration(minutes: 40)));
    await content.saveProgress(playlist, episode());

    await content.clearProgress(playlist, film());

    expect(await content.continueWatching(playlist, ContentKind.movie), isEmpty);
    expect((await content.continueWatching(playlist, ContentKind.series)).map((p) => p.id), ['3:9']);
  });

  test('a catalogue is read once and then served from memory', () async {
    await storage.saveChannels(box, const [Channel(streamId: 1, name: 'One')]);

    final first = await content.channels(playlist);

    expect(first.single.name, 'One');
    expect(await content.channels(playlist), same(first));
  });

  test('visiting another kind keeps what was already read', () async {
    await storage.saveChannels(box, const [Channel(streamId: 1, name: 'One')]);
    await storage.saveMovies(box, const [Movie(streamId: 2, name: 'A Film')]);

    final channels = await content.channels(playlist);

    expect((await content.movies(playlist)).single.name, 'A Film');
    expect(await content.channels(playlist), same(channels));
  });

  test('categories are cached per kind', () async {
    await storage.saveCategories(box, ContentKindKey.live, const [Category(id: 'l', name: 'Live')]);
    await storage.saveCategories(box, ContentKindKey.movie, const [Category(id: 'm', name: 'Movie')]);

    final live = await content.categories(playlist, ContentKind.live);

    expect((await content.categories(playlist, ContentKind.movie)).single.name, 'Movie');
    expect(live.single.name, 'Live');
    expect(await content.categories(playlist, ContentKind.live), same(live));
  });

  test('only the playlist in use is held', () async {
    const other = Playlist(id: 'p2', name: 'Two', url: 'http://other.invalid', type: PlaylistType.m3u);
    await storage.saveChannels(box, const [Channel(streamId: 1, name: 'One')]);
    await storage.saveChannels(await boxFor(other.id), const [Channel(streamId: 2, name: 'Two')]);

    final first = await content.channels(playlist);
    expect((await content.channels(other)).single.name, 'Two');

    final again = await content.channels(playlist);
    expect(again.single.name, 'One');
    expect(again, isNot(same(first)));
  });

  test('clearing a playlist drops its cache', () async {
    await storage.saveChannels(box, const [Channel(streamId: 1, name: 'One')]);
    final first = await content.channels(playlist);

    await content.clearPlaylistCache(playlist);
    await storage.saveChannels(box, const [Channel(streamId: 3, name: 'Three')]);

    final again = await content.channels(playlist);
    expect(again.single.name, 'Three');
    expect(again, isNot(same(first)));
  });

  test('a sync drops the cache even when it fails', () async {
    // Port 1 on loopback refuses immediately, so the sync throws before it can
    // write anything — which is exactly the case the cache must not survive.
    const unreachable =
        Playlist(id: 'unreachable', name: 'Unreachable', url: 'http://127.0.0.1:1', type: PlaylistType.m3u);
    final unreachableBox = await boxFor(unreachable.id);
    await storage.saveChannels(unreachableBox, const [Channel(streamId: 1, name: 'Before')]);

    final first = await content.channels(unreachable);
    expect(first.single.name, 'Before');

    await storage.saveChannels(unreachableBox, const [Channel(streamId: 2, name: 'After')]);
    await expectLater(content.sync(unreachable), throwsA(anything));

    final again = await content.channels(unreachable);
    expect(again.single.name, 'After');
    expect(again, isNot(same(first)));
  });

  test('the lists handed out cannot be modified in place', () async {
    await storage.saveChannels(box, const [Channel(streamId: 1, name: 'One')]);

    final channels = await content.channels(playlist);

    expect(() => channels.add(const Channel(streamId: 9, name: 'Nine')), throwsUnsupportedError);
  });
}
