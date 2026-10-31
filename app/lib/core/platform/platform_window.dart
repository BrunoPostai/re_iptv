import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// The OS window this build runs in — and what to do when there isn't one.
///
/// Windows owns a resizable frameless window that the app draws its own title
/// bar into: drag it, minimise it, close it, go fullscreen inside it. Android
/// and iOS have nothing of the sort, and `window_manager` ships no
/// implementation for them, so every call there would raise
/// `MissingPluginException`. Routing those calls through this class is what
/// lets a single widget tree run on both, with the desktop behaviour untouched.
abstract final class PlatformWindow {
  /// Whether the app draws its own window chrome.
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Whether the status bar sits on top of the app's own background.
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> initialize() async {
    if (isMobile) {
      // Mobile: draw under the system bars so the app background reaches the
      // edges, then let the widgets pad themselves with the safe area.
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return;
    }
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
  }

  /// Shows the window once Flutter is ready to paint. No-op off the desktop.
  static Future<void> show(WindowOptions options) async {
    if (!isDesktop) return;
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  static void addListener(WindowListener listener) {
    if (isDesktop) windowManager.addListener(listener);
  }

  static void removeListener(WindowListener listener) {
    if (isDesktop) windowManager.removeListener(listener);
  }

  static Future<bool> isMaximized() async =>
      isDesktop ? await windowManager.isMaximized() : false;

  static Future<void> maximize() async {
    if (isDesktop) await windowManager.maximize();
  }

  static Future<void> unmaximize() async {
    if (isDesktop) await windowManager.unmaximize();
  }

  /// Maximises a restored window and restores a maximised one.
  static Future<void> toggleMaximize() async {
    if (!isDesktop) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  static Future<void> minimize() async {
    if (isDesktop) await windowManager.minimize();
  }

  static Future<void> close() async {
    if (isDesktop) await windowManager.close();
  }

  static Future<void> destroy() async {
    if (isDesktop) await windowManager.destroy();
  }

  /// Lets a window close be deferred while playback progress is written out.
  ///
  /// Only the desktop has a window to hold; on mobile the route is disposed by
  /// the usual lifecycle callbacks.
  static Future<void> setPreventClose(bool prevent) async {
    if (isDesktop) await windowManager.setPreventClose(prevent);
  }

  static Future<void> startDragging() async {
    if (isDesktop) await windowManager.startDragging();
  }

  /// Enlarges the player onto the whole display.
  ///
  /// The desktop resizes its window; mobile hides the system bars instead,
  /// which is the same thing from the viewer's point of view.
  static Future<void> setFullScreen(bool fullscreen) async {
    if (isDesktop) {
      await windowManager.setFullScreen(fullscreen);
      return;
    }
    if (!isMobile) return;
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Turns a phone sideways for a film, and lets it back afterwards.
  ///
  /// A stream is wider than it is tall, so in portrait the picture is a band
  /// across the middle of the screen with black above and below it. The desktop
  /// has no orientation to set and ignores this; an empty list hands the choice
  /// back to the system.
  static Future<void> setLandscape(bool landscape) async {
    if (!isMobile) return;
    await SystemChrome.setPreferredOrientations(
      landscape
          ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const <DeviceOrientation>[],
    );
  }
}
