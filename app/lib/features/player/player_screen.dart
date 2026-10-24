import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../blocs/player_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';
import 'player_stats.dart';

/// Full-screen playback surface with a custom overlay.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    this.startAt = Duration.zero,
  });

  final MediaItem item;
  final Duration startAt;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  PlayerState? _last;
  Timer? _hideTimer;
  bool _overlayVisible = true;
  bool _fullscreen = false;

  /// Whether the mpv diagnostics read-out is on screen.
  bool _showStats = false;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _persistProgress();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  void _showOverlay() {
    if (!_overlayVisible) setState(() => _overlayVisible = true);
    _scheduleHide();
  }

  /// Stores resume position and marks the item as watched.
  Future<void> _persistProgress() async {
    final state = _last;
    if (state == null) return;
    final item = widget.item;
    if (state.duration.inSeconds < 30) return;
    final playlists = getIt<PlaylistRepository>();
    final playlist = playlists.active;
    if (playlist == null) return;

    final content = getIt<ContentRepository>();
    final progress = WatchProgress(
      id: item.kind == 'episode' ? '${item.parentId}:${item.streamId}' : '${item.streamId}',
      kind: item.kind,
      title: item.title,
      image: item.image ?? '',
      position: state.position,
      duration: state.duration,
      updatedAt: DateTime.now(),
      parentId: item.parentId,
      season: item.season,
      episodeNum: item.episodeNum,
      containerExtension: item.containerExtension,
    );
    await content.saveProgress(playlist, progress);
    if (state.completed || state.progress > 0.92) {
      await content.markWatched(
        playlist,
        item.kind == 'live' ? ContentKind.live : ContentKind.movie,
        item.streamId,
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bloc = context.read<PlayerBloc>();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        bloc.add(const PlayerPlayPause());
        break;
      case LogicalKeyboardKey.arrowRight:
        bloc.add(PlayerSeeked(
          (_last?.position ?? Duration.zero) + const Duration(seconds: 10),
        ));
        break;
      case LogicalKeyboardKey.arrowLeft:
        final target = (_last?.position ?? Duration.zero) - const Duration(seconds: 10);
        bloc.add(PlayerSeeked(target.isNegative ? Duration.zero : target));
        break;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        break;
      case LogicalKeyboardKey.keyI:
        setState(() => _showStats = !_showStats);
        break;
      case LogicalKeyboardKey.escape:
        // Back out of the enlarged player before closing it: Esc leaves
        // fullscreen first, and only closes the player from there.
        if (_fullscreen) {
          _toggleFullscreen();
        } else {
          Navigator.of(context).maybePop();
        }
        break;
      default:
        return KeyEventResult.ignored;
    }
    _showOverlay();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsBloc>().state;

    return BlocProvider<PlayerBloc>(
      create: (_) {
        final config = getIt<AppConfig>();
        return PlayerBloc(
          settings.subtitleSize,
          volume: settings.volume,
          title: config.branding.windowTitle,
          hardwareDecoding: config.player.hardwareDecoding,
          liveTuning: config.player.liveTuning,
        )..add(PlayerOpened(widget.item, startAt: widget.startAt));
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: BlocListener<PlayerBloc, PlayerState>(
            listenWhen: (a, b) =>
                a.position != b.position || a.completed != b.completed || a.error != b.error,
            listener: (context, state) {
              _last = state;
              if (state.completed) _persistProgress();
            },
            child: MouseRegion(
              onHover: (_) => _showOverlay(),
              child: Builder(
                builder: (context) => Stack(
                  fit: StackFit.expand,
                  children: [
                    // Kept out of the reactive subtree: libmpv reports position
                    // several times a second, and rebuilding the video surface
                    // on every tick is wasted work.
                    Center(
                      child: Video(
                        controller: context.read<PlayerBloc>().controller,
                        controls: NoVideoControls,
                        fill: Colors.black,
                      ),
                    ),
                    BlocBuilder<PlayerBloc, PlayerState>(
                      buildWhen: _overlayNeedsRebuild,
                      builder: (context, state) {
                        _last = state;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            // The player route is frameless, so this invisible
                            // strip is what allows the window to be dragged
                            // during playback. It sits above the video but below
                            // the overlay, and is translucent so the controls
                            // still receive their taps.
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 34,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onPanStart: (_) => windowManager.startDragging(),
                                onDoubleTap: () async {
                                  if (await windowManager.isMaximized()) {
                                    await windowManager.unmaximize();
                                  } else {
                                    await windowManager.maximize();
                                  }
                                },
                              ),
                            ),
                            if (state.buffering)
                              const Center(
                                child: SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                ),
                              ),
                            if (state.error != null)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.red),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: AppColors.red, size: 34),
                                      const SizedBox(height: 8),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 520),
                                        child: Text(
                                          state.error!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: Colors.white70, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            AnimatedOpacity(
                              opacity: _overlayVisible ? 1 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: IgnorePointer(
                                ignoring: !_overlayVisible,
                                child: _Overlay(
                                  state: state,
                                  onBack: () => Navigator.of(context).maybePop(),
                                  onToggleFullscreen: _toggleFullscreen,
                                  fullscreen: _fullscreen,
                                  subtitleSize: settings.subtitleSize,
                                  statsVisible: _showStats,
                                  onToggleStats: () =>
                                      setState(() => _showStats = !_showStats),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (_showStats)
                      Positioned(
                        top: 46,
                        right: 14,
                        child: PlayerStatsOverlay(
                          player: context.read<PlayerBloc>().player,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether a new player state has to rebuild the overlay.
///
/// A live stream has no scrubber, so the position ticks libmpv emits several
/// times a second are ignored — otherwise the overlay would rebuild
/// continuously for the whole time a channel is playing.
bool _overlayNeedsRebuild(PlayerState previous, PlayerState current) {
  if (previous == current) return false;
  if (!current.isLive) return true;
  return previous.copyWith(position: current.position) != current;
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.state,
    required this.onBack,
    required this.onToggleFullscreen,
    required this.fullscreen,
    required this.subtitleSize,
    required this.statsVisible,
    required this.onToggleStats,
  });

  final PlayerState state;
  final VoidCallback onBack;
  final VoidCallback onToggleFullscreen;
  final bool fullscreen;
  final int subtitleSize;
  final bool statsVisible;
  final VoidCallback onToggleStats;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PlayerBloc>();
    final item = state.item;

    return Column(
      children: [
        GestureDetector(
          // The player route is frameless, so the overlay's top bar doubles as
          // the window's drag handle (and double-click still maximises).
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 22),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Back',
              ),
              Expanded(
                child: Text(
                  item?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              if (item?.subtitle != null)
                Text(
                  item!.subtitle!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => bloc.add(const PlayerControlsToggled()),
            child: Center(
              child: AnimatedOpacity(
                opacity: state.playing ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: IconButton(
                  iconSize: 74,
                  onPressed: () => bloc.add(const PlayerPlayPause()),
                  icon: const Icon(Icons.play_circle_fill, color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 30, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!state.isLive)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: AppColors.gold,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: AppColors.gold,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: state.progress.clamp(0.0, 1.0),
                    onChanged: (value) => bloc.add(PlayerSeeked(
                      Duration(milliseconds: (state.duration.inMilliseconds * value).round()),
                    )),
                  ),
                ),
              Row(
                children: [
                  _ControlButton(
                    icon: state.playing ? Icons.pause : Icons.play_arrow,
                    tooltip: state.playing ? 'Pause' : 'Play',
                    onTap: () => bloc.add(const PlayerPlayPause()),
                    size: 30,
                  ),
                  const SizedBox(width: 6),
                  if (state.isLive)
                    const Text('LIVE', style: TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.bold))
                  else
                    Text(
                      '${formatDuration(state.position)} / ${formatDuration(state.duration)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  const Spacer(),
                  _IconControl(
                    icon: Icons.subtitles_outlined,
                    tooltip: 'Subtitles',
                    onTap: () => _showTrackSheet(context, state, true),
                  ),
                  _IconControl(
                    icon: Icons.graphic_eq,
                    tooltip: 'Audio track',
                    onTap: () => _showTrackSheet(context, state, false),
                  ),
                  _IconControl(
                    icon: Icons.speed,
                    tooltip: statsVisible ? 'Hide playback stats' : 'Show playback stats',
                    onTap: onToggleStats,
                  ),
                  SizedBox(
                    width: 130,
                    child: Row(
                      children: [
                        Icon(
                          state.volume == 0 ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white70,
                          size: 18,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              activeTrackColor: Colors.white70,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            ),
                            child: Slider(
                              value: state.volume.clamp(0, 100),
                              max: 100,
                              onChanged: (value) => bloc.add(PlayerVolumeSet(value)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _IconControl(
                    icon: fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    tooltip: 'Fullscreen',
                    onTap: onToggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTrackSheet(BuildContext context, PlayerState state, bool subtitles) {
    final bloc = context.read<PlayerBloc>();
    final List<(String, String?, VoidCallback)> entries = subtitles
        ? [
            for (final track in state.tracks.subtitle)
              (
                track.title ?? track.language ?? track.id,
                track.language,
                () => bloc.add(PlayerSubtitleSelected(track)),
              ),
          ]
        : [
            for (final track in state.tracks.audio)
              (
                track.title ?? track.language ?? track.id,
                track.language,
                () => bloc.add(PlayerAudioSelected(track)),
              ),
          ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panelAlt,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text(
              subtitles ? 'Subtitles' : 'Audio track',
              style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
            ),
          ),
          if (subtitles)
            ListTile(
              dense: true,
              title: const Text('Off', style: TextStyle(fontSize: 13, color: Colors.white)),
              onTap: () {
                bloc.add(PlayerSubtitleSelected(SubtitleTrack.no()));
                Navigator.of(sheetContext).pop();
              },
            ),
          for (final entry in entries)
            ListTile(
              dense: true,
              title: Text(
                entry.$1,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
              subtitle: (entry.$2 ?? '').isEmpty
                  ? null
                  : Text(
                      entry.$2!,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
              onTap: () {
                entry.$3();
                Navigator.of(sheetContext).pop();
              },
            ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'No tracks reported by the stream.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 24,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onTap,
      iconSize: size,
      icon: Icon(icon, color: Colors.white),
      splashRadius: size,
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _IconControl extends StatelessWidget {
  const _IconControl({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onTap,
      iconSize: 20,
      icon: Icon(icon, color: Colors.white70),
      splashRadius: 16,
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
