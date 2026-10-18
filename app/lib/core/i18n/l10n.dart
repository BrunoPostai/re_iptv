import 'dart:convert';

import 'package:flutter/services.dart';

/// Lightweight JSON-backed translations.
///
/// Files live in `assets/languages/<code>.json`:
/// ```json
/// { "code": "en", "name": "English", "words": { "settings": "Settings" } }
/// ```
/// Add a language by dropping a file in that folder and listing it in
/// `assets/languages/index.json` (or in `app_config.local.json`).
class L10n {
  const L10n({required this.code, required this.name, required this.words});

  final String code;
  final String name;
  final Map<String, String> words;

  static const fallbackCode = 'en';

  String t(String key) => words[key] ?? key;

  String format(String key, Map<String, Object?> args) {
    var value = t(key);
    args.forEach((k, v) => value = value.replaceAll('{$k}', '$v'));
    return value;
  }

  static Future<L10n> load(String code) async {
    try {
      final raw = await rootBundle.loadString('assets/languages/$code.json');
      final decoded = Map<String, dynamic>.from(json.decode(raw) as Map);
      return L10n(
        code: decoded['code']?.toString() ?? code,
        name: decoded['name']?.toString() ?? code,
        words: Map<String, String>.from(
          (decoded['words'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
        ),
      );
    } catch (_) {
      if (code != fallbackCode) return load(fallbackCode);
      return L10n(code: fallbackCode, name: 'English', words: await _embeddedDefaults());
    }
  }

  static Future<Map<String, String>> _embeddedDefaults() async {
    const keys = [
      'settings',
      'live_tv',
      'movies',
      'series',
      'replay',
      'change_playlist',
      'search',
      'favorite',
      'continue_watching',
      'select_playlist',
      'add_playlist',
      'remove_playlist',
      'search_hint',
    ];
    return {for (final k in keys) k: _defaults[k] ?? k};
  }

  static const Map<String, String> _defaults = {
    'settings': 'Settings',
    'live_tv': 'Live TV',
    'movies': 'Movies',
    'series': 'Series',
    'replay': 'Replay',
    'change_playlist': 'Change Playlist',
    'search': 'Search',
    'favorite': 'Favorite',
    'continue_watching': 'Continue Watching',
    'select_playlist': 'Select Playlist',
    'add_playlist': 'Add Playlist',
    'remove_playlist': 'Remove Playlist',
    'search_hint': 'Search...',
  };

  /// Languages listed in `assets/languages/index.json`.
  static Future<List<({String code, String name})>> available() async {
    try {
      final raw = await rootBundle.loadString('assets/languages/index.json');
      final list = json.decode(raw) as List;
      return [
        for (final e in list.whereType<Map>())
          (code: e['code'].toString(), name: e['name'].toString()),
      ];
    } catch (_) {
      return const [(code: 'en', name: 'English')];
    }
  }
}
