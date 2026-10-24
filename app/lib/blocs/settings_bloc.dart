import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/app_config.dart';
import '../../core/constants.dart';
import '../../core/i18n/l10n.dart';
import '../../data/sources/playlist_source.dart';
import '../../data/storage/app_storage.dart';

class SettingsState extends Equatable {
  final L10n l10n;
  final ThemeSpec theme;
  final String languageCode;
  final String streamFormat;
  final int subtitleSize;

  /// Volume (0-100) live channels open at.
  final double volume;

  /// Volume (0-100) films and episodes open at, kept apart from [volume].
  final double vodVolume;
  final String pin;
  final Set<String> hiddenCategories;
  final String sortType;
  final String syncStage;
  final double syncProgress;
  final bool ready;

  const SettingsState({
    required this.l10n,
    required this.theme,
    this.languageCode = 'en',
    this.streamFormat = 'default',
    this.subtitleSize = 20,
    this.volume = 20,
    this.vodVolume = 20,
    this.pin = '',
    this.hiddenCategories = const {},
    this.sortType = 'default',
    this.syncStage = '',
    this.syncProgress = 0,
    this.ready = false,
  });

  SettingsState copyWith({
    L10n? l10n,
    ThemeSpec? theme,
    String? languageCode,
    String? streamFormat,
    int? subtitleSize,
    double? volume,
    double? vodVolume,
    String? pin,
    Set<String>? hiddenCategories,
    String? sortType,
    String? syncStage,
    double? syncProgress,
    bool? ready,
  }) =>
      SettingsState(
        l10n: l10n ?? this.l10n,
        theme: theme ?? this.theme,
        languageCode: languageCode ?? this.languageCode,
        streamFormat: streamFormat ?? this.streamFormat,
        subtitleSize: subtitleSize ?? this.subtitleSize,
        volume: volume ?? this.volume,
        vodVolume: vodVolume ?? this.vodVolume,
        pin: pin ?? this.pin,
        hiddenCategories: hiddenCategories ?? this.hiddenCategories,
        sortType: sortType ?? this.sortType,
        syncStage: syncStage ?? this.syncStage,
        syncProgress: syncProgress ?? this.syncProgress,
        ready: ready ?? this.ready,
      );

  bool isHidden(String categoryId) => hiddenCategories.contains(categoryId);

  @override
  List<Object?> get props => [
        l10n,
        theme,
        languageCode,
        streamFormat,
        subtitleSize,
        volume,
        vodVolume,
        pin,
        hiddenCategories,
        sortType,
        syncStage,
        syncProgress,
        ready,
      ];
}

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override
  List<Object?> get props => [];
}

class SettingsStarted extends SettingsEvent {
  const SettingsStarted();
}

class ThemeChanged extends SettingsEvent {
  const ThemeChanged(this.themeId);
  final String themeId;
  @override
  List<Object?> get props => [themeId];
}

class LanguageChanged extends SettingsEvent {
  const LanguageChanged(this.code);
  final String code;
  @override
  List<Object?> get props => [code];
}

class StreamFormatChanged extends SettingsEvent {
  const StreamFormatChanged(this.format);
  final String format;
  @override
  List<Object?> get props => [format];
}

class SubtitleSizeChanged extends SettingsEvent {
  const SubtitleSizeChanged(this.size);
  final int size;
  @override
  List<Object?> get props => [size];
}

/// Which remembered volume a change is for.
///
/// Live channels and films are kept apart, so muting a channel that was left
/// running does not leave the next film silent.
enum VolumeScope { live, video }

class VolumeChanged extends SettingsEvent {
  const VolumeChanged(this.volume, {this.scope = VolumeScope.live});
  final double volume;
  final VolumeScope scope;
  @override
  List<Object?> get props => [volume, scope];
}

class PinChanged extends SettingsEvent {
  const PinChanged(this.pin);
  final String pin;
  @override
  List<Object?> get props => [pin];
}

class CategoryVisibilityToggled extends SettingsEvent {
  const CategoryVisibilityToggled(this.kind, this.categoryId);
  final ContentKind kind;
  final String categoryId;
  @override
  List<Object?> get props => [kind, categoryId];
}

class SortTypeChanged extends SettingsEvent {
  const SortTypeChanged(this.sortType);
  final String sortType;
  @override
  List<Object?> get props => [sortType];
}

class SyncProgressChanged extends SettingsEvent {
  const SyncProgressChanged(this.stage, this.progress);
  final String stage;
  final double progress;
  @override
  List<Object?> get props => [stage, progress];
}

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(this._storage, this._config)
      : super(SettingsState(
          l10n: const L10n(code: 'en', name: 'English', words: {}),
          theme: _config.defaultTheme,
        )) {
    on<SettingsStarted>(_onStarted);
    on<ThemeChanged>(_onThemeChanged);
    on<LanguageChanged>(_onLanguageChanged);
    on<StreamFormatChanged>(_onStreamFormatChanged);
    on<SubtitleSizeChanged>(_onSubtitleSizeChanged);
    on<VolumeChanged>(_onVolumeChanged);
    on<PinChanged>(_onPinChanged);
    on<CategoryVisibilityToggled>(_onCategoryVisibilityToggled);
    on<SortTypeChanged>(_onSortTypeChanged);
    on<SyncProgressChanged>(_onSyncProgressChanged);
  }

  final AppStorage _storage;
  final AppConfig _config;

  Future<void> _onStarted(SettingsStarted event, Emitter<SettingsState> emit) async {
    final code = _storage.readSetting(StoreKeys.languageCode, _config.defaultLanguage);
    final l10n = await L10n.load(code);
    final themeId = _storage.readSetting(StoreKeys.theme, _config.defaultTheme.id);
    emit(state.copyWith(
      l10n: l10n,
      languageCode: code,
      theme: _config.themeById(themeId),
      streamFormat: _storage.readSetting(StoreKeys.streamFormat, _config.player.streamFormat),
      subtitleSize: _storage.readSetting(StoreKeys.subtitleSize, _config.player.subtitleSize),
      volume: _storage.readSetting<double>(StoreKeys.volume, _config.player.defaultVolume),
      vodVolume:
          _storage.readSetting<double>(StoreKeys.vodVolume, _config.player.defaultVolume),
      pin: _storage.readSetting(StoreKeys.lockCode, ''),
      sortType: _storage.readSetting(StoreKeys.sortChannelType, 'default'),
      hiddenCategories: _storage.readStringList(StoreKeys.hideLiveCategories).toSet(),
      ready: true,
    ));
  }

  Future<void> _onThemeChanged(ThemeChanged event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(theme: _config.themeById(event.themeId)));
    await _storage.writeSetting(StoreKeys.theme, event.themeId);
  }

  Future<void> _onLanguageChanged(LanguageChanged event, Emitter<SettingsState> emit) async {
    final l10n = await L10n.load(event.code);
    emit(state.copyWith(l10n: l10n, languageCode: event.code));
    await _storage.writeSetting(StoreKeys.languageCode, event.code);
  }

  Future<void> _onStreamFormatChanged(
      StreamFormatChanged event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(streamFormat: event.format));
    await _storage.writeSetting(StoreKeys.streamFormat, event.format);
  }

  Future<void> _onSubtitleSizeChanged(SubtitleSizeChanged event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(subtitleSize: event.size));
    await _storage.writeSetting(StoreKeys.subtitleSize, event.size);
  }

  Future<void> _onVolumeChanged(VolumeChanged event, Emitter<SettingsState> emit) async {
    final volume = event.volume.clamp(0, 100).toDouble();
    final live = event.scope == VolumeScope.live;
    emit(state.copyWith(volume: live ? volume : null, vodVolume: live ? null : volume));
    await _storage.writeSetting(live ? StoreKeys.volume : StoreKeys.vodVolume, volume);
  }

  Future<void> _onPinChanged(PinChanged event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(pin: event.pin));
    await _storage.writeSetting(StoreKeys.lockCode, event.pin);
  }

  Future<void> _onCategoryVisibilityToggled(
      CategoryVisibilityToggled event, Emitter<SettingsState> emit) async {
    final key = switch (event.kind) {
      ContentKind.live => StoreKeys.hideLiveCategories,
      ContentKind.movie => StoreKeys.hideVodCategories,
      ContentKind.series => StoreKeys.hideSeriesCategories,
    };
    final all = <String>{
      ..._storage.readStringList(StoreKeys.hideLiveCategories),
      ..._storage.readStringList(StoreKeys.hideVodCategories),
      ..._storage.readStringList(StoreKeys.hideSeriesCategories),
    };
    final kindSpecific = _storage.readStringList(key).toSet();
    if (!kindSpecific.remove(event.categoryId)) {
      kindSpecific.add(event.categoryId);
    }
    all
      ..remove(event.categoryId)
      ..addAll(kindSpecific);
    emit(state.copyWith(hiddenCategories: all));
    await _storage.writeStringList(key, kindSpecific.toList());
  }

  Future<void> _onSortTypeChanged(SortTypeChanged event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(sortType: event.sortType));
    await _storage.writeSetting(StoreKeys.sortChannelType, event.sortType);
  }

  Future<void> _onSyncProgressChanged(
      SyncProgressChanged event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(syncStage: event.stage, syncProgress: event.progress));
  }
}
