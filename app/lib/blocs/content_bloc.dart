import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';

/// A row in the category sidebar (may be a synthetic row such as "ALL").
class CategoryRow extends Equatable {
  final String id;
  final String name;
  final int count;
  final bool pseudo;

  const CategoryRow({
    required this.id,
    required this.name,
    required this.count,
    this.pseudo = false,
  });

  @override
  List<Object?> get props => [id, name, count, pseudo];
}

class ContentState extends Equatable {
  final ContentKind kind;
  final bool loading;
  final String? error;
  final List<CategoryRow> rows;
  final List<Channel> channels;
  final List<Movie> movies;
  final List<Series> series;
  final List<WatchProgress> progress;
  final String selectedCategoryId;
  final String query;
  final String sortType;
  final Set<String> favorites;

  const ContentState({
    required this.kind,
    this.loading = false,
    this.error,
    this.rows = const [],
    this.channels = const [],
    this.movies = const [],
    this.series = const [],
    this.progress = const [],
    this.selectedCategoryId = allCategoryId,
    this.query = '',
    this.sortType = 'default',
    this.favorites = const {},
  });

  static const continueCategoryId = '_continue';
  static const favoritesCategoryId = '_favorites';
  static const allCategoryId = '_all';

  bool get isEmpty =>
      !loading && channels.isEmpty && movies.isEmpty && series.isEmpty;

  ContentState copyWith({
    ContentKind? kind,
    bool? loading,
    String? error,
    bool clearError = false,
    List<CategoryRow>? rows,
    List<Channel>? channels,
    List<Movie>? movies,
    List<Series>? series,
    List<WatchProgress>? progress,
    String? selectedCategoryId,
    String? query,
    String? sortType,
    Set<String>? favorites,
  }) =>
      ContentState(
        kind: kind ?? this.kind,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        rows: rows ?? this.rows,
        channels: channels ?? this.channels,
        movies: movies ?? this.movies,
        series: series ?? this.series,
        progress: progress ?? this.progress,
        selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
        query: query ?? this.query,
        sortType: sortType ?? this.sortType,
        favorites: favorites ?? this.favorites,
      );

  @override
  List<Object?> get props => [
        kind,
        loading,
        error,
        rows,
        channels,
        movies,
        series,
        progress,
        selectedCategoryId,
        query,
        sortType,
        favorites,
      ];
}

abstract class ContentEvent extends Equatable {
  const ContentEvent();
  @override
  List<Object?> get props => [];
}

class ContentStarted extends ContentEvent {
  const ContentStarted(this.kind, {this.sortType = 'default'});
  final ContentKind kind;
  final String sortType;
  @override
  List<Object?> get props => [kind, sortType];
}

class ContentCategorySelected extends ContentEvent {
  const ContentCategorySelected(this.categoryId);
  final String categoryId;
  @override
  List<Object?> get props => [categoryId];
}

class ContentQueryChanged extends ContentEvent {
  const ContentQueryChanged(this.query);
  final String query;
  @override
  List<Object?> get props => [query];
}

class ContentSortChanged extends ContentEvent {
  const ContentSortChanged(this.sortType);
  final String sortType;
  @override
  List<Object?> get props => [sortType];
}

class ContentFavoriteToggled extends ContentEvent {
  const ContentFavoriteToggled(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

class ContentRefreshed extends ContentEvent {
  const ContentRefreshed();
}

/// Re-reads the cached catalogue (e.g. after returning from the player) while
/// keeping the current category selection and query.
class ContentReloaded extends ContentEvent {
  const ContentReloaded();
}

/// Refreshes only the watch-state lists — favourites and continue-watching —
/// without re-reading and re-decoding the whole catalogue.
///
/// Returning from the player only changes watch state, but [ContentReloaded]
/// also re-parses every channel/movie/series, which freezes the UI for a moment
/// on large playlists.
class ContentWatchStateReloaded extends ContentEvent {
  const ContentWatchStateReloaded();
}

class ContentProgressSaved extends ContentEvent {
  const ContentProgressSaved(this.progress);
  final WatchProgress progress;
  @override
  List<Object?> get props => [progress];
}

class ContentBloc extends Bloc<ContentEvent, ContentState> {
  ContentBloc(this._content, this._playlists) : super(const ContentState(kind: ContentKind.live)) {
    on<ContentStarted>(_onStarted);
    on<ContentCategorySelected>(_onSelected);
    on<ContentQueryChanged>(_onQueryChanged);
    on<ContentSortChanged>(_onSortChanged);
    on<ContentFavoriteToggled>(_onFavoriteToggled);
    on<ContentRefreshed>(_onRefreshed);
    on<ContentReloaded>(_onReloaded);
    on<ContentWatchStateReloaded>(_onWatchStateReloaded);
    on<ContentProgressSaved>(_onProgressSaved);
  }

  final ContentRepository _content;
  final PlaylistRepository _playlists;

  List<Category> _categories = const [];
  List<Channel> _allChannels = const [];
  List<Movie> _allMovies = const [];
  List<Series> _allSeries = const [];
  List<String> _favoriteIds = const [];

  Playlist? get _active => _playlists.active;

  Future<void> _load(ContentKind kind, Emitter<ContentState> emit) async {
    final playlist = _active;
    if (playlist == null) {
      emit(state.copyWith(kind: kind, loading: false, rows: const [], channels: const [], movies: const [], series: const []));
      return;
    }
    emit(state.copyWith(kind: kind, loading: true, clearError: true));
    try {
      _categories = await _content.categories(playlist, kind);
      _allChannels = kind == ContentKind.live ? await _content.channels(playlist) : const [];
      _allMovies = kind == ContentKind.movie ? await _content.movies(playlist) : const [];
      _allSeries = kind == ContentKind.series ? await _content.series(playlist) : const [];
      _favoriteIds = await _content.favorites(playlist, kind);
      final progress = kind == ContentKind.live
          ? const <WatchProgress>[]
          : await _content.continueWatching(playlist, kind);
      emit(state.copyWith(progress: progress, favorites: _favoriteIds.toSet()));
      _emitFiltered(emit, loading: false);
    } catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

  void _emitFiltered(Emitter<ContentState> emit, {bool? loading}) {
    final query = state.query.trim().toLowerCase();
    final selected = state.selectedCategoryId;

    List<T> filter<T>(List<T> source, String Function(T) id, String Function(T) name) {
      if (query.isNotEmpty) {
        return source.where((e) => name(e).toLowerCase().contains(query)).toList();
      }
      switch (selected) {
        case ContentState.allCategoryId:
          return source.toList();
        case ContentState.favoritesCategoryId:
          return source.where((e) => _favoriteIds.contains(id(e))).toList();
        case ContentState.continueCategoryId:
          return source.where((e) => state.progress.any((p) => p.id == id(e))).toList();
        default:
          return source.where((e) => id(e) == selected).toList();
      }
    }

    void sortBy<T>(List<T> list, String Function(T) name, String Function(T) added, double Function(T) rating) {
      switch (state.sortType) {
        case 'a-z':
          list.sort((a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()));
          break;
        case 'z-a':
          list.sort((a, b) => name(b).toLowerCase().compareTo(name(a).toLowerCase()));
          break;
        case 'added':
          list.sort((a, b) => added(b).compareTo(added(a)));
          break;
        case 'rating':
          list.sort((a, b) => rating(b).compareTo(rating(a)));
          break;
      }
    }

    final channels = filter<Channel>(_allChannels, (c) => c.categoryId, (c) => c.name);
    final movies = filter<Movie>(_allMovies, (m) => m.categoryId, (m) => m.name);
    final series = filter<Series>(_allSeries, (s) => s.categoryId, (s) => s.name);
    sortBy(movies, (m) => m.name, (m) => m.added, (m) => m.rating5Based);
    sortBy(series, (s) => s.name, (s) => s.lastModified, (s) => s.rating5Based);

    int countFor(String categoryId) => switch (categoryId) {
          ContentState.allCategoryId => switch (state.kind) {
              ContentKind.live => _allChannels.length,
              ContentKind.movie => _allMovies.length,
              ContentKind.series => _allSeries.length,
            },
          ContentState.favoritesCategoryId => _favoriteIds.length,
          ContentState.continueCategoryId => state.progress.length,
          _ => switch (state.kind) {
              ContentKind.live => _allChannels.where((c) => c.categoryId == categoryId).length,
              ContentKind.movie => _allMovies.where((m) => m.categoryId == categoryId).length,
              ContentKind.series => _allSeries.where((s) => s.categoryId == categoryId).length,
            },
        };

    final rows = <CategoryRow>[
      CategoryRow(
        id: ContentState.continueCategoryId,
        name: state.kind == ContentKind.live ? 'Recently Viewed' : 'Continue Watching',
        count: countFor(ContentState.continueCategoryId),
        pseudo: true,
      ),
      CategoryRow(
        id: ContentState.favoritesCategoryId,
        name: 'Favorites',
        count: countFor(ContentState.favoritesCategoryId),
        pseudo: true,
      ),
      CategoryRow(
        id: ContentState.allCategoryId,
        name: 'ALL',
        count: countFor(ContentState.allCategoryId),
        pseudo: true,
      ),
      for (final c in _categories)
        CategoryRow(id: c.id, name: c.name, count: countFor(c.id)),
    ];

    emit(state.copyWith(
      rows: rows,
      channels: channels,
      movies: movies,
      series: series,
      loading: loading ?? false,
    ));
  }

  Future<void> _onStarted(ContentStarted event, Emitter<ContentState> emit) async {
    emit(state.copyWith(
      kind: event.kind,
      query: '',
      selectedCategoryId: ContentState.allCategoryId,
      sortType: event.sortType,
    ));
    await _load(event.kind, emit);
  }

  Future<void> _onSelected(ContentCategorySelected event, Emitter<ContentState> emit) async {
    emit(state.copyWith(selectedCategoryId: event.categoryId, query: ''));
    _emitFiltered(emit);
  }

  Future<void> _onQueryChanged(ContentQueryChanged event, Emitter<ContentState> emit) async {
    emit(state.copyWith(query: event.query));
    _emitFiltered(emit);
  }

  Future<void> _onSortChanged(ContentSortChanged event, Emitter<ContentState> emit) async {
    emit(state.copyWith(sortType: event.sortType));
    _emitFiltered(emit);
  }

  Future<void> _onFavoriteToggled(ContentFavoriteToggled event, Emitter<ContentState> emit) async {
    final playlist = _active;
    if (playlist == null) return;
    await _content.toggleFavorite(playlist, state.kind, event.id);
    _favoriteIds = await _content.favorites(playlist, state.kind);
    emit(state.copyWith(favorites: _favoriteIds.toSet()));
    _emitFiltered(emit);
  }

  Future<void> _onRefreshed(ContentRefreshed event, Emitter<ContentState> emit) async {
    final playlist = _active;
    if (playlist == null) return;
    await _content.sync(playlist);
    await _load(state.kind, emit);
  }

  Future<void> _onReloaded(ContentReloaded event, Emitter<ContentState> emit) async {
    await _load(state.kind, emit);
  }

  /// Picks up favourites/continue-watching changes without touching the
  /// catalogue loaded in memory.
  Future<void> _onWatchStateReloaded(
      ContentWatchStateReloaded event, Emitter<ContentState> emit) async {
    final playlist = _active;
    if (playlist == null) return;
    _favoriteIds = await _content.favorites(playlist, state.kind);
    final progress = state.kind == ContentKind.live
        ? const <WatchProgress>[]
        : await _content.continueWatching(playlist, state.kind);
    emit(state.copyWith(favorites: _favoriteIds.toSet(), progress: progress));
    _emitFiltered(emit);
  }

  Future<void> _onProgressSaved(ContentProgressSaved event, Emitter<ContentState> emit) async {
    final playlist = _active;
    if (playlist == null) return;
    await _content.saveProgress(playlist, event.progress);
    final progress = await _content.continueWatching(playlist, state.kind);
    emit(state.copyWith(progress: progress));
    _emitFiltered(emit);
  }
}
