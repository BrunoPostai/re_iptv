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
| While a movie or an episode played, every position tick (several a second) rebuilt the whole overlay — progress bar, buttons, volume slider — when only the scrubber and the elapsed time had changed | the overlay ignores a position-only change for every kind now; the scrubber and the label read the state through `_PositionBuilder`, so a tick repaints two widgets |

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

### Searching waits for typing to pause

Filtering lower-cases the name of every item in the catalogue and a query change
arrives on every keystroke, so a query is now held back until typing stops — the
same 320 ms the search screen already used (`searchDebounce`). The query itself is
recorded straight away, a later keystroke supersedes the one that is waiting, and
selecting a category or switching kind drops the pending filter entirely. A burst
therefore costs one pass, and it is the last query that is filtered for.
`app/test/content_bloc_test.dart` covers the deferral, the burst and the category
change — the first two fail if the filter runs per keystroke, which is how they
were checked.

**To check:** type in the browse search box on a large playlist. The list should
settle once you stop rather than narrowing letter by letter, and clearing the box
should bring everything back.

---

## 9. No key did anything in the player — `[~]`

`I` (stats), `F` (fullscreen), space, the arrow keys and `Escape` all did nothing,
while every button on the same overlay worked. The handler was reading the player's
bloc out of the widget tree — `context.read<PlayerBloc>()` — but this screen
*creates* that `BlocProvider` in its own `build`, so the `State`'s context sits
above it. The read threw `ProviderNotFoundException` before the switch was ever
reached, on every key press, in a release build where nothing listens for it.
A `State` cannot reach a provider its own `build` creates.

Verified rather than guessed: a throwaway probe printed
`FROM STATE CONTEXT: ProviderNotFoundException` / `FROM INNER CONTEXT: found`.

The bloc is now created by the screen and handed to `BlocProvider.value`, so the
handler reaches it directly, and `dispose` closes it since the provider no longer
owns it. Physical-key matching for `F`/`I` stays, so the shortcuts still work on a
keyboard that does not put those letters where they are labelled.

**To check:** in the player, `I` shows the stats read-out, `F` and `Escape` leave
fullscreen — `Escape` closing the player when it is not fullscreen, space pausing,
and the arrows seeking ten seconds either way.

---

## 10. A film started again instead of resuming — `[~]`

Four separate faults, and it took all four to keep a film from resuming:

1. **Nothing was written.** Progress was saved only when the player screen was
   disposed or the film finished. The app's close button closes the window, and
   closing a window destroys it without ever unmounting the player's route — so
   quitting mid-film saved nothing at all. Backing out with the player's own
   button did save, as a write nothing waited for.
2. **The saved position was never applied.** The player opened the stream and then
   immediately called `player.seek(startAt)`. `open` returns as soon as libmpv has
   been handed the file; for a network stream the file is still being opened for
   seconds after that, and mpv drops a seek that arrives before it has one — this
   is `media_kit` #1215, "the video always ignores the `seek()` command and starts
   from `Duration.zero`". So every attempt at resuming was thrown away, which is
   why the fix for (1) on its own changed nothing.
3. **The write had not landed yet.** The screens that push the player re-read the
   resume position the moment the route pops (`movie_detail_screen`, `series_detail_screen`),
   and the write was made from `dispose` — a moment after that. Backing out of the
   player onto the film's own page and pressing play again therefore read a list
   with nothing in it, while going back further, to the list, and opening the film
   again gave the write time to land and resumed correctly. That asymmetry is what
   gave this fault away.
4. **The page read its resume state too late.** The bar and the play button on a
   film's own page come from a copy of the resume list that the page reads itself,
   and that read was queued behind the provider's metadata call (`get_vod_info`,
   `get_series_info`). Right after a stream has closed that call can take seconds,
   and until it answered the page showed no bar and its play button started the
   film over — while the *grid* showed the bar correctly, because the grid takes
   its bars from the bloc's state, which needs no provider call. List right, page
   stale: that split is what pointed here.

**Fixed:** progress is written as playback goes — every `progressSaveInterval`
(10 s), after a seek, and on completion. Each write is queued behind the previous
one, because a write reads the list it is about to replace and two at once could
drop an entry. Leaving the player now saves first and waits for that write, so the
page behind it already sees the new position — both the back button and `Escape`
go through `_exit()`. The resume position itself goes to libmpv inside the `Media`
handed to `open`, which mpv applies in its `on_load` hook, before it starts
decoding — the way libmpv is meant to be told. Since that does not stick for every
stream, `PlayerBloc` also arms a one-shot check on the first duration the demuxer
reports: a stream still sitting near its beginning two seconds later is seeked
instead. It is looked at once, and never after the viewer seeks themselves. Live
streams and anything under 30 s are left alone, as before.

A film watched to the end now drops its resume entry, so playing it again starts
the film over rather than dropping the viewer on its last minute.

The two detail screens now read their watch state — the favourite flag and the
resume positions — on its own and straight from the local store, before and
independently of the metadata call, and re-read that part alone as the player
pops. Nothing on the way to the bar waits on the provider any more.

`Settings → About` shows the running build (`data\app.so`'s timestamp). The exe
keeps the date it was first built — all the Dart ships beside it — so the file
name alone could not say whether a build had been replaced or a fix had failed.

`app/test/content_repository_test.dart` pins the contract resume depends on: the id
the player files a film under is the one the detail screen looks it up by, an
episode lands in the series list rather than with the films, re-watching moves an
entry to the front instead of adding a second one, and clearing one entry leaves
the others alone.

**To check:** play a film for a minute or two, then back out with the player's own
button and press play again *from the film's page* — it should carry on where it
stopped, and the **Continue watching** bar should be on that page the moment it
appears. Same for an episode. Watch one through to the end and play it again — it
should start over.

**Still open:** nothing — the exact-on-close save this note used to ask for is now
implemented (see §13). A write still only lands every ten seconds *while* playing;
the close itself is what catches the last one.

---

## 11. The guide was requested again on every channel switch — `[~]`

The guide in **Live TV** asked the panel for the selected channel's listings on
every selection — the same day's listings, however often the viewer moved between
channels — and each request lands exactly when a stream is being opened, which is
already the slowest part of picking a channel.

**Fixed:** the repository keeps a channel's guide for the day it was fetched for
(`epgCacheLimit` channels, the oldest dropped), and two lookups of one channel in
flight at once share a single request. A panel that answers with no listings at
all is remembered for `epgEmptyRetry` — ten minutes, not the day — because an
empty answer is as likely to be a request that failed as a channel without a
guide. The screen also fetches the guide for the `epgPrefetchAhead` channels
*below* the selection in the background, `epgPrefetchGap` apart, stopping the
moment the selection moves: the next row down is the likeliest pick.

The request itself is unchanged — the full day's table (`get_simple_data_table`)
first, the short guide as fallback — which is what the earlier guide fixes
established.

`app/test/content_repository_test.dart` counts what the repository asks its source
for: a channel is fetched once and then answered from memory, two lookups at once
share one request, and an empty answer is not asked for again.

**To check:** move up and down a long channel list. A channel's guide should be
there as soon as it is picked, and coming back to a channel should not cost a
fresh request.

**Still open:** the cache is in memory for the session, so a restart forgets it,
and a guide fetched before midnight is served until that channel is picked again
after it. Persisting it per day would carry listings across restarts, at the cost
of a few hundred channels' worth of JSON in the content box.

---

## 12. The watched marker never showed — `[~]`

The original client puts a green **watched check** on the poster of a film or
series that has been watched through to the end (`docs/analysis/05-ui-screens.md`,
Movies grid), and `PosterCard` has had the parameter for it from the start — but
no screen ever passed `watched:`, so the check could not appear on anything. The
lists behind it were written and never read.

Worse, what was written was wrong: the player marked **films** for both kinds, so
an episode recorded *its own* stream id in `watched-movies` — a film that was
never played would have shown the check, while its series showed nothing.

**Fixed:** the player files a watched item where it belongs
(`ContentRepository.watchedEntry`): a film under its own id, an episode under its
**series'** id, a channel under its own. The bloc reads the watched list for the
kind in view alongside favourites and resume positions — on load and on
`ContentWatchStateReloaded`, which the detail screens already dispatch as the
player pops — and the Movies and Series grids pass it to their poster cards.

`app/test/content_repository_test.dart` pins the mapping and the read: watching an
episode leaves the series list holding the series id and the film list untouched,
which is what the grid's check is looked up by.

**To check:** watch a film to the end — its poster should gain the green check,
and with it the resume bar should be gone. Do the same with an episode: the check
should appear on its **series** poster, not on any film.

**Still open:** live channels mark themselves watched on exit with nothing reading
it; the original shows no check on a channel row, so that list stays unused. (The
search results were the other half of this and are done — see §15.)

---

## 13. Closing the window lost the last ten seconds — `[~]`

Progress is now written as playback goes (§10), so closing the window mid-film
leaves a resume that is at most one `progressSaveInterval` (10 s) behind where the
viewer stopped. The close button closes the *window*, and closing a window
destroys it without ever unmounting the player's route — so the write queued by
`dispose` (the exact position, and a completion) never happened.

**Fixed:** while the player is open it asks `window_manager` to hold the close
(`setPreventClose(true)`), and the close request is answered in `onWindowClose`:
flush the position, then `destroy()` the window itself. The write is given two
seconds and the window is handed back whatever happens — a close held open by a
write that never finishes is an app that cannot be quit. The hold is dropped in
`dispose` too, so leaving the player normally leaves the window closable.

**To check:** pause a film a minute in and close the app — from the player's own
close button (§16) or the title bar — start the app again and open the film: it
should resume within a second or two of where it was left, not ten seconds earlier.

---

## 14. One volume for everything — `[~]`

The volume was a single setting: whatever was last set while watching anything was
what the next stream opened at, live channel or film alike. Watching a film at 60%
meant a channel switched on in the background at 60%, and muting a channel left the
next film silent.

**Fixed:** two remembered volumes — one for live channels, one for films and
episodes (`StoreKeys.volume`, `StoreKeys.vodVolume`). The player opens at the
volume for the stream's kind, and writes back to that kind's entry only when the
volume actually changes (`VolumeChanged` with a `VolumeScope`), so a stream's own
opening volume is not rewritten on every position tick. `Settings → volume` shows
both and its dialog has a slider for each.

`app/test/settings_bloc_test.dart` pins it: each kind is stored under its own key,
changing one leaves the other alone, an out-of-range value is clamped before it is
stored, and both survive a restart.

**To check:** play a film, set it to 65%, leave. Play a channel — it should open at
the live volume (20% by default), not 65%. Change the channel to 40%, then watch
another film: it should come back at 65%.

Note: the live **preview** still opens muted and unmutes to the live volume without
remembering it — a preview is not watched, so it does not get to set the level.

---

## 15. Search results knew nothing about the viewer — `[~]`

§12 left the search results without any watch state: a film that had been watched
to the end carried no green check there, nothing showed as a favourite, and no
poster had a resume bar — and they would have gone stale on the way back from a
film even once they did, the same fault the detail page had in §10.

**Fixed:** the search screen reads favourites, watched ids and resume positions for
the three kinds (local store only — no provider calls) on open, and again each time
a channel, film or series page pops. Results carry the same marks as the grids they
came from, and the star can be toggled from the results themselves.

**To check:** search for a film you have watched to the end — it should show the
green check and no resume bar. Play a film's first minute from the results, back
out to search: the poster should now have a resume bar, without searching again.

---

## 16. The player had no window buttons — `[~]`

Reported while testing §13: *there is no close button in title bar*. The app draws
its own title bar (`title_bar_style: custom`, so Windows draws none) and that bar
does put minimise, maximise and close at its right-hand end — but the **player** is
a route on top of it with a top bar of its own, and that bar held nothing but a
Back arrow. So while anything was playing there was no minimise and no close
anywhere: the only way to quit the app mid-film was to leave the player first.
That is the very case §13 is about, which made its own test impossible to run as
written.

**Fixed:** the player's top bar carries minimise and close, drawn like the title
bar's own buttons (flat, the height of the bar, red on hover for close). Close goes
through the same held close as the title bar, so the position is flushed before the
window goes (§13) — quitting from the player is now the *best* way out of a film,
not the worst. Maximise is deliberately left out: double-clicking the top bar
already toggles it, and it sits next to the overlay's own fullscreen toggle, which
is a different thing.

**To check:** while a film plays, move the mouse to the top of the screen — a `-`
and an `✕` should appear at the right. `-` minimises, `✕` quits the app, and
opening the film again resumes where it was.

---

## Backlog

- Preview: optional custom "offline" image via `branding`, if the built-in card
  is not wanted.
