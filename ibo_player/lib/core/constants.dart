/// Hive box names and store keys.
///
/// The key names intentionally mirror the schema observed in the
/// original application's local database (see docs/analysis/04-storage-schema.md)
/// so that the recreation is behaviourally comparable. They are plain schema
/// identifiers, not vendor content.
class HiveBoxes {
  /// Global settings / playlists / localisation table.
  static const settings = 'hive-ibo-tv-box';

  /// One content cache box per playlist, keyed by playlist id.
  static String content(String playlistId) => 'ibo-tv-$playlistId';

  /// Content box of the bundled demo playlist (`content('demo')`).
  static const demo = 'ibo-tv-demo';
}

class StoreKeys {
  static const theme = 'theme';
  static const languageCode = 'language-code';
  static const streamFormat = 'stream-format';
  static const subtitleSize = 'subtitle-size';
  static const subtitleEnabled = 'subtitle-enabled';
  static const lockCode = 'lock-code';
  static const playlists = 'playlists';
  static const recentPlaylistId = 'recent-playlist-id';
  static const apiUrl = 'api-url';
  static const apiUrls = 'api-urls';
  static const mainUrl = 'main-url';
  static const deviceId = 'windows-device-id';
  static const deviceKey = 'device-key';
  static const macAddress = 'mac-address';
  static const accountExpireDate = 'account-expire-date';

  /// Cached localisation table. The recreation reads its languages from
  /// `assets/languages/`; the key is recognised so an existing database is not
  /// mistaken for an unknown one.
  static const languages = 'languages';

  /// When the catalogue was last imported, as an ISO-8601 string, in the
  /// **settings** box.
  static const contentUpdateDate = 'saved-content-update-date';
  static const hideLiveCategories = 'hide-live-categories';
  static const hideVodCategories = 'hide-vod-categories';
  static const hideSeriesCategories = 'hide-series-categories';
  static const lockedChannels = 'locked-channels';
  static const lockedMovies = 'locked-movies';
  static const lockedSeries = 'locked-series';
  static const sortChannelType = 'sort-channel-type';
  static const categoryOrder = 'category-order';
  static const recentlyViewed = 'recently-viewed';
  static const recentlySearched = 'recent-search';
  static const windowSize = 'window-size';
  static const onboardingDone = 'onboarding-done';
}

class ContentKeys {
  static const channels = 'saved-channels';
  static const movies = 'saved-movies';
  static const series = 'saved-series';
  static const channelCategories = 'saved-channel-categories';
  static const movieCategories = 'saved-movie-categories';
  static const seriesCategories = 'saved-series-categories';
  static const watchedChannels = 'watched-channels';
  static const watchedMovies = 'watched-movies';
  static const watchedSeries = 'watched-series';
  static const favoriteChannels = 'favorite-channels';
  static const favoriteMovies = 'favorite-movies';
  static const favoriteSeries = 'favorite-series';
  static const continueMovies = 'continue-watch-movies';
  static const continueSeries = 'continue-watch-episods';
}
