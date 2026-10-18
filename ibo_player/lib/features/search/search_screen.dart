import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/media_grid.dart';
import '../../widgets/search_field.dart';
import '../../widgets/title_bar.dart';
import '../movies/movie_detail_screen.dart';
import '../player/player_screen.dart';
import '../series/series_detail_screen.dart';

/// Global search across live channels, movies and series.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  Timer? _debounce;
  String _query = '';
  bool _loading = false;

  List<Channel> _channels = const [];
  List<Movie> _movies = const [];
  List<Series> _series = const [];

  Playlist? get _playlist => getIt<PlaylistRepository>().active;

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _search);
  }

  Future<void> _search() async {
    final playlist = _playlist;
    final query = _query.trim();
    if (playlist == null) return;
    if (query.length < 2) {
      setState(() {
        _channels = const [];
        _movies = const [];
        _series = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final content = getIt<ContentRepository>();
    final results = await Future.wait([
      content.searchChannels(playlist, query),
      content.searchMovies(playlist, query),
      content.searchSeries(playlist, query),
    ]);
    if (!mounted) return;
    setState(() {
      _channels = results[0] as List<Channel>;
      _movies = results[1] as List<Movie>;
      _series = results[2] as List<Series>;
      _loading = false;
    });
  }

  Future<void> _playChannel(Channel channel) async {
    final playlist = _playlist;
    if (playlist == null) return;
    final url = getIt<PlaylistRepository>().sourceFor(playlist).liveUrl(channel);
    if (url.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: MediaItem(
            title: channel.name,
            image: channel.icon,
            url: url,
            isLive: true,
            streamId: channel.streamId,
            kind: 'live',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();
    final settings = context.watch<SettingsBloc>().state;

    return Scaffold(
      body: AppBackground(
        image: settings.theme.background,
        child: Column(
          children: [
            AppTitleBar(
              title: config.branding.windowTitle,
              logo: config.branding.logoSmall,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  Expanded(child: ScreenHeading(title: settings.l10n.t('search'))),
                  SearchField(
                    width: 420,
                    hint: settings.l10n.t('search_hint'),
                    onChanged: _onQuery,
                    onSubmitted: (_) => _search(),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.divider),
              ),
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                indicatorColor: AppColors.gold,
                labelColor: AppColors.gold,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(text: '${settings.l10n.t('live_tv')} (${_channels.length})'),
                  Tab(text: '${settings.l10n.t('movies')} (${_movies.length})'),
                  Tab(text: '${settings.l10n.t('series')} (${_series.length})'),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const LoadingBlock(message: 'Searching...')
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _channelResults(),
                        _movieResults(),
                        _seriesResults(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelResults() {
    if (_channels.isEmpty) {
      return const EmptyBlock(message: 'No matching channels.', icon: Icons.search_off);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _channels.length,
      itemBuilder: (context, index) {
        final channel = _channels[index];
        return ChannelRow(
          name: channel.name,
          image: channel.icon,
          number: channel.num == 0 ? index + 1 : channel.num,
          onTap: () => _playChannel(channel),
        );
      },
    );
  }

  Widget _movieResults() {
    if (_movies.isEmpty) {
      return const EmptyBlock(message: 'No matching movies.', icon: Icons.search_off);
    }
    return MediaGrid(
      children: [
        for (final movie in _movies)
          PosterCard(
            title: movie.name,
            image: movie.icon,
            rating: movie.rating5Based,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
            ),
          ),
      ],
    );
  }

  Widget _seriesResults() {
    if (_series.isEmpty) {
      return const EmptyBlock(message: 'No matching series.', icon: Icons.search_off);
    }
    return MediaGrid(
      children: [
        for (final series in _series)
          PosterCard(
            title: series.name,
            image: series.cover,
            rating: series.rating5Based,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)),
            ),
          ),
      ],
    );
  }
}