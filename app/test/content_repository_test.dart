import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:re_iptv/core/config/app_config.dart';
import 'package:re_iptv/core/constants.dart';
import 'package:re_iptv/data/models/models.dart';
import 'package:re_iptv/data/repositories/content_repository.dart';
import 'package:re_iptv/data/repositories/playlist_repository.dart';
import 'package:re_iptv/data/sources/playlist_source.dart';
import 'package:re_iptv/data/storage/app_storage.dart';

/// `ContentRepository` keeps the decoded catalogue for the playlist in use. These
/// tests pin the two things that make that safe — a catalogue is only read once,
/// and anything that writes to the store drops what was cached — plus the resume
/// progress the player writes and the detail screens read back, and the guide,
/// which is fetched per channel per day rather than per channel switch.
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

  test('an episode is filed under the id the page looks it up by, however it is numbered', () async {
    // Not every panel numbers its episodes plainly: `e9`, `007`, or a whole URL
    // are all real, and the fallback for each is the episode number. The page
    // used to look the position up under the provider's raw episode id while the
    // player filed it under the stream id derived from it, so those panels lost
    // the episode's progress bar and started the episode over from the top.
    const odd = Episode(id: 'e9', episodeNum: 9, season: 1);
    const padded = Episode(id: '007', episodeNum: 7, season: 1);
    const plain = Episode(id: '42', episodeNum: 7, season: 1);
    const url = Episode(id: 'http://playlist.invalid/series/e9.mp4', episodeNum: 9, season: 1);

    expect(ContentRepository.episodeProgressId(3, odd.streamId), '3:9');
    expect(ContentRepository.episodeProgressId(3, padded.streamId), '3:7');
    expect(ContentRepository.episodeProgressId(3, url.streamId), '3:9');
    // A plain id is used as it is, and is not the episode number.
    expect(ContentRepository.episodeProgressId(3, plain.streamId), '3:42');

    await content.saveProgress(
      playlist,
      WatchProgress(
        id: ContentRepository.episodeProgressId(3, odd.streamId),
        kind: 'episode',
        title: 'An Episode',
        position: const Duration(minutes: 2),
        duration: const Duration(minutes: 45),
        updatedAt: DateTime(2026, 1, 2),
        parentId: 3,
        season: 1,
        episodeNum: 9,
      ),
    );

    // Read back exactly as the page reads it.
    final saved = await content.continueWatching(playlist, ContentKind.series);
    expect(saved.single.id, ContentRepository.episodeProgressId(3, odd.streamId));
  });

  test('re-watching moves an entry to the front instead of adding another', () async {    await content.saveProgress(playlist, film(position: const Duration(minutes: 5)));
    await content.saveProgress(playlist, episode());
    await content.saveProgress(playlist, film(position: const Duration(minutes: 40)));

    final films = await content.continueWatching(playlist, ContentKind.movie);

    expect(films.length, 1);
    expect(films.single.position, const Duration(minutes: 40));
  });

  test('an episode marks its series watched, not a film of its own', () {
    expect(ContentRepository.watchedEntry('episode', 9, 3), (ContentKind.series, 3));
    expect(ContentRepository.watchedEntry('movie', 7, 7), (ContentKind.movie, 7));
    expect(ContentRepository.watchedEntry('live', 5, 5), (ContentKind.live, 5));
  });

  test('the watched list the marker reads is the one the player writes', () async {
    final (kind, id) = ContentRepository.watchedEntry('episode', 9, 3);
    await content.markWatched(playlist, kind, id);

    // The series grid draws its watched check from this list, under the series
    // id: were the two to disagree, watching an episode would light up a film.
    expect(await content.watched(playlist, ContentKind.series), ['3']);
    expect(await content.watched(playlist, ContentKind.movie), isEmpty);
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

  /// A repository whose source counts guide requests, so what the repository
  /// asks the panel for can be observed directly.
  (ContentRepository, _CountingSource) countingContent({List<EpgProgram> programs = const []}) {
    final source = _CountingSource(
      const Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid', type: PlaylistType.xc),
      programs: programs,
    );
    final playlists = _FakePlaylists(storage, AppConfig.fromJson(const {}), source);
    return (ContentRepository(storage, playlists), source);
  }

  EpgProgram programme() => EpgProgram(
        title: 'Evening News',
        start: DateTime(2026, 1, 1, 20),
        end: DateTime(2026, 1, 1, 21),
      );

  test('a channel guide is fetched once and then answered from memory', () async {
    final (content, source) = countingContent(programs: [programme()]);
    const playlist = Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid');

    final first = await content.shortEpg(playlist, 11);
    final second = await content.shortEpg(playlist, 11);

    expect(first.single.title, 'Evening News');
    expect(second.single.title, 'Evening News');
    // Per channel per day: picking a channel again must not ask the panel again,
    // which is what made browsing a list cost a request per row.
    expect(source.callsFor(11), 1);
  });

  test('two lookups of one channel share a single request', () async {
    final (content, source) = countingContent(programs: [programme()]);
    const playlist = Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid');

    await Future.wait([
      content.shortEpg(playlist, 11),
      content.shortEpg(playlist, 11),
    ]);

    expect(source.callsFor(11), 1);
  });

  test('a channel with no guide is not asked for over and over', () async {
    final (content, source) = countingContent();
    const playlist = Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid');

    expect(await content.shortEpg(playlist, 12), isEmpty);
    expect(await content.shortEpg(playlist, 12), isEmpty);

    // An empty answer is remembered for [epgEmptyRetry] rather than for the day:
    // long enough that switching between channels does not re-ask, short enough
    // that a request which failed is tried again.
    expect(source.callsFor(12), 1);
  });

  test('a guide outlives a restart', () async {
    const playlist = Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid');
    final (before, beforeRestart) = countingContent(programs: [programme()]);
    await before.shortEpg(playlist, 11);
    expect(beforeRestart.callsFor(11), 1);

    // A second repository over the same store is what a restart looks like. The
    // panel must not be asked again for a listing that was already fetched: the
    // guide opening with a request per channel is what this is for.
    final (after, afterRestart) = countingContent(programs: [programme()]);
    final programs = await after.shortEpg(playlist, 11);

    expect(programs.single.title, 'Evening News');
    expect(programs.single.start, DateTime(2026, 1, 1, 20));
    expect(programs.single.end, DateTime(2026, 1, 1, 21));
    expect(afterRestart.callsFor(11), 0);
  });

  test('a guide that came back empty is asked for again after a restart', () async {
    const playlist = Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid');
    final (before, _) = countingContent();
    expect(await before.shortEpg(playlist, 12), isEmpty);

    final (after, afterRestart) = countingContent(programs: [programme()]);
    final programs = await after.shortEpg(playlist, 12);

    // A channel with nothing to show leaves nothing behind, because an empty
    // answer is as likely to be a request that failed as a channel without a
    // guide — so the next session asks again.
    expect(afterRestart.callsFor(12), 1);
    expect(programs.single.title, 'Evening News');
  });

  test('a guide stored for a day that has passed is dropped', () async {
    const playlist = Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid');
    final guideBox = await boxFor(playlist.id);
    await storage.saveEpgPrograms(guideBox, 'epg-2000-01-01-11', [programme()]);

    final (content, source) = countingContent(programs: [programme()]);
    await content.shortEpg(playlist, 11);

    // The day is in the key, so a listing from another day is found and dropped
    // without being read at all, and yesterday's guide is not served as today's.
    expect(storage.keysStartingWith(guideBox, 'epg-2000'), isEmpty);
    expect(storage.keysStartingWith(guideBox, 'epg-'), hasLength(1));
    expect(source.callsFor(11), 1);
  });

  test('the store keeps the channels the session cache keeps, and no more', () async {
    const playlist = Playlist(id: 'xc', name: 'Xtream', url: 'http://panel.invalid');
    final (content, source) = countingContent(programs: [programme()]);
    final guideBox = await boxFor(playlist.id);

    for (var streamId = 1; streamId <= epgCacheLimit + 1; streamId++) {
      await content.shortEpg(playlist, streamId);
    }

    // One channel past the limit, so the first has gone — from the box as well as
    // from memory, or a browse across a whole playlist would fill the disk with
    // the listings the session itself has already forgotten.
    expect(storage.keysStartingWith(guideBox, 'epg-'), hasLength(epgCacheLimit));

    // And it is a real eviction: asking for that channel again is a request.
    await content.shortEpg(playlist, 1);
    expect(source.callsFor(1), 2);
  });
}

/// A `PlaylistRepository` handing out one counting source.
class _FakePlaylists extends PlaylistRepository {
  _FakePlaylists(super._storage, super._config, this._source);

  final _CountingSource _source;

  @override
  PlaylistSource sourceFor(Playlist playlist) => _source;
}

/// A source that answers the guide from memory and counts what it was asked for.
class _CountingSource extends M3uSource {
  _CountingSource(super.playlist, {this.programs = const []});

  /// What the panel answers with; empty stands for a channel with no guide.
  final List<EpgProgram> programs;

  final Map<int, int> _calls = {};

  int callsFor(int streamId) => _calls[streamId] ?? 0;

  @override
  Future<List<EpgProgram>> shortEpg(int streamId) async {
    _calls[streamId] = callsFor(streamId) + 1;
    return programs;
  }
}
