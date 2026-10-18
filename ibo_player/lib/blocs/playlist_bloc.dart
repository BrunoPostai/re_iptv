import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';

class PlaylistState extends Equatable {
  final List<Playlist> playlists;
  final Playlist? active;
  final bool loading;
  final bool syncing;
  final String syncStage;
  final double syncProgress;
  final String? error;
  final PlaylistAuth? auth;

  /// `true` once the stored playlists have been read from disk. Used by the
  /// splash screen to know when it may hand over to the home screen.
  final bool ready;

  const PlaylistState({
    this.playlists = const [],
    this.active,
    this.loading = false,
    this.syncing = false,
    this.syncStage = '',
    this.syncProgress = 0,
    this.error,
    this.auth,
    this.ready = false,
  });

  PlaylistState copyWith({
    List<Playlist>? playlists,
    Playlist? active,
    bool? loading,
    bool? syncing,
    String? syncStage,
    double? syncProgress,
    String? error,
    PlaylistAuth? auth,
    bool? ready,
    bool clearError = false,
    bool clearAuth = false,
  }) =>
      PlaylistState(
        playlists: playlists ?? this.playlists,
        active: active ?? this.active,
        loading: loading ?? this.loading,
        syncing: syncing ?? this.syncing,
        syncStage: syncStage ?? this.syncStage,
        syncProgress: syncProgress ?? this.syncProgress,
        error: clearError ? null : (error ?? this.error),
        auth: clearAuth ? null : (auth ?? this.auth),
        ready: ready ?? this.ready,
      );

  @override
  List<Object?> get props =>
      [playlists, active, loading, syncing, syncStage, syncProgress, error, auth, ready];
}

abstract class PlaylistEvent extends Equatable {
  const PlaylistEvent();
  @override
  List<Object?> get props => [];
}

class PlaylistsStarted extends PlaylistEvent {
  const PlaylistsStarted();
}

class PlaylistSelected extends PlaylistEvent {
  const PlaylistSelected(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class PlaylistAddedEvent extends PlaylistEvent {
  const PlaylistAddedEvent(this.playlist);
  final Playlist playlist;
  @override
  List<Object?> get props => [playlist];
}

class PlaylistRemovedEvent extends PlaylistEvent {
  const PlaylistRemovedEvent(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class PlaylistsSynced extends PlaylistEvent {
  const PlaylistsSynced({this.force = false});
  final bool force;
  @override
  List<Object?> get props => [force];
}

class PlaylistSyncProgress extends PlaylistEvent {
  const PlaylistSyncProgress(this.stage, this.progress);
  final String stage;
  final double progress;
  @override
  List<Object?> get props => [stage, progress];
}

class PlaylistBloc extends Bloc<PlaylistEvent, PlaylistState> {
  PlaylistBloc(this._playlists, this._content) : super(const PlaylistState()) {
    on<PlaylistsStarted>(_onStarted);
    on<PlaylistSelected>(_onSelected);
    on<PlaylistAddedEvent>(_onAdded);
    on<PlaylistRemovedEvent>(_onRemoved);
    on<PlaylistsSynced>(_onSynced);
    on<PlaylistSyncProgress>(_onProgress);
  }

  final PlaylistRepository _playlists;
  final ContentRepository _content;

  Future<void> _onStarted(PlaylistsStarted event, Emitter<PlaylistState> emit) async {
    emit(state.copyWith(loading: true, clearError: true));
    await _playlists.ensureDemoPlaylist();
    final list = _playlists.playlists;
    final active = _playlists.active;
    if (active != null) {
      await _playlists.setActive(active.id);
    }
    emit(state.copyWith(playlists: list, active: active, loading: false, ready: true));
    if (active != null) {
      add(const PlaylistsSynced());
    }
  }

  Future<void> _onSelected(PlaylistSelected event, Emitter<PlaylistState> emit) async {
    final playlist = state.playlists.firstWhere((p) => p.id == event.id);
    await _playlists.setActive(playlist.id);
    emit(state.copyWith(active: playlist, clearError: true, clearAuth: true));
    add(const PlaylistsSynced());
  }

  Future<void> _onAdded(PlaylistAddedEvent event, Emitter<PlaylistState> emit) async {
    await _playlists.add(event.playlist);
    emit(state.copyWith(
      playlists: _playlists.playlists,
      active: event.playlist,
      clearError: true,
      clearAuth: true,
    ));
    add(const PlaylistsSynced());
  }

  Future<void> _onRemoved(PlaylistRemovedEvent event, Emitter<PlaylistState> emit) async {
    await _playlists.remove(event.id);
    emit(state.copyWith(playlists: _playlists.playlists, active: _playlists.active));
  }

  Future<void> _onSynced(PlaylistsSynced event, Emitter<PlaylistState> emit) async {
    final playlist = state.active;
    if (playlist == null) return;
    emit(state.copyWith(syncing: true, clearError: true, syncStage: 'connecting', syncProgress: 0));
    try {
      final auth = await _playlists.sourceFor(playlist).authenticate();
      emit(state.copyWith(auth: auth));
      await _content.sync(
        playlist,
        onProgress: (stage, progress) => add(PlaylistSyncProgress(stage, progress)),
      );
      emit(state.copyWith(syncing: false, syncStage: 'ready', syncProgress: 1));
    } catch (error) {
      emit(state.copyWith(syncing: false, error: error.toString(), syncStage: 'failed'));
    }
  }

  Future<void> _onProgress(PlaylistSyncProgress event, Emitter<PlaylistState> emit) async {
    emit(state.copyWith(syncStage: event.stage, syncProgress: event.progress));
  }
}
