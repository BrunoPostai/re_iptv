import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/content_bloc.dart';
import '../../blocs/playlist_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/platform/window_class.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';
import '../../widgets/category_sidebar.dart';
import '../../widgets/common.dart';
import '../../widgets/media_grid.dart';
import '../../widgets/search_field.dart';
import '../../widgets/title_bar.dart';
import '../movies/movie_detail_screen.dart';
import '../series/series_detail_screen.dart';

/// Shared catalogue browser used by the Movies and Series screens:
/// category sidebar, search, sort and a poster grid.
class ContentBrowserScreen extends StatelessWidget {
  const ContentBrowserScreen({super.key, required this.kind, required this.heading});

  final ContentKind kind;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsBloc>().state;

    return BlocProvider<ContentBloc>(
      create: (_) => ContentBloc(
        getIt<ContentRepository>(),
        getIt<PlaylistRepository>(),
      )..add(ContentStarted(kind, sortType: settings.sortType)),
      child: _BrowserBody(kind: kind, heading: heading),
    );
  }
}

class _BrowserBody extends StatefulWidget {
  const _BrowserBody({required this.kind, required this.heading});

  final ContentKind kind;
  final String heading;

  @override
  State<_BrowserBody> createState() => _BrowserBodyState();
}

class _BrowserBodyState extends State<_BrowserBody> {
  /// Opens the category drawer, which only exists when there is no room for a
  /// sidebar.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _openMovie(BuildContext context, Movie movie) async {
    final bloc = context.read<ContentBloc>();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
    );
    bloc.add(const ContentWatchStateReloaded());
  }

  Future<void> _openSeries(BuildContext context, Series series) async {
    final bloc = context.read<ContentBloc>();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)),
    );
    bloc.add(const ContentWatchStateReloaded());
  }

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();
    final settings = context.watch<SettingsBloc>().state;
    final compact = WindowClass.of(context).isCompact;

    // A phone has no room for a 250 pixel category sidebar beside a poster
    // grid — what is left is one column of posters 160 wide. There the
    // categories become a drawer, as they already do on Live and Catch Up, and
    // the grid takes the whole width.
    return BlocBuilder<ContentBloc, ContentState>(
      builder: (context, state) => Scaffold(
        key: _scaffoldKey,
        drawer: compact ? _categoryDrawer(state, settings.isHidden) : null,
        body: AppBackground(
          image: settings.theme.background,
          child: Column(
            children: [
              AppTitleBar(
                title: config.branding.windowTitle,
                logo: settings.theme.logoSmallFor(config.branding),
                onBack: () => Navigator.of(context).maybePop(),
                actions: [
                  if (compact)
                    IconButton(
                      tooltip: 'Categories',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(
                        Icons.format_list_bulleted,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                    ),
                ],
              ),
              ScreenHeader(
                heading: BlocBuilder<PlaylistBloc, PlaylistState>(
                  builder: (context, playlistState) => ScreenHeading(
                    title: widget.heading,
                    subtitle: playlistState.active?.name,
                  ),
                ),
                search: SearchField(
                  width: compact ? null : 250,
                  hint: settings.l10n.t('search_hint'),
                  onChanged: (value) =>
                      context.read<ContentBloc>().add(ContentQueryChanged(value)),
                ),
                controls: [
                  BlocBuilder<ContentBloc, ContentState>(
                    builder: (context, state) => SortDropdown(
                      value: state.sortType,
                      onChanged: (value) {
                        context.read<ContentBloc>().add(ContentSortChanged(value));
                        context.read<SettingsBloc>().add(SortTypeChanged(value));
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reload from server',
                    onPressed: () => context.read<ContentBloc>().add(const ContentRefreshed()),
                    icon: const Icon(Icons.refresh, color: AppColors.textMuted, size: 20),
                  ),
                ],
              ),
              Expanded(
                child: compact
                    ? _buildContent(context, state)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CategorySidebar(
                            rows: state.rows,
                            selectedId: state.selectedCategoryId,
                            onSelected: (id) =>
                                context.read<ContentBloc>().add(ContentCategorySelected(id)),
                            isHidden: (id) => settings.isHidden(id),
                          ),
                          Expanded(child: _buildContent(context, state)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The category list, as a drawer, for screens too narrow to hold a sidebar.
  Widget _categoryDrawer(ContentState state, bool Function(String id) hidden) {
    // The sidebar's own colour is 80% opaque, which reads as glass beside a
    // list and as a poster grid showing through a drawer. The drawer gets a
    // solid floor for it to sit on.
    return Drawer(
      backgroundColor: const Color(0xFF04080F),
      child: SafeArea(
        child: Builder(
          builder: (drawerContext) => CategorySidebar(
            width: double.infinity,
            rows: state.rows,
            selectedId: state.selectedCategoryId,
            onSelected: (id) {
              Navigator.pop(drawerContext);
              context.read<ContentBloc>().add(ContentCategorySelected(id));
            },
            isHidden: hidden,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ContentState state) {
    if (state.loading && state.rows.isEmpty) {
      return const LoadingBlock(message: 'Loading catalogue...');
    }
    if (state.error != null && state.rows.isEmpty) {
      return ErrorBlock(
        message: state.error!,
        onRetry: () => context.read<ContentBloc>().add(const ContentRefreshed()),
      );
    }

    if (widget.kind == ContentKind.movie) {
      if (state.movies.isEmpty) {
        return const EmptyBlock(message: 'No movies in this category.', icon: Icons.movie_outlined);
      }
      return MediaGrid(
        children: [
          for (final movie in state.movies)
            PosterCard(
              title: movie.name,
              image: movie.icon,
              subtitle: movie.releaseDate,
              rating: movie.rating5Based,
              favorite: state.favorites.contains('${movie.streamId}'),
              onToggleFavorite: () =>
                  context.read<ContentBloc>().add(ContentFavoriteToggled(movie.streamId)),
              progress: _progressOf(state, (p) => p.id == '${movie.streamId}'),
              watched: state.watched.contains('${movie.streamId}'),
              onTap: () => _openMovie(context, movie),
            ),
        ],
      );
    }

    if (state.series.isEmpty) {
      return const EmptyBlock(message: 'No series in this category.', icon: Icons.video_library_outlined);
    }
    return MediaGrid(
      children: [
        for (final series in state.series)
          PosterCard(
            title: series.name,
            image: series.cover,
            subtitle: series.releaseDate,
            rating: series.rating5Based,
            favorite: state.favorites.contains('${series.seriesId}'),
            onToggleFavorite: () =>
                context.read<ContentBloc>().add(ContentFavoriteToggled(series.seriesId)),
            progress: _progressOf(state, (p) => p.parentId == series.seriesId),
            watched: state.watched.contains('${series.seriesId}'),
            onTap: () => _openSeries(context, series),
          ),
      ],
    );
  }

  static double? _progressOf(ContentState state, bool Function(WatchProgress) test) {
    for (final progress in state.progress) {
      if (test(progress)) return progress.percent;
    }
    return null;
  }
}
