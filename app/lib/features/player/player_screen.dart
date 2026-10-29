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
import '../../core/platform/platform_window.dart';
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

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  PlayerState? _last;
  Timer? _hideTimer;
  bool _overlayVisible = true;
  bool _fullscreen = false;

  /// What is actually playing.
  ///
  /// Not [PlayerScreen.item]: an episode carries its series' other episodes in
  /// `siblings`, and stepping to the next one re-opens the stream on the same
  /// player rather than pushing another route — so the screen has to be able to
  /// move past the item it was built with.
  late MediaItem _item = widget.item;

  /// The queue this item sits in: the series it belongs to, or the item alone.
  List<MediaItem> get _queue => _item.siblings.isEmpty ? [_item] : _item.siblings;

  int get _queueIndex => _queue.indexWhere((item) => item.url == _item.url);

  bool get _hasPrevious => _queueIndex > 0;

  bool get _hasNext {
    final index = _queueIndex;
    return index >= 0 && index < _queue.length - 1;
  }

  /// The next episode's title, for the end-of-playback prompt.
  String? get _nextLabel {
    if (!_hasNext) return null;
    final next = _queue[_queueIndex + 1];
    return next.subtitle ?? next.title;
  }

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

  /// The last volume handed back to the settings.
  ///
  /// A stream opens at the remembered volume, so without this the opening volume
  /// would be written back on every position tick; with it, only a change — the
  /// viewer moving the slider, or muting — is remembered.
  double? _volumeWritten;

  @override
  void initState() {
    super.initState();
    PlatformWindow.addListener(this);
    // Closing the window destroys it without unmounting this route, so the
    // write queued by [dispose] never happens and the last ten seconds of a film
    // are lost. Holding the close here is what makes a resume land exactly.
    // (Desktop only: a mobile app is not closed by a window button.)
    PlatformWindow.setPreventClose(true);
    _scheduleHide();
  }

  @override
  void dispose() {
    PlatformWindow.removeListener(this);
    PlatformWindow.setPreventClose(false);
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
    await PlatformWindow.setPreventClose(false);
    await PlatformWindow.destroy();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      // A finished stream leaves the overlay up: it carries the replay and next
      // episode buttons, and a last frame on its own says nothing.
      if (mounted && _last?.completed != true) {
        setState(() => _overlayVisible = false);
      }
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
    final item = _item;
    if (state.duration.inSeconds < 30) return;
    final playlists = getIt<PlaylistRepository>();
    final playlist = playlists.active;
    if (playlist == null) return;

    final content = getIt<ContentRepository>();
    final progress = WatchProgress(
      id: item.kind == 'episode'
          ? ContentRepository.episodeProgressId(item.parentId, item.streamId)
          : '${item.streamId}',
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

  /// Opens the queue's [index] on this player — the next or previous episode.
  ///
  /// The item being left is saved before the new one opens: this screen is not
  /// unmounted, so nothing else would write it, and watching three episodes in a
  /// row has to leave three resume positions. The volume is left alone; see
  /// `PlayerOpened.keepVolume`.
  Future<void> _playItem(int index) async {
    final queue = _queue;
    if (index < 0 || index >= queue.length) return;
    final item = queue[index];
    if (item.url == _item.url) return;
    await _flushProgress();
    if (!mounted) return;
    final startAt = await _resumePosition(item);
    if (!mounted) return;
    setState(() {
      _item = item;
      // Nothing may be written until the new item's own state arrives, or the
      // previous episode's position would be filed under this one.
      _last = null;
      _savedPosition = Duration.zero;
    });
    _bloc?.add(PlayerOpened(item, startAt: startAt, keepVolume: true));
    _showOverlay();
  }

  /// Where [item] was left off, if anywhere.
  ///
  /// Found by series, season and episode number rather than by the id the entry
  /// was filed under, which is derived from the provider's episode id.
  Future<Duration> _resumePosition(MediaItem item) async {
    if (item.kind != 'episode') return Duration.zero;
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) return Duration.zero;
    final progress =
        await getIt<ContentRepository>().continueWatching(playlist, ContentKind.series);
    for (final entry in progress) {
      if (entry.parentId == item.parentId &&
          entry.season == item.season &&
          entry.episodeNum == item.episodeNum) {
        return entry.position;
      }
    }
    return Duration.zero;
  }

  void _previousEpisode() => _playItem(_queueIndex - 1);

  void _nextEpisode() => _playItem(_queueIndex + 1);

  /// Starts the item over from the beginning.
  void _replay() {
    _savedPosition = Duration.zero;
    _bloc?.add(const PlayerReplayed());
    _showOverlay();
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await PlatformWindow.setFullScreen(_fullscreen);
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
      volume: settings.volume,
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
                context.read<SettingsBloc>().add(VolumeChanged(state.volume));
              }
              if (state.completed) {
                _persistProgress();
                // The overlay is what carries the end-of-episode buttons, so it
                // stays up at the end rather than fading like a stale control
                // bar over a last frame.
                if (!_overlayVisible) setState(() => _overlayVisible = true);
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
                                onPanStart: (_) => PlatformWindow.startDragging(),
                                onDoubleTap: () => PlatformWindow.toggleMaximize(),
                              ),
                            ),
                            // A stream that has run out of file reports itself as
                            // buffering, which turned the spinner on for good at
                            // the end of an episode.
                            if (state.buffering && !state.completed)
                              const Center(
                                child: SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                ),
                              ),
                            // Fades on the way out. The message takes itself down
                            // (see `playerErrorVisible`) because libmpv logs some
                            // of these for a stream that goes on to play, and an
                            // error leaving should look deliberate rather than
                            // like it was never there.
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: state.error == null
                                  ? const SizedBox.shrink()
                                  : Center(
                                      key: const ValueKey('playback-error'),
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
                                  onPrevious: _hasPrevious ? _previousEpisode : null,
                                  onNext: _hasNext ? _nextEpisode : null,
                                  nextLabel: _nextLabel,
                                  onReplay: _replay,
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
    required this.onPrevious,
    required this.onNext,
    required this.nextLabel,
    required this.onReplay,
  });

  final PlayerState state;
  final VoidCallback onBack;
  final VoidCallback onToggleFullscreen;
  final bool fullscreen;
  final int subtitleSize;
  final bool statsVisible;
  final VoidCallback onToggleStats;

  /// Null when there is no episode either side of this one — a film, or the
  /// first or last of a series.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? nextLabel;
  final VoidCallback onReplay;

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
          onPanStart: (_) => PlatformWindow.startDragging(),
          onDoubleTap: () => PlatformWindow.toggleMaximize(),
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
              // position is written before the window goes. Mobile has no such
              // window, so these only appear on the desktop.
              if (PlatformWindow.isDesktop) ...[
                _WindowButton(
                  icon: Icons.remove,
                  tooltip: 'Minimise',
                  onTap: PlatformWindow.minimize,
                ),
                _WindowButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  hoverColor: AppColors.red,
                  onTap: PlatformWindow.close,
                ),
              ],
            ],
          ),
        ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => bloc.add(const PlayerControlsToggled()),
            child: Center(
              // The end of a stream used to leave a last frame, a play button
              // that did nothing (libmpv has no file left to play), and — when
              // mpv called itself buffering as it ran out — a spinner for ever.
              child: state.completed
                  ? _FinishedCard(
                      nextLabel: nextLabel,
                      onReplay: onReplay,
                      onNext: onNext,
                    )
                  : AnimatedOpacity(
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
                  if (onPrevious != null)
                    _ControlButton(
                      icon: Icons.skip_previous,
                      tooltip: 'Previous episode',
                      onTap: onPrevious!,
                      size: 26,
                    ),
                  _ControlButton(
                    icon: state.completed
                        ? Icons.replay
                        : (state.playing ? Icons.pause : Icons.play_arrow),
                    tooltip: state.completed
                        ? 'Play again'
                        : (state.playing ? 'Pause' : 'Play'),
                    onTap: state.completed
                        ? onReplay
                        : () => bloc.add(const PlayerPlayPause()),
                    size: 30,
                  ),
                  if (onNext != null)
                    _ControlButton(
                      icon: Icons.skip_next,
                      tooltip: 'Next episode',
                      onTap: onNext!,
                      size: 26,
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

/// What the end of a stream shows.
///
/// Replaying at the end is not the same as pressing play: libmpv is sitting on
/// its last frame with nothing left to play, so the button sends
/// [PlayerReplayed], which seeks back to the start first.
class _FinishedCard extends StatelessWidget {
  const _FinishedCard({
    required this.nextLabel,
    required this.onReplay,
    required this.onNext,
  });

  /// The episode after this one, as the player listed it.
  final String? nextLabel;
  final VoidCallback onReplay;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final next = onNext;
    final label = nextLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Finished',
          style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.6),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OverlayAction(icon: Icons.replay, label: 'Play again', onTap: onReplay),
            if (next != null) ...[
              const SizedBox(width: 10),
              _OverlayAction(icon: Icons.skip_next, label: 'Next episode', onTap: next),
            ],
          ],
        ),
        if (label != null) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

/// A gold, labelled button for the end-of-stream card.
class _OverlayAction extends StatelessWidget {
  const _OverlayAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.gold,
        backgroundColor: Colors.black.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
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
