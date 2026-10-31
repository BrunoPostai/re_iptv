# Third-party notices

This repository contains the source of the player only; the dependencies are
resolved from `pub.dev` at build time. Compiled binaries carry more, though, and
the ones attached to a release include a media library and a rendering engine that
are not ours and are not MIT.

Nothing below is a substitute for a licence text. Each Dart package's own
`LICENSE` ships inside the package and is readable in the pub cache after
`flutter pub get` (or on the package's page on `pub.dev`); the Flutter engine's
full notice file is generated into every build.

## What is inside a release build

| Component | Licence | Notes |
|---|---|---|
| Flutter SDK and engine | BSD-3-Clause | Includes the Dart runtime and Skia. The engine bundles its own third-party components and prints the complete list from `LicenseRegistry`. |
| `media_kit`, `media_kit_video`, `media_kit_libs_*` | MIT | The Dart and platform plugin code. |
| libmpv, and the FFmpeg it links | LGPL-2.1-or-later as distributed by media_kit | See below — this is the only component with obligations that survive compilation. |
| Material Icons font | Apache-2.0 | |
| Cupertino Icons | MIT | |
| `font_awesome_flutter` | MIT | The Font Awesome fonts themselves are SIL OFL 1.1 and the icons CC BY 4.0, as their package states. |
| Remaining Dart packages | MIT or Apache-2.0 | Per package; nothing here is copyleft. |

## libmpv and FFmpeg

`media_kit` fetches prebuilt libmpv libraries — `libmpv-2.dll` on Windows, the
equivalent `.so` per Android ABI — and links them **dynamically**. That is what
keeps the LGPL's relinking requirement satisfiable: the library sits next to the
app as a separate file and can be replaced with another build of the same ABI
without rebuilding the app.

The builds used are media_kit's, published at
[`github.com/media-kit/libmpv-*`](https://github.com/media-kit) together with the
configure flags they were built with, and their source is available from there and
from `mpv` and `ffmpeg` upstream. If you redistribute a build of this app, ship
that licence text and that source offer with it. Running it yourself, or handing a
copy to family, needs nothing from you.

## Names and marks

"REIPTV" and the play mark are placeholders for this repository's own branding
system, described in [`docs/PERSONALIZING.md`](docs/PERSONALIZING.md). No
third-party product name, logo or artwork is included, and nothing here is
affiliated with or endorsed by any IPTV service or client vendor.
