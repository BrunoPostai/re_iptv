# 03 — Network surface

Two distinct things are documented here:

1. **Xtream Codes**, the industry-standard IPTV API. It is what the app uses to
   talk to *your* playlist server, and what this recreation implements.
2. The vendor's **own** service endpoints, which the original app also contacts.
   Only the *paths and shapes* are recorded — the hostnames are deliberately left
   out of this repository (see the note at the end).

## 1. Xtream Codes (playlist server)

Base URL: `http://<host>:<port>` (the app accepts a host with or without scheme).

### Account / authentication

```
GET /player_api.php?username=<u>&password=<p>
```

Returns the account envelope used across the app:

```jsonc
{
  "user_info": {
    "username": "…", "password": "…",
    "message": "…",
    "auth": 1, "status": "Active",
    "exp_date": "1735689600",        // unix seconds, string or null
    "is_trial": "0",
    "active_cons": "1", "max_connections": "2",
    "created_at": "1700000000",
    "allowed_output_formats": ["m3u8", "ts"]
  },
  "server_info": {
    "url": "host:port", "port": "8080", "https_port": "8443",
    "server_protocol": "http", "rtmp_port": "…",
    "timezone": "Europe/London", "timestamp_now": 1700000000,
    "time_now": "2024-01-01 12:00:00"
  }
}
```

`auth == 0` or a non-empty `user_info.message` is treated as an authentication
failure; `exp_date` drives the "Current Playlist Expired On" status in the UI.

### Catalogue

```
GET /player_api.php?username=&password=&action=get_live_categories
GET /player_api.php?username=&password=&action=get_vod_categories
GET /player_api.php?username=&password=&action=get_series_categories

GET /player_api.php?username=&password=&action=get_live_streams[&category_id=<id>]
GET /player_api.php?username=&password=&action=get_vod_streams[&category_id=<id>]
GET /player_api.php?username=&password=&action=get_series[&category_id=<id>]

GET /player_api.php?username=&password=&action=get_vod_info&vod_id=<id>
GET /player_api.php?username=&password=&action=get_series_info&series_id=<id>

GET /player_api.php?username=&password=&action=get_short_epg&stream_id=<id>&limit=<n>
GET /player_api.php?username=&password=&action=get_simple_data_table&stream_id=<id>
```

Observed field sets are mirrored by `lib/data/models/models.dart`
(`Channel`, `Movie`, `Series`, `SeriesInfo`, `Episode`, `Category`); the models
tolerate the usual provider quirks (numbers arriving as strings, missing keys,
`rating_5based` as a string, `tv_archive` as `"0"`/`1`, etc.).

### Stream URLs

```
Live       http://<host>/live/<user>/<pass>/<stream_id>.ts | .m3u8
VOD        http://<host>/movie/<user>/<pass>/<stream_id>.<container_extension>
Series     http://<host>/series/<user>/<pass>/<episode_id>.<container_extension>
Catch-up   http://<host>/streaming/timeshift.php
             ?username=<u>&password=<p>&stream=<stream_id>
             &start=YYYY-MM-DD:hh-mm&duration=<minutes>
Export     http://<host>/get.php?username=<u>&password=<p>&type=m3u_plus&output=ts
```

The `ts`/`m3u8` choice for live streams is a user setting ("Stream Format");
providers that mark channels as protected only work with `m3u8`.

### M3U playlists

For `type=m3u` playlists the app fetches the playlist URL directly and parses the
extended M3U attributes:

```
#EXTM3U
#EXTINF:-1 tvg-id="…" tvg-name="…" tvg-logo="…" group-title="…",Channel name
<url>
```

The parser keys stream URLs by a stable id (the `tvg-id` when present, otherwise
a hash of the URL) and groups entries by `group-title`. Series are expressed as
`#EXTINF` entries whose `group-title` encodes `S01 E02` style information; the
recreation follows the same convention.

## 2. Vendor service endpoints (paths only)

The original also talks to its own backend, over paths such as:

```
/playlist_info
/user_account
/device/playlists
/update_playlist2
/changeParentPin2
/localData
```

Some of these carry device identity (`macAddress`, a generated `deviceKey`, an
optional `deviceId`) and the vendor's application id. They were used by the
original for device registration, playlist bookkeeping and remote preference
storage.

**Why the recreation does not call them:** they belong to a third party, are not
documented, and are not needed for playback. The recreation is fully local: it
generates its own `deviceKey`/`macAddress`/`deviceId`, stores everything in Hive,
and exposes `AppConfig.apiBaseUrls` (empty by default) for anyone who wants to
plug in their *own* account service. See
[../EXTENDING.md](../EXTENDING.md) §6.

The concrete hostnames deliberately stay out of the public repository; if you need
them for interoperability research, recover them yourself from your own copy of
the binary (`tools/extract_strings.py`).

## 3. Requests actually made by the recreation

| Call | When |
|---|---|
| `/player_api.php` (no action) | playlist activation, and every refresh |
| `get_*_categories` | on first sync, and on "Reload from server" |
| `get_live_streams` / `get_vod_streams` / `get_series` | on first sync per kind |
| `get_vod_info` / `get_series_info` | when a detail screen is opened (then cached in memory) |
| `get_short_epg` | when a channel is selected in Live TV |
| stream URLs as above | on play, and for catch-up |
| M3U URL | on first sync, then parsed and cached |

Everything else (browsing, searching, favourites, resume) reads from the local
cache only, which is why the app remains usable offline after the first sync.
