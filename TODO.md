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

**Checked:** partly — the panel lists and scrolls, which was the part that
mattered. Titles and times were not gone through closely; not urgent.

## 2. Live preview with an "offline" placeholder — `[x]`

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

**Checked:** confirmed.

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

## 6. Live playback stability — `[x]`

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

**Checked:** confirmed — live playback is fine on the real playlist.
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

## 7. VOD browsing came back the expensive way — `[x]`

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

**Checked:** confirmed — the grids return without a pause.

---

## 8. The catalogue no longer decodes on the UI isolate — `[x]`

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

**Checked:** confirmed.

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

## 10. A film started again instead of resuming — `[x]`

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

**Checked:** partly — the guide scrolls and does not feel slow. Whether a return
to a channel is answered from the cache was not measured; not urgent.

**Still open:** nothing. The listings are kept in the playlist's content box as well
as in memory now, so a restart no longer re-asks the panel for every channel:

* one entry per channel per day, keyed `epg-<date>-<streamId>` — the day is in the
  key, so an entry from a day that has passed is found and dropped without a single
  value being read, and that sweep runs once a session, when the guide is first
  looked at;
* the store holds exactly what memory holds: what the session cache evicts
  (`epgCacheLimit` channels, the ones gone longest without being asked for) is
  deleted from the box too, so a browse across a whole playlist cannot fill the
  disk with listings the session itself has already forgotten;
* an empty answer is never written, because a panel that answered with nothing is
  asked again rather than remembered for the day;
* the day is read at each use rather than fixed, so an app left running across
  midnight files the new day's listings under the new day — a guide fetched before
  midnight is no longer served after it.

Every visit to the store is best-effort: the store is an optimisation, and a box
closed under a request in flight (its playlist deleted while it was pending) must
not turn into a guide that never arrives. `epgPrograms` stores a listing's title,
description and both times as they are, rather than the provider's shape, whose
base64 text and unix times have already been decoded by then.

`app/test/content_repository_test.dart` covers it: a guide outlives a restart with
the panel asked zero times, an empty answer is asked for again after one, a listing
stored for another day is dropped and refetched, and the store is held to
`epgCacheLimit` channels — with the evicted one proving to be a real eviction by
costing a request when it is next picked.

**To check:** pick through a few channels in **Live TV**, close the app, open it
again and pick one of them: its guide should be there at once, with no loading
state, because it never went away. The guide of a channel picked for the first time
today should still arrive as it does now.

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
search results were the other half of this and are done — see §15.) The
episode → series mapping still wants one end-to-end look: the green check is
confirmed on a watched film (§15), and an episode can now be watched to the end at
all — see §17. Its *resume* id was the other half of the same story and is now
derived once instead of twice — see §18.

---

## 13. Closing the window lost the last ten seconds — `[x]`

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

**Checked:** confirmed — the film came back where it was stopped.

---

## 14. One volume for everything — `[x]`

The volume was rebuilt as two remembered ones — live apart from films — and that
was wrong: set 40% on a channel and the next film came back at 20%, which reads as
a bug however it is argued (reported exactly that way). A volume is a volume.

**Fixed:** one remembered volume (`StoreKeys.volume`). The player opens at it,
whatever the stream, and writes back only when the volume actually changes
(`VolumeChanged`), so a stream's own opening volume is not rewritten on every
position tick. `Settings → volume` has a single slider for it, and the value shown
on the tile is that one number.

`app/test/settings_bloc_test.dart` pins it: the last volume wins whatever it was
set on, an out-of-range value is clamped before it is stored, and it survives a
restart.

**To check:** set 40% while watching a channel, leave, open a film — it should open
at 40%. Set 65% while watching a film; the next channel should open at 65%.

Note: the live **preview** still opens muted and unmutes to the remembered volume
without writing it back — a preview is not watched, so it does not get to set the
level. Switching to the next episode inside the player keeps the volume too
(`PlayerOpened.keepVolume`), rather than snapping back to the opening one.

---

## 15. Search results knew nothing about the viewer — `[x]`

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

**Checked:** confirmed — the green check appears on a watched film.

---

## 16. The player had no window buttons — `[x]`

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

**Checked:** confirmed — this is how §13 was tested.

---

## 17. The end of an episode was a dead end — `[x]`

Reported: *when the episode ends it keeps loading and nothing happens*. Three
things were wrong at once, and only together did they explain it:

1. **The spinner never stopped** — see below: the first try at this did not work,
   because the signal it was watching for never arrives.
2. **The play button did nothing.** At the end of a file libmpv has nothing left to
   play from, so `playOrPause` was a no-op: the one button on screen did nothing.
   The button becomes **Play again** and sends `PlayerReplayed`, which seeks back to
   the start first — which is why pressing play at the end of anything did nothing
   before, films included.
3. **There was no next episode.** An episode's page is where the next one lived, so
   watching three in a row meant backing out and picking each one by hand.

**Fixed:** the series page builds the whole series in season and episode order —
sorted, so `Next` is the episode after this one even if the panel lists `1, 10, 2` —
and hands it to the player as the item's `siblings` (a field `MediaItem` has had
since the beginning and nothing filled in). The player opens the next or previous
episode **on the same player** rather than pushing another route: the item being
left is saved first, so three episodes in a row leave three resume positions, and
the new one opens at its own resume position (found by series, season and episode
number, not by the id the entry was filed under). The volume is kept across the
switch (`PlayerOpened.keepVolume`) instead of snapping back to the opening volume,
which would also have written that lower volume back to the settings.

The overlay carries `⏮` and `⏭` around the play button when there is an episode
either side, and at the end of a stream stays up — rather than fading after four
seconds like a stale control bar — showing **Finished**, **Play again** and, when
there is one, **Next episode** with its `S·E` line underneath.

**It still span.** Reported back: *when I end an ep it still spins and nothing
happens, I should just exit the player*. The first attempt was watching for
`completed` — and `completed` is never set for these streams. `media_kit` sets it
from mpv's `eof-reached`, and the panel never lets mpv reach it: the connection is
held open at the end of a film, so mpv runs out of data, goes **idle** and waits.
`media_kit` reports that idle state as `buffering`, which is precisely the spinner
that would not stop, and with no `completed` there was no end card and nothing to
press either. Every signal the first attempt used was one the stream never sent.

**Fixed, second attempt:** `hasEndedPlayback()` — a stream within `_endSlack` (3 s)
of its **reported** end that is not playing normally has ended, whether mpv says so
or not. Waiting for data counts as ended; a pause does not; a live channel or a clip
under 30 s never ends this way; and a stream that plays *past* its reported end is
left alone until it stops, so a provider that under-reports a duration does not have
its film cut off early. When it fires, playback is paused, so mpv stops asking the
panel for the rest of a file that has ended instead of sitting on the connection.
`app/test/player_end_test.dart` pins all seven cases, that rule being exactly the
kind of thing that is easy to get subtly wrong.

The stats overlay (`I`) grew three rows for this class of hang — **End of file**,
**Core idle**, **Waiting for data** — because "why did playback stop moving" is the
question it exists to answer, and `eof-reached` is what separates the two ways mpv
goes idle.

**Checked:** confirmed — the spinner stops, **Finished** appears, and both the end
of an episode and `⏮`/`⏭` work. The first attempt was watching for a signal these
streams never send, which is why it took a second pass and why the rule is pinned
by a test rather than left to the next reader.

**Still open:** nothing advances on its own at the end of an episode — the buttons
are there, but the viewer presses them. Auto-advance (with a countdown) is the
obvious next step if it is wanted.

---

## 18. An episode's resume position was filed under an id nothing read — `[x]`

The player files an episode's progress under the series it belongs to and the
stream id it was played by — `parentId:streamId` — and that stream id is derived
from the provider's episode id, because the episode's own stream is what the panel
is asked for by it. The series page looked the position up under
`seriesId:episode.id` instead: the **raw** episode id, not the derived one.

The two strings come out identical for any panel that numbers its episodes plainly,
which is why nothing had caught it: they agreed by coincidence. On a panel that
sends `e9`, or `007`, or a whole URL as an episode id — all of which are real — the
episode row had no progress bar and the episode started over from the top, however
much of it had been watched.

**Fixed:** the derivation lives on the model, beside the data it is about —
`Episode.streamId`, the parsed id with the episode number as its fallback, since
that is the only other thing about an episode every panel sends — and the id format
lives in one place, `ContentRepository.episodeProgressId`, next to `watchedEntry`.
The player writes it, and the series page's **Continue watching** bar and its
episode rows read it. Nothing builds a `series:episode` string by hand any more.

`app/test/content_repository_test.dart` pins the four shapes an episode id arrives
in — `e9`, `007`, `42` and a URL — and reads the entry back from the store the way
the page reads it.

**To check:** on this playlist nothing should look different — the bug only showed
on panels that number episodes oddly. Watching part of an episode and backing out
should leave the progress bar on its row and carry on from there when pressed, same
as before.

---

## 19. An error about a stream that recovered stayed on screen — `[~]`

libmpv reports errors as it opens a stream, and `media_kit` turns its error-level
log lines into `Player.stream.error`: a connection reset while the stream was being
opened, a codec that would not start. Several of them are survivable — the stream
goes on to play — and the player kept the message until something else was opened.
A red box with libmpv's text therefore sat over video that was playing perfectly
well, and only leaving the player or opening another stream took it down.

**Fixed:** the message takes itself down. `_showErrorBriefly()` gives it
`playerErrorVisible` (five seconds) and then clears it from the state, and
`_clearErrorIfPlaying()` takes it down sooner when video is actually on screen —
playing, and not waiting for data — because that is the contradiction: whatever was
logged, this stream is playing. Opening a stream still clears it outright, an empty
log line is no longer treated as a message (it showed as an empty red box), and the
card fades out rather than blinking away, so the message leaving looks deliberate.

Both places that showed it gain: the player's card, and the live preview, which
chooses its offline card from `state.error` too — a stale error there kept *Nothing
on air right now* over a preview that had started playing. A channel that really is
off air is unchanged: the preview's own startup grace still marks it unavailable
after twelve seconds.

**To check:** force-start something while it is still loading. The red box should go
five seconds later, or sooner if playback starts, and video that is playing should
never have an error sitting over it.

**Still open:** nothing — with one thing to be aware of. A stream that is genuinely
dead goes quiet after those five seconds: the spinner, or a frozen frame, is all
that is left in the player, because the message about it has gone. The live preview
still shows its own card for a channel that never starts. If that turns out to be
too little to go on, the player could carry an *unavailable* card of its own the way
the preview does; the message is five seconds' worth of information either way.

---

## 20. Android is a platform now, and the live screen fits a phone — `[~]`

The app could only be a Windows program, in the way that matters: `main.dart` called
`windowManager.ensureInitialized()` and `waitUntilReadyToShow()` before the first
frame, the title bar asked `isMaximized()` of it, and the player called
`setPreventClose(true)` as it opened. `window_manager` publishes no Android
implementation, so on a phone the first of those threw `MissingPluginException` and
the app ended before it drew anything.

**Done:** `PlatformWindow` is the single place that touches it, and everything else
asks it the one question — is there a window. The startup sequence sizes and shows
one on the desktop only; the title bar keeps back, title and actions, drops minimise,
maximise and close, and grows by the status bar inset the body was ignoring; the
player's fullscreen hides the system bars instead of resizing a window; holding a
close open while progress is written stays a desktop behaviour, since a phone is not
closed by a window button. `buildStamp()` reports `unknown` off Windows rather than
dating the build by the phone's own files.

The screens are the second half. `WindowClass` splits widths into compact below 600,
medium below 1024 and expanded above it, so the desktop — never narrower than
`window.min_width` 1024 — keeps the layout it had. The live screen was the first to
use it: on a phone the 250 pixel category sidebar becomes a drawer and the 320 pixel
details panel becomes the page, with back returning to the list. Catch Up then
followed it pane for pane, because the two screens are the same shape and somebody
who has learnt one should not have to learn the other: the archive picker is the page
once a channel is picked.

The heading row is where the rest of the change went. The desktop puts a heading, a
search box and the sort order on one line; a phone cannot, because the search box
alone is 250 of a 360 pixel line, so the heading keeps the controls beside it and the
search box takes the line below. `ScreenHeader` is that one widget now, and it
replaced four hand-written rows — live, catch up, movies/series and search.
`SearchField` takes a null width, meaning fill the line you were given, because a
stacked line has no width to give it.

The two detail pages came out differently, because they hold different things. A
movie keeps its poster beside the text and shrinks it from 250 to 120, with the gaps
and the padding to match. A series has more to show and cannot spare a 320 pixel
column at all, so on a phone its details become the top of the page and the episodes
follow them down it under an `EPISODES` heading — one scroll instead of two panes.

Fixed widths were the other way this broke: a thing wider than the screen overflows
rather than shrinks. `fitWidth` caps the settings dialogs (560, 460, 420 and 380
pixels) and the splash's identity card and status lines at what is actually there;
the home screen's expiry pill can now wrap beside the clock instead of running past
the edge. The player gained what a phone needs to be watchable at all: a tap on the
picture brings the control bar back, since there is no pointer to hover with, and ten
second skips stand in for the arrow keys where there is no keyboard. The keys still
work; the two share one `_seekBy` so they cannot drift apart.

Setting any of this up was its own afternoon: JDK 17 and the SDK live outside the
project — `C:\Users\you\Android\jdk17` and `C:\Users\you\Android\sdk`, both
pointed at by `flutter config` — and the build wants an NDK that the toolchain does
not fetch for itself, so `ndk;28.2.13676358` was installed by hand. None of that
belongs in the repository, which is why it is written down here.

**To check:** on a phone the live screen should show the channel list with no
overflow banner, a categories button in the title bar, and a tap on a channel should
open its preview, guide and Watch button with back returning to the list. Catch up
should behave the same way. Movies, series and search should stack their headings
without the yellow-and-black overflow stripes; a movie page should fit its poster and
text side by side; a series should read top to bottom, episodes under details;
settings should open its dialogs without running off the screen. In the player a tap
on the picture should bring the bar back, and the ten second buttons should move the
film. Windows should be untouched: three panes, the same title bar, the same
fullscreen.

**What the phone said:** the layout above was right, and three things were still
wrong once it was in a hand. Android 15 draws the app edge to edge, so the navigation
bar sat on top of the bottom of every page — `AppBackground` now pads its child by
the system insets while the artwork behind it still reaches the edges. The home grid
kept its fixed 132 pixel tiles, which is a stripe of background down each side and a
seventh tile stranded on a row of its own; on a phone the tiles now divide the width
three to a row, twelve pixels apart, which is what fits all seven on one screen. And
the player still had to be asked for fullscreen, which is a desktop habit: where
there is no window to resize it now opens with the system bars already hidden and
gives them back as it closes. Home, Change Playlist, Live — list, preview and Watch
— Catch Up and the player were walked on the phone; the rest of the screens are
still to come.

**Still open:** the player's subtitle, audio and stats panels are still dialogs sized
for a desktop, and seeking only goes ten seconds at a time rather than following a
drag along the picture. The APK builds — 205 MB, because a debug build carries libmpv
for four architectures — and it installs and plays on a phone; iOS still needs a Mac.

---

## 21. Every channel row showed a letter where its logo should be — `[~]`

The first thing the phone showed that the desktop had not: every channel in the
list was a single letter. `SmartImage` falls back to the first character of the name
when an image will not load, so the fallback was doing its job — across the whole
list, on a screen the port had only just started drawing. It looked like news,
because the port was what had changed.

It was not the port. The content cache pulled off the phone
(`run-as com.reiptv.re_iptv cat files/localData/re-iptv-<id>.hive`) holds 84,084
image URLs and every one of them is on `cdn.invalid`, which answers Cloudflare's `403`
"Attention Required!" page — to the phone, to a desktop Chrome user agent, to VLC's,
to a Dalvik one. It refuses everyone, so the desktop had been showing the same letters.
The same ids are served by the panel itself: `https://panel.invalid/logo/53084.jpg`
is `200 image/jpeg`, 17 KB, the Digimon logo. The playlist data names a host the
provider has left behind, and nothing on our side can fix that but ignore it.

**Done:** `Artwork` remembers the panel the active playlist talks to — set when a
playlist is made active, and again on every source lookup, because the first frame can
draw from Hive before anything has been fetched — and offers the same path there.
`SmartImage` became stateful in order to ask twice: the provider's URL, then the
panel's, then the placeholder letter. Nothing is rewritten in the stored data, so a
provider that mends its logos is picked up as it stands; an image already on the
panel, a local file, and an M3U playlist — which names its own hosts and has no panel
to ask — are left alone. `test/artwork_test.dart` pins the rewriting: scheme, host and
port are replaced, the path and its query kept.

**To check:** channel rows on the phone should draw logos instead of letters, and so
should the movie and series posters the provider hosts itself; TMDB artwork, already
on a host that answers, should not be asked for twice.

---

## 22. The catalogue and settings keep their desktop columns — `[~]`

Live and Catch Up were given one pane at a time; Movies and Series were only given a
stacked heading, which fixed the overflow banner and left the shape of the screen
alone. On a phone that shape was a 250 pixel category sidebar and, beside it, a poster
grid with 160 pixels to work in: one column of posters down the right-hand side, 14,000
of them a scroll away.

**Done:** the browser now follows the screens it resembles. Where there is no room for
a sidebar the categories become a drawer, opened from the title bar, and the grid takes
the whole width — three columns instead of one. The drawer is the same one Live and
Catch Up already had, so this was a rearrangement rather than a second design.

Two things fell out of looking at it. `AppColors.sidebar` is 80% opaque, which reads as
glass beside a list and as the poster grid showing through a drawer, so the three
drawers now sit on a solid floor and the sidebar keeps its translucency. And the
settings screen's tiles are 210 pixels wide with a 16 pixel gap, which on a phone is a
single column of tiles with a stripe of background beside them: compact now divides the
width in two, which is what the desktop does at its narrowest anyway.

**To check:** on a phone, Movies and Series should open three posters across with a
categories button in the title bar, and picking a category should close the drawer and
refilter the grid. Settings should show two tiles per row, and its dialogs should
scroll rather than run past the screen. On the desktop nothing should have moved: the
sidebar is still beside the grid, the drawers do not exist, and the settings tiles are
still 210.

---

## 23. A film opens the phone sideways — `[x]`

The player hid the system bars and then played a 16:9 stream in a 20:9 portrait window:
a band across the middle, black above and below, and a viewer holding the phone
upright to watch it.

**Done:** `PlatformWindow.setLandscape` asks Flutter for both landscape orientations,
and the player takes it in `initState` beside fullscreen, handing the choice back in
`dispose`, so closing a film returns to the portrait screen and the channel list it
came from. The desktop has no orientation to set and ignores it.

**To check:** a channel should open sideways on the phone, and the back gesture should
put the app upright again on the detail screen behind it.

---

## 24. A theme is a paint job, not a background swap — `[x]`

Choosing Gold Honor recoloured the wallpaper and left everything drawn on top of it
blue: headings, tile labels, the selected tab, the ring under the cursor, the progress
bar, the buttons. The three themes had been written as pictures, and the palette was a
constant that only the default theme happened to agree with.

**Done:** the palette became a `ThemeExtension` built by `AppTheme.build` from whatever
theme is active, and every screen reads `context.palette` instead of `AppColors`. It
carries the accent, an `accentBright` (38% toward white) for lettering on dark surfaces,
and an `accentDeep` (45% toward black) for edges that should not glare. Surfaces are
tinted from the accent too — panels 18% over `#152740`, the sidebar 16% over `#0A1420`
— so the tiles, dialogs and drawers belong to the theme rather than sit on it. Filled
buttons read `inkOn`: white lettering below a luminance of 0.18, black above it, which
is what lets the gold Watch button carry black text and the blue one keep white.

**To check:** switching theme should repaint the whole app at once, including the boot
screen, which now draws the chosen theme's wallpaper rather than the default one.

---

## 25. Each theme carries its own mark — `[x]`

The blue app icon on a gold home screen looks like a sticker left on the furniture. The
icon is part of the skin, so each theme now names a logo of its own: `ThemeSpec.logo`
and `logoSmall`, both optional, resolved through `logoFor` / `logoSmallFor`. A theme
that names none keeps the branding mark, so a provider's own logo still wins everywhere
it is configured. The home screen, the boot screen and every title bar draw the active
theme's mark; the theme picker draws each card's, so the choice shows what it changes.

The pictures themselves were re-coloured from the stock PNG rather than drawn again,
mapping hue and value through HSV so the "REIPTV" wordmark stays the one the provider
shipped. The stock art carries a soft drop shadow, which is invisible on the dark
default wallpaper and becomes a black rectangle on a gold tile; the themed copies strip
the neutral dark pixels to transparency. `logo_main.png` is the stock mark treated the
same way, so all three themes resolve through the same path.

**To check:** on the phone, each of the three themes should draw its own icon with no
dark halo, on the home screen, the boot screen, and every title bar.

---

## 26. The detail page and the playlist screen, opened on a phone — `[x]`

Two screens had not been opened on the phone before, and both had a desktop column
that a phone cannot hold.

The movie detail puts the poster in a 120 pixel column with the Play button and the
favourite heart side by side under it, which leaves the button about sixty pixels of
label: "Play" wrapped one letter per line inside a tall blue box. Compact now moves the
heart onto the corner of the poster, the way the grid cards already do, and the button
takes the whole column.

The playlist screen gives the account panel a fixed 360 pixels beside the list. On a
phone that panel is the screen, so the playlists were a stripe on the left with a
scrollbar and nothing else. Compact stacks them: the cards first at full width, then
the panel as a bordered block under them, inside the one scroll view rather than a
second one inside the first.

**To check:** on the phone, a movie's Play button should be a wide button under the
poster with the heart on the poster itself, and Change Playlist should show every
playlist in full with the device and account details below them. On the desktop both
should be exactly as they were.

---

## 27. A release key of its own — `[x]`

The release build was signed with the debug key, which is fine for the one phone
attached to this machine and useless for anything else: a debug keystore lives in
`~/.android` on the machine that built it, so an APK handed to someone else cannot be
upgraded by the next build - Android refuses a signature change and the app has to be
uninstalled, taking the saved playlist with it.

**Done:** a PKCS12 key pair, `re_iptv-release.jks`, kept outside the repository in
`Documents/keystores/re_iptv/`, and `app/android/key.properties` pointing at it (both
gitignored, with `app/android/key.properties.example` committed as the template).
`app/android/app/build.gradle.kts` reads the properties file when it exists and signs
with it; when it does not, it still signs with the debug key, so a fresh clone can make
an APK for its own phone without being told about a key it cannot have.

The README now says how to build for Android, how to sideload, and what losing the
keystore costs. The certificate fingerprint, for whoever needs to compare it later:

```
SHA-256 96:FD:5A:4D:9E:A7:88:2B:26:91:32:6D:D3:8C:24:C7:F8:36:EA:FD:49:DB:A0:05:F4:F8:ED:8E:57:23:F5:90
```

**To check:** `flutter build apk --release` should produce an APK signed by `CN=REIPTV`
rather than `CN=Android Debug` (`apksigner verify --print-certs`), and the phone that
carried the debug build must be uninstalled once before it will take this one.

---

## Backlog

- Preview: optional custom "offline" image via `branding`, if the built-in card
  is not wanted.
