import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/playlist_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/i18n/l10n.dart';
import '../../core/platform/window_class.dart';
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
    // A 210 pixel tile in a 26 pixel margin leaves a phone with a single column
    // and a stripe of nothing beside it, so on a phone two tiles share the
    // width, as they do on the desktop at its narrowest.
    final compact = WindowClass.of(context).isCompact;
    final tileWidth = compact
        ? ((MediaQuery.sizeOf(context).width - 52 - 16) / 2).clamp(140.0, 210.0)
        : 210.0;

    return Scaffold(
      body: AppBackground(
        image: settings.theme.background,
        child: Column(
          children: [
            AppTitleBar(
              title: config.branding.windowTitle,
              logo: settings.theme.logoSmallFor(config.branding),
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
                            width: tileWidth,
                            height: 128,
                            label: l10n.t('user_account'),
                            icon: Icons.account_box_outlined,
                            onTap: () => _showAccount(context),
                          ),
                        if (features.themes)
                          _settingsTile(
                            context,
                            width: tileWidth,
                            height: 128,
                            label: l10n.t('change_theme'),
                            icon: Icons.palette_outlined,
                            value: settings.theme.name,
                            onTap: () => _showThemes(context),
                          ),
                        if (features.languages)
                          _settingsTile(
                            context,
                            width: tileWidth,
                            height: 128,
                            label: l10n.t('change_language'),
                            icon: Icons.translate,
                            value: settings.l10n.name,
                            onTap: () => _showLanguages(context),
                          ),
                        if (features.streamFormat)
                          _settingsTile(
                            context,
                            width: tileWidth,
                            height: 128,
                            label: l10n.t('stream_format'),
                            icon: Icons.settings_input_component,
                            value: _streamFormatLabel(settings.streamFormat),
                            onTap: () => _showStreamFormat(context),
                          ),
                        if (features.subtitleSettings)
                          _settingsTile(
                            context,
                            width: tileWidth,
                            height: 128,
                            label: l10n.t('subtitle_settings'),
                            icon: Icons.subtitles_outlined,
                            value: '${settings.subtitleSize} pt',
                            onTap: () => _showSubtitleSettings(context),
                          ),
                        _settingsTile(
                          context,
                          width: tileWidth,
                          height: 128,
                          label: l10n.t('volume'),
                          icon: Icons.volume_up_outlined,
                          value: '${settings.volume.round()}%',
                          onTap: () => _showVolume(context),
                        ),
                        if (features.parentalControl)
                          _settingsTile(
                            context,
                            width: tileWidth,
                            height: 128,
                            label: l10n.t('parental_control'),
                            icon: Icons.lock_outline,
                            value: settings.pin.isEmpty ? 'Disabled' : 'PIN set',
                            onTap: () => _showParental(context),
                          ),
                        _settingsTile(
                          context,
                          width: tileWidth,
                          height: 128,
                          label: l10n.t('hide_live_categories'),
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _showHideCategories(context, ContentKind.live),
                        ),
                        _settingsTile(
                          context,
                          width: tileWidth,
                          height: 128,
                          label: l10n.t('hide_movie_categories'),
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _showHideCategories(context, ContentKind.movie),
                        ),
                        _settingsTile(
                          context,
                          width: tileWidth,
                          height: 128,
                          label: l10n.t('hide_series_categories'),
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _showHideCategories(context, ContentKind.series),
                        ),
                        _settingsTile(
                          context,
                          width: tileWidth,
                          height: 128,
                          label: l10n.t('change_playlist'),
                          icon: Icons.playlist_play,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PlaylistScreen()),
                          ),
                        ),
                        _settingsTile(
                          context,
                          width: tileWidth,
                          height: 128,
                          label: l10n.t('clear_cache'),
                          icon: Icons.cleaning_services_outlined,
                          onTap: () => _clearCache(context),
                        ),
                        _settingsTile(
                          context,
                          width: tileWidth,
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
    final palette = context.palette;
    final config = getIt<AppConfig>();
    final settings = context.read<SettingsBloc>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change theme', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: fitWidth(context, 560, inset: 128),
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
                            ? palette.accent
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Image.asset(
                                theme.logoSmallFor(config.branding),
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                theme.name,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                              ),
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
    final palette = context.palette;
    final settings = context.read<SettingsBloc>();
    final languages = await L10n.available();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change language', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: fitWidth(context, 420, inset: 128),
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
                    color: selected ? palette.accent : AppColors.textPrimary,
                  ),
                ),
                trailing: selected ? Icon(Icons.check, size: 16, color: palette.accent) : null,
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
    final palette = context.palette;
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
          width: fitWidth(context, 420, inset: 128),
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
                        ? palette.accent
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
    final palette = context.palette;
    final settings = context.read<SettingsBloc>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final size = settings.state.subtitleSize;
          return AlertDialog(
            title: const Text('Subtitle settings', style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: fitWidth(context, 420, inset: 128),
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
                    activeColor: palette.accent,
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
              width: fitWidth(context, 420, inset: 128),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'The volume a stream opens at, live or on demand. Changing it '
                    'while watching is what is remembered next time.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 12),
                  _VolumeSlider(
                    label: 'Every stream, live or on demand',
                    volume: volume,
                    onChanged: (value) {
                      settings.add(VolumeChanged(value));
                      setState(() {});
                    },
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
    final palette = context.palette;
    final settings = context.read<SettingsBloc>();
    final controller = TextEditingController(text: settings.state.pin);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Parental control', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: fitWidth(context, 380, inset: 128),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: inkOn(palette.accent),
              elevation: 0,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) settings.add(PinChanged(result));
  }

  Future<void> _showHideCategories(BuildContext context, ContentKind kind) async {
    final palette = context.palette;
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
            width: fitWidth(context, 460, inset: 128),
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
                        activeColor: palette.accent,
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
    final palette = context.palette;
    final config = getIt<AppConfig>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(config.branding.appName, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: fitWidth(context, 460, inset: 128),
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
                style: TextStyle(fontSize: 12, color: palette.accent),
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
    final palette = context.palette;
    final storage = getIt<AppStorage>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('User account', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: fitWidth(context, 420, inset: 128),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoRow(label: 'Device Key', value: storage.deviceKey, color: palette.accent),
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
/// One remembered volume, as a slider with its own read-out.
class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.label,
    required this.volume,
    required this.onChanged,
  });

  final String label;
  final double volume;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5)),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: volume,
                max: 100,
                divisions: 20,
                label: '${volume.round()}%',
                activeColor: palette.accent,
                inactiveColor: Colors.white24,
                onChanged: (value) => onChanged(value.roundToDouble()),
              ),
            ),
            Icon(
              volume == 0 ? Icons.volume_off : Icons.volume_up_outlined,
              size: 18,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              child: Text(
                '${volume.round()}%',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
