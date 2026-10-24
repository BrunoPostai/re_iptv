/// Hive box names and store keys.
///
/// The **key names** mirror the schema observed in the original application's
/// local database (see docs/analysis/04-storage-schema.md) so that the two are
/// behaviourally comparable — they are plain schema identifiers, not vendor
/// content. The **box file names** carry this project's own neutral prefix.
class HiveBoxes {
  /// Global settings / playlists / localisation table.
  static const settings = 'hive-re-iptv-box';

  /// One content cache box per playlist, keyed by playlist id.
  static String content(String playlistId) => 're-iptv-$playlistId';

  /// Content box of the bundled demo playlist (`content('demo')`).
  static const demo = 're-iptv-demo';
}

class StoreKeys {
  static const theme = 'theme';
  static const languageCode = 'language-code';
  static const streamFormat = 'stream-format';
  static const subtitleSize = 'subtitle-size';

  /// Volume new streams open at, as a percentage.
  ///
  /// One value for every kind of stream: changing the volume while watching
  /// anything is what the next thing opens at.
  static const volume = 'volume';
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

  /// Prefix of the guide listings kept in a content box: one entry per channel per
  /// day, keyed `epg-<date>-<streamId>`, so a day's entries can be found and
  /// dropped by key alone.
  static const epg = 'epg';
}

/// How long a search box waits for typing to pause before it filters.
///
/// Filtering lower-cases the name of every item in the catalogue, which is felt
/// per keystroke on a large playlist, so a query is only worth running once the
/// user has stopped moving.
const searchDebounce = Duration(milliseconds: 320);

/// How much playback may be lost if the app is closed rather than backed out of.
///
/// Progress is written as it goes, so this is the most the resume position can
/// be behind where the viewer actually stopped.
const progressSaveInterval = Duration(seconds: 10);

/// How long a channel's guide is remembered after a panel answered with no
/// listings at all.
///
/// A day's listings never change once the panel has answered them, so a channel
/// that returned programmes is asked for once and served from memory after that.
/// An empty answer is as likely to be a request that failed as a channel without
/// a guide, so it is retried rather than remembered for the day.
const epgEmptyRetry = Duration(minutes: 10);

/// How many channels' guides are held in memory.
///
/// Each is a few dozen small programmes, but a long browse can touch a whole
/// playlist; past this the channel fetched longest ago is dropped. The store keeps
/// the same channels as memory — whatever is let go of here is let go of there —
/// so a browse cannot fill the disk either.
const epgCacheLimit = 250;

/// How many channels below the selected one the guide is fetched for in the
/// background, [epgPrefetchGap] apart.
const epgPrefetchAhead = 4;

/// Pause between background guide requests, so moving down the list does not
/// read to the panel as a burst.
const epgPrefetchGap = Duration(milliseconds: 400);
