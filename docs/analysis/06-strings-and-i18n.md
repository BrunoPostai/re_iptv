# 06 — Strings and localisation

## What the original does

The localisation data is embedded in the AOT snapshot as a table of
`key → phrase` maps: **14 languages**, with an English table of **233 keys**. The
`localization` bloc holds the active table, and every view reads through it, so
switching language is instant and requires no round trip.

Keys are English snake_case identifiers describing UI roles (`live_tv`,
`movies`, `series`, `change_playlist`, `setting`, …), and the language files are
interchangeable (same key set, translated values) — a typical
copy-and-translate workflow.

Because the tables are the vendor's translated copy, they are **not** reproduced
here. What this repository keeps from that design is the *mechanism*.

## What the recreation does

```
assets/languages/index.json   → [{ "code": "en", "name": "English" }]
assets/languages/<code>.json  → { "code", "name", "words": { key: phrase } }
```

* `L10n.load(code)` reads the file and builds the table.
* `l10n.t('key')` returns the phrase, or the key itself when missing.
* A missing or unreadable file silently falls back to English, so a partial
  translation (or a bad upload) can never break the UI.
* The active `code` is persisted in the settings box (`language-code`) and shared
  through `SettingsBloc`, which rebuilds the whole app on change — the same
  instant switch as the original.

The bundled set is English only; adding a language is a drop-in file plus an
entry in `index.json` (see [../PERSONALIZING.md](../PERSONALIZING.md#languages)).
This keeps the repository free of third-party translated text while preserving
the UX.

## Key vocabulary

The recreation uses its own, smaller key set (the screens need ~45 keys rather
than 233 because several original keys covered vendor-only screens):

| Key | Used by |
|---|---|
| `live_tv`, `movies`, `series`, `replay`, `change_playlist`, `search`, `settings` | home tiles, headings, search tabs |
| `search_hint`, `no_results` | search fields/blocks |
| `all`, `favorites`, `continue_watching`, `recently_viewed` | pseudo-categories |
| `select_playlist`, `add_playlist`, `remove_playlist`, `no_playlist` | playlist screen |
| `user_account`, `change_theme`, `change_language`, `stream_format`, `subtitle_settings`, `parental_control`, `hide_live_categories`, `hide_movie_categories`, `hide_series_categories`, `clear_cache`, `about`, `profile_settings` | settings |
| `play`, `watch`, `retry`, `refresh`, `close`, `cancel`, `loading` | actions |
| `live`, `movie`, `episode`, `season`, `seasons`, `episodes`, `plot`, `cast`, `director`, `genre`, `expired` | detail screens |

Screens that are not yet localised (detail/dialog deep text) fall back to
literals; they are listed in the key table above so they can be migrated without
touching layout code.

## Where the original's other 180+ keys went

Most of the remaining original keys covered features that are vendor-backend
specific (device registration, remote preference sync, trial notices, server
switching, sports guide, update prompts). Rather than carry dead strings, those
features exist in the recreation as **feature flags** (off by default) and their
copy returns with the feature. See
[../PERSONALIZING.md](../PERSONALIZING.md#feature-flags).

## Dates and numbers

* Dates are rendered `dd/MM/yyyy` (matching the original's account-expiry pill).
* The clock is `HH:mm:ss`, ticking every second.
* Durations are `mm:ss` / `h:mm:ss`; the catch-up duration slider is shown as
  `45m` / `1h 30m`.
* `intl` is available for adding locale-aware formatting without changing the
  call sites.
