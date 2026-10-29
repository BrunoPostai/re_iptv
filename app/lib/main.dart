import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/di/injector.dart';
import 'core/platform/platform_window.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // libmpv / media_kit must be initialised before any player is created.
  MediaKit.ensureInitialized();

  await PlatformWindow.initialize();

  // Personal overrides live next to the app data, so a local build can be
  // customised without editing tracked files.
  try {
    final support = await getApplicationSupportDirectory();
    AppConfig.overrideDirectory = support.path;
  } catch (_) {
    AppConfig.overrideDirectory = null;
  }

  final config = await AppConfig.load();

  // Window sizing is a desktop concern; on a phone the app fills the display.
  if (PlatformWindow.isDesktop) {
    await PlatformWindow.show(
      WindowOptions(
        size: Size(config.window.width.toDouble(), config.window.height.toDouble()),
        minimumSize: Size(config.window.minWidth.toDouble(), config.window.minHeight.toDouble()),
        center: true,
        title: config.branding.windowTitle,
        backgroundColor: AppTheme.windowBackground,
        titleBarStyle: config.window.titleBarStyle == 'custom'
            ? TitleBarStyle.hidden
            : TitleBarStyle.normal,
        windowButtonVisibility: config.window.titleBarStyle != 'custom',
      ),
    );
  }

  await configureDependencies(config);

  runApp(const ReIptvApp());
}
