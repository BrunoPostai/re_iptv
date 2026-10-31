import 'package:flutter_test/flutter_test.dart';
import 'package:re_iptv/core/config/app_config.dart';

void main() {
  group('deepMerge', () {
    test('overrides only the keys that are present', () {
      final merged = deepMerge(
        {
          'branding': {'app_name': 'Default', 'website': 'https://default'},
          'window': {'width': 1280, 'height': 760},
        },
        {
          'branding': {'app_name': 'Mine'},
          'window': {'width': 1600},
        },
      );

      expect((merged['branding'] as Map)['app_name'], 'Mine');
      // Untouched keys survive.
      expect((merged['branding'] as Map)['website'], 'https://default');
      expect((merged['window'] as Map)['height'], 760);
      expect((merged['window'] as Map)['width'], 1600);
    });

    test('replaces lists wholesale instead of merging them', () {
      final merged = deepMerge(
        {
          'themes': [
            {'id': 'main'},
            {'id': 'honor'},
          ],
        },
        {
          'themes': [
            {'id': 'mine'},
          ],
        },
      );

      expect((merged['themes'] as List), hasLength(1));
      expect(((merged['themes'] as List).first as Map)['id'], 'mine');
    });

    test('ignores a null or empty overlay', () {
      final base = {
        'branding': {'app_name': 'Default'},
      };
      expect(deepMerge(base, null)['branding'], base['branding']);
      expect(deepMerge(base, const {})['branding'], base['branding']);
    });

    test('does not mutate its inputs', () {
      final base = {
        'window': {'width': 1280},
      };
      final overlay = {
        'window': {'width': 1920},
      };

      deepMerge(base, overlay);

      expect((base['window'] as Map)['width'], 1280);
      expect((overlay['window'] as Map)['width'], 1920);
    });
  });

  group('AppConfig defaults', () {
    test('produces a usable configuration from an empty document', () {
      final config = AppConfig.fromJson(const {});

      expect(config.branding.appName, isNotEmpty);
      expect(config.themes, isNotEmpty);
      expect(config.window.width, greaterThan(0));
      expect(config.window.minWidth, lessThanOrEqualTo(config.window.width));
      expect(config.player.subtitleSize, greaterThan(0));
      expect(config.features.live, isTrue);
    });

    test('resolves the active theme by id and falls back to the default', () {
      final config = AppConfig.fromJson(const {
        'default_theme': 'honor',
        'themes': [
          {'id': 'main', 'name': 'Main'},
          {'id': 'honor', 'name': 'Honor'},
        ],
      });

      expect(config.defaultTheme.id, 'honor');
      expect(config.themeById('main').name, 'Main');
      expect(config.themeById('does-not-exist').id, 'honor');
    });

    test('reads branding, features and window overrides', () {
      final config = AppConfig.fromJson(const {
        'branding': {'app_name': 'My TV'},
        'features': {'series': false},
        'window': {'width': 1500, 'title_bar_style': 'normal'},
      });

      expect(config.branding.appName, 'My TV');
      expect(config.features.series, isFalse);
      expect(config.window.width, 1500);
      expect(config.window.titleBarStyle, 'normal');
    });
  });

  group('LiveTuning', () {
    test('is inert by default, so nothing is applied unless configured', () {
      final tuning = LiveTuning.fromJson(const {});

      expect(tuning.isEmpty, isTrue);
      expect(tuning.cacheOnDisk, isNull);
    });

    test('reads the provider-specific switches', () {
      final tuning = LiveTuning.fromJson(const {
        'reconnect': true,
        'reconnect_delay_max': 15,
        'cache_on_disk': false,
        'user_agent': 'REIPTV/1.0',
        'properties': {'network-timeout': 15},
      });

      expect(tuning.reconnect, isTrue);
      expect(tuning.reconnectDelayMax, 15);
      expect(tuning.cacheOnDisk, isFalse);
      expect(tuning.userAgent, 'REIPTV/1.0');
      // Extra options are stringified, since that is what libmpv takes.
      expect(tuning.properties, {'network-timeout': '15'});
      expect(tuning.isEmpty, isFalse);
    });

    test('is read from the player block', () {
      final config = AppConfig.fromJson(const {
        'player': {
          'hardware_decoding': false,
          'live_tuning': {'reconnect': true},
        },
      });

      expect(config.player.hardwareDecoding, isFalse);
      expect(config.player.liveTuning.reconnect, isTrue);
      expect(config.player.liveTuning.cacheOnDisk, isNull);
    });
  });

  group('theme mark', () {
    test('a theme that names no mark keeps the branding one', () {
      const branding = Branding();
      final theme = ThemeSpec.fromJson(const {
        'id': 'main',
        'name': 'Background Main',
        'background': '',
      });

      expect(theme.logoFor(branding), branding.logo);
      expect(theme.logoSmallFor(branding), branding.logoSmall);
    });

    test('a theme that names its own mark is drawn in its colours', () {
      const branding = Branding();
      final theme = ThemeSpec.fromJson(const {
        'id': 'honor',
        'name': 'Gold Honor',
        'background': '',
        'logo': 'assets/branding/logo_honor.png',
        'logo_small': 'assets/branding/logo_honor_small.png',
      });

      expect(theme.logoFor(branding), 'assets/branding/logo_honor.png');
      expect(theme.logoSmallFor(branding), 'assets/branding/logo_honor_small.png');
    });

    test('the mark survives a round trip through json', () {
      final theme = ThemeSpec.fromJson(const {
        'id': 'black',
        'name': 'Solid Black',
        'background': '',
        'logo': 'assets/branding/logo_black.png',
      });

      final again = ThemeSpec.fromJson(theme.toJson());
      expect(again.logo, 'assets/branding/logo_black.png');
      expect(again.logoSmall, isNull);
    });
  });
}
