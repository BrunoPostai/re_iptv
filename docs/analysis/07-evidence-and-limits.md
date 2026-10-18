# 07 — Evidence, method, and limits

## How each claim was obtained

| Claim | Method | Confidence |
|---|---|---|
| Product version 1.0.4 | shipped `.env` (`APP_VERSION`), in-app title bar | high |
| Flutter / Dart AOT | `data/app.so` is an ELF64 AOT snapshot next to `flutter_windows.dll` and `icudtl.dat` | high |
| Source file/class layout (`views/`, `blocs/`, …) | `package:ibo_tv/...` paths present as string constants in the snapshot | high for names, medium for roles |
| Third-party packages | package-specific symbols/strings in the snapshot + bundled `libmpv-2.dll` | high |
| Xtream request shapes | URL templates and `action=` names as string constants; response fields confirmed against the models that consume them | high |
| Vendor-only endpoint paths | string constants (`/playlist_info`, `/device/playlists`, …) | medium — presence is certain, usage order is inferred |
| Storage schema (box names, keys, value shapes) | enumerating and decoding the Hive boxes written by the app on an analysis machine | high |
| UI layout, wording, order of tiles, dialog contents | direct observation of the running application (screen captures) | high for layout, high for section titles |
| Behavioural details (sync stages, resume-on-play, watched thresholds) | observed state changes plus the storage schema (e.g. `continue-watch-*`, `watched-*`) | medium |
| Parental-PIN semantics | `lock-code` in settings, hidden-category keys, lock glyphs in the channel list | medium |

## Known limits

* **No decompilation of control flow.** Claims about *ordering* (which request
  happens before which, what triggers a sync) are inferred from names, storage
  side effects and observation, not from reading the original's code.
* **The vendor backend is out of scope.** Paths are recorded, behaviour is not
  reproduced, and hosts are omitted from this repository on purpose.
* **Vendor copy is not reproduced.** Localisation tables and artwork are the
  vendor's; the recreation keeps the mechanism and renders neutral text.
* **No pixel-comparison.** The recreation reproduces layout, spacing and colour
  *intent*; it does not ship the vendor's background images, so a visual diff
  will never be byte-identical.
* **The original's edge-case handling is unknown** — e.g. how it reacts to a
  provider returning `auth: 0` mid-session, or to a playlist that changes
  container extension. The recreation applies its own documented policy
  (surface the error, keep cached content browsable).

## Data handling during analysis

The analysis machine had a real provider playlist configured. Consequences:

* All captures, dumps and notes that contained playlists, credentials, channel
  names, posters or other provider content stayed in a scratch directory outside
  the repository and were **not** committed.
* This repository contains no playlists, credentials, channel/movie/series
  names, logos or vendor graphics. Only *structure* is documented: key names,
  JSON shapes, path templates.
* `.gitignore` excludes the artefacts most likely to leak user data
  (`*.hive`, `hive_dump*.json`, `app_config.local.json`, `assets/branding/local/`).

The plaintext-credential weakness of the original is documented in
[04](04-storage-schema.md#security-observation-important) rather than reproduced
as an endorsement.

## Reproducing the analysis

The techniques used are all local and non-invasive:

```powershell
# strings / endpoint paths from the compiled snapshot
python tools/extract_strings.py "C:\Program Files (x86)\Ibo Player\data\app.so" --grep player_api

# inspect a Hive box (from inside the Flutter package)
cd ibo_player
dart run tool/hive_dump.dart "%APPDATA%\com.example\ibo_tv\localData" hive-ibo-tv-box --keys
```

`tool/hive_dump.dart` opens a box read-only and prints it as JSON, which is also
the quickest way to confirm that the recreation reads an existing database
correctly. Treat any output as **sensitive**: it can contain credentials.

## Verification status of the recreation

| Check | Result |
|---|---|
| `flutter analyze` | clean |
| `flutter test` | 20 tests, all passing (models, config merge, Xtream/M3U parsing, URL builders, timeshift formatting, authentication) |
| `flutter build windows --release` | succeeds |
| Runtime smoke test | launches, renders the splash with branding and identity panel, reaches home with an empty playlist list |
| End-to-end playback against a real provider | **not part of the automated checks** — requires your playlist |

Known gap: the release build was produced and the splash/home flow was observed,
but full navigation through every screen with a live playlist is left to you,
since it needs credentials this repository must not contain.
