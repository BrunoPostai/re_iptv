import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../blocs/content_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/platform/window_class.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_image.dart';
import '../../widgets/title_bar.dart';
import '../player/player_screen.dart';

/// Series detail: seasons, episode list and resume support.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});

  final Series series;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  SeriesInfo? _info;
  bool _loading = true;
  bool _favorite = false;
  int? _season;
  final Map<String, WatchProgress> _progress = {};

  /// Every episode of the series, in order, each carrying the whole list as its
  /// siblings — what lets the player step to the next episode without coming
  /// back through this page.
  List<MediaItem> _queue = const [];

  Playlist? get _playlist => getIt<PlaylistRepository>().active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlist = _playlist;
    if (playlist == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Resume positions are read from the local store while the provider's
    // metadata is still on its way, rather than after it: the episodes list
    // waits for the metadata either way, but the positions must not.
    final watchState = _refreshWatchState();
    final info = await getIt<ContentRepository>().seriesInfo(playlist, widget.series.seriesId);
    final queue = _buildQueue(info, playlist);
    await watchState;
    if (!mounted) return;
    setState(() {
      _info = info;
      _queue = queue;
      _season = info.seasons.isEmpty ? null : info.seasons.first;
      _loading = false;
    });
  }

  /// One playable episode.
  MediaItem _mediaItem(
    Series series,
    Episode episode,
    Playlist playlist, {
    List<MediaItem> siblings = const [],
  }) {
    return MediaItem(
      title: series.name,
      subtitle: episode.title.isEmpty
          ? 'S${episode.season} · E${episode.episodeNum}'
          : 'S${episode.season} · E${episode.episodeNum} · ${episode.title}',
      image: episode.image.isNotEmpty ? episode.image : series.cover,
      url: getIt<PlaylistRepository>().sourceFor(playlist).episodeUrl(episode),
      streamId: episode.streamId,
      kind: 'episode',
      parentId: series.seriesId,
      season: episode.season,
      episodeNum: episode.episodeNum,
      containerExtension: episode.containerExtension,
      siblings: siblings,
    );
  }

  /// The series' episodes in season then episode order.
  ///
  /// Sorted rather than left as the panel sent them: `Next` has to mean the
  /// episode after this one, and a panel that lists `1, 10, 2` would otherwise
  /// put episode 10 next.
  List<MediaItem> _buildQueue(SeriesInfo info, Playlist playlist) {
    final items = <MediaItem>[];
    for (final season in ([...info.seasons]..sort())) {
      final episodes = [...?info.episodes[season]]
        ..sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
      for (final episode in episodes) {
        items.add(_mediaItem(info.series, episode, playlist));
      }
    }
    return [for (final item in items) _withSiblings(item, items)];
  }

  /// [item] with the queue attached: the queue cannot contain itself as it is
  /// built, so each item is copied once the list is complete.
  static MediaItem _withSiblings(MediaItem item, List<MediaItem> siblings) => MediaItem(
        title: item.title,
        url: item.url,
        subtitle: item.subtitle,
        image: item.image,
        isLive: item.isLive,
        streamId: item.streamId,
        kind: item.kind,
        parentId: item.parentId,
        season: item.season,
        episodeNum: item.episodeNum,
        containerExtension: item.containerExtension,
        siblings: siblings,
      );

  /// Reads this series' favourite flag and its episodes' resume positions from
  /// the local store.
  ///
  /// Called on load and again as the player pops, which is safe precisely
  /// because it touches no network.
  Future<void> _refreshWatchState() async {
    final playlist = _playlist;
    if (playlist == null) return;
    final content = getIt<ContentRepository>();
    final favorite =
        await content.isFavorite(playlist, ContentKind.series, widget.series.seriesId);
    final progress = await content.continueWatching(playlist, ContentKind.series);
    if (!mounted) return;
    setState(() {
      _favorite = favorite;
      _progress
        ..clear()
        ..addEntries(progress.map((p) => MapEntry(p.id, p)));
    });
  }

  Future<void> _toggleFavorite() async {
    final playlist = _playlist;
    if (playlist == null) return;
    final added = await getIt<ContentRepository>()
        .toggleFavorite(playlist, ContentKind.series, widget.series.seriesId);
    if (mounted) setState(() => _favorite = added);
  }

  Future<void> _play(Episode episode, Series series) async {
    final playlist = _playlist;
    if (playlist == null) return;
    final index = _queue.indexWhere(
      (item) => item.season == episode.season && item.episodeNum == episode.episodeNum,
    );
    // The queue is built from this series' episodes, so only an episode the
    // panel sent twice, or not at all, misses it; that one plays on its own.
    final item = index >= 0
        ? _queue[index]
        : _mediaItem(series, episode, playlist);
    if (item.url.isEmpty) return;
    final id = ContentRepository.episodeProgressId(series.seriesId, episode.streamId);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: item,
          startAt: _progress[id]?.position ?? Duration.zero,
        ),
      ),
    );
    if (mounted && context.mounted) {
      context.read<ContentBloc>().add(const ContentWatchStateReloaded());
      // Only the watch state: the episode list has not changed, and asking for
      // it again would leave the resume positions behind a provider call that
      // can be slow right after a stream has closed.
      await _refreshWatchState();
    }
  }

  Future<void> _openTrailer(String trailer) async {
    if (trailer.isEmpty) return;
    final uri = Uri.parse('https://www.youtube.com/watch?v=$trailer');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();
    final theme = context.watch<SettingsBloc>().state.theme;
    // A phone has no room for a column beside a list: the details come first
    // and the episodes follow them down the same page.
    final compact = WindowClass.of(context).isCompact;
    final info = _info;
    final series = info?.series ?? widget.series;
    final episodes = _season == null ? const <Episode>[] : (info?.episodes[_season] ?? const <Episode>[]);

    return Scaffold(
      body: AppBackground(
        image: theme.background,
        scrim: 0.62,
        child: Column(
          children: [
            AppTitleBar(
              title: config.branding.windowTitle,
              logo: config.branding.logoSmall,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: _loading
                  ? const LoadingBlock(message: 'Loading episodes...')
                  : compact
                  ? SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _details(series, info, episodes),
                            ),
                          ),
                          if (episodes.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                              child: Text(
                                'EPISODES',
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          Container(
                            color: Colors.black.withValues(alpha: 0.22),
                            child: episodes.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 26),
                                    child: EmptyBlock(
                                      message: 'No episodes found for this season.',
                                      icon: Icons.video_library_outlined,
                                    ),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                                    child: Column(
                                      children: [
                                        for (final episode in episodes)
                                          _EpisodeTile(
                                            episode: episode,
                                            progress: _progress[ContentRepository.episodeProgressId(
                                                series.seriesId, episode.streamId)],
                                            onTap: () => _play(episode, series),
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 320,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _details(series, info, episodes),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.22),
                            child: episodes.isEmpty
                                ? const EmptyBlock(
                                    message: 'No episodes found for this season.',
                                    icon: Icons.video_library_outlined,
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: episodes.length,
                                    itemBuilder: (context, index) {
                                      final episode = episodes[index];
                                      return _EpisodeTile(
                                        episode: episode,
                                        progress: _progress[ContentRepository.episodeProgressId(
                                            series.seriesId, episode.streamId)],
                                        onTap: () => _play(episode, series),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cover, title, season picker, actions and metadata.
  ///
  /// One column on the desktop, where it sits beside the episode list; the top
  /// of the page on a phone, where there is no room to sit beside anything.
  List<Widget> _details(Series series, SeriesInfo? info, List<Episode> episodes) {
    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: SmartImage(
                path: series.cover,
                fallbackText: series.name,
                showBorder: true,
                borderRadius: 8,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.name,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (series.rating5Based > 0)
                  Row(
                    children: [
                      const Icon(Icons.star, size: 13, color: AppColors.gold),
                      const SizedBox(width: 4),
                      Text(
                        series.rating5Based.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                if (series.releaseDate.isNotEmpty)
                  Text(
                    series.releaseDate,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (info != null && info.seasons.isNotEmpty)
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _season,
                            dropdownColor: AppColors.panelAlt,
                            isDense: true,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.5,
                            ),
                            items: [
                              for (final s in info.seasons)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text('Season $s'),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _season = value),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: AccentButton(
              label: 'Play first episode',
              icon: Icons.play_arrow,
              onPressed: episodes.isEmpty
                  ? null
                  : () => _play(episodes.first, series),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _toggleFavorite,
            tooltip: _favorite
                ? 'Remove from favourites'
                : 'Add to favourites',
            icon: Icon(
              _favorite ? Icons.favorite : Icons.favorite_border,
              color: _favorite ? AppColors.red : AppColors.textMuted,
            ),
          ),
        ],
      ),
      if (series.plot.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text(
          'PLOT',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          series.plot,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      ],
      if (series.genre.isNotEmpty) ...[
        const SizedBox(height: 12),
        InfoRow(label: 'Genre', value: series.genre),
      ],
      if (series.cast.isNotEmpty) InfoRow(label: 'Cast', value: series.cast),
      if (series.youtubeTrailer.isNotEmpty) ...[
        const SizedBox(height: 12),
        OutlineButtonX(
          label: 'Watch trailer',
          icon: Icons.ondemand_video,
          onPressed: () => _openTrailer(series.youtubeTrailer),
        ),
      ],
    ];
  }
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({required this.episode, required this.onTap, this.progress});

  final Episode episode;
  final VoidCallback onTap;
  final WatchProgress? progress;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final progress = widget.progress;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _hovered ? AppColors.gold.withValues(alpha: 0.6) : AppColors.divider),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SmartImage(
                    path: episode.image,
                    fallbackText: '${episode.episodeNum}',
                    borderRadius: 4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${episode.episodeNum}. ${episode.title.isEmpty ? 'Episode ${episode.episodeNum}' : episode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: progress.percent,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                      ),
                    ],
                    if (episode.plot.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          episode.plot,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              if (episode.duration.isNotEmpty)
                Text(
                  episode.duration,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_outline, color: AppColors.gold, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
