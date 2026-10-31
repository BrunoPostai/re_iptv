import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../blocs/playlist_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/storage/app_storage.dart';
import '../../widgets/common.dart';
import '../../widgets/title_bar.dart';

/// Playlist management: add, select, remove and inspect account details.
class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

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
            Expanded(
              child: BlocBuilder<PlaylistBloc, PlaylistState>(
                builder: (context, state) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                      child: Row(
                        children: [
                          Expanded(child: ScreenHeading(title: settings.l10n.t('change_playlist'))),
                          AccentButton(
                            label: settings.l10n.t('add_playlist'),
                            icon: Icons.add,
                            onPressed: () => _addPlaylist(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: state.playlists.isEmpty
                                ? const EmptyBlock(
                                    message: 'No playlists yet. Add an Xtream or M3U playlist.',
                                    icon: Icons.playlist_add,
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: state.playlists.length,
                                    itemBuilder: (context, index) {
                                      final playlist = state.playlists[index];
                                      return _PlaylistCard(
                                        playlist: playlist,
                                        active: playlist.id == state.active?.id,
                                        onSelect: () => context
                                            .read<PlaylistBloc>()
                                            .add(PlaylistSelected(playlist.id)),
                                        onRemove: () => _removePlaylist(context, playlist),
                                      );
                                    },
                                  ),
                          ),
                          _AccountPanel(state: state),
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

  Future<void> _addPlaylist(BuildContext context) async {
    final bloc = context.read<PlaylistBloc>();
    final playlist = await showDialog<Playlist>(
      context: context,
      builder: (_) => const AddPlaylistDialog(),
    );
    if (playlist != null) bloc.add(PlaylistAddedEvent(playlist));
  }

  Future<void> _removePlaylist(BuildContext context, Playlist playlist) async {
    final bloc = context.read<PlaylistBloc>();
    final confirmed = await confirmDialog(
      context,
      title: 'Remove playlist',
      message: 'Remove "${playlist.name}" and all of its cached content?',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await getIt<ContentRepository>().clearPlaylistCache(playlist);
    bloc.add(PlaylistRemovedEvent(playlist.id));
  }
}

class _PlaylistCard extends StatefulWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.active,
    required this.onSelect,
    required this.onRemove,
  });

  final Playlist playlist;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final playlist = widget.playlist;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.active
                ? palette.accent.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.active
                  ? palette.accent
                  : (_hovered ? Colors.white24 : AppColors.divider),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.accentDeep,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  playlist.type == PlaylistType.xc ? Icons.dns_outlined : Icons.list_alt,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.active)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      playlist.displayAccount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                    Text(
                      playlist.type == PlaylistType.xc ? 'Xtream Codes' : 'M3U playlist',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove playlist',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({required this.state});

  final PlaylistState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final storage = getIt<AppStorage>();
    final settings = context.watch<SettingsBloc>().state;
    final auth = state.auth;

    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(left: BorderSide(color: AppColors.divider)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DEVICE',
              style: TextStyle(
                color: palette.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            InfoRow(label: 'Mac Address', value: storage.macAddress),
            InfoRow(label: 'Device Key', value: storage.deviceKey, color: palette.accent),
            InfoRow(label: 'Device Id', value: storage.deviceId),
            const Divider(height: 30, color: AppColors.divider),
            Text(
              'ACCOUNT',
              style: TextStyle(
                color: palette.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            if (state.active == null)
              const Text(
                'No active playlist.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              )
            else ...[
              InfoRow(label: 'Playlist', value: state.active!.name),
              InfoRow(label: 'Host', value: state.active!.host),
              InfoRow(
                label: 'Expires on',
                value: auth?.expiryDateTime != null ? formatDate(auth!.expiryDateTime!) : '—',
                color: (auth?.expired ?? false) ? AppColors.red : AppColors.green,
              ),
              InfoRow(label: 'Status', value: auth?.status.isEmpty ?? true ? '—' : auth!.status),
              InfoRow(label: 'Connections', value: '${auth?.maxConnections ?? '—'}'),
              if (auth?.isTrial == true)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'TRIAL ACCOUNT',
                    style: TextStyle(color: palette.accentBright, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
            const Divider(height: 30, color: AppColors.divider),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    label: state.syncing ? 'Refreshing...' : 'Refresh content',
                    icon: Icons.refresh,
                    onPressed: state.syncing
                        ? null
                        : () => context.read<PlaylistBloc>().add(const PlaylistsSynced(force: true)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlineButtonX(
              label: 'Clear cached content',
              icon: Icons.cleaning_services_outlined,
              onPressed: state.active == null
                  ? null
                  : () async {
                      final playlist = state.active!;
                      final ok = await confirmDialog(
                        context,
                        title: 'Clear cache',
                        message: 'Delete the cached channels, movies and series for '
                            '"${playlist.name}"? They will be downloaded again on the next refresh.',
                      );
                      if (!ok || !context.mounted) return;
                      await getIt<ContentRepository>().clearPlaylistCache(playlist);
                      if (context.mounted) {
                        context.read<PlaylistBloc>().add(const PlaylistsSynced(force: true));
                      }
                    },
            ),
            const SizedBox(height: 20),
            Text(
              getIt<AppConfig>().branding.disclaimer,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Disconnect all playlists  ·  ${settings.l10n.t('profile_settings')}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for adding an Xtream Codes or M3U playlist.
class AddPlaylistDialog extends StatefulWidget {
  const AddPlaylistDialog({super.key});

  @override
  State<AddPlaylistDialog> createState() => _AddPlaylistDialogState();
}

class _AddPlaylistDialogState extends State<AddPlaylistDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _epg = TextEditingController();
  PlaylistType _type = PlaylistType.xc;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _epg.dispose();
    super.dispose();
  }

  String _normaliseUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  void _submit() {
    final url = _normaliseUrl(_url.text);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a name.');
      return;
    }
    if (url.isEmpty) {
      setState(() => _error = 'Please enter the playlist address.');
      return;
    }
    if (_type == PlaylistType.xc &&
        (_username.text.trim().isEmpty || _password.text.trim().isEmpty)) {
      setState(() => _error = 'Xtream playlists require a username and password.');
      return;
    }
    Navigator.of(context).pop(
      Playlist(
        id: const Uuid().v4(),
        name: _name.text.trim(),
        url: url,
        username: _username.text.trim(),
        password: _password.text.trim(),
        type: _type,
        epgUrl: _epg.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: const Text('Add playlist', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TypeChip(
                      label: 'Xtream Codes',
                      icon: Icons.dns_outlined,
                      selected: _type == PlaylistType.xc,
                      onTap: () => setState(() => _type = PlaylistType.xc),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeChip(
                      label: 'M3U / M3U8',
                      icon: Icons.list_alt,
                      selected: _type == PlaylistType.m3u,
                      onTap: () => setState(() => _type = PlaylistType.m3u),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Field(controller: _name, label: 'Playlist name'),
              const SizedBox(height: 10),
              _Field(
                controller: _url,
                label: _type == PlaylistType.xc ? 'Server address (http://host:port)' : 'M3U URL',
              ),
              if (_type == PlaylistType.xc) ...[
                const SizedBox(height: 10),
                _Field(controller: _username, label: 'Username'),
                const SizedBox(height: 10),
                _Field(controller: _password, label: 'Password', obscure: true),
              ],
              const SizedBox(height: 10),
              _Field(controller: _epg, label: 'EPG URL (optional)'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 11.5),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'Credentials are stored only on this device and are never sent anywhere else.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: inkOn(palette.accent),
            elevation: 0,
          ),
          child: const Text('Add playlist'),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, this.obscure = false});

  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 12)),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? palette.accent.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: selected ? palette.accent : AppColors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? palette.accent : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
