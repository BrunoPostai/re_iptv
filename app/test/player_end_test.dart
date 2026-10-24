import 'package:flutter_test/flutter_test.dart';
import 'package:re_iptv/blocs/player_bloc.dart';

/// The end of a stream that mpv never announces.
///
/// `eof-reached` was never reported for the provider's streams: playback ran out
/// of data at the end of an episode and mpv sat there calling itself idle, which
/// `media_kit` reports as buffering — the spinner that never stopped. This rule
/// is what the player uses instead, and every case below is one it has to get
/// right: ending a film early or late are both worse than the spinner.
void main() {
  const hour = Duration(hours: 1);

  /// An hour-long stream, `at` into it, playing and buffering as given.
  bool ended(
    Duration at, {
    Duration duration = hour,
    bool playing = true,
    bool buffering = false,
    bool isLive = false,
  }) =>
      hasEndedPlayback(
        position: at,
        duration: duration,
        playing: playing,
        buffering: buffering,
        isLive: isLive,
      );

  test('a stream waiting for data at its end has ended', () {
    // mpv is not paused — it is idle because the file ran out, which media_kit
    // reports as buffering. This is the reported hang.
    expect(ended(hour, buffering: true), isTrue);
    expect(ended(hour - const Duration(seconds: 2), buffering: true), isTrue);
  });

  test('a stream that plays past its reported end has ended when it stops', () {
    expect(ended(hour + const Duration(minutes: 5), buffering: true), isTrue);
  });

  test('a stream stalled half way through has not ended', () {
    expect(ended(const Duration(minutes: 30), buffering: true), isFalse);
    expect(ended(hour - const Duration(minutes: 1), buffering: true), isFalse);
  });

  test('the viewer pausing is not the end', () {
    expect(ended(const Duration(minutes: 30), playing: false), isFalse);
    // Even at the end: paused is paused, and it is not waiting for anything.
    expect(ended(hour - const Duration(seconds: 1), playing: false), isFalse);
  });

  test('still playing at the reported end is not the end', () {
    // A duration shorter than the film must not cut it off.
    expect(ended(hour), isFalse);
    expect(ended(hour + const Duration(minutes: 1)), isFalse);
  });

  test('a live channel never ends', () {
    expect(ended(hour, buffering: true, isLive: true), isFalse);
  });

  test('a clip too short to resume is left alone', () {
    expect(
      ended(const Duration(seconds: 20), duration: const Duration(seconds: 20), buffering: true),
      isFalse,
    );
  });
}
