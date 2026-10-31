import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../blocs/playlist_bloc.dart';
import '../../blocs/settings_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../data/storage/app_storage.dart';
import '../../widgets/common.dart';
import '../home_screen.dart';

/// Boot screen: shows branding, local device identity and playlist sync
/// progress, then hands over to the home screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _version = '';
  Timer? _fallback;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    context.read<PlaylistBloc>().add(const PlaylistsStarted());
    // Never trap the user on the splash screen if a playlist server hangs.
    _fallback = Timer(const Duration(seconds: 45), _goHome);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      if (mounted) setState(() => _version = '1.0.4');
    }
  }

  void _goHome() {
    if (!mounted || _navigated) return;
    _navigated = true;
    _fallback?.cancel();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final config = getIt<AppConfig>();
    final storage = getIt<AppStorage>();
    // The boot screen is the first frame of the chosen theme, not of the
    // default one: the picture and the mark should already be the pair the
    // viewer picked.
    final theme = context.watch<SettingsBloc>().state.theme;

    return Scaffold(
      body: AppBackground(
        image: theme.background,
        child: BlocListener<PlaylistBloc, PlaylistState>(
          listenWhen: (previous, current) =>
              previous.ready != current.ready ||
              previous.syncing != current.syncing ||
              previous.error != current.error ||
              previous.active != current.active,
          listener: (context, state) {
            if (state.error != null) {
              _goHome();
            } else if (state.ready && !state.syncing) {
              _goHome();
            }
          },
          child: Column(
            children: [
              const SizedBox(height: 30),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 110,
                        child: Image.asset(
                          theme.logoFor(config.branding),
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.play_circle_outline,
                            size: 84,
                            color: palette.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        config.branding.appName,
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'version $_version',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 34),
                      _IdentityPanel(
                        mac: storage.macAddress,
                        deviceKey: storage.deviceKey,
                        deviceId: storage.deviceId,
                      ),
                      const SizedBox(height: 30),
                      BlocBuilder<PlaylistBloc, PlaylistState>(
                        builder: (context, state) {
                          if (state.error != null) {
                            return SizedBox(
                              width: fitWidth(context, 360),
                              child: Text(
                                'No playlist available. Add one to start watching.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                              ),
                            );
                          }
                          if (state.active == null) {
                            return SizedBox(
                              width: fitWidth(context, 360),
                              child: Text(
                                'Preparing...',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                              ),
                            );
                          }
                          if (state.syncing) {
                            return SizedBox(
                              width: fitWidth(context, 360),
                              child: Column(
                                children: [
                                  LinearProgressIndicator(
                                    value: state.syncProgress == 0 ? null : state.syncProgress,
                                    minHeight: 4,
                                    backgroundColor: Colors.white12,
                                    valueColor: AlwaysStoppedAnimation(palette.accent),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _stageLabel(state.syncStage),
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  config.branding.disclaimer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _stageLabel(String stage) => switch (stage) {
        'authenticating' || 'connecting' => 'Connecting to playlist...',
        'live' => 'Loading live channels...',
        'movies' => 'Loading movies...',
        'series' => 'Loading series...',
        'ready' => 'Ready',
        'failed' => 'Could not reach the playlist',
        _ => 'Preparing...',
      };
}

class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({required this.mac, required this.deviceKey, required this.deviceId});

  final String mac;
  final String deviceKey;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: fitWidth(context, 430),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          InfoRow(label: 'Mac Address', value: mac),
          InfoRow(label: 'Device Key', value: deviceKey, color: palette.accent),
          InfoRow(label: 'Device Id', value: deviceId.isEmpty ? '—' : deviceId),
        ],
      ),
    );
  }
}
