import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:re_iptv/blocs/settings_bloc.dart';
import 'package:re_iptv/core/config/app_config.dart';
import 'package:re_iptv/core/constants.dart';
import 'package:re_iptv/data/storage/app_storage.dart';

/// Live channels and films remember their volume apart from one another: a
/// channel left running in the background should not decide how loud the next
/// film opens, and muting that channel should not leave it silent either.
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

  test('each kind is remembered under its own key', () async {
    bloc.add(const VolumeChanged(35));
    await settle();
    bloc.add(const VolumeChanged(70, scope: VolumeScope.video));
    await settle();

    expect(bloc.state.volume, 35);
    expect(bloc.state.vodVolume, 70);
    expect(storage.readSetting<double>(StoreKeys.volume, 0), 35);
    expect(storage.readSetting<double>(StoreKeys.vodVolume, 0), 70);
  });

  test('changing one kind leaves the other alone', () async {
    bloc.add(const VolumeChanged(35));
    bloc.add(const VolumeChanged(70, scope: VolumeScope.video));
    await settle();

    bloc.add(const VolumeChanged(0, scope: VolumeScope.video));
    final state = await settle();
    expect(state.vodVolume, 0, reason: 'a muted film');
    expect(state.volume, 35, reason: 'the channel volume is untouched');

    bloc.add(const VolumeChanged(15));
    final after = await settle();
    expect(after.volume, 15);
    expect(after.vodVolume, 0);
  });

  test('an out-of-range volume is clamped before it is stored', () async {
    bloc.add(const VolumeChanged(150));
    await settle();
    expect(bloc.state.volume, 100);
    expect(storage.readSetting<double>(StoreKeys.volume, 0), 100);
  });

  test('starting reads back what was left behind', () async {
    await storage.writeSetting(StoreKeys.volume, 12.0);
    await storage.writeSetting(StoreKeys.vodVolume, 64.0);

    bloc.add(const SettingsStarted());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.volume, 12);
    expect(bloc.state.vodVolume, 64);
  });
}
