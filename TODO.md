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

## 6. Live playback stability — `[~]`

Live TV felt heavy on large playlists. Four app-side causes of that were fixed:

| Cause | Fix |
|---|---|
| Every channel tapped built a new libmpv player (32 MB buffer) and disposed the old one without awaiting it, churning native players and connections while browsing | the preview box now reuses **one** player for the screen and just re-opens the stream on it |
| Selecting a channel opened a stream and asked for its guide immediately, so running down the list started playback for every row | preview and guide wait 350 ms for the selection to settle; stale guide replies are discarded |
| Returning from the player reloaded the whole catalogue — re-reading and re-decoding every channel — although only watch state had changed | the new `ContentWatchStateReloaded` event refreshes favourites/continue-watching only |
| The player *and the preview box* rebuilt the video surface on every position tick libmpv emits (several a second) | the video is built outside the reactive subtree, and position ticks are ignored for live (which has no scrubber); the preview box only rebuilds on play/error/volume changes |

**To check:** browse a long channel list (few or no streams should open), leave
one channel previewing, open **Watch** and come back (the list should come back
without a pause), and confirm audio/subtitle/fullscreen controls still work.
While a channel plays, press **I** or the gauge button to bring up the stats
overlay described below.

### What the player is actually doing

Checked against `media_kit` 1.2.6 / `media_kit_video` 2.0.1 in the pub cache, so
the obvious knobs are **already set** and do not need touching:

| Option | Value | Set by |
|---|---|---|
| `vo` | `libmpv` | `media_kit_video` |
| `hwdec` | `auto` (hardware decoding on) | `media_kit_video` |
| `cache` / `cache-on-disk` | `yes` / `yes` | `media_kit` |
| `demuxer-max-bytes` / `-back-bytes` | 32 MB (from `bufferSize`) | `media_kit` |
| `network-timeout` | `5` | `media_kit` |
| `demuxer-lavf-o` | `seg_max_retry=5`, `strict=experimental`, `allowed_extensions=ALL`, `protocol_whitelist=[…]` | `media_kit` |
| `hr-seek`, `scale`/`dscale=bilinear`, `dither=no` | — | `media_kit` |

So if a **single untouched stream** still stutters, hardware decoding and caching
are not the cause — it is the stream, the network path to the provider, or
decoder/display load.

`player.hardware_decoding` now drives `hwdec` (`auto`/`no`), and
`player.live_tuning` exposes the provider-dependent options listed below plus a
free-form `properties` map — see `docs/PERSONALIZING.md`.

### Reading the stats overlay

The player now has a stats overlay — the **I** key, or the gauge button in the
controls — which reads these straight from mpv once a second:

| Row | mpv property | What it tells you |
|---|---|---|
| Decoder | `hwdec-current` | the hardware decoder that *actually* engaged, or `no` for software |
| Codec / Resolution / FPS | `video-codec`, `width`/`height`, `estimated-vf-fps` | what is being decoded, and at what rate |
| Dropped (decode) / (output) / Mistimed | `decoder-frame-drop-count`, `frame-drop-count`, `mistimed-frame-count` | frames lost |
| Buffered / Cache fill / Cache rate | `demuxer-cache-time`, `cache-buffering-state`, `cache-speed` | how much stream is buffered |
| A/V sync | `avsync` | drift between audio and video |

That is what tells the two cases apart:

- **dropped frames with cache fill at 100%** → decode or display cannot keep up
  (try `hwdec=no` to compare, or a lower resolution);
- **cache fill falling below 100% with few dropped frames** → the network or the
  provider is starving the stream;
- **Decoder says `no`** → hardware decoding did not engage for that codec.

Nothing in this project should be changed on a hunch before that is measured.
Note that `cache-on-disk=yes` on a live stream writes the cache to a temporary
file, which is a candidate if the disks are busy.

Still open:

- `player.live_tuning` is applied to live streams only; movies and series may
  want the same treatment once a provider that needs it turns up.
- The overlay polls with `Timer.periodic` and is not localised; fine for a
  diagnostic, but it should move to the language files if it is kept.
- For **movies/series** the position ticks still rebuild the overlay, because the
  scrubber needs them; scope that rebuild to the slider alone.
- The catalogue is `json.decode`d / `json.encode`d on the UI isolate in
  `AppStorage`; a large playlist belongs on an isolate via `compute`.

What to try if the numbers point at the provider, now that they no longer need a
rebuild: in `player.live_tuning`, `reconnect: true` for streams that drop
mid-playback, `cache_on_disk: false` if the disks are busy, and `user_agent` set
to the playlist's if the provider checks it. Apply one at a time and re-read the
overlay after each — what fixes one provider can break another.

## 7. VOD browsing came back the expensive way — `[~]`

The same mistake that made Live TV feel heavy was still present on the VOD side,
plus two smaller ones found next to it:

| Cause | Fix |
|---|---|
| Backing out of a movie/series detail screen, and returning from the player on those screens, re-read and re-decoded the whole catalogue for what is only a watch-state change | all four sites now use `ContentWatchStateReloaded`; `ContentReloaded` had no callers left and is gone |
| Category counts rescanned the entire catalogue once per category row, making every filter, sort and *keystroke* in search `O(categories × items)` | counted in one pass |
| The favourites row tested membership against a `List`, so it was `O(items × favourites)` | tests against `state.favorites`, which is already a `Set` |
| `Dio` was created without timeouts, so a provider that stops answering hangs the caller — and the guide's two-endpoint fallback never reaches its second endpoint | one shared client in `core/utils/http.dart` with a 15 s connect and 30 s receive timeout |

**To check:** open a movie, back out (the grid should return without a pause),
play one and come back, and type in search on a large playlist. If a provider is
normally slow to connect, the new timeouts are the thing to watch — they are
generous on purpose.

---

## 8. The catalogue no longer decodes on the UI isolate — `[~]`

`AppStorage` ran `json.decode` and then built a model per entry for the whole
catalogue on the isolate that draws the frame. On a large playlist that is tens
of thousands of strings and objects blocking the UI, which is what made opening
the app, switching playlists and moving between Live, Films and Series stall
before anything appeared.

The four catalogue reads — `channels`, `movies`, `series`, `categories` — now go
through `compute`, so the parsing and the model building happen in a short-lived
background isolate. A corrupt or empty store still degrades to an empty list, and
`app/test/app_storage_test.dart` round-trips all four shapes through a real box to
prove the models survive being copied across the boundary.

The finished list is still copied back to the UI isolate, so this is not free on
a very large catalogue — the parsing and the map lookups are simply no longer
spent there.

**Deliberately not moved:** `json.encode` when saving after a sync. Getting the
models *to* an isolate costs a full copy of the catalogue, so encoding there would
trade one pass over the data for another; the save also already sits behind a
progress spinner.

### The catalogue is read once per playlist

A catalogue that is never read twice is never copied twice, so `ContentRepository`
holds the decoded one for the playlist in use. Moving between Live, Films and
Series is now instant instead of a fresh decode each way, and it takes the decode
out of search entirely — every search read all three kinds out of their boxes in
full, on top of its own debounce.

Only one playlist is held, and each of the three writers to the store — `sync`,
`clearPlaylistCache`, `clearEverything` — drops it. `sync` drops it *before* it
writes, so a sync that fails halfway cannot leave the cache serving the catalogue
it just half-replaced. `app/test/content_repository_test.dart` covers reading once,
the per-kind category keys, the eviction, both clearing paths, the failed sync, and
that the lists handed out cannot be modified in place.

**Still open:** typing in the **browse** search box has no debounce, so every
keystroke lowercases the name of every item in the catalogue before matching. The
search screen debounces for 320 ms; the grid does not. Cheap to postpone now that
the decode is gone, but it is the next thing that will stutter on a large playlist.

---

## Backlog

- Persist the last used volume per stream kind instead of resetting to the
  default on every open.
- Programme guide: fetch the full day in the background and cache it per channel,
  so switching channels does not re-request.
- Preview: optional custom "offline" image via `branding`, if the built-in card
  is not wanted.
