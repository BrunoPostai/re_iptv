import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/playlist_bloc.dart';
import 'blocs/settings_bloc.dart';
import 'core/config/app_config.dart';
import 'core/di/injector.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/content_repository.dart';
import 'data/repositories/playlist_repository.dart';
import 'data/storage/app_storage.dart';
import 'features/splash/splash_screen.dart';

/// Root widget: owns the global blocs and rebuilds the theme when settings
/// change.
class ReIptvApp extends StatelessWidget {
  const ReIptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();

    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsBloc>(
          create: (_) => SettingsBloc(getIt<AppStorage>(), config)..add(const SettingsStarted()),
        ),
        BlocProvider<PlaylistBloc>(
          create: (_) => PlaylistBloc(getIt<PlaylistRepository>(), getIt<ContentRepository>()),
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settings) {
          if (!settings.ready) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(config.defaultTheme),
              home: const Scaffold(
                backgroundColor: AppTheme.windowBackground,
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          return MaterialApp(
            title: config.branding.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(settings.theme),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
