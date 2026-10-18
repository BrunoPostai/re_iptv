# 05 — Screens and interaction model

This is the specification the recreation implements, derived from observing the
running application and from the view/class names in the binary. Screen titles
are quoted as they appear in the UI.

## Shell

* Frameless window (`window_manager`) with an in-app title bar: small logo on the
  left, `<brand> v<version>` next to it, then minimise / maximise / close on the
  right. Drag anywhere on the bar; double-click toggles maximise.
* Dark theme, photographic background with a dotted world-map overlay, gold
  headings, orange tile labels, blue translucent cards.
* Every sub-screen keeps the same title bar and adds a back arrow.

## 1. Splash

Visible content, top to bottom:

| Element | Notes |
|---|---|
| Logo + product name | centred, gold |
| `version 1.0.4` | from package metadata |
| Identity panel | `Mac Address`, `Device Key`, `Device Id` |
| Progress area | linear progress + stage text during the first sync |
| Disclaimer | bottom, muted |

Behaviour: read stored playlists → authenticate the active playlist → import the
catalogue, reporting progress (`Connecting to playlist…`, `Loading live
channels…`, `Loading movies…`, `Loading series…`, `Ready`). On failure the user
is still taken home (the app is usable, just empty) rather than being trapped.

## 2. Home

* Top-right: live clock, and a status pill reading
  **"Current Playlist Expired On: dd/MM/yyyy"**.
* Centre: logo and the active playlist name.
* Navigation tiles (order matters — it is the original's):

  `Live TV` · `Movies` · `Series` · `Replay` · `Change Playlist` · `Search` · `Settings`

* Footer: "not for sale" style notice; a thin progress bar while re-syncing.
* Tiles are individually switchable through feature flags, so a reduced build
  simply shows fewer tiles.

## 3. Live TV ("Live Channels")

Three panes:

1. **Categories** (left, 250 px): `Continue Watching`, `Favourites`, `ALL`, then
   server categories with item counts. Hidden categories are marked and gated
   behind the parental PIN.
2. **Channel list** (centre): number, logo, name; a star toggles favourite; a
   clock glyph marks catch-up-enabled channels; locked channels show a padlock.
   Single click selects, double-click (or long-press) plays.
3. **Details** (right, 320 px): large logo, channel name, catch-up badge
   ("Catch up · N days"), **Watch** button and a short-EPG list with the current
   programme highlighted in gold.

Header: search box, sort selector, reload-from-server button.

## 4. Movies

Header: heading + active playlist name, search, sort, reload.
Sidebar: same pseudo-categories as Live (`Continue Watching` shows partially
watched films with a progress bar under the poster).
Grid: poster cards (2:3) with rating badge, favourite toggle, watched check and
resume progress; hover highlights the border in gold.

## 5. Movie detail

Two columns: poster + **Play** + favourite toggle on the left; on the right the
title, chips (rating, release date, duration, container), a "Continue watching"
progress bar when a resume point exists, plot, genre, director, cast, and a
"Watch trailer" button that opens YouTube externally.

## 6. Series

Same shell as Movies. The poster grid is series-level; resume progress is
aggregated from the newest watched episode.

## 7. Series detail

Left column: cover, title, rating, release date, season dropdown, **Play first
episode**, favourite toggle, plot, genre, cast, trailer.
Right column: episode list — thumbnail, `N. Title`, per-episode progress bar,
duration, play glyph.

## 8. Replay / catch-up ("Catch Up")

Left: categories. Centre: only channels flagged with an archive, each showing the
archive window in days. Right panel: selected channel name, availability, a
**date** picker bounded by the archive window, a **time** picker, a duration
slider (15–240 min), and **Play catch up**, which builds the
`/streaming/timeshift.php` URL.

## 9. Search

One field, debounced, with three tabs whose labels include result counts:
`Live TV (n)`, `Movies (n)`, `Series (n)`. Channel hits play directly; movie and
series hits open their detail screens.

## 10. Change Playlist

* **Add Playlist** dialog: type selector (Xtream Codes / M3U-M3U8), name, server
  address or M3U URL, username + password (Xtream only), optional EPG URL;
  validates and normalises the address (adds `http://`, strips trailing slashes).
* Playlist cards: icon by type, name, `username · host`, type, ACTIVE badge,
  delete button (with confirmation that also clears that playlist's cache).
* Right panel: device identity, then account details — playlist, host,
  **Expires on** (green/red), status, connections, TRIAL marker — plus
  "Refresh content" and "Clear cached content".

## 11. Settings

A wrapped grid of blue cards (4 across at 1280 px):

`User Account` · `Change Theme` · `Change Language` · `Stream Format` ·
`Subtitle Settings` · `Parental Control` · `Hide Live Categories` ·
`Hide Movie Categories` · `Hide Series Categories` · `Change Playlist` ·
`Clear Cache` · `About`

Each card shows its current value underneath the label (theme name, language,
`HLS (m3u8)`, `22 pt`, `PIN set`/`Disabled`).

Dialogs:

* **Theme** — thumbnail + name per theme, gold border on the active one.
* **Language** — scrollable list, check mark on the active language.
* **Stream format** — `Default`, `HLS (m3u8)`, `MPEG-TS` with radio rows.
* **Subtitle settings** — 10–60 pt slider with a live preview rendered at the
  chosen size.
* **Parental control** — set/clear a 4–6 digit PIN.
* **Hide … categories** — checkbox list per content kind.
* **About** — disclaimer, no-sale notice, website.

## 12. Player

Full-bleed video on black with an auto-hiding overlay (4 s):

* top: back arrow, title, `S1 · E2 · Episode name` subtitle for episodes;
* centre: play/pause on click;
* bottom: seek bar (VOD only), position/duration (or a red `LIVE` tag), subtitle
  and audio track sheets listing every track the stream reports, volume slider,
  fullscreen toggle.

Keyboard: `Space` play/pause, `←`/`→` ±10 s, `F` fullscreen, `Esc` back.

Progress is written every 10 s and on exit; crossing ~92 % (or reaching the end)
marks the item watched. Live playback marks the channel watched on exit.

## Notes on fidelity

* The recreation keeps the original's information architecture and interaction
  patterns; it does not reproduce its artwork, fonts or wording where those are
  vendor assets (see [06](06-strings-and-i18n.md)).
* The ERG-like "sports guide", server-switch and trial-notice features exist as
  flags but are off: they depend on the vendor backend.
