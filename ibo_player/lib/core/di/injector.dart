import 'package:get_it/get_it.dart';

import '../config/app_config.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/storage/app_storage.dart';

final GetIt getIt = GetIt.instance;

/// Wires the data layer. Blocs are created by the widget tree so that they can
/// be scoped and disposed with the screens that own them.
Future<void> configureDependencies(AppConfig config) async {
  getIt.registerSingleton<AppConfig>(config);

  final storage = AppStorage();
  await storage.init();
  getIt.registerSingleton<AppStorage>(storage);

  final playlists = PlaylistRepository(storage, config);
  getIt.registerSingleton<PlaylistRepository>(playlists);

  getIt.registerSingleton<ContentRepository>(ContentRepository(storage, playlists));
}
