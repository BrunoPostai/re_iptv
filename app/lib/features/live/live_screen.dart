import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/content_bloc.dart';
import '../../blocs/playlist_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
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

  Future<void> _select(Channel channel) async {
    setState(() {
      _selected = channel;
      _epg = const [];
      _loadingEpg = true;
    });
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) {
      setState(() => _loadingEpg = false);
      return;
    }
    final programs = await getIt<ContentRepository>().shortEpg(playlist, channel.streamId);
    if (!mounted) return;
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
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) return;
    final source = getIt<PlaylistRepository>().sourceFor(playlist);
    final url = source.liveUrl(channel);
    if (url.isEmpty) return;

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
    if (mounted) {
      await getIt<ContentRepository>().markWatched(playlist, ContentKind.live, channel.streamId);
      if (mounted) context.read<ContentBloc>().add(const ContentReloaded());
    }
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
    required this.onPlay,
  });

  final Channel? channel;
  final List<EpgProgram> epg;
  final bool loading;
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
                  Center(
                    child: SizedBox(
                      width: 180,
                      height: 120,
                      child: SmartImage(path: channel!.icon, fallbackText: channel!.name),
                    ),
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
                  Expanded(
                    child: loading
                        ? const LoadingBlock()
                        : epg.isEmpty
                            ? const Text(
                                'No programme information available for this channel.',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                              )
                            : ListView.builder(
                                itemCount: epg.length,
                                itemBuilder: (context, index) {
                                  final program = epg[index];
                                  final now = program.isNow;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      color: now
                                          ? AppColors.blue.withValues(alpha: 0.28)
                                          : Colors.black.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: now ? AppColors.gold : AppColors.divider,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_time(program.start)} - ${_time(program.end)}',
                                          style: TextStyle(
                                            color: now ? AppColors.gold : AppColors.textMuted,
                                            fontSize: 10.5,
                                            fontWeight: now ? FontWeight.w700 : FontWeight.w400,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          program.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
    );
  }

  static String _time(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}