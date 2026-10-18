import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/content_bloc.dart';
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
import '../../widgets/search_field.dart';
import '../../widgets/title_bar.dart';
import '../player/player_screen.dart';

/// Catch-up / replay: pick an archive channel, a date and a start time.
class ReplayScreen extends StatelessWidget {
  const ReplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsBloc>().state;
    return BlocProvider<ContentBloc>(
      create: (_) => ContentBloc(
        getIt<ContentRepository>(),
        getIt<PlaylistRepository>(),
      )..add(ContentStarted(ContentKind.live, sortType: settings.sortType)),
      child: const _ReplayBody(),
    );
  }
}

class _ReplayBody extends StatefulWidget {
  const _ReplayBody();

  @override
  State<_ReplayBody> createState() => _ReplayBodyState();
}

class _ReplayBodyState extends State<_ReplayBody> {
  Channel? _selected;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay(hour: 12, minute: 0);
  int _duration = 60;

  bool get _hasArchive => _selected?.hasArchive ?? false;

  Future<void> _play() async {
    final channel = _selected;
    if (channel == null) return;
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) return;
    final start = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    final url = getIt<PlaylistRepository>().sourceFor(playlist).timeshiftUrl(channel, start, _duration);
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catch-up is not available for this playlist type.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: MediaItem(
            title: channel.name,
            subtitle: 'Catch up · ${formatDate(start)} ${_time.format(context)}',
            image: channel.icon,
            url: url,
            streamId: channel.streamId,
            kind: 'live',
            parentId: channel.streamId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();
    final settings = context.watch<SettingsBloc>().state;
    final window = _selected?.archiveDuration ?? 7;

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
                  const Expanded(child: ScreenHeading(title: 'Catch Up')),
                  SearchField(
                    width: 250,
                    hint: settings.l10n.t('search_hint'),
                    onChanged: (value) =>
                        context.read<ContentBloc>().add(ContentQueryChanged(value)),
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
                    ),
                    Expanded(child: _buildChannelList(state)),
                    _ReplayPanel(
                      channel: _selected,
                      date: _date,
                      time: _time,
                      duration: _duration,
                      maxDays: window,
                      onDate: (value) => setState(() => _date = value),
                      onTime: (value) => setState(() => _time = value),
                      onDuration: (value) => setState(() => _duration = value),
                      onPlay: _hasArchive ? _play : null,
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

  Widget _buildChannelList(ContentState state) {
    if (state.loading && state.rows.isEmpty) {
      return const LoadingBlock(message: 'Loading channels...');
    }
    if (state.error != null && state.rows.isEmpty) {
      return ErrorBlock(
        message: state.error!,
        onRetry: () => context.read<ContentBloc>().add(const ContentRefreshed()),
      );
    }
    final archived = state.channels.where((c) => c.hasArchive).toList();
    if (archived.isEmpty) {
      return const EmptyBlock(
        message: 'No catch-up channels for this playlist.',
        icon: Icons.history_toggle_off,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: archived.length,
      itemBuilder: (context, index) {
        final channel = archived[index];
        return ChannelRow(
          name: channel.name,
          image: channel.icon,
          number: channel.num == 0 ? index + 1 : channel.num,
          onTap: () => setState(() {
            _selected = channel;
            _duration = (channel.archiveDuration * 60).clamp(15, 240);
          }),
          trailing: Text(
            '${channel.archiveDuration}d',
            style: const TextStyle(color: AppColors.gold, fontSize: 11),
          ),
        );
      },
    );
  }
}

class _ReplayPanel extends StatelessWidget {
  const _ReplayPanel({
    required this.channel,
    required this.date,
    required this.time,
    required this.duration,
    required this.maxDays,
    required this.onDate,
    required this.onTime,
    required this.onDuration,
    required this.onPlay,
  });

  final Channel? channel;
  final DateTime date;
  final TimeOfDay time;
  final int duration;
  final int maxDays;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<TimeOfDay> onTime;
  final ValueChanged<int> onDuration;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CATCH UP',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            if (channel == null)
              const Text(
                'Select a channel with a catch-up icon to replay a past programme.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              )
            else ...[
              Text(
                channel!.name,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Available for ${channel!.archiveDuration} days',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
              const Divider(height: 26, color: AppColors.divider),
              const Text('Start', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text(formatDate(date), style: const TextStyle(fontSize: 12)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime.now().subtract(Duration(days: maxDays.clamp(1, 60))),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) onDate(picked);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 14),
                      label: Text(
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: time);
                        if (picked != null) onTime(picked);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Duration', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              Slider(
                value: duration.toDouble(),
                min: 15,
                max: 240,
                divisions: (240 - 15) ~/ 15,
                label: formatMinutes(duration),
                activeColor: AppColors.gold,
                inactiveColor: Colors.white24,
                onChanged: (value) => onDuration(value.round()),
              ),
              Text(
                formatMinutes(duration),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
              const SizedBox(height: 18),
              AccentButton(label: 'Play catch up', icon: Icons.play_arrow, onPressed: onPlay),
            ],
          ],
        ),
      ),
    );
  }
}