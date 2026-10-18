# Personalising your build

Everything user-visible is data-driven. You can restyle, rename, re-brand and
re-scope the app **without editing Dart code**, and your changes survive a
`git pull`.

## The override chain

At startup `AppConfig.load()` deep-merges, in this order (later wins):

1. `ibo_player/assets/config/app_config.json` — tracked defaults
2. `<app data>/app_config.local.json` — **not tracked** (highest priority in a
   normal build)
3. `ibo_player/assets/config/app_config.local.json` — optional tracked-or-local
   asset overlay

The app data folder on Windows is
`%APPDATA%\com.reiptv\ibo_player\app_config.local.json` (`getApplicationSupportDirectory()`).
Putting the file there means you can tweak a **shipped** build without
rebuilding.

Maps are merged key-by-key; arrays (like `themes`) are **replaced wholesale**, so
re-declare the whole array when you change it.

To brand your own build, also drop files in `ibo_player/assets/branding/local/`
and point the config at them — that folder is git-ignored.

## Branding

```json
{
  "branding": {
    "app_name": "My TV",
    "window_title": "My TV 1.0",
    "logo": "assets/branding/local/logo.png",
    "logo_small": "assets/branding/local/logo_small.png",
    "website": "https://my.tv",
    "disclaimer": "...",
    "no_sell_notice": "..."
  }
}
```

`logo` / `logo_small` accept three kinds of path:

| Value | Meaning |
|---|---|
| `assets/...` | bundled asset |
| `C:\path\to\file.png` | absolute file path (great for local overrides) |
| `https://...` | remote image |

## Feature flags

```json
{
  "features": {
    "live": true, "movies": true, "series": true, "replay": true,
    "change_playlist": true, "search": true, "settings": true,
    "user_account": false, "stream_format": true, "subtitle_settings": true,
    "parental_control": true, "themes": true, "languages": true,
    "sort_options": true, "sports_guide": false, "demo_playlist": false
  }
}
```

Turning a flag off removes its home tile and (for `user_account`) its settings
tile. Use this to ship a reduced build, e.g. a movies-only player.

## Themes

```json
{
  "default_theme": "main",
  "themes": [
    { "id": "main",  "name": "Background Main", "background": "assets/branding/bg_main.jpg", "accent": "#2C6FBB", "dark": true },
    { "id": "mine",  "name": "My Theme",        "background": "C:\\art\\wall.jpg",        "accent": "#E0A83C", "dark": true }
  ]
}
```

`background` is any image path (asset / file / URL), `accent` is the seed colour
used for selection and focus states. Themes are selectable at runtime from
**Settings → Change Theme**.

## Player defaults

```json
{
  "player": {
    "stream_format": "default",   // default | m3u8 | ts
    "subtitle_size": 22,
    "hardware_decoding": true,
    "start_fullscreen": false,
    "user_agent": "IPTVPlayer/1.0"
  }
}
```

## Window

```json
{
  "window": {
    "width": 1280, "height": 760, "min_width": 1024, "min_height": 600,
    "title_bar_style": "custom"   // custom → frameless + in-app title bar; "normal" → OS chrome
  }
}
```

## Languages

Add `assets/languages/<code>.json` and list it in
`assets/languages/index.json`:

```json
[
  { "code": "en", "name": "English" },
  { "code": "es", "name": "Español" }
]
```

Missing keys fall back to the key name, and a missing file falls back to
English, so a partial translation is safe to ship.

## Demo playlist

```json
{
  "demo_playlist": {
    "name": "Demo", "url": "http://your-server:8080",
    "username": "user", "password": "pass", "type": "xc"
  }
}
```

Only used when `features.demo_playlist` is `true` **and** no playlist is
configured. Keep credentials out of tracked files — put this block in your
`app_config.local.json`.

## Re-generating the placeholder artwork

```powershell
python tools/make_branding.py
```

Edit the colours/landmass list at the top of the script, or replace the files in
`assets/branding/` outright.
