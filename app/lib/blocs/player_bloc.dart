import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

import '../core/config/app_config.dart';
import '../core/player/mpv_tuning.dart';
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
  const PlayerOpened(this.item, {this.startAt = Duration.zero, this.keepVolume = false});
  final MediaItem item;
  final Duration startAt;

  /// True when this bloc is switching between items on its own — the next
  /// episode — rather than opening a stream for a screen.
  ///
  /// The volume is then left where the viewer put it: re-applying the opening
  /// volume would both jump the sound and, since the player writes the volume it
  /// sees back to the settings, forget the volume they had chosen.
  final bool keepVolume;
  @override
  List<Object?> get props => [item, startAt, keepVolume];
}

class PlayerPlayPause extends PlayerEvent {
  const PlayerPlayPause();
}

/// Starts the item over.
///
/// At the end of a stream `play` alone does nothing: libmpv is sitting on its
/// last frame with no file position left to play from.
class PlayerReplayed extends PlayerEvent {
  const PlayerReplayed();
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
  ///
  /// [hardwareDecoding] and [liveTuning] come straight from `app_config.json`;
  /// see `core/player/mpv_tuning.dart` for what the tuning does.
  PlayerBloc(
    int subtitleSize, {
    double volume = 20,
    String title = 'REIPTV',
    bool hardwareDecoding = true,
    LiveTuning liveTuning = const LiveTuning(),
  })  : _initialVolume = _clampVolume(volume),
        _title = title,
        _hardwareDecoding = hardwareDecoding,
        _liveTuning = liveTuning,
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
    on<PlayerReplayed>(_onReplayed);
    on<PlayerSubtitleSizeSet>(_onSubtitleSize);
    on<PlayerControlsToggled>(_onControlsToggled);
    on<PlayerSubtitleSelected>(_onSubtitleSelected);
    on<PlayerAudioSelected>(_onAudioSelected);
    on<PlayerStopped>(_onStopped);
    on<_Emit>((event, emit) => emit(event.state));

    _subscriptions.addAll([
      player.stream.playing.listen((v) => add(_Emit(state.copyWith(playing: v)))),
      player.stream.buffering.listen((v) => add(_Emit(state.copyWith(buffering: v)))),
      player.stream.completed.listen((v) => add(_Emit(state.copyWith(
            completed: v,
            // mpv reporting "buffering" as it runs out of file is what left the
            // spinner turning for ever at the end of an episode.
            buffering: v ? false : null,
          )))),
      player.stream.position.listen((v) => add(_Emit(state.copyWith(position: v)))),
      player.stream.duration.listen((v) {
        add(_Emit(state.copyWith(duration: v)));
        _checkResume(v);
      }),
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
  final bool _hardwareDecoding;
  final LiveTuning _liveTuning;

  /// Where this stream was left off. Handed to libmpv as it opens, and kept for
  /// [_checkResume] in case the stream ignores it.
  Duration? _resumeAt;

  /// The one-shot check armed once the demuxer has reported a duration.
  Timer? _resumeCheck;

  late final Player player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// `media_kit_video` defaults `hwdec` to `auto`, and the config can turn it
  /// off for machines where hardware decoding misbehaves.
  VideoController get controller => _controller ??= VideoController(
        player,
        configuration: VideoControllerConfiguration(
          hwdec: _hardwareDecoding ? 'auto' : 'no',
        ),
      );
  VideoController? _controller;

  static double _clampVolume(double value) => value.clamp(0, 100).toDouble();

  Future<void> _onOpened(PlayerOpened event, Emitter<PlayerState> emit) async {
    emit(state.copyWith(
      item: event.item,
      isLive: event.item.isLive,
      // A reused player is still reporting the previous stream as playing until
      // libmpv catches up; clear it so the new stream starts from "loading".
      playing: false,
      error: null,
      clearError: true,
      controlsVisible: true,
      completed: false,
      // Switching between items inside the player keeps the volume the viewer
      // set; only a fresh screen arrives at the configured one.
      volume: event.keepVolume ? state.volume : _initialVolume,
    ));
    // Open at the configured volume instead of libmpv's default of 100%.
    if (!event.keepVolume) await player.setVolume(_initialVolume);
    // Stream options only apply to the connection made by open(), so they have
    // to be in place before it.
    if (event.item.isLive) {
      await applyLiveTuning(player, _liveTuning);
    }
    final resume = event.startAt > Duration.zero ? event.startAt : null;
    _resumeAt = resume;
    _resumeCheck?.cancel();
    _resumeCheck = null;
    await player.open(
      Media(
        event.item.url,
        // Handed to libmpv as part of opening the file, because mpv applies it
        // in its `on_load` hook, before it starts decoding. Seeking straight
        // after the open instead sends the command while the stream is still
        // being opened and mpv drops it: a resumed film started from the top.
        start: resume,
      ),
      play: true,
    );
  }

  Future<void> _onPlayPause(PlayerPlayPause event, Emitter<PlayerState> emit) async {
    await player.playOrPause();
  }

  Future<void> _onSeeked(PlayerSeeked event, Emitter<PlayerState> emit) async {
    // The viewer is driving, so whatever this stream was meant to resume to is
    // no longer wanted.
    _resumeAt = null;
    _resumeCheck?.cancel();
    _resumeCheck = null;
    await player.seek(event.position);
  }

  /// Nudges playback to the resume position if opening the stream did not.
  ///
  /// `Media.start` is applied by mpv's own `on_load` hook, which is how libmpv
  /// is meant to be told to open a stream part-way in — but it does not stick
  /// for every stream (the package has this open: `media_kit` #1215). So once
  /// the demuxer has reported a duration, and given [_resumeSettle] for the
  /// position stream to catch up, a stream still sitting near its beginning is
  /// seeked instead. Looked at once, and never after the viewer seeks.
  void _checkResume(Duration duration) {
    if (_resumeAt == null || duration <= Duration.zero || _resumeCheck != null) return;
    _resumeCheck = Timer(_resumeSettle, () {
      _resumeCheck = null;
      final resume = _resumeAt;
      if (resume == null) return;
      _resumeAt = null;
      if (state.position < resume - _resumeSlack) player.seek(resume);
    });
  }

  Future<void> _onVolume(PlayerVolumeSet event, Emitter<PlayerState> emit) async {
    await player.setVolume(event.volume);
  }

  Future<void> _onReplayed(PlayerReplayed event, Emitter<PlayerState> emit) async {
    emit(state.copyWith(completed: false, buffering: false));
    await player.seek(Duration.zero);
    await player.play();
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
    _resumeCheck?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await player.dispose();
    return super.close();
  }
}

/// How long playback is given to settle before checking whether it started
/// where it was asked to: the position stream needs a moment to report the
/// stream's real position.
const _resumeSettle = Duration(seconds: 2);

/// A stream that started this far before where it was asked to counts as having
/// started at the beginning. mpv rounds a start back to the previous keyframe,
/// and keyframes can be seconds apart on a broadcast stream.
const _resumeSlack = Duration(seconds: 10);

class _Emit extends PlayerEvent {
  const _Emit(this.state);
  final PlayerState state;
  @override
  List<Object?> get props => [state];
}
