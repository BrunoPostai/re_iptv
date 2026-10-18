# 01 — Target inventory

## Target

| Property | Value |
|---|---|
| Product | a commercial Windows IPTV client (identified in *Provenance* below) |
| Version | 1.0.4 |
| Platform | Windows x64 desktop (Flutter Windows embedder) |
| Engine | Flutter, Dart AOT snapshot |
| Install root | per-machine program files directory (see *Provenance*) |
| Dart package | internal package name, recovered from embedded source paths |
| Runtime data | a per-user `%APPDATA%` folder (see *Provenance*) |

Version 1.0.4 was confirmed from the shipped `.env` file
(`APP_VERSION = 1.0.4`) and cross-checked against the version string embedded in
the binary and the in-app title bar.

## Shipped artefacts and their roles

| Path (relative to install root) | Role | Notes |
|---|---|---|
| the host `.exe` | Windows host executable | Flutter Windows runner |
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

## Provenance

> Kept apart so that the rest of these notes can stay brand-neutral, and recorded
> so the analysis remains verifiable. The target was the retail Windows client
> **IBO Player v1.0.4**, installed at `C:\Program Files (x86)\Ibo Player`, whose
> Dart package is `ibo_tv` and whose data lives under
> `%APPDATA%\com.example\ibo_tv`. These identifiers are deliberately absent
> everywhere else in this repository, and nothing belonging to the product —
> source, artwork, wording, translation tables, endpoint hostnames or user data —
> is reproduced.
