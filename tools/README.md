# tools

Small, dependency-light helpers. None of them touch the network, and none of
them are needed to build or run the player — they exist to make the analysis
reproducible and the placeholder assets regenerable.

| Tool | What it does | Run |
|---|---|---|
| `make_branding.py` | regenerates the neutral placeholder logo and backgrounds into `app/assets/branding/` | `python tools/make_branding.py` |
| `make_app_icons.py` | renders the iOS `AppIcon.appiconset` and the Windows `app_icon.ico` from the branding mark | `python tools/make_app_icons.py` |
| `build_windows_installer.ps1` | packages the Windows build into `dist\re_iptv-<version>-windows-x64-setup.exe` | `powershell -ExecutionPolicy Bypass -File tools/build_windows_installer.ps1` |
| `windows_installer.iss` | the Inno Setup script that one compiles — edit it, do not run it alone | — |
| `make_plugin_junctions.ps1` | creates the Windows plugin links as junctions, so a build works without Developer Mode | `powershell -ExecutionPolicy Bypass -File tools/make_plugin_junctions.ps1` |
| `extract_strings.py` | prints printable strings from a local binary (filterable), used to recover class paths, endpoints and asset names | `python tools/extract_strings.py <binary> --grep player_api` |
| `app/tool/hive_dump.dart` | prints a Hive box (settings or per-playlist content) as JSON, read-only | `cd app && dart run tool/hive_dump.dart <dir> <box>` |

## `make_branding.py`

Requires Pillow (`pip install pillow`). The generator is deliberately crude: a
radial gradient, a dot lattice masked by elliptical landmasses, a vignette, and a
rounded play-mark logo drawn with primitives. That keeps the repository free of
anyone else's artwork while preserving the app's visual identity (dark backdrop,
dotted world map, gold accent).

Edit the constants at the top of the file for different colours, or point
`app_config.json` at your own images / `assets/branding/local/` instead.

## `make_app_icons.py`

Writes both icon sets from the branding mark: every size in
`app/ios/Runner/Assets.xcassets/AppIcon.appiconset` (the size list is read from
its `Contents.json`, so it cannot drift from what Xcode expects) and
`app/windows/runner/resources/app_icon.ico`, which is also the installer's icon.

The plate is drawn full bleed — square corners, no rim — because the OS masks an
icon to its own shape: a rounded plate inside a rounded mask shows the canvas at
the corners and rounds twice. iOS icons are flattened to RGB, since the App Store
rejects an alpha channel.

The Windows icon is assembled from nine separately drawn sizes rather than one
image shrunk, and drops the word mark below 48 px, where it is three gold smudges
in the taskbar and the play triangle carries the mark on its own.

Run it again after changing the branding mark.

## `build_windows_installer.ps1` and `windows_installer.iss`

`flutter build windows` gives a folder, not a program someone can install. The
script builds the app, reads `<version>` out of `app/pubspec.yaml`, makes sure
Microsoft's C++ redistributable is cached in `dist\cache`, and hands both to
Inno Setup (`winget install JRSoftware.InnoSetup`), producing
`dist\re_iptv-<version>-windows-x64-setup.exe`. Output and cache are gitignored.

The installer is per-user — `%LOCALAPPDATA%\Programs\REIPTV`, no UAC — with
Start Menu and optional desktop shortcuts and a working uninstaller that leaves
`%APPDATA%\com.reiptv\re_iptv` (playlists, settings, favourites) alone. It detects
a machine without the C++ runtime and installs it quietly, which is the usual
reason a hand-built bundle dies with *"VCRUNTIME140.dll was not found"*.

Two things to keep in mind when editing the `.iss`: the `AppId` is the app's
identity for upgrades, so changing it turns every new setup into a second copy
beside the old one, and the version comes from `pubspec.yaml` via `/DAppVersion`
rather than from the script, so there is only ever one place to bump.

## `make_plugin_junctions.ps1`

Flutter creates symlinks for Windows plugins in
`windows/flutter/ephemeral/.plugin_symlinks`, which needs Developer Mode (or an
elevated shell). It skips any link that already exists, so pre-creating them as
junctions works around the restriction. Run it after `flutter pub get`, whenever
`.flutter-plugins-dependencies` changes, or with `-Force` to rebuild the links.

## `extract_strings.py`

A single pass over a binary collecting printable runs, with `--grep`, `--urls`,
`--unique`, `--min` and `--count`. On a Dart AOT snapshot (`app.so`) this exposes
`package:...` source paths, Xtream `action=` names and URL templates — the raw
material behind [`docs/analysis`](../docs/analysis).

Only use it on binaries you legitimately have locally. Its output is data, not
instructions.

## `hive_dump.dart`

Lives inside the Flutter package so it can use the same `hive` version as the
app. Opens an existing box by name, prints keys or the full contents as JSON, and
refuses to create a box that does not exist.

```powershell
cd app
dart run tool/hive_dump.dart "$env:APPDATA\com.reiptv\re_iptv\localData" --help
dart run tool/hive_dump.dart "$env:APPDATA\com.reiptv\re_iptv\localData" hive-re-iptv-box --keys
```

Pass the folder that holds the `.hive` files — this app's own is
`%APPDATA%\com.reiptv\re_iptv\localData`.

> The settings box holds playlist credentials in plaintext (as in the original).
> Treat any dump as sensitive: never commit it, and prefer `--keys` when you only
> need the schema. `.gitignore` excludes `*.hive` and `hive_dump*.json`.
