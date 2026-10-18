# Extending

The app is split so that behaviour lives behind small interfaces. Each section
below is a self-contained change that does not require touching feature screens.

## 1. A new playlist type

`PlaylistSource` (`lib/data/sources/playlist_source.dart`) is the only thing the
data layer knows about:

```dart
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
```

Steps:

1. Add a value to `PlaylistType` in `lib/data/models/models.dart` (e.g. `xtreamV2`)
   and to `playlistTypeFrom` / `playlistTypeTo`.
2. Implement the interface in a new file next to `M3uSource`.
3. Register it in `PlaylistRepository.sourceFor`.

Everything downstream (caching, browsing, search, favourites, resume, player)
works unchanged because it only talks to `ContentRepository`.

## 2. A different playback backend

`PlayerBloc` (`lib/blocs/player_bloc.dart`) wraps `media_kit`:

* it owns the platform player and exposes a `VideoController`
* it mirrors `position`, `duration`, `playing`, `buffering`, `tracks` and `error`
  into an immutable `PlayerState`
* the UI only reads `PlayerState` and sends `PlayerEvent`s

To swap engines, keep the same event/state surface and replace the internals —
`PlayerScreen` needs no changes.

## 3. A new screen in the home grid

1. Add a flag to `FeatureFlags` (and to `app_config.json`).
2. Create `lib/features/<area>/<area>_screen.dart`.
3. Add a `NavTile` entry in `lib/features/home_screen.dart`.

## 4. A new language

See [PERSONALIZING.md](PERSONALIZING.md#languages). No code change is required;
`L10n.load` falls back to English for any missing key.

## 5. A new storage key

Add it to `StoreKeys` / `ContentKeys` in `lib/core/constants.dart` and read it
through `AppStorage` — never touch Hive boxes directly outside
`lib/data/storage/app_storage.dart`.

## 6. Account / licensing backends

`AppConfig.apiBaseUrls` is reserved for an external account service. The current
build keeps everything local: `AppStorage` generates a `deviceId`, `deviceKey`
and `macAddress`, and the account panel simply displays them. If you add a
service, put its client in `lib/data/repositories/` and keep the UI reading from
the bloc state.
