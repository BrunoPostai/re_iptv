# re_iptv

A clean-room, cross-platform **IPTV player client** built with Flutter, supporting
**Xtream Codes** and **M3U/M3U8** playlists: live TV, movies, series, catch-up,
search, favourites, continue-watching, parental control and a libmpv-based player.

The UI is a faithful *recreation* of the layout and behaviour of a well-known
Windows IPTV desktop client, rebuilt from scratch with **neutral placeholder
branding** — no vendor artwork, names or content is included.

> **Legal / ethics.** This repository contains no playlists, credentials, channels,
> movies, series or vendor assets. The application is a general-purpose media
> player; you supply your own playlist and are responsible for having the right to
> access it. The reverse-engineering notes in [`docs/analysis`](docs/analysis) are
> recorded for interoperability and educational purposes only.

---

## Repository layout

```
re_iptv/
├─ app/          Flutter application (Windows desktop; Android/iOS ready)
│  ├─ lib/
│  │  ├─ core/          config, theme, i18n, DI, utils
│  │  ├─ data/          models, Xtream/M3U sources, repositories, Hive storage
│  │  ├─ blocs/         settings · playlist · content · player
│  │  ├─ features/      splash · home · live · movies · series · replay · search · playlist · settings
│  │  └─ widgets/       title bar, tiles, grids, dialogs
│  ├─ assets/
│  │  ├─ config/        app_config.json  ← personalisation
│  │  ├─ branding/      neutral placeholder logo/backgrounds (regenerable)
│  │  └─ languages/     en.json + index.json
│  ├─ test/             unit tests
│  └─ tool/             hive_dump.dart (local database inspector)
├─ docs/
│  ├─ analysis/         reverse-engineering notes (sanitised)
│  ├─ PERSONALIZING.md  theming, branding, providers, feature flags
│  └─ EXTENDING.md      adding playlist types, languages, screens
├─ tools/               asset generator + string extractor
└─ LICENSE              MIT
```

## Features

| Area | Implemented |
|---|---|
| Playlists | Xtream Codes (`player_api.php`) and M3U/M3U8, multiple playlists, active playlist switching |
| Live TV | categories, channel list, inline muted preview with an off-air card, programme guide with the on-air programme highlighted, favourites, catch-up badge |
| Movies | categories, poster grid, search, sort, detail page with plot/cast/rating/trailer, resume |
| Series | categories, seasons, episodes, resume per episode, favourites |
| Catch-up | archive channels, date + start-time + duration picker, timeshift playback |
| Search | global, tabbed by live/movies/series |
| Library state | favourites, watched, continue-watching, all stored per playlist |
| Player | libmpv via `media_kit`: seek, volume, audio/subtitle track selection, fullscreen, window dragging while playing, keyboard shortcuts, resume position, libmpv stats overlay (**I**) |
| Settings | theme, language, stream format, subtitle size, playback volume, parental PIN, hide categories, cache control |
| Shell | frameless window with custom title bar, clock, account expiry status |

## Building (Windows)

Requirements: Flutter stable (3.29+), Visual Studio 2022 with the *Desktop
development with C++* workload.

```powershell
cd app
flutter pub get
flutter run -d windows          # or: flutter build windows --release
```

> **Developer Mode.** Flutter creates plugin symlinks on Windows; enable
> *Settings → System → For developers → Developer Mode* once, otherwise the build
> stops with *"Building with plugins requires symlink support"*. On a machine
> where you cannot enable it, run the bundled workaround instead, which
> pre-creates the same links as directory junctions:
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File ..\tools\make_plugin_junctions.ps1
> ```
>
> Re-run it (with `-Force`) after `flutter pub get` changes the plugin list.

Checks:

```powershell
flutter analyze        # clean
flutter test           # models, config merge, Xtream/M3U parsing, URL builders
```

The demo/registration-free build starts with an empty playlist list — add your own
through **Change Playlist → Add Playlist**.

## Personalising

Everything user-visible lives in `app/assets/config/app_config.json`
(branding, feature flags, themes, window, defaults). Create
`assets/config/app_config.local.json` — or drop one next to the app's data
folder — and it is **deep-merged over the defaults at startup**, so your custom
build keeps working after `git pull`. See
[`docs/PERSONALIZING.md`](docs/PERSONALIZING.md).

Out of the box the app calls itself **REIPTV** — set `branding.app_name` and
`branding.window_title` to rename it.

## Status

| Area | State |
|---|---|
| UI replica (all captured screens) | done |
| Xtream + M3U data layer | done |
| Playback, resume, favourites | done |
| Programme guide + live preview | done |
| Storage schema parity with the original | verified against a real database |
| `flutter analyze` | clean |
| Tests | 25 passing (models, EPG parsing, config merge, Xtream/M3U parsing, URL builders, auth) |
| Windows release build | succeeds |
| End-to-end playback on a live provider | needs your playlist — not part of the automated checks |
| Remaining | see [`TODO.md`](TODO.md); EPG grid view and multi-window are still open |

The reverse-engineering notes record exactly which claims were observed and which
are inferred: see [`docs/analysis/07`](docs/analysis/07-evidence-and-limits.md).

## License

MIT — see [LICENSE](LICENSE).
