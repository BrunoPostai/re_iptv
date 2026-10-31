import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/constants.dart';
import '../../core/di/injector.dart';
import '../../core/platform/window_class.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';
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

  /// Favourites, watched ids and resume positions per kind, so a result carries
  /// the same marks as it does in the grids it came from.
  Map<ContentKind, Set<String>> _favorites = const {};
  Map<ContentKind, Set<String>> _watched = const {};
  Map<ContentKind, List<WatchProgress>> _progress = const {};

  Playlist? get _playlist => getIt<PlaylistRepository>().active;

  @override
  void initState() {
    super.initState();
    _loadWatchState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  /// Reads the watch state for all three kinds.
  ///
  /// Local store only, so it can run again the moment a film's page or a channel
  /// pops — which is what keeps a result from showing the state it had before it
  /// was played, the way the grids did.
  Future<void> _loadWatchState() async {
    final playlist = _playlist;
    if (playlist == null) return;
    final content = getIt<ContentRepository>();
    final favorites = <ContentKind, Set<String>>{};
    final watched = <ContentKind, Set<String>>{};
    final progress = <ContentKind, List<WatchProgress>>{};
    for (final kind in ContentKind.values) {
      favorites[kind] = (await content.favorites(playlist, kind)).toSet();
      watched[kind] = (await content.watched(playlist, kind)).toSet();
      progress[kind] = kind == ContentKind.live
          ? const <WatchProgress>[]
          : await content.continueWatching(playlist, kind);
    }
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _watched = watched;
      _progress = progress;
    });
  }

  bool _isFavorite(ContentKind kind, int id) => _favorites[kind]?.contains('$id') ?? false;

  bool _isWatched(ContentKind kind, int id) => _watched[kind]?.contains('$id') ?? false;

  double? _resumeOf(ContentKind kind, bool Function(WatchProgress) test) {
    for (final progress in _progress[kind] ?? const <WatchProgress>[]) {
      if (test(progress)) return progress.percent;
    }
    return null;
  }

  void _onQuery(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, _search);
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
    if (!mounted) return;
    await _loadWatchState();
  }

  Future<void> _openMovie(Movie movie) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
    );
    if (!mounted) return;
    await _loadWatchState();
  }

  Future<void> _openSeries(Series series) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)),
    );
    if (!mounted) return;
    await _loadWatchState();
  }

  /// Flips a favourite from the results themselves.
  ///
  /// The map is updated in place rather than re-read, so the star fills in at
  /// once instead of after a round trip to the store.
  Future<void> _toggleFavorite(ContentKind kind, int id) async {
    final playlist = _playlist;
    if (playlist == null) return;
    final added = await getIt<ContentRepository>().toggleFavorite(playlist, kind, id);
    if (!mounted) return;
    setState(() {
      final favorites = Map<ContentKind, Set<String>>.of(_favorites);
      final ids = Set<String>.of(favorites[kind] ?? const <String>{});
      if (added) {
        ids.add('$id');
      } else {
        ids.remove('$id');
      }
      favorites[kind] = ids;
      _favorites = favorites;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final config = getIt<AppConfig>();
    final settings = context.watch<SettingsBloc>().state;

    return Scaffold(
      body: AppBackground(
        image: settings.theme.background,
        child: Column(
          children: [
            AppTitleBar(
              title: config.branding.windowTitle,
              logo: settings.theme.logoSmallFor(config.branding),
              onBack: () => Navigator.of(context).maybePop(),
            ),
            ScreenHeader(
              heading: ScreenHeading(title: settings.l10n.t('search')),
              search: SearchField(
                width: WindowClass.of(context).isCompact ? null : 420,
                hint: settings.l10n.t('search_hint'),
                onChanged: _onQuery,
                onSubmitted: (_) => _search(),
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
                indicatorColor: palette.accent,
                labelColor: palette.accent,
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
        final favorite = _isFavorite(ContentKind.live, channel.streamId);
        return ChannelRow(
          name: channel.name,
          image: channel.icon,
          number: channel.num == 0 ? index + 1 : channel.num,
          favorite: favorite,
          onToggleFavorite: () => _toggleFavorite(ContentKind.live, channel.streamId),
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
            favorite: _isFavorite(ContentKind.movie, movie.streamId),
            onToggleFavorite: () => _toggleFavorite(ContentKind.movie, movie.streamId),
            progress: _resumeOf(ContentKind.movie, (p) => p.id == '${movie.streamId}'),
            watched: _isWatched(ContentKind.movie, movie.streamId),
            onTap: () => _openMovie(movie),
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
            favorite: _isFavorite(ContentKind.series, series.seriesId),
            onToggleFavorite: () => _toggleFavorite(ContentKind.series, series.seriesId),
            progress: _resumeOf(ContentKind.series, (p) => p.parentId == series.seriesId),
            watched: _isWatched(ContentKind.series, series.seriesId),
            onTap: () => _openSeries(series),
          ),
      ],
    );
  }
}
