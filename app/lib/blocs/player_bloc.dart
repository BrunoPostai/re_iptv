import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models/models.dart';

class PlayerState extends Equatable {
  final MediaItem? item;
  final bool playing;
  final bool buffering;
  final bool completed;
  final Duration position;
  final Duration duration;
  final double volume;
  final int subtitleSize;
  final bool controlsVisible;
  final String? error;
  final Tracks tracks;
  final SubtitleTrack? subtitleTrack;
  final AudioTrack? audioTrack;
  final bool isLive;

  const PlayerState({
    this.item,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.subtitleSize = 20,
    this.controlsVisible = true,
    this.error,
    this.tracks = const Tracks(),
    this.subtitleTrack,
    this.audioTrack,
    this.isLive = false,
  });

  double get progress =>
      duration.inMilliseconds == 0 ? 0 : position.inMilliseconds / duration.inMilliseconds;

  PlayerState copyWith({
    MediaItem? item,
    bool? playing,
    bool? buffering,
    bool? completed,
    Duration? position,
    Duration? duration,
    double? volume,
    int? subtitleSize,
    bool? controlsVisible,
    String? error,
    bool clearError = false,
    Tracks? tracks,
    SubtitleTrack? subtitleTrack,
    AudioTrack? audioTrack,
    bool? isLive,
  }) =>
      PlayerState(
        item: item ?? this.item,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        completed: completed ?? this.completed,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        subtitleSize: subtitleSize ?? this.subtitleSize,
        controlsVisible: controlsVisible ?? this.controlsVisible,
        error: clearError ? null : (error ?? this.error),
        tracks: tracks ?? this.tracks,
        subtitleTrack: subtitleTrack ?? this.subtitleTrack,
        audioTrack: audioTrack ?? this.audioTrack,
        isLive: isLive ?? this.isLive,
      );

  @override
  List<Object?> get props => [
        item,
        playing,
        buffering,
        completed,
        position,
        duration,
        volume,
        subtitleSize,
        controlsVisible,
        error,
        tracks,
        subtitleTrack,
        audioTrack,
        isLive,
      ];
}

abstract class PlayerEvent extends Equatable {
  const PlayerEvent();
  @override
  List<Object?> get props => [];
}

class PlayerOpened extends PlayerEvent {
  const PlayerOpened(this.item, {this.startAt = Duration.zero});
  final MediaItem item;
  final Duration startAt;
  @override
  List<Object?> get props => [item, startAt];
}

class PlayerPlayPause extends PlayerEvent {
  const PlayerPlayPause();
}

class PlayerSeeked extends PlayerEvent {
  const PlayerSeeked(this.position);
  final Duration position;
  @override
  List<Object?> get props => [position];
}

class PlayerVolumeSet extends PlayerEvent {
  const PlayerVolumeSet(this.volume);
  final double volume;
  @override
  List<Object?> get props => [volume];
}

class PlayerSubtitleSizeSet extends PlayerEvent {
  const PlayerSubtitleSizeSet(this.size);
  final int size;
  @override
  List<Object?> get props => [size];
}

class PlayerControlsToggled extends PlayerEvent {
  const PlayerControlsToggled();
}

class PlayerSubtitleSelected extends PlayerEvent {
  const PlayerSubtitleSelected(this.track);
  final SubtitleTrack track;
  @override
  List<Object?> get props => [track];
}

class PlayerAudioSelected extends PlayerEvent {
  const PlayerAudioSelected(this.track);
  final AudioTrack track;
  @override
  List<Object?> get props => [track];
}

class PlayerStopped extends PlayerEvent {
  const PlayerStopped();
}

/// Wraps `media_kit` (libmpv) playback.
class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  /// [volume] is applied to every stream this bloc opens; opening live channels
  /// at libmpv's default of 100% is unpleasant, so callers pass a lower value.
  PlayerBloc(int subtitleSize, {double volume = 20, String title = 'REIPTV'})
      : _initialVolume = _clampVolume(volume),
        _title = title,
        super(PlayerState(subtitleSize: subtitleSize, volume: _clampVolume(volume))) {
    player = Player(
      configuration: PlayerConfiguration(
        title: _title,
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    on<PlayerOpened>(_onOpened);
    on<PlayerPlayPause>(_onPlayPause);
    on<PlayerSeeked>(_onSeeked);
    on<PlayerVolumeSet>(_onVolume);
    on<PlayerSubtitleSizeSet>(_onSubtitleSize);
    on<PlayerControlsToggled>(_onControlsToggled);
    on<PlayerSubtitleSelected>(_onSubtitleSelected);
    on<PlayerAudioSelected>(_onAudioSelected);
    on<PlayerStopped>(_onStopped);
    on<_Emit>((event, emit) => emit(event.state));

    _subscriptions.addAll([
      player.stream.playing.listen((v) => add(_Emit(state.copyWith(playing: v)))),
      player.stream.buffering.listen((v) => add(_Emit(state.copyWith(buffering: v)))),
      player.stream.completed.listen((v) => add(_Emit(state.copyWith(completed: v)))),
      player.stream.position.listen((v) => add(_Emit(state.copyWith(position: v)))),
      player.stream.duration.listen((v) => add(_Emit(state.copyWith(duration: v)))),
      player.stream.volume.listen((v) => add(_Emit(state.copyWith(volume: v)))),
      player.stream.tracks.listen((v) => add(_Emit(state.copyWith(tracks: v)))),
      player.stream.track.listen((v) => add(_Emit(state.copyWith(
            subtitleTrack: v.subtitle,
            audioTrack: v.audio,
          )))),
      player.stream.error.listen((v) => add(_Emit(state.copyWith(error: v)))),
    ]);
  }

  /// Volume every stream opens at, and the media title reported to libmpv.
  final double _initialVolume;
  final String _title;

  late final Player player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  VideoController get controller => _controller ??= VideoController(player);
  VideoController? _controller;

  static double _clampVolume(double value) => value.clamp(0, 100).toDouble();

  Future<void> _onOpened(PlayerOpened event, Emitter<PlayerState> emit) async {
    emit(state.copyWith(
      item: event.item,
      isLive: event.item.isLive,
      error: null,
      clearError: true,
      controlsVisible: true,
      completed: false,
      volume: _initialVolume,
    ));
    // Open at the configured volume instead of libmpv's default of 100%.
    await player.setVolume(_initialVolume);
    await player.open(Media(event.item.url), play: true);
    if (event.startAt > Duration.zero) {
      await player.seek(event.startAt);
    }
  }

  Future<void> _onPlayPause(PlayerPlayPause event, Emitter<PlayerState> emit) async {
    await player.playOrPause();
  }

  Future<void> _onSeeked(PlayerSeeked event, Emitter<PlayerState> emit) async {
    await player.seek(event.position);
  }

  Future<void> _onVolume(PlayerVolumeSet event, Emitter<PlayerState> emit) async {
    await player.setVolume(event.volume);
  }

  Future<void> _onSubtitleSize(PlayerSubtitleSizeSet event, Emitter<PlayerState> emit) async {
    emit(state.copyWith(subtitleSize: event.size));
  }

  Future<void> _onControlsToggled(PlayerControlsToggled event, Emitter<PlayerState> emit) async {
    emit(state.copyWith(controlsVisible: !state.controlsVisible));
  }

  Future<void> _onSubtitleSelected(
      PlayerSubtitleSelected event, Emitter<PlayerState> emit) async {
    await player.setSubtitleTrack(event.track);
  }

  Future<void> _onAudioSelected(PlayerAudioSelected event, Emitter<PlayerState> emit) async {
    await player.setAudioTrack(event.track);
  }

  Future<void> _onStopped(PlayerStopped event, Emitter<PlayerState> emit) async {
    await player.stop();
    emit(const PlayerState());
  }

  @override
  Future<void> close() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await player.dispose();
    return super.close();
  }
}

class _Emit extends PlayerEvent {
  const _Emit(this.state);
  final PlayerState state;
  @override
  List<Object?> get props => [state];
}
