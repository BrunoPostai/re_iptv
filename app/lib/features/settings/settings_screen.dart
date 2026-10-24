import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/playlist_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/i18n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/sources/playlist_source.dart';
import '../../data/storage/app_storage.dart';
import '../../widgets/common.dart';
import '../../widgets/nav_tile.dart';
import '../../widgets/title_bar.dart';
import '../playlist/playlist_screen.dart';

/// Application settings, presented as a grid of tiles like the original.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();
    final features = config.features;
    final settings = context.watch<SettingsBloc>().state;
    final l10n = settings.l10n;

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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ScreenHeading(title: l10n.t('settings'), subtitle: config.branding.appName),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        if (features.userAccount)
                          _settingsTile(
                            context,
                            width: 210,
                            height: 128,
                            label: l10n.t('user_account'),
                            icon: Icons.account_box_outlined,
                            onTap: () => _showAccount(context),
                          ),
                        if (features.themes)
                          _settingsTile(
                            context,
                            width: 210,
                            height: 128,
                            label: l10n.t('change_theme'),
                            icon: Icons.palette_outlined,
                            value: settings.theme.name,
                            onTap: () => _showThemes(context),
                          ),
                        if (features.languages)
                          _settingsTile(
                            context,
                            width: 210,
                            height: 128,
                            label: l10n.t('change_language'),
                            icon: Icons.translate,
                            value: settings.l10n.name,
                            onTap: () => _showLanguages(context),
                          ),
                        if (features.streamFormat)
                          _settingsTile(
                            context,
                            width: 210,
                            height: 128,
                            label: l10n.t('stream_format'),
                            icon: Icons.settings_input_component,
                            value: _streamFormatLabel(settings.streamFormat),
                            onTap: () => _showStreamFormat(context),
                          ),
                        if (features.subtitleSettings)
                          _settingsTile(
                            context,
                            width: 210,
                            height: 128,
                            label: l10n.t('subtitle_settings'),
                            icon: Icons.subtitles_outlined,
                            value: '${settings.subtitleSize} pt',
                            onTap: () => _showSubtitleSettings(context),
                          ),
                        _settingsTile(
                          context,
                          width: 210,
                          height: 128,
                          label: l10n.t('volume'),
                          icon: Icons.volume_up_outlined,
                          value: '${settings.volume.round()}%',
                          onTap: () => _showVolume(context),
                        ),
                        if (features.parentalControl)
                          _settingsTile(
                            context,
                            width: 210,
                            height: 128,
                            label: l10n.t('parental_control'),
                            icon: Icons.lock_outline,
                            value: settings.pin.isEmpty ? 'Disabled' : 'PIN set',
                            onTap: () => _showParental(context),
                          ),
                        _settingsTile(
                          context,
                          width: 210,
                          height: 128,
                          label: l10n.t('hide_live_categories'),
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _showHideCategories(context, ContentKind.live),
                        ),
                        _settingsTile(
                          context,
                          width: 210,
                          height: 128,
                          label: l10n.t('hide_movie_categories'),
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _showHideCategories(context, ContentKind.movie),
                        ),
                        _settingsTile(
                          context,
                          width: 210,
                          height: 128,
                          label: l10n.t('hide_series_categories'),
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _showHideCategories(context, ContentKind.series),
                        ),
                        _settingsTile(
                          context,
                          width: 210,
                          height: 128,
                          label: l10n.t('change_playlist'),
                          icon: Icons.playlist_play,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PlaylistScreen()),
                          ),
                        ),
                        _settingsTile(
                          context,
                          width: 210,
                          height: 128,
                          label: l10n.t('clear_cache'),
                          icon: Icons.cleaning_services_outlined,
                          onTap: () => _clearCache(context),
                        ),
                        _settingsTile(
                          context,
                          width: 210,
                          height: 128,
                          label: l10n.t('about'),
                          icon: Icons.info_outline,
                          onTap: () => _showAbout(context),
                        ),
                      ],
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

  Widget _settingsTile(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required double width,
    required double height,
    String? value,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: SettingsTile(label: label, icon: icon, value: value, onTap: onTap),
    );
  }

  static String _streamFormatLabel(String format) => switch (format) {
        'm3u8' => 'HLS (m3u8)',
        'ts' => 'MPEG-TS',
        'default' => 'Default',
        _ => format,
      };

  // ------------------------------------------------------------------ dialogs

  Future<void> _showThemes(BuildContext context) async {
    final config = getIt<AppConfig>();
    final settings = context.read<SettingsBloc>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change theme', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 560,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final theme in config.themes)
                GestureDetector(
                  onTap: () {
                    settings.add(ThemeChanged(theme.id));
                    Navigator.of(dialogContext).pop();
                  },
                  child: Container(
                    width: 168,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.id == settings.state.theme.id
                            ? AppColors.gold
                            : AppColors.divider,
                        width: theme.id == settings.state.theme.id ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 84,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.asset(
                              theme.background,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: Color(theme.accent).withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          theme.name,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguages(BuildContext context) async {
    final settings = context.read<SettingsBloc>();
    final languages = await L10n.available();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change language', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          height: 380,
          child: ListView.builder(
            itemCount: languages.length,
            itemBuilder: (context, index) {
              final language = languages[index];
              final selected = language.code == settings.state.languageCode;
              return ListTile(
                dense: true,
                title: Text(
                  language.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? AppColors.gold : AppColors.textPrimary,
                  ),
                ),
                trailing: selected ? const Icon(Icons.check, size: 16, color: AppColors.gold) : null,
                onTap: () {
                  settings.add(LanguageChanged(language.code));
                  Navigator.of(dialogContext).pop();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _showStreamFormat(BuildContext context) async {
    final settings = context.read<SettingsBloc>();
    const options = {
      'default': 'Default (as provided by the server)',
      'm3u8': 'HLS (m3u8) — best compatibility',
      'ts': 'MPEG-TS — lowest latency',
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stream format', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in options.entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    settings.state.streamFormat == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: settings.state.streamFormat == entry.key
                        ? AppColors.gold
                        : AppColors.textMuted,
                  ),
                  title: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                  ),
                  onTap: () => settings.add(StreamFormatChanged(entry.key)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSubtitleSettings(BuildContext context) async {
    final settings = context.read<SettingsBloc>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final size = settings.state.subtitleSize;
          return AlertDialog(
            title: const Text('Subtitle settings', style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Subtitle size',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                  Slider(
                    value: size.toDouble(),
                    min: 10,
                    max: 60,
                    divisions: 50,
                    label: '$size pt',
                    activeColor: AppColors.gold,
                    inactiveColor: Colors.white24,
                    onChanged: (value) {
                      settings.add(SubtitleSizeChanged(value.round()));
                      setState(() {});
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Preview subtitle text',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size.toDouble(),
                        shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done', style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showVolume(BuildContext context) async {
    final settings = context.read<SettingsBloc>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final volume = settings.state.volume.clamp(0.0, 100.0).toDouble();
          return AlertDialog(
            title: const Text('Playback volume', style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'The volume new live channels and movies open at. You can still '
                    'change it while watching.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                  Slider(
                    value: volume,
                    max: 100,
                    divisions: 20,
                    label: '${volume.round()}%',
                    activeColor: AppColors.gold,
                    inactiveColor: Colors.white24,
                    onChanged: (value) {
                      settings.add(VolumeChanged(value.roundToDouble()));
                      setState(() {});
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        volume == 0 ? Icons.volume_off : Icons.volume_up_outlined,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${volume.round()}%',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done', style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showParental(BuildContext context) async {
    final settings = context.read<SettingsBloc>();
    final controller = TextEditingController(text: settings.state.pin);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Parental control', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Set a 4 to 6 digit PIN. Categories marked as hidden will require it.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(hintText: 'PIN', counterText: ''),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('Disable', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, elevation: 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) settings.add(PinChanged(result));
  }

  Future<void> _showHideCategories(BuildContext context, ContentKind kind) async {
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) return;
    final categories = await getIt<ContentRepository>().categories(playlist, kind);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) => AlertDialog(
          title: Text(
            'Hide ${kind == ContentKind.live ? 'live' : kind == ContentKind.movie ? 'movie' : 'series'} categories',
            style: const TextStyle(fontSize: 16),
          ),
          content: SizedBox(
            width: 460,
            height: 420,
            child: categories.isEmpty
                ? const Text(
                    'No categories found. Refresh the playlist first.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  )
                : ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final hidden = state.isHidden(category.id);
                      return CheckboxListTile(
                        dense: true,
                        value: hidden,
                        activeColor: AppColors.gold,
                        title: Text(
                          category.name,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                        ),
                        onChanged: (_) => context
                            .read<SettingsBloc>()
                            .add(CategoryVisibilityToggled(kind, category.id)),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done', style: TextStyle(color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final playlist = getIt<PlaylistRepository>().active;
    if (playlist == null) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Clear cache',
      message: 'Delete cached channels, movies and series? They will be downloaded again.',
    );
    if (!confirmed || !context.mounted) return;
    await getIt<ContentRepository>().clearPlaylistCache(playlist);
    if (context.mounted) {
      context.read<PlaylistBloc>().add(const PlaylistsSynced(force: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared. Refreshing...')),
      );
    }
  }

  Future<void> _showAbout(BuildContext context) async {
    final config = getIt<AppConfig>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(config.branding.appName, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                config.branding.disclaimer,
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                config.branding.noSellNotice,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              SelectableText(
                config.branding.website,
                style: const TextStyle(fontSize: 12, color: AppColors.gold),
              ),
              const SizedBox(height: 12),
              // The `data\app.so` timestamp: the quickest way to tell whether the
              // build on disk is the one in use. Closing the window without
              // restarting keeps the old build running.
              InfoRow(label: 'Build', value: buildStamp()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccount(BuildContext context) async {
    final storage = getIt<AppStorage>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('User account', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoRow(label: 'Device Key', value: storage.deviceKey, color: AppColors.gold),
              InfoRow(label: 'Mac Address', value: storage.macAddress),
              InfoRow(label: 'Device Id', value: storage.deviceId),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}