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
├─ app/          Flutter application (Windows desktop, Android, iOS)
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
│  ├─ android/          Gradle project — release key in key.properties
│  ├─ ios/              Xcode project — prepared here, built on a Mac
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

## Building (Android)

Requirements: Flutter stable, the Android SDK, and a JDK 17 — `flutter doctor`
reports all three.

```powershell
cd app
flutter pub get
flutter run -d <device>                                   # debug, over USB
flutter build apk --release                               # every ABI, ~95 MB
flutter build apk --release --target-platform android-arm64   # one phone's, ~60 MB
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Sideloading on a phone that is not attached to this machine: copy the APK over,
open it, allow installs from that app, and dismiss Play Protect's *unsafe app
blocked* with *more details → install anyway* — expected for any self-signed
build.

### Release signing

Release builds read `android/key.properties` (gitignored, as is the keystore it
points at); copy [`app/android/key.properties.example`](app/android/key.properties.example)
and fill it in. A checkout without that file still builds, signing with the debug
key, which is fine for your own phone and useless for anyone else's: a debug
keystore lives on one machine, so the next build from another machine cannot be
installed over it.

Generate the key once, keep it out of the repository, and keep a copy somewhere
you would keep a passport:

```powershell
keytool -genkeypair -v -keystore re_iptv-release.jks -storetype PKCS12 `
        -keyalg RSA -keysize 2048 -validity 10000 -alias re_iptv
```

Losing it means every phone must uninstall the app — and its saved playlists —
before the next build can be installed.

## Building (iOS)

The iOS target is prepared but unproven: it was written on Windows, where
nothing Apple can compile, sign or run. The first real build happens on a Mac,
and the first real build is also the first chance to find whatever is wrong with
`ios/`.

Requirements: macOS with Xcode 15+, CocoaPods (`brew install cocoapods`), and an
Apple ID added to Xcode under *Settings → Accounts*.

```bash
cd app
flutter pub get
flutter build ios --no-codesign   # first run: writes ios/Podfile, downloads libmpv
open ios/Runner.xcworkspace       # Runner → Signing & Capabilities → pick a team
flutter run                       # or: flutter build ipa
```

The first build installs the video libraries: `media_kit_libs_ios_video` fetches
the libmpv frameworks from GitHub while CocoaPods resolves, so it needs network
and a few hundred megabytes of disk. Flutter writes the `ios/Podfile` itself the
first time it sees a plugin that only ships a podspec — which is most of them
here. Do that before opening the workspace, or `Runner.xcworkspace` has no Pods
project in it and the plugins do not link.

What is already set up, and why:

| | |
|---|---|
| Bundle id | `com.reiptv.reIptv` — iOS forbids underscores, so it cannot match Android's `com.reiptv.re_iptv`. They are separate apps as far as a store is concerned. |
| Orientations | portrait and both landscapes, because the player turns the phone for a film and the rest of the app is laid out upright. |
| App Transport Security | `NSAllowsArbitraryLoads`, the counterpart of `android:usesCleartextTraffic`. Providers still serve `http://` playlists and logos, which iOS blocks by default. |
| Display name | `REIPTV`, from `CFBundleDisplayName`. |
| Icons | `Runner/Assets.xcassets/AppIcon.appiconset`, rendered from the branding mark by `python tools/make_app_icons.py`. |
| Launch screen | the app's own dark background, so the first half-second is not a white flash. |

Getting it onto an iPhone without a paid account: a free Apple ID team signs
builds that expire after seven days and cover three apps, installed through
Xcode, [Sideloadly](https://sideloadly.io) or AltStore on this machine. A paid
account removes the expiry. No `.ipa` is kept in this repository.

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
| Tests | 85 passing (models, EPG parsing, config merge, Xtream/M3U parsing, URL builders, auth, layout breakpoints) |
| Windows release build | succeeds |
| Android release build | succeeds; signed with the release key, running on a phone (Android 16) |
| iOS | target written (`app/ios/`), never compiled — no Mac here |
| End-to-end playback on a live provider | needs your playlist — not part of the automated checks |
| Remaining | see [`TODO.md`](TODO.md); EPG grid view and multi-window are still open |

The reverse-engineering notes record exactly which claims were observed and which
are inferred: see [`docs/analysis/07`](docs/analysis/07-evidence-and-limits.md).

## License

MIT — see [LICENSE](LICENSE).
