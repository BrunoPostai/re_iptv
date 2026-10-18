# TODO

Open work on the player. `[ ]` open · `[~]` implemented, needs checking on a real
playlist · `[x]` done.

## 1. Programme guide is wrong — `[~]`

The EPG panel in **Live TV** showed gibberish titles and was empty for most
channels. Five separate causes were found and fixed:

| Cause | Fix |
|---|---|
| Xtream base64-encodes `title` / `description`; they were printed raw | `decodeEpgText()` decodes them, and keeps plain text when a value only *looks* encoded |
| Only `start_timestamp` / `stop_timestamp` were read, so panels that send only the `start` / `end` strings showed everything as 1970 | `parseEpgTime()` falls back to the date strings |
| Those strings are UTC and were parsed as local time | parsed as UTC, then converted to the viewer's timezone |
| `get_short_epg` only returns the current programme and the next few, and not every panel implements it | the full `get_simple_data_table` is tried first, `get_short_epg` is the fallback |
| The on-air programme was not pinned or highlighted in view | the list scrolls to it and marks it **NOW** |

A row with no readable time now says "Time unavailable" rather than
`01:00 - 01:00`.

**To check:** open Live TV, pick a few channels, confirm titles are readable,
times match the channel, and the **NOW** row is the one actually on air.

## 2. Live preview with an "offline" placeholder — `[~]`

Selecting a channel now previews it inline in the details panel, replacing the
static logo:

- stream starts → it plays, muted, with a speaker button to unmute;
- stream unavailable, errors, or reports nothing within 12 seconds → a
  "Nothing on air right now / Check back later" card over the dimmed channel
  logo;
- pressing **Watch** stops the preview so it never plays underneath the full
  player, and it restarts when you come back.

**To check:** select a working channel (preview plays), select a dead one (card
appears), then press Watch (no double audio).

## 3. Default volume 20%, not 100% — `[x]`

`PlayerState.volume` defaulted to 100 and nothing set it on open. Streams now
open at `player.default_volume` (20 in `app_config.json`), and the value is
adjustable from the new **Volume** tile in Settings, which is remembered.

## 4. Drag the window while a video plays — `[x]`

The player route is frameless with no title bar, so the window could not be
moved during playback. Both the player overlay's top bar and an invisible strip
along the top edge (for when the overlay has faded out) now drag the window, and
double-clicking still maximises.

## 5. Brand as REIPTV — `[x]`

The visible name is now **REIPTV** (window title, splash, in-app titles), and the
placeholder artwork was regenerated with an `REIPTV` wordmark. The Dart package
and the executable are unchanged (`re_iptv` / `re_iptv.exe`) — see
[docs/PERSONALIZING.md](docs/PERSONALIZING.md#renaming-the-application-itself) to
go further.

---

## Backlog

- Persist the last used volume per stream kind instead of resetting to the
  default on every open.
- Programme guide: fetch the full day in the background and cache it per channel,
  so switching channels does not re-request.
- Preview: optional custom "offline" image via `branding`, if the built-in card
  is not wanted.
