import 'package:flutter_test/flutter_test.dart';
import 'package:re_iptv/core/utils/artwork.dart';

/// What an image does when the host in the playlist's own data refuses it.
///
/// The panel is not guessed: it is the address the playlist was entered with,
/// and the retry keeps the path the provider gave, because a panel that moved
/// its logos keeps serving them where they always were.
void main() {
  tearDown(() => Artwork.usePanel(null));

  test('a logo on another host is asked of the panel instead', () {
    Artwork.usePanel('https://inter2.example');
    expect(
      Artwork.mirror('http://cdn.example/logo/53084.jpg'),
      'https://inter2.example/logo/53084.jpg',
    );
  });

  test('the path and its query are kept, the host is not', () {
    Artwork.usePanel('http://panel.example:8080');
    expect(
      Artwork.mirror('http://cdn.example/img/a.png?w=300&h=200'),
      'http://panel.example:8080/img/a.png?w=300&h=200',
    );
  });

  test('a trailing slash on the panel does not become two', () {
    Artwork.usePanel('http://panel.example///');
    expect(Artwork.mirror('http://cdn.example/logo/1.jpg'), 'http://panel.example/logo/1.jpg');
  });

  test('an image already on the panel is not retried against itself', () {
    Artwork.usePanel('http://panel.example');
    expect(Artwork.mirror('http://panel.example/logo/1.jpg'), isNull);
  });

  test('a port that was written is part of the address', () {
    Artwork.usePanel('http://panel.example:8080');
    expect(Artwork.mirror('http://panel.example:8080/logo/1.jpg'), isNull);
    expect(Artwork.mirror('http://panel.example/logo/1.jpg'), 'http://panel.example:8080/logo/1.jpg');
  });

  test('there is nothing to retry without a panel', () {
    expect(Artwork.mirror('http://cdn.example/logo/1.jpg'), isNull);
    Artwork.usePanel(null);
    expect(Artwork.mirror('http://cdn.example/logo/1.jpg'), isNull);
  });

  test('an M3U playlist forgets the panel it replaced', () {
    Artwork.usePanel('https://inter2.example');
    Artwork.usePanel(null);
    expect(Artwork.mirror('http://cdn.example/logo/1.jpg'), isNull);
  });

  test('a local file or an empty path is left alone', () {
    Artwork.usePanel('https://inter2.example');
    expect(Artwork.mirror('C:\\Users\\me\\logo.png'), isNull);
    expect(Artwork.mirror('assets/branding/logo.png'), isNull);
    expect(Artwork.mirror(''), isNull);
  });
}
