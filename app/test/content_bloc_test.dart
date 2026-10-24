import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:re_iptv/blocs/content_bloc.dart';
import 'package:re_iptv/core/config/app_config.dart';
import 'package:re_iptv/core/constants.dart';
import 'package:re_iptv/data/models/models.dart';
import 'package:re_iptv/data/repositories/content_repository.dart';
import 'package:re_iptv/data/repositories/playlist_repository.dart';
import 'package:re_iptv/data/sources/playlist_source.dart';
import 'package:re_iptv/data/storage/app_storage.dart';

/// Filtering a catalogue lower-cases the name of every item in it, and a query
/// change arrives on every keystroke. These tests pin the compromise: the query
/// is recorded at once, the filtering waits for typing to pause, and it is the
/// last keystroke that is filtered for.
void main() {
  const playlist =
      Playlist(id: 'p1', name: 'One', url: 'http://playlist.invalid', type: PlaylistType.m3u);
  const channels = [
    Channel(streamId: 1, name: 'Alpha'),
    Channel(streamId: 2, name: 'Alpine'),
    Channel(streamId: 3, name: 'Beta'),
  ];

  late Directory dir;
  late AppStorage storage;
  late ContentBloc bloc;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('re_iptv_bloc');
    Hive.init(dir.path);
    storage = AppStorage();
    // `AppStorage.init()` asks the platform for a support directory, which a test
    // cannot answer; the settings box is the only thing it would have opened.
    storage.settings = await Hive.openBox<dynamic>(HiveBoxes.settings);
    await storage.savePlaylists(const [playlist]);
    await storage.setRecentPlaylistId(playlist.id);
    await storage.saveChannels(await storage.openContentBox(playlist.id), channels);

    final playlists = PlaylistRepository(storage, AppConfig.fromJson(const {}));
    bloc = ContentBloc(ContentRepository(storage, playlists), playlists);
  });

  tearDown(() async {
    await bloc.close();
    await Hive.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<void> loaded() async {
    // The first state that is neither loading nor empty is the loaded one.
    final ready = bloc.stream.firstWhere(
      (state) => !state.loading && state.channels.isNotEmpty,
    );
    bloc.add(const ContentStarted(ContentKind.live));
    await ready;
    expect(bloc.state.channels, hasLength(3));
  }

  test('a query filters once typing pauses', () async {
    await loaded();

    bloc.add(const ContentQueryChanged('alp'));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(bloc.state.query, 'alp');
    expect(bloc.state.channels, hasLength(3), reason: 'the filter has not run yet');

    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(bloc.state.channels.map((c) => c.name), ['Alpha', 'Alpine']);
  });

  test('a burst of keystrokes is filtered once, for the last of them', () async {
    await loaded();

    // Each of these would narrow the list on its own, so a filter that ran per
    // keystroke would have shown a shorter list well before the pause.
    for (final query in ['a', 'al', 'alp', 'alph']) {
      bloc.add(ContentQueryChanged(query));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    expect(bloc.state.channels, hasLength(3), reason: 'still typing');
    expect(bloc.state.query, 'alph');

    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(bloc.state.channels.map((c) => c.name), ['Alpha']);
  });

  test('selecting a category clears the query rather than filtering by it', () async {
    await loaded();

    bloc.add(const ContentQueryChanged('alp'));
    bloc.add(const ContentCategorySelected(ContentState.allCategoryId));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(bloc.state.query, '');
    expect(bloc.state.channels, hasLength(3));
  });
}
