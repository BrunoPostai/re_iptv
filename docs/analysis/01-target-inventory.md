# 01 — Target inventory

## Target

| Property | Value |
|---|---|
| Product name | "IBO Player" (as displayed by the vendor's installer/shortcut) |
| Version | 1.0.4 |
| Platform | Windows x64 desktop (Flutter Windows embedder) |
| Install root | `C:\Program Files (x86)\Ibo Player` |
| App / package id | `ibo_tv` (Dart package name, per embedded source paths) |
| Engine | Flutter, Dart AOT snapshot |
| Vendor runtime data | `%APPDATA%\com.example\ibo_tv` |

Version 1.0.4 was confirmed from the shipped `.env` file
(`APP_VERSION = 1.0.4`) and cross-checked against the version string embedded in
the binary and the in-app title bar.

## Shipped artefacts and their roles

| Path (relative to install root) | Role | Notes |
|---|---|---|
| `Ibo Player.exe` | Windows host executable | Flutter Windows runner |
| `data\app.so` | Dart AOT snapshot | **main analysis target** — application logic, class names, string constants |
| `data\flutter_windows.dll` | Flutter engine | unmodified stock engine |
| `data\icudtl.dat` | ICU data | locale/i18n support |
| `libmpv-2.dll` | libmpv | media backend |
| `data\flutter_assets\*` | bundled assets | fonts, images, language data |
| `.env` | build metadata | `APP_VERSION = 1.0.4` |

The application is a single AOT-compiled Dart program: there is no obfuscation of
symbol/string data, so type names, file paths and string constants are readable
with a plain `strings` pass. Control flow has to be inferred from those names,
from UI observation and from the storage/HTTP surface (see
[07 — Evidence and limits](07-evidence-and-limits.md)).

## What the app is

An IPTV client for Xtream Codes and M3U playlists offering live TV, VOD
(movies), series, catch-up/replay, EPG, search, favourites, continue-watching,
parental controls, multiple languages and selectable themes. Playlists are
indexed into a local database so that browsing is offline after the first sync.

## Out of scope for this repository

* The vendor's artwork, icon, logo and localisation tables.
* The vendor's own account/registration service (hostnames are deliberately
  omitted here — see 03).
* Any user playlist, credential or cached content observed on the analysis
  machine.
