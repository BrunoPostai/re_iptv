import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/constants.dart';
import '../../core/utils/artwork.dart';
import '../../core/utils/http.dart';
import '../models/models.dart';
import '../sources/playlist_source.dart';
import '../storage/app_storage.dart';

class PlaylistRepository {
  PlaylistRepository(this._storage, this._config);

  final AppStorage _storage;
  final AppConfig _config;
  final Dio _dio = createHttpClient();
  final Map<String, PlaylistSource> _sources = {};

  List<Playlist> get playlists => _storage.loadPlaylists();

  String? get activeId => _storage.recentPlaylistId;

  Playlist? get active {
    final id = activeId;
    if (id == null) return null;
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return playlists.isEmpty ? null : playlists.first;
  }

  Future<void> setActive(String id) async {
    await _storage.setRecentPlaylistId(id);
    await _storage.openContentBox(id);
    // Artwork in this playlist's data may name a host that no longer answers,
    // and the panel is where an image asks next. Set here as well as on every
    // lookup: the first frame can draw from the cache before anything is
    // fetched, and it should already know where to look.
    final playlist = active;
    if (playlist != null) {
      Artwork.usePanel(playlist.type == PlaylistType.xc ? playlist.host : null);
    }
  }

  Future<void> add(Playlist playlist) async {
    final list = playlists.toList()
      ..removeWhere((p) => p.id == playlist.id)
      ..add(playlist);
    await _storage.savePlaylists(list);
    await _storage.openContentBox(playlist.id);
    await setActive(playlist.id);
  }

  Future<void> update(Playlist playlist) async {
    final list = playlists.map((p) => p.id == playlist.id ? playlist : p).toList();
    await _storage.savePlaylists(list);
    _sources.remove(playlist.id);
  }

  Future<void> remove(String id) async {
    final list = playlists.where((p) => p.id != id).toList();
    await _storage.savePlaylists(list);
    _sources.remove(id);
    await _storage.closeContentBox(id);
    if (activeId == id && list.isNotEmpty) {
      await setActive(list.first.id);
    }
  }

  PlaylistSource sourceFor(Playlist playlist) {
    // Artwork is about to be read out of this playlist's data, and the URLs in
    // it may name a host that no longer answers; the panel is where an image
    // asks next. Set on every lookup rather than on creation, because switching
    // between playlists reuses the sources already built.
    Artwork.usePanel(playlist.type == PlaylistType.xc ? playlist.host : null);
    return _sources.putIfAbsent(
      playlist.id,
      () => switch (playlist.type) {
        PlaylistType.xc => XtreamSource(
            playlist,
            dio: _dio,
            userAgent: _config.player.userAgent,
            format: _storage.readSetting(StoreKeys.streamFormat, _config.player.streamFormat),
          ),
        _ => M3uSource(playlist, dio: _dio, userAgent: _config.player.userAgent),
      },
    );
  }

  /// Adds the bundled demo playlist when enabled and nothing is configured.
  Future<void> ensureDemoPlaylist() async {
    if (!_config.features.demoPlaylist || !_config.demoPlaylist.isUsable) return;
    if (playlists.isNotEmpty) return;
    final spec = _config.demoPlaylist;
    await add(Playlist(
      id: 'demo',
      name: spec.name,
      url: spec.url,
      username: spec.username,
      password: spec.password,
      type: playlistTypeFrom(spec.type),
      isDemo: true,
    ));
  }
}
