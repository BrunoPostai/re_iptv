import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../blocs/content_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_image.dart';
import '../../widgets/title_bar.dart';
import '../player/player_screen.dart';

/// Movie detail: artwork, metadata and playback entry point.
class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movie});

  final Movie movie;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  late Movie _movie = widget.movie;
  bool _loading = true;
  bool _favorite = false;
  List<WatchProgress> _progress = const [];

  Playlist? get _playlist => getIt<PlaylistRepository>().active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlist = _playlist;
    if (playlist != null) {
      final content = getIt<ContentRepository>();
      final info = await content.movieInfo(playlist, widget.movie);
      final favorite = await content.isFavorite(playlist, ContentKind.movie, widget.movie.streamId);
      final progress = await content.continueWatching(playlist, ContentKind.movie);
      if (!mounted) return;
      setState(() {
        _movie = info;
        _favorite = favorite;
        _progress = progress.where((p) => p.id == '${widget.movie.streamId}').toList();
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleFavorite() async {
    final playlist = _playlist;
    if (playlist == null) return;
    final added = await getIt<ContentRepository>()
        .toggleFavorite(playlist, ContentKind.movie, _movie.streamId);
    if (mounted) setState(() => _favorite = added);
  }

  Future<void> _play() async {
    final playlist = _playlist;
    if (playlist == null) return;
    final source = getIt<PlaylistRepository>().sourceFor(playlist);
    final url = source.movieUrl(_movie);
    if (url.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: MediaItem(
            title: _movie.name,
            subtitle: _movie.genre,
            image: _movie.icon,
            url: url,
            streamId: _movie.streamId,
            kind: 'movie',
            parentId: _movie.streamId,
            containerExtension: _movie.containerExtension,
          ),
          startAt: _progress.isEmpty ? Duration.zero : _progress.first.position,
        ),
      ),
    );
    if (mounted && context.mounted) {
      context.read<ContentBloc>().add(const ContentWatchStateReloaded());
      await _load();
    }
  }

  Future<void> _openTrailer() async {
    final id = _movie.youtubeTrailer;
    if (id.isEmpty) return;
    final uri = Uri.parse('https://www.youtube.com/watch?v=$id');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();
    final theme = context.watch<SettingsBloc>().state.theme;

    return Scaffold(
      body: AppBackground(
        image: theme.background,
        scrim: 0.6,
        child: Column(
          children: [
            AppTitleBar(
              title: config.branding.windowTitle,
              logo: config.branding.logoSmall,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: _loading
                  ? const LoadingBlock(message: 'Loading details...')
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 250,
                            child: Column(
                              children: [
                                AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: SmartImage(
                                    path: _movie.icon,
                                    fallbackText: _movie.name,
                                    showBorder: true,
                                    borderRadius: 8,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: AccentButton(
                                        label: 'Play',
                                        icon: Icons.play_arrow,
                                        onPressed: _play,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: _favorite ? 'Remove from favourites' : 'Add to favourites',
                                      child: IconButton(
                                        onPressed: _toggleFavorite,
                                        icon: Icon(
                                          _favorite ? Icons.favorite : Icons.favorite_border,
                                          color: _favorite ? AppColors.red : AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 26),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _movie.name,
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (_movie.rating5Based > 0)
                                      _Chip(
                                        icon: Icons.star,
                                        label: _movie.rating5Based.toStringAsFixed(1),
                                      ),
                                    if (_movie.releaseDate.isNotEmpty)
                                      _Chip(icon: Icons.calendar_today, label: _movie.releaseDate),
                                    if (_movie.duration.isNotEmpty)
                                      _Chip(icon: Icons.schedule, label: _movie.duration),
                                    if (_movie.containerExtension.isNotEmpty)
                                      _Chip(
                                        icon: Icons.high_quality,
                                        label: _movie.containerExtension.toUpperCase(),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                if (_progress.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Continue watching',
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                                        ),
                                        const SizedBox(height: 6),
                                        LinearProgressIndicator(
                                          value: _progress.first.percent,
                                          minHeight: 4,
                                          backgroundColor: Colors.white12,
                                          valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_movie.plot.isNotEmpty) ...[
                                  const _SectionLabel('Plot'),
                                  Text(
                                    _movie.plot,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12.5,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (_movie.genre.isNotEmpty)
                                  InfoRow(label: 'Genre', value: _movie.genre),
                                if (_movie.director.isNotEmpty)
                                  InfoRow(label: 'Director', value: _movie.director),
                                if (_movie.cast.isNotEmpty) InfoRow(label: 'Cast', value: _movie.cast),
                                if (_movie.youtubeTrailer.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  OutlineButtonX(
                                    label: 'Watch trailer',
                                    icon: Icons.ondemand_video,
                                    onPressed: _openTrailer,
                                  ),
                                ],
                              ],
                            ),
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
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.gold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.gold),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11.5)),
        ],
      ),
    );
  }
}
