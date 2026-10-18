# 04 — Local storage schema

Everything the original stores lives in **Hive** boxes under a per-user
application-data folder:

```
%APPDATA%\<vendor>\<app>\localData\
```

Hive boxes are length-prefixed key/value files, so they can be enumerated and
read without any help from the vendor's code — which is how the tables below were
produced (each one was verified by opening the real database, see
[07](07-evidence-and-limits.md)).

| Box file | Purpose | Scope |
|---|---|---|
| `hive-<app>-box.hive` | identity, playlists, preferences, cached language tables | global |
| `<app>-<playlistId>.hive` | that playlist's imported catalogue | per playlist |
| `<app>-demo.hive` | content of the built-in demo playlist | per playlist (demo) |

Having one content box per playlist is what makes "change playlist" cheap:
switching selects another box, and nothing has to be re-imported.

### How the recreation maps onto this

`HiveBoxes` in `app/lib/core/constants.dart` keeps the same *structure* under the
neutral project name:

| Original | Recreation |
|---|---|
| `hive-<app>-box` | `hive-re-iptv-box` |
| `<app>-<playlistId>` | `re-iptv-<playlistId>` |
| `<app>-demo` | `re-iptv-demo` |

The **key names inside the boxes are identical** (`saved-channels`,
`playlist_name`, `category_id`, …), so an existing database remains readable if you
rename its box files — the app simply will not look for the vendor's names by
itself.

## Global box — `hive-re-iptv-box` / `hive-<app>-box`

Observed keys, exactly as stored:

| Key | Type | Meaning |
|---|---|---|
| `windows-device-id` | String | generated device id, `WINDOWS-<32 hex>` |
| `device-key` | String | 6-digit numeric key generated at first run |
| `mac-address` | String | generated `xx:xx:xx:xx:xx:xx` |
| `account-expire-date` | String | expiry as `yyyy-MM-dd` (empty when unknown) |
| `api-url` | String | active account-service base (vendor; unused here) |
| `api-urls` | String | newline-separated list of those bases |
| `main-url` | String | primary base |
| `playlists` | String | JSON array of playlist objects (see below) |
| `recent-playlist-id` | String | id of the active playlist |
| `theme` | String | active theme id (empty = default) |
| `language-code` | String | active UI language, e.g. `en` |
| `languages` | String | the whole localisation table, cached |
| `lock-code` | String | parental PIN (empty = disabled) |
| `saved-content-update-date` | String | last successful import |

Notes:

* `device-id` **does not exist** — the key is `windows-device-id`.
* `saved-content-update-date` lives in the **settings** box, not per playlist. The
  recreation writes an ISO-8601 string there; the original's own value is a
  `yyyy-MM-dd HH…` string.
* `languages` holds a full `[{code, name, words}]` document, i.e. the app caches
  the server's translations locally. The recreation reads its languages from
  `assets/languages/` instead and simply tolerates this key existing.
* Preference keys such as `stream-format`, `subtitle-size`, `sort-type` and
  `hide-*-categories` were **not present** in the inspected profile — either they
  are only written when changed or the original names them differently. The
  recreation writes those names (documented in `StoreKeys`) for the settings it
  exposes.

### Playlist objects (`playlists`)

Stored as a JSON **string** containing an array; each element was:

```jsonc
{
  "id": "9f2c1b0a7e6d5c4b3a29187f",
  "playlist_name": "…",
  "playlist_type": "xc",          // or m3u / m3u8
  "origin_type": "xc",
  "origin_url": "…",
  "url": "…",
  "username": "…",
  "password": "…",
  "is_protected": 0               // 1 = provider requires HLS
}
```

`Playlist.fromJson`/`toJson` in `lib/data/models/models.dart` read and write these
field names, so an existing `playlists` entry loads without conversion.

## Per-playlist box — `re-iptv-<playlistId>` / `<app>-<playlistId>`

Observed keys in a populated box:

| Key | Type | Meaning |
|---|---|---|
| `saved-channel-categories` | String (JSON array) | live categories |
| `saved-movie-categories` | String (JSON array) | movie categories — note the singular `movie` |
| `saved-series-categories` | String (JSON array) | series categories |
| `saved-channels` | String (JSON array) | live channels |
| `saved-movies` | String (JSON array) | VOD movies |
| `saved-series` | String (JSON array) | series |
| `watched-channels` | String | ids of watched live streams |
| `watched-movies` | String | ids of watched movies |

Watch lists are stored as a **comma-terminated string** (`"12,44,87,"`), not a JSON
array.

Keys the recreation also uses, which appear once the corresponding feature is
used (not present in the inspected profile, so their exact shape is inferred from
the naming convention):

| Key | Meaning |
|---|---|
| `watched-series` | ids of watched series |
| `favorite-channels`, `favorite-movies`, `favorite-series` | favourites |
| `continue-watch-movies` | resume positions for movies |
| `continue-watch-episods` | resume positions for episodes (spelling carried over from the original's convention) |
| `series-info-<id>` | cached `get_series_info` response, written by this recreation |

`continue-watch-*` entries are `WatchProgress`-shaped:

```jsonc
{
  "id": "1234",            // stream id, or "<seriesId>:<episodeId>" for episodes
  "kind": "movie",         // movie | episode
  "title": "…",
  "image": "…",
  "position": 1234567,     // milliseconds
  "duration": 5400000,     // milliseconds
  "updated_at": 1735689600000,
  "parent_id": 0, "season": 0, "episode_num": 0,
  "container_extension": "mkv"
}
```

### Item shapes (verified)

The catalogue is stored as JSON arrays of the provider's own objects, so the
field names are the Xtream ones. Verified key sets:

```
channel  num, name, stream_type, stream_id, stream_icon, epg_channel_id, added,
         category_id, custom_sid, tv_archive, direct_source, tv_archive_duration
movie    num, name, stream_type, stream_id, stream_icon, rating, rating_5based,
         added, category_id, container_extension, custom_sid, direct_source
series   num, name, series_id, cover, plot, cast, director, genre, releaseDate,
         last_modified, rating, rating_5based, backdrop_path, youtube_trailer,
         episode_run_time, category_id
category category_id, category_name, parent_id
```

`Channel`, `Movie`, `Series` and `Category` in the recreation round-trip exactly
these names (plus a handful of optional fields such as `plot`/`duration` on
movies), which is why "open an existing cache" works.

## Pseudo-categories

Content boxes only contain real server categories. The sidebar's synthetic rows are
derived at display time:

| id | Label | Contents |
|---|---|---|
| `_continue` | Continue Watching | resume entries for that kind |
| `_favorites` | Favourites | favourited items of that kind |
| `_all` | ALL | every item |

Any other id is a real server category id.

## Security observation (important)

The original stores **playlist credentials in plaintext** in the global box, next
to the parental `lock-code`. Anyone who can read the user profile can read the
username/password of every configured playlist.

The recreation mirrors this for schema compatibility. If you deploy it beyond your
own machine, treat it as a known weakness:

* the Hive file is protected only by user-profile ACLs;
* the `lock-code` is a UI gate, not encryption;
* use a per-install secret (DPAPI / Keychain / libsecret) for the `password`
  field before shipping a build to anyone else.

Tracked files in this repository never contain credentials: the analysis notes
name keys and types only, and `.gitignore` excludes local dumps
(`*.hive`, `hive_dump*.json`, `app_config.local.json`).
