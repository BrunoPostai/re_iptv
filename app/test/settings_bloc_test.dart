import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:re_iptv/blocs/settings_bloc.dart';
import 'package:re_iptv/core/config/app_config.dart';
import 'package:re_iptv/core/constants.dart';
import 'package:re_iptv/data/storage/app_storage.dart';

/// One remembered volume, whatever it was set on.
///
/// An earlier version kept live and on-demand volumes apart; setting 40% on a
/// channel and finding the next film at 20% reads as a bug no matter how it is
/// explained, so there is one number.
void main() {
  late Directory dir;
  late AppStorage storage;
  late SettingsBloc bloc;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('re_iptv_settings');
    Hive.init(dir.path);
    storage = AppStorage();
    // `AppStorage.init()` asks the platform for a support directory, which a test
    // cannot answer; the settings box is the only thing it would have opened.
    storage.settings = await Hive.openBox<dynamic>(HiveBoxes.settings);
    bloc = SettingsBloc(storage, AppConfig.fromJson(const {}));
  });

  tearDown(() async {
    await bloc.close();
    await Hive.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Waits for the handler to have run, then reads the state it left.
  Future<SettingsState> settle() async {
    await Future<void>.delayed(Duration.zero);
    return bloc.state;
  }

  test('a volume is remembered under the one key', () async {
    bloc.add(const VolumeChanged(35));
    await settle();

    expect(bloc.state.volume, 35);
    expect(storage.readSetting<double>(StoreKeys.volume, 0), 35);
  });

  test('the last volume wins, whatever it was set on', () async {
    bloc.add(const VolumeChanged(40));
    bloc.add(const VolumeChanged(65));
    final state = await settle();

    expect(state.volume, 65);
    expect(storage.readSetting<double>(StoreKeys.volume, 0), 65);
  });

  test('an out-of-range volume is clamped before it is stored', () async {
    bloc.add(const VolumeChanged(150));
    await settle();
    expect(bloc.state.volume, 100);
    expect(storage.readSetting<double>(StoreKeys.volume, 0), 100);

    bloc.add(const VolumeChanged(-20));
    await settle();
    expect(bloc.state.volume, 0);
    expect(storage.readSetting<double>(StoreKeys.volume, 0), 0);
  });

  test('starting reads back what was left behind', () async {
    await storage.writeSetting(StoreKeys.volume, 12.0);

    bloc.add(const SettingsStarted());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.volume, 12);
  });
}
