# tools

Small, dependency-light helpers. None of them touch the network, and none of
them are needed to build or run the player — they exist to make the analysis
reproducible and the placeholder assets regenerable.

| Tool | What it does | Run |
|---|---|---|
| `make_branding.py` | regenerates the neutral placeholder logo and backgrounds into `app/assets/branding/` | `python tools/make_branding.py` |
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
