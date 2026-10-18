import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Deep-merges [override] onto [base] (maps only, lists are replaced).
Map<String, dynamic> deepMerge(Map<String, dynamic> base, Map<String, dynamic>? override) {
  if (override == null) return base;
  final out = Map<String, dynamic>.from(base);
  override.forEach((key, value) {
    final existing = out[key];
    if (existing is Map && value is Map) {
      out[key] = deepMerge(Map<String, dynamic>.from(existing), Map<String, dynamic>.from(value));
    } else {
      out[key] = value;
    }
  });
  return out;
}

class FeatureFlags {
  final bool live;
  final bool movies;
  final bool series;
  final bool replay;
  final bool changePlaylist;
  final bool search;
  final bool settings;
  final bool userAccount;
  final bool streamFormat;
  final bool subtitleSettings;
  final bool parentalControl;
  final bool themes;
  final bool languages;
  final bool sortOptions;
  final bool sportsGuide;
  final bool demoPlaylist;
  final bool trialNotice;
  final bool multiServerSwitch;

  const FeatureFlags({
    this.live = true,
    this.movies = true,
    this.series = true,
    this.replay = true,
    this.changePlaylist = true,
    this.search = true,
    this.settings = true,
    this.userAccount = false,
    this.streamFormat = true,
    this.subtitleSettings = true,
    this.parentalControl = true,
    this.themes = true,
    this.languages = true,
    this.sortOptions = true,
    this.sportsGuide = false,
    this.demoPlaylist = true,
    this.trialNotice = false,
    this.multiServerSwitch = false,
  });

  factory FeatureFlags.fromJson(Map<String, dynamic> j) => FeatureFlags(
        live: j['live'] as bool? ?? true,
        movies: j['movies'] as bool? ?? true,
        series: j['series'] as bool? ?? true,
        replay: j['replay'] as bool? ?? true,
        changePlaylist: j['change_playlist'] as bool? ?? true,
        search: j['search'] as bool? ?? true,
        settings: j['settings'] as bool? ?? true,
        userAccount: j['user_account'] as bool? ?? false,
        streamFormat: j['stream_format'] as bool? ?? true,
        subtitleSettings: j['subtitle_settings'] as bool? ?? true,
        parentalControl: j['parental_control'] as bool? ?? true,
        themes: j['themes'] as bool? ?? true,
        languages: j['languages'] as bool? ?? true,
        sortOptions: j['sort_options'] as bool? ?? true,
        sportsGuide: j['sports_guide'] as bool? ?? false,
        demoPlaylist: j['demo_playlist'] as bool? ?? true,
        trialNotice: j['trial_notice'] as bool? ?? false,
        multiServerSwitch: j['multi_server_switch'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'live': live,
        'movies': movies,
        'series': series,
        'replay': replay,
        'change_playlist': changePlaylist,
        'search': search,
        'settings': settings,
        'user_account': userAccount,
        'stream_format': streamFormat,
        'subtitle_settings': subtitleSettings,
        'parental_control': parentalControl,
        'themes': themes,
        'languages': languages,
        'sort_options': sortOptions,
        'sports_guide': sportsGuide,
        'demo_playlist': demoPlaylist,
        'trial_notice': trialNotice,
        'multi_server_switch': multiServerSwitch,
      };
}

class Branding {
  final String appName;
  final String windowTitle;
  final String logo;
  final String logoSmall;
  final String website;
  final String disclaimer;
  final String noSellNotice;

  const Branding({
    this.appName = 'REIPTV',
    this.windowTitle = 'REIPTV',
    this.logo = 'assets/branding/logo.png',
    this.logoSmall = 'assets/branding/logo_small.png',
    this.website = 'https://example.com',
    this.disclaimer =
        'This application is a general purpose media player and does not include any content. '
            'You must provide your own playlists and are responsible for the content you use.',
    this.noSellNotice = 'This application does not sell playlists or subscriptions.',
  });

  factory Branding.fromJson(Map<String, dynamic> j) => Branding(
        appName: j['app_name'] as String? ?? 'REIPTV',
        windowTitle: j['window_title'] as String? ?? 'REIPTV',
        logo: j['logo'] as String? ?? 'assets/branding/logo.png',
        logoSmall: j['logo_small'] as String? ?? 'assets/branding/logo_small.png',
        website: j['website'] as String? ?? 'https://example.com',
        disclaimer: j['disclaimer'] as String? ?? Branding().disclaimer,
        noSellNotice: j['no_sell_notice'] as String? ?? Branding().noSellNotice,
      );

  Map<String, dynamic> toJson() => {
        'app_name': appName,
        'window_title': windowTitle,
        'logo': logo,
        'logo_small': logoSmall,
        'website': website,
        'disclaimer': disclaimer,
        'no_sell_notice': noSellNotice,
      };
}

class ThemeSpec {
  final String id;
  final String name;
  final String background;
  final int accent;
  final bool dark;

  const ThemeSpec({
    required this.id,
    required this.name,
    required this.background,
    this.accent = 0xFF2196F3,
    this.dark = true,
  });

  factory ThemeSpec.fromJson(Map<String, dynamic> j) => ThemeSpec(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        background: j['background'] as String? ?? 'assets/branding/bg_main.jpg',
        accent: _parseColor(j['accent'] as String?),
        dark: j['dark'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'background': background,
        'accent': '#${accent.toRadixString(16).padLeft(8, '0').substring(2)}',
        'dark': dark,
      };

  static int _parseColor(String? value) {
    if (value == null) return 0xFF2196F3;
    var v = value.replaceFirst('#', '');
    if (v.length == 6) v = 'FF$v';
    return int.tryParse(v, radix: 16) ?? 0xFF2196F3;
  }
}

class PlayerDefaults {
  final String streamFormat;
  final int subtitleSize;

  /// Volume applied when a stream is opened, as a percentage (0-100).
  ///
  /// Opening live channels at full volume is unpleasant, so this defaults low.
  final double defaultVolume;
  final bool hardwareDecoding;
  final bool startFullscreen;
  final String userAgent;

  const PlayerDefaults({
    this.streamFormat = 'default',
    this.subtitleSize = 20,
    this.defaultVolume = 20,
    this.hardwareDecoding = true,
    this.startFullscreen = false,
    this.userAgent = 'VLC/3.0.20 LibVLC/3.0.20',
  });

  factory PlayerDefaults.fromJson(Map<String, dynamic> j) => PlayerDefaults(
        streamFormat: j['stream_format'] as String? ?? 'default',
        subtitleSize: (j['subtitle_size'] as num?)?.toInt() ?? 20,
        defaultVolume: ((j['default_volume'] as num?)?.toDouble() ?? 20).clamp(0, 100),
        hardwareDecoding: j['hardware_decoding'] as bool? ?? true,
        startFullscreen: j['start_fullscreen'] as bool? ?? false,
        userAgent: j['user_agent'] as String? ?? 'VLC/3.0.20 LibVLC/3.0.20',
      );

  Map<String, dynamic> toJson() => {
        'stream_format': streamFormat,
        'subtitle_size': subtitleSize,
        'default_volume': defaultVolume,
        'hardware_decoding': hardwareDecoding,
        'start_fullscreen': startFullscreen,
        'user_agent': userAgent,
      };
}

class WindowSpec {
  final int width;
  final int height;
  final int minWidth;
  final int minHeight;
  final String titleBarStyle;

  const WindowSpec({
    this.width = 1280,
    this.height = 720,
    this.minWidth = 1024,
    this.minHeight = 576,
    this.titleBarStyle = 'custom',
  });

  factory WindowSpec.fromJson(Map<String, dynamic> j) => WindowSpec(
        width: (j['width'] as num?)?.toInt() ?? 1280,
        height: (j['height'] as num?)?.toInt() ?? 720,
        minWidth: (j['min_width'] as num?)?.toInt() ?? 1024,
        minHeight: (j['min_height'] as num?)?.toInt() ?? 576,
        titleBarStyle: j['title_bar_style'] as String? ?? 'custom',
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'min_width': minWidth,
        'min_height': minHeight,
        'title_bar_style': titleBarStyle,
      };
}

class DemoPlaylistSpec {
  final String name;
  final String url;
  final String username;
  final String password;
  final String type;

  const DemoPlaylistSpec({
    this.name = 'Demo',
    this.url = '',
    this.username = '',
    this.password = '',
    this.type = 'xc',
  });

  bool get isUsable => url.isNotEmpty;

  factory DemoPlaylistSpec.fromJson(Map<String, dynamic> j) => DemoPlaylistSpec(
        name: j['name'] as String? ?? 'Demo',
        url: j['url'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        type: j['type'] as String? ?? 'xc',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'type': type,
      };
}

class AppConfig {
  final Branding branding;
  final FeatureFlags features;
  final ThemeSpec defaultTheme;
  final List<ThemeSpec> themes;
  final PlayerDefaults player;
  final WindowSpec window;
  final String defaultLanguage;
  final List<String> apiBaseUrls;
  final DemoPlaylistSpec demoPlaylist;

  /// Optional directory holding `app_config.local.json` and `branding/local/`.
  /// Set from `main()`; lets a personal build override the bundled defaults
  /// without touching tracked files.
  static String? overrideDirectory;

  AppConfig({
    required this.branding,
    required this.features,
    required this.themes,
    required this.defaultTheme,
    required this.player,
    required this.window,
    required this.defaultLanguage,
    required this.apiBaseUrls,
    required this.demoPlaylist,
  });

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final themes = ((j['themes'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ThemeSpec.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final list = themes.isEmpty
        ? [
            const ThemeSpec(id: 'main', name: 'Background Main', background: 'assets/branding/bg_main.jpg'),
          ]
        : themes;
    final defaultId = j['default_theme'] as String? ?? list.first.id;
    return AppConfig(
      branding: Branding.fromJson(Map<String, dynamic>.from((j['branding'] as Map?) ?? const {})),
      features: FeatureFlags.fromJson(Map<String, dynamic>.from((j['features'] as Map?) ?? const {})),
      themes: list,
      defaultTheme: list.firstWhere((t) => t.id == defaultId, orElse: () => list.first),
      player: PlayerDefaults.fromJson(Map<String, dynamic>.from((j['player'] as Map?) ?? const {})),
      window: WindowSpec.fromJson(Map<String, dynamic>.from((j['window'] as Map?) ?? const {})),
      defaultLanguage: j['default_language'] as String? ?? 'en',
      apiBaseUrls: ((j['endpoints']?['api_base_urls'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      demoPlaylist:
          DemoPlaylistSpec.fromJson(Map<String, dynamic>.from((j['demo_playlist'] as Map?) ?? const {})),
    );
  }

  ThemeSpec themeById(String id) =>
      themes.firstWhere((t) => t.id == id, orElse: () => defaultTheme);

  /// Reads a JSON map from either an absolute file path or a bundled asset.
  ///
  /// Missing or malformed files are not fatal: personalisation is optional, so
  /// an unreadable overlay simply contributes nothing.
  static Future<Map<String, dynamic>> _loadMap(String source) async {
    try {
      if (source.contains(':') || source.startsWith('/') || source.startsWith(r'\')) {
        final file = File(source);
        if (!await file.exists()) return const {};
        return _decode(await file.readAsString());
      }
      return _decode(await rootBundle.loadString(source));
    } catch (_) {
      return const {};
    }
  }

  static Map<String, dynamic> _decode(String raw) {
    if (raw.trim().isEmpty) return const {};
    final decoded = json.decode(raw);
    if (decoded is! Map) return const {};
    return Map<String, dynamic>.from(decoded);
  }

  /// Bundled defaults, overlaid by an optional `app_config.local.json`
  /// (bundled asset or `overrideDirectory`), so personalisation survives pulls.
  static Future<AppConfig> load({String asset = 'assets/config/app_config.json'}) async {
    var merged = await _loadMap(asset);
    for (final candidate in [
      if (overrideDirectory != null) '$overrideDirectory${Platform.pathSeparator}app_config.local.json',
      'assets/config/app_config.local.json',
    ]) {
      final overlay = await _loadMap(candidate);
      if (overlay.isNotEmpty) merged = deepMerge(merged, overlay);
    }
    return AppConfig.fromJson(merged);
  }
}
