# re_iptv (application)

The Flutter desktop client. Everything you need is in the repository root
[`README.md`](../README.md); this file only covers working inside the package.

## Run / build

```powershell
flutter pub get
flutter run -d windows
flutter build windows --release     # -> build\windows\x64\runner\Release\re_iptv.exe
```

On a machine without Developer Mode, create the Windows plugin links as junctions
first:

```powershell
powershell -ExecutionPolicy Bypass -File ..\tools\make_plugin_junctions.ps1
```

## Checks

```powershell
flutter analyze
flutter test
```

## Layout

```
lib/
├─ core/       config (app_config.json loading), theme, i18n, DI, utils
├─ data/       models, playlist sources (Xtream, M3U), repositories, Hive storage
├─ blocs/      settings · playlist · content · player
├─ features/   splash · home · live · movies · series · replay · search · playlist · settings
└─ widgets/    title bar, tiles, grids, dialogs
assets/
├─ config/     app_config.json — the personalisation entry point
├─ branding/   neutral placeholder logo and backgrounds (regenerate with tools/make_branding.py)
└─ languages/  en.json + index.json

tool/hive_dump.dart    read-only inspector for the app's own Hive boxes
```

See [`../docs/PERSONALIZING.md`](../docs/PERSONALIZING.md) for branding, feature
flags, themes and languages, and [`../docs/EXTENDING.md`](../docs/EXTENDING.md)
for adding playlist types or screens.
