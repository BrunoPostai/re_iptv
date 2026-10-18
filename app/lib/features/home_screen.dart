import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../blocs/playlist_bloc.dart';
import '../blocs/settings_bloc.dart';
import '../core/config/app_config.dart';
import '../core/di/injector.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/nav_tile.dart';
import '../widgets/title_bar.dart';
import 'live/live_screen.dart';
import 'movies/movies_screen.dart';
import 'playlist/playlist_screen.dart';
import 'replay/replay_screen.dart';
import 'search/search_screen.dart';
import 'series/series_screen.dart';
import 'settings/settings_screen.dart';

/// Landing screen: branding, account status and the navigation tiles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _version = '1.0.4';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
  }

  /// Opens a catalogue screen, or redirects the user to the playlist manager
  /// when no playlist has been configured yet.
  void _open(Widget screen) {
    final hasPlaylist = context.read<PlaylistBloc>().state.active != null;
    final Widget destination = !hasPlaylist &&
            screen is! PlaylistScreen &&
            screen is! SettingsScreen
        ? const PlaylistScreen()
        : screen;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();
    final settings = context.watch<SettingsBloc>().state;
    final theme = settings.theme;
    final features = config.features;

    return Scaffold(
      body: AppBackground(
        image: theme.background,
        child: Column(
          children: [
            AppTitleBar(
              title: '${config.branding.windowTitle}  v$_version',
              logo: config.branding.logoSmall,
            ),
            Expanded(
              child: BlocBuilder<PlaylistBloc, PlaylistState>(
                builder: (context, state) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: Row(
                          children: [
                            const LiveClock(),
                            const Spacer(),
                            StatusPill(
                              label: 'Current Playlist Expired On:',
                              value: state.auth?.expiryDateTime != null
                                  ? formatDate(state.auth!.expiryDateTime!)
                                  : '—',
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 120,
                                  child: Image.asset(
                                    config.branding.logo,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.play_circle_outline,
                                      size: 92,
                                      color: AppColors.gold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  state.active?.name ?? settings.l10n.t('no_playlist'),
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 40),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 18,
                                  runSpacing: 18,
                                  children: [
                                    if (features.live)
                                      NavTile(
                                        label: settings.l10n.t('live_tv'),
                                        icon: Icons.live_tv,
                                        onTap: () => _open(const LiveScreen()),
                                      ),
                                    if (features.movies)
                                      NavTile(
                                        label: settings.l10n.t('movies'),
                                        icon: Icons.movie_creation_outlined,
                                        onTap: () => _open(const MoviesScreen()),
                                      ),
                                    if (features.series)
                                      NavTile(
                                        label: settings.l10n.t('series'),
                                        icon: Icons.video_library_outlined,
                                        onTap: () => _open(const SeriesScreen()),
                                      ),
                                    if (features.replay)
                                      NavTile(
                                        label: settings.l10n.t('replay'),
                                        icon: Icons.history,
                                        onTap: () => _open(const ReplayScreen()),
                                      ),
                                    if (features.changePlaylist)
                                      NavTile(
                                        label: settings.l10n.t('change_playlist'),
                                        icon: Icons.playlist_play,
                                        onTap: () => _open(const PlaylistScreen()),
                                      ),
                                    if (features.search)
                                      NavTile(
                                        label: settings.l10n.t('search'),
                                        icon: Icons.search,
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => const SearchScreen()),
                                        ),
                                      ),
                                    if (features.settings)
                                      NavTile(
                                        label: settings.l10n.t('settings'),
                                        icon: Icons.settings,
                                        onTap: () => _open(const SettingsScreen()),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (state.syncing)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                            value: state.syncProgress == 0 ? null : state.syncProgress,
                            minHeight: 3,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          config.branding.noSellNotice,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
