import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../blocs/content_bloc.dart';
import '../../blocs/player_bloc.dart';
import '../../blocs/playlist_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';
import '../../widgets/category_sidebar.dart';
import '../../widgets/common.dart';
import '../../widgets/media_grid.dart';
import '../../widgets/pin_dialog.dart';
import '../../widgets/search_field.dart';
import '../../widgets/smart_image.dart';
import '../../widgets/title_bar.dart';
import '../player/player_screen.dart';

/// Live TV: category sidebar, channel list and a details/EPG panel.
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsBloc>().state;
    return BlocProvider<ContentBloc>(
      create: (_) => ContentBloc(
        getIt<ContentRepository>(),
        getIt<PlaylistRepository>(),
      )..add(ContentStarted(ContentKind.live, sortType: settings.sortType)),
      child: const _LiveBody(),
    );
  }
}

class _LiveBody extends StatefulWidget {
  const _LiveBody();

  @override
  State<_LiveBody> createState() => _LiveBodyState();
}

class _LiveBodyState extends State<_LiveBody> {
  Channel? _selected;
  List<EpgProgram> _epg = const [];
  bool _loadingEpg = false;

  /// Inline preview of the selected channel.
  ///
  /// Owned here rather than by the details panel so it can be torn down when
  /// playback is handed to the full player — otherwise the preview would keep
  /// playing audio underneath it. One player is reused for the lifetime of the
  /// screen: opening a stream on it replaces whatever it was playing, so
  /// browsing the list does not spawn a libmpv instance per channel.
  PlayerBloc? _preview;

  /// Bumped whenever the preview is (re)started, so the box drops a stale
  /// "off air" verdict even when the same channel is opened twice.
  int _previewSequence = 0;

  /// Opening a stream costs a player plus a network connection, so the preview
  /// and the guide request wait for the selection to settle — running down the
  /// list must not open every channel it passes over.
  static const _selectDelay = Duration(milliseconds: 350);
  Timer? _selectDebounce;

  /// Identifies the most recent selection; work that finishes after a newer one
  /// has started is discarded.
  int _selection = 0;

  @override
  void dispose() {
    _selectDebounce?.cancel();
    _stopPreview();
    super.dispose();
  }

  /// Starts a muted preview of [channel], replacing any previous one.
  void _startPreview(Channel channel) {
    final playlist = getIt<PlaylistRepository>().active;
    final url = playlist == null
        ? ''
        : getIt<PlaylistRepository>().sourceFor(playlist).liveUrl(channel);
    if (url.isEmpty) {
      // Nothing to open — drop the preview rather than leave the previous
      // channel playing under the new channel's name.
      _stopPreview();
      return;
    }
    final settings = context.read<SettingsBloc>().state;
    final config = getIt<AppConfig>();
    final bloc = _preview ??= PlayerBloc(
      settings.subtitleSize,
      volume: 0,
      title: config.branding.windowTitle,
      hardwareDecoding: config.player.hardwareDecoding,
      liveTuning: config.player.liveTuning,
    );
    _previewSequence++;
    bloc.add(PlayerOpened(MediaItem(
      title: channel.name,
      url: url,
      isLive: true,
      streamId: channel.streamId,
      kind: 'live',
      parentId: channel.streamId,
    )));
  }

  void _stopPreview() {
    final bloc = _preview;
    _preview = null;
    bloc?.close();
  }

  void _select(Channel channel) {
    // Do not preview a channel the user has hidden behind parental control —
    // that would show content the PIN is meant to guard.
    final settings = context.read<SettingsBloc>().state;
    final locked = settings.isHidden(channel.categoryId);
    final token = ++_selection;
    _selectDebounce?.cancel();
    if (locked) _stopPreview();
    setState(() {
      _selected = channel;
      _epg = const [];
      _loadingEpg = !locked;
    });
    if (locked) return;
    _selectDebounce = Timer(_selectDelay, () {
      if (!mounted || token != _selection) return;
      setState(() => _startPreview(channel));
      _loadEpg(channel, token);
    });
  }

  Future<void> _loadEpg(Channel channel, int token) async {
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) {
      if (mounted && token == _selection) setState(() => _loadingEpg = false);
      return;
    }
    final programs = await getIt<ContentRepository>().shortEpg(playlist, channel.streamId);
    if (!mounted || token != _selection) return;
    setState(() {
      _epg = programs;
      _loadingEpg = false;
    });
  }

  Future<void> _play(Channel channel) async {
    final settings = context.read<SettingsBloc>().state;
    if (settings.isHidden(channel.categoryId)) {
      final ok = await requestPin(context, expected: settings.pin, title: 'Parental control');
      if (!ok || !mounted) return;
    }
    // A deliberate play: abandon whatever is still pending for the previously
    // selected channel.
    _selectDebounce?.cancel();
    _selection++;
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) return;
    final source = getIt<PlaylistRepository>().sourceFor(playlist);
    final url = source.liveUrl(channel);
    if (url.isEmpty) return;

    // Hand the stream over to the full player: stop the preview first so the
    // two do not play at once, then bring it back when the player is closed.
    _stopPreview();
    setState(() {});

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: MediaItem(
            title: channel.name,
            subtitle: playlist.name,
            image: channel.icon,
            url: url,
            isLive: true,
            streamId: channel.streamId,
            kind: 'live',
            parentId: channel.streamId,
          ),
        ),
      ),
    );
    if (!mounted) return;
    await getIt<ContentRepository>().markWatched(playlist, ContentKind.live, channel.streamId);
    if (!mounted) return;
    // Watching only changes watch state; reloading the whole catalogue here
    // re-read and re-decoded every channel and froze the list on large
    // playlists.
    context.read<ContentBloc>().add(const ContentWatchStateReloaded());
    setState(() => _startPreview(channel));
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
                  Expanded(
                    child: BlocBuilder<PlaylistBloc, PlaylistState>(
                      builder: (context, playlistState) => ScreenHeading(
                        title: 'Live Channels',
                        subtitle: playlistState.active?.name,
                      ),
                    ),
                  ),
                  SearchField(
                    width: 250,
                    hint: settings.l10n.t('search_hint'),
                    onChanged: (value) =>
                        context.read<ContentBloc>().add(ContentQueryChanged(value)),
                  ),
                  const SizedBox(width: 10),
                  BlocBuilder<ContentBloc, ContentState>(
                    builder: (context, state) => SortDropdown(
                      value: state.sortType,
                      onChanged: (value) {
                        context.read<ContentBloc>().add(ContentSortChanged(value));
                        context.read<SettingsBloc>().add(SortTypeChanged(value));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Reload from server',
                    onPressed: () => context.read<ContentBloc>().add(const ContentRefreshed()),
                    icon: const Icon(Icons.refresh, color: AppColors.textMuted, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<ContentBloc, ContentState>(
                builder: (context, state) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CategorySidebar(
                      rows: state.rows,
                      selectedId: state.selectedCategoryId,
                      onSelected: (id) =>
                          context.read<ContentBloc>().add(ContentCategorySelected(id)),
                      isHidden: (id) => settings.isHidden(id),
                    ),
                    Expanded(child: _buildList(state)),
                    _DetailsPanel(
                      channel: _selected,
                      epg: _epg,
                      loading: _loadingEpg,
                      preview: _preview,
                      previewSequence: _previewSequence,
                      locked: _selected != null && settings.isHidden(_selected!.categoryId),
                      onPlay: _selected == null ? null : () => _play(_selected!),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ContentState state) {
    if (state.loading && state.rows.isEmpty) {
      return const LoadingBlock(message: 'Loading channels...');
    }
    if (state.error != null && state.rows.isEmpty) {
      return ErrorBlock(
        message: state.error!,
        onRetry: () => context.read<ContentBloc>().add(const ContentRefreshed()),
      );
    }
    if (state.channels.isEmpty) {
      return const EmptyBlock(message: 'No channels in this category.', icon: Icons.tv_off);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.channels.length,
      itemBuilder: (context, index) {
        final channel = state.channels[index];
        return ChannelRow(
          name: channel.name,
          image: channel.icon,
          number: channel.num == 0 ? index + 1 : channel.num,
          locked: context.read<SettingsBloc>().state.isHidden(channel.categoryId),
          favorite: state.favorites.contains('${channel.streamId}'),
          onToggleFavorite: () =>
              context.read<ContentBloc>().add(ContentFavoriteToggled(channel.streamId)),
          onTap: () => _select(channel),
          onLongPress: () => _play(channel),
          trailing: channel.hasArchive
              ? const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Catch up available',
                    child: Icon(Icons.history, size: 15, color: AppColors.gold),
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({
    required this.channel,
    required this.epg,
    required this.loading,
    required this.preview,
    required this.previewSequence,
    required this.locked,
    required this.onPlay,
  });

  final Channel? channel;
  final List<EpgProgram> epg;
  final bool loading;
  final PlayerBloc? preview;

  /// Increments each time a stream is opened into [preview].
  final int previewSequence;

  /// True when the channel sits behind parental control; it is not previewed.
  final bool locked;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.divider)),
      ),
      child: channel == null
          ? const EmptyBlock(message: 'Select a channel to see details.', icon: Icons.info_outline)
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PreviewBox(
                    channel: channel!,
                    preview: preview,
                    sequence: previewSequence,
                    locked: locked,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    channel!.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (channel!.hasArchive)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Catch up · ${channel!.archiveDuration} days',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ),
                  const SizedBox(height: 14),
                  AccentButton(label: 'Watch', icon: Icons.play_arrow, onPressed: onPlay),
                  const Divider(height: 28, color: AppColors.divider),
                  const Text(
                    'PROGRAMME GUIDE',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: _GuideList(epg: epg, loading: loading)),
                ],
              ),
            ),
    );
  }
}

/// Inline preview of the selected channel.
///
/// Plays the live stream when it starts, and falls back to a "nothing on air"
/// card when the channel cannot be opened — an empty black box reads as a bug,
/// a message does not.
class _PreviewBox extends StatefulWidget {
  const _PreviewBox({
    required this.channel,
    required this.preview,
    this.sequence = 0,
    this.locked = false,
  });

  final Channel channel;
  final PlayerBloc? preview;

  /// Changes every time a stream is opened, even on the same channel.
  final int sequence;

  /// Locked channels are never previewed; they show a padlock card instead.
  final bool locked;

  @override
  State<_PreviewBox> createState() => _PreviewBoxState();
}

class _PreviewBoxState extends State<_PreviewBox> {
  /// How long to wait for a stream to report playback before calling it off air.
  static const _startupGrace = Duration(seconds: 12);

  Timer? _giveUp;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant _PreviewBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channelChanged = oldWidget.channel.streamId != widget.channel.streamId;
    final blocChanged = !identical(oldWidget.preview, widget.preview);
    final restarted = oldWidget.sequence != widget.sequence;
    if (channelChanged || blocChanged || restarted) {
      // A fresh stream gets a fresh grace period — otherwise a channel that
      // timed out once would show the offline card the next time it is opened.
      _timedOut = false;
      _arm();
    }
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    super.dispose();
  }

  /// A stream that never reports playback is treated as off air.
  void _arm() {
    _giveUp?.cancel();
    if (widget.preview == null) return;
    _giveUp = Timer(_startupGrace, () {
      if (!mounted) return;
      // Playback may have started while the timer ran; only flag the channel if
      // it never did.
      if (widget.preview?.state.playing ?? false) return;
      setState(() => _timedOut = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bloc = widget.preview;
    if (widget.locked) return _OfflinePreview(channel: widget.channel, locked: true);
    if (bloc == null) return _OfflinePreview(channel: widget.channel);

    return BlocBuilder<PlayerBloc, PlayerState>(
      bloc: bloc,
      // [state] is only read for these three; the position libmpv reports
      // several times a second must not rebuild the preview — and with it the
      // video surface — for as long as a channel is playing.
      buildWhen: (previous, current) =>
          previous.playing != current.playing ||
          previous.error != current.error ||
          previous.volume != current.volume,
      builder: (context, state) {
        final unavailable = state.error != null || (_timedOut && !state.playing);
        final live = state.playing && !unavailable;
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (live)
                  Video(
                    controller: bloc.controller,
                    controls: NoVideoControls,
                    fill: Colors.black,
                  )
                else if (unavailable)
                  _OfflinePreview(channel: widget.channel)
                else
                  const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                if (live)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _PreviewButton(
                      icon: state.volume == 0 ? Icons.volume_off : Icons.volume_up,
                      tooltip: state.volume == 0 ? 'Unmute preview' : 'Mute preview',
                      onTap: () {
                        final volume = context.read<SettingsBloc>().state.volume;
                        bloc.add(PlayerVolumeSet(state.volume == 0 ? volume : 0));
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Placeholder shown when there is nothing to preview on a channel.
class _OfflinePreview extends StatelessWidget {
  const _OfflinePreview({required this.channel, this.locked = false});

  final Channel channel;

  /// Shows the parental-control wording rather than the off-air one.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (channel.icon.isNotEmpty)
              Opacity(
                opacity: 0.18,
                child: SmartImage(path: channel.icon, fallbackText: channel.name),
              ),
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    locked ? Icons.lock_outline : Icons.tv_off,
                    size: 24,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    locked ? 'Locked channel' : 'Nothing on air right now',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    locked ? 'Press Watch and enter your PIN.' : 'Check back later.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small translucent button used on top of the preview video.
class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Programme guide list, scrolled to whichever programme is on air.
class _GuideList extends StatefulWidget {
  const _GuideList({required this.epg, required this.loading});

  final List<EpgProgram> epg;
  final bool loading;

  @override
  State<_GuideList> createState() => _GuideListState();
}

class _GuideListState extends State<_GuideList> {
  /// Roughly one card plus its margin, used to reach the on-air row before the
  /// list has laid it out.
  static const _rowEstimate = 72.0;

  final _controller = ScrollController();
  final _nowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollToNow();
  }

  @override
  void didUpdateWidget(covariant _GuideList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.epg, widget.epg)) _scrollToNow();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Brings the on-air programme into view.
  ///
  /// A full-day guide usually starts at midnight, so the on-air row is often far
  /// below the fold and has never been laid out — `ensureVisible` alone cannot
  /// reach it. Jump to an estimated offset first, then fine-tune on the next
  /// frame once the rows around it exist.
  void _scrollToNow() {
    final index = widget.epg.indexWhere((program) => program.isNow);
    if (index <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final target =
          (index * _rowEstimate).clamp(0.0, _controller.position.maxScrollExtent);
      _controller.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nowRow = _nowKey.currentContext;
        if (!mounted || nowRow == null) return;
        Scrollable.ensureVisible(
          nowRow,
          alignment: 0.15,
          duration: const Duration(milliseconds: 200),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const LoadingBlock();
    if (widget.epg.isEmpty) {
      return const Text(
        'No programme information available for this channel.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
      );
    }
    return ListView.builder(
      controller: _controller,
      itemCount: widget.epg.length,
      itemBuilder: (context, index) {
        final program = widget.epg[index];
        final now = program.isNow;
        return Container(
          key: now ? _nowKey : null,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: now
                ? AppColors.blue.withValues(alpha: 0.28)
                : Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: now ? AppColors.gold : AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    program.hasUsableTime
                        ? '${_clock(program.start)} - ${_clock(program.end)}'
                        : 'Time unavailable',
                    style: TextStyle(
                      color: now ? AppColors.gold : AppColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: now ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  if (now) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text(
                        'NOW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                program.title.isEmpty ? 'No title' : program.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
              if (program.description.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  program.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _clock(DateTime date) => '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}