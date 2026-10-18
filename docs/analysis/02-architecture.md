# 02 — Architecture

## Runtime shape

```
Ibo Player.exe                (Windows runner: window, DPI, title bar)
└─ flutter_windows.dll        (stock Flutter engine)
   └─ data\app.so             (AOT Dart: all application logic)
      ├─ libmpv-2.dll         (media playback, via media_kit)
      ├─ Hive boxes           (%APPDATA%\com.example\ibo_tv\localData\*)
      └─ HTTPS                (Xtream Codes API + playlist servers)
```

Dart package name `ibo_tv`; the runner uses the standard Flutter Windows embedder
with `window_manager` in control of the native window (frameless title bar,
minimise/maximise/close drawn by Flutter itself).

## Recovered source layout

Static strings in `app.so` reveal the source file paths of the compiled program.
They reconstruct the following structure (paths under `package:ibo_tv/`):

```
lib/
├─ main.dart
├─ views/          app, splash_screen, home_screen, channels, contents,
│                  reply, search, playlist, setting
├─ blocs/          content, episods, localization, playlist, theme, user
├─ models/         category, channel, content, playlist, series
├─ repositories/   content, player, playlist, storage, util
└─ shared/         config, theme, utils, widgets
```

Two conclusions follow directly:

1. **State management is BLoC** (`flutter_bloc`), with one bloc per concern and
   a `localization` bloc holding the active string table.
2. **Layering is views → blocs → repositories → storage/network**, with models
   shared at the bottom. The recreation mirrors this layering so that behaviour
   is comparable screen by screen.

Note the singular/plural filenames (`channels`, `contents`, `reply` [replay],
`episods` [episodes], `setting`) — the naming quirks are the vendor's.

## Third-party runtime dependencies (observed)

| Dependency | Evidence | Used for |
|---|---|---|
| `flutter_bloc` / `bloc` | bloc/state class names, `Cubit`/`Bloc` symbols | state management |
| `get_it` | service-locator symbols | dependency injection |
| `hive` / `hive_flutter` | box files `hive-*.hive`, `Hive` symbols | local database |
| `media_kit` + `libmpv-2.dll` | bundled mpv, `Player`/`VideoController` symbols | playback |
| `window_manager` | window options symbols | frameless window, custom title bar |
| `dio` and/or `http` | `Dio`, `RequestOptions` symbols | HTTP |
| `wakelock_plus` | symbols | keep-awake during playback |
| `cached_network_image` | symbols | poster/logo caching |
| `safe_local_storage` | symbols | key/value helpers |
| `url_launcher` | symbols | external links |
| `package_info_plus` | symbols | version display |
| `screen_retriever` (transitive) | symbols | fullscreen/window sizing |

## Data flow (as reconstructed)

```
splash ──▶ storage.read(playlists, settings)
        ──▶ playlist bloc.authenticate(activePlaylist)
        ──▶ repositories.content.sync()
              ├─ categories(kind)     → Hive: saved-*-categories
              ├─ channels/movies/series → Hive: saved-channels/movies/series
              └─ box: saved-content-update-date
home ───▶ channels | contents | search | playlist | setting views
        ──▶ repositories.content (cache-first reads)
        ──▶ repositories.player  → media_kit → libmpv
```

Live/VOD/series items are addressed by `stream_id`/`series_id`; the player builds
the stream URL from the playlist host plus those ids (see
[03 — API endpoints](03-api-endpoints.md)).

## Reproduced by this repository

| Original concern | Recreation |
|---|---|
| `views/*` | `lib/features/*` |
| `blocs/*` | `lib/blocs/{settings,playlist,content,player}_bloc.dart` |
| `models/*` | `lib/data/models/models.dart` |
| `repositories/*` | `lib/data/repositories/*` + `lib/data/storage/app_storage.dart` |
| `shared/*` | `lib/core/*` + `lib/widgets/*` |

The recreation consolidates the original's six blocs into four (settings covers
theme + localisation + user preferences) and keeps the same storage schema so
existing local databases remain readable.
