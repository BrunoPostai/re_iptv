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
import '../../core/constants.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
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

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  PlayerState? _last;
  Timer? _hideTimer;
  bool _overlayVisible = true;
  bool _fullscreen = false;

  /// This screen's bloc, created on the first build and closed in [dispose]:
  /// `BlocProvider.value` hands ownership to the screen rather than keeping it.
  ///
  /// It is held here because the key handler must be able to reach it — see the
  /// note in [build].
  PlayerBloc? _bloc;

  /// Progress writes, queued one after the other: each write reads the list it is
  /// about to replace, so two in flight at once could drop an entry. Queueing
  /// also leaves the write made as this screen goes away ordered last, so the
  /// newest position is the one that lands.
  Future<void> _progressWrites = Future<void>.value();

  /// The position the last write was queued for, so that writes are spaced
  /// [progressSaveInterval] apart as playback goes.
  Duration _savedPosition = Duration.zero;

  /// Whether the mpv diagnostics read-out is on screen.
  bool _showStats = false;

  /// The last volume handed back to the settings, and which of the two remembered
  /// volumes this stream's kind belongs to.
  ///
  /// A stream opens at its kind's volume, so without this the opening volume
  /// would be written back on every position tick; with it, only a change — the
  /// viewer moving the slider, or muting — is remembered.
  double? _volumeWritten;
  VolumeScope get _volumeScope =>
      widget.item.isLive ? VolumeScope.live : VolumeScope.video;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Closing the window destroys it without unmounting this route, so the
    // write queued by [dispose] never happens and the last ten seconds of a film
    // are lost. Holding the close here is what makes a resume land exactly.
    windowManager.setPreventClose(true);
    _scheduleHide();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    windowManager.setPreventClose(false);
    _hideTimer?.cancel();
    _persistProgress();
    _bloc?.close();
    super.dispose();
  }

  /// The window's close came in: save the position, then let the window go.
  @override
  void onWindowClose() async {
    try {
      // Whatever happens, the window is handed back — a close held open by a
      // write that never finishes is an app that cannot be quit.
      await _flushProgress().timeout(const Duration(seconds: 2));
    } catch (_) {
      // The position is up to ten seconds stale in the worst case; that is not
      // worth refusing to close over.
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
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

  /// Records how far the item has been watched.
  ///
  /// Called as playback goes, not only when this screen is left: closing the
  /// window destroys it without unmounting the player's route, so a save that
  /// waited for [dispose] never happened at all and the item started from the
  /// beginning next time.
  void _persistProgress() {
    _progressWrites = _progressWrites.then<void>(
      (_) => _writeProgress(),
      // A failed write must not cancel the writes queued behind it.
      onError: (Object _) {},
    );
  }

  /// Stores resume position and marks the item as watched.
  Future<void> _writeProgress() async {
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
    if (state.completed) {
      // Watched to the end, so there is nothing left to resume: the entry goes
      // and playing it again starts the film over rather than dropping the
      // viewer on its last minute.
      await content.clearProgress(playlist, progress);
    } else {
      await content.saveProgress(playlist, progress);
    }
    if (state.completed || state.progress > 0.92) {
      // An episode counts as its series being watched, not as a film of its own.
      final (kind, id) =
          ContentRepository.watchedEntry(item.kind, item.streamId, item.parentId);
      await content.markWatched(playlist, kind, id);
    }
  }

  /// Leaves the player, saving the position first.
  ///
  /// The screen that pushed this one re-reads the resume position the moment the
  /// route pops, and a write left to the queue is still in flight by then:
  /// backing out to the film's own page and pressing play again looked like no
  /// progress had been made at all, while going back further — to the list — and
  /// opening the film again gave the write time to land and resumed properly.
  Future<void> _exit() async {
    await _flushProgress();
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Queues the current position and waits for the queue to drain.
  Future<void> _flushProgress() {
    _persistProgress();
    return _progressWrites;
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bloc = _bloc;
    if (bloc == null) return KeyEventResult.ignored;
    switch (_shortcutKey(event)) {
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
          _exit();
        }
        break;
      default:
        return KeyEventResult.ignored;
    }
    _showOverlay();
    return KeyEventResult.handled;
  }

  /// Which key to act on for [event].
  ///
  /// The two letter shortcuts are matched on the physical key rather than the
  /// logical one. `logicalKey` follows the layout, so on a keyboard that puts a
  /// different letter or symbol where "I" and "F" sit — or with an IME active —
  /// pressing the key labelled "I" reports something else entirely, and the
  /// shortcut looks broken with nothing to hint at why. The physical key is the
  /// position actually pressed, so the shortcut holds wherever the hands are.
  LogicalKeyboardKey _shortcutKey(KeyEvent event) => switch (event.physicalKey) {
        PhysicalKeyboardKey.keyF => LogicalKeyboardKey.keyF,
        PhysicalKeyboardKey.keyI => LogicalKeyboardKey.keyI,
        _ => event.logicalKey,
      };

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsBloc>().state;

    // Created here rather than inside `BlocProvider.create` so that the key
    // handler can reach it. This screen builds the provider, so `State.context`
    // sits *above* it: reading the bloc from there throws for every key press,
    // which looks exactly like the keyboard doing nothing at all.
    final config = getIt<AppConfig>();
    final bloc = _bloc ??= PlayerBloc(
      settings.subtitleSize,
      volume: widget.item.isLive ? settings.volume : settings.vodVolume,
      title: config.branding.windowTitle,
      hardwareDecoding: config.player.hardwareDecoding,
      liveTuning: config.player.liveTuning,
    )..add(PlayerOpened(widget.item, startAt: widget.startAt));

    return BlocProvider<PlayerBloc>.value(
      value: bloc,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: BlocListener<PlayerBloc, PlayerState>(
            listenWhen: (a, b) =>
                a.position != b.position ||
                a.completed != b.completed ||
                a.error != b.error ||
                a.volume != b.volume,
            listener: (context, state) {
              _last = state;
              // The viewer changed the volume: remember it for this kind of
              // stream, so the next film or channel opens where they left this
              // one rather than back at the setting.
              if (_volumeWritten != state.volume) {
                _volumeWritten = state.volume;
                context
                    .read<SettingsBloc>()
                    .add(VolumeChanged(state.volume, scope: _volumeScope));
              }
              if (state.completed) {
                _persistProgress();
                return;
              }
              // Written as playback goes, so that quitting the hard way — the
              // window closing, which never unmounts this route — costs at most
              // [progressSaveInterval] of the film rather than all of it.
              if (!state.isLive &&
                  (state.position - _savedPosition).abs() >= progressSaveInterval) {
                _savedPosition = state.position;
                _persistProgress();
              }
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
                                  onBack: _exit,
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
  // libmpv reports the position several times a second. Only the scrubber and the
  // elapsed-time label draw it, and those read the state through
  // [_PositionBuilder] below, so a tick no longer repaints the whole overlay.
  return previous.copyWith(position: current.position) != current;
}

/// Rebuilds [builder] when the playback position or duration changes.
///
/// The overlay itself ignores position ticks (see [_overlayNeedsRebuild]), so the
/// two widgets that do draw the position read it through here: a tick then
/// repaints two widgets instead of every control on screen.
class _PositionBuilder extends StatelessWidget {
  const _PositionBuilder({required this.builder});

  final Widget Function(BuildContext context, PlayerState current) builder;

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerBloc, PlayerState>(
        buildWhen: (previous, current) =>
            previous.position != current.position || previous.duration != current.duration,
        builder: builder,
      );
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
              // The player covers the window's title bar and draws none of its
              // own, so minimising and closing the app have to live here or not
              // at all — otherwise the only way out of a film is to leave it
              // first. Closing goes through the held close (§13), so the
              // position is written before the window goes.
              _WindowButton(
                icon: Icons.remove,
                tooltip: 'Minimise',
                onTap: windowManager.minimize,
              ),
              _WindowButton(
                icon: Icons.close,
                tooltip: 'Close',
                hoverColor: AppColors.red,
                onTap: windowManager.close,
              ),
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
                _PositionBuilder(
                  builder: (context, current) => SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppColors.gold,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: AppColors.gold,
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: current.progress.clamp(0.0, 1.0),
                      onChanged: (value) => bloc.add(PlayerSeeked(
                        Duration(
                          milliseconds: (current.duration.inMilliseconds * value).round(),
                        ),
                      )),
                    ),
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
                    _PositionBuilder(
                      builder: (context, current) => Text(
                        '${formatDuration(current.position)} / ${formatDuration(current.duration)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
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

/// A window button in the player's top bar: flat, filling the bar's height the
/// way the title bar's own buttons do, so minimise and close read as window
/// controls rather than as another playback control.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.hoverColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? hoverColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 40,
            height: 34,
            alignment: Alignment.center,
            color: _hovered
                ? (widget.hoverColor ?? Colors.white).withValues(alpha: 0.18)
                : Colors.transparent,
            child: Icon(widget.icon, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
