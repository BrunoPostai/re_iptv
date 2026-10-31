import 'package:flutter_test/flutter_test.dart';
import 'package:re_iptv/core/platform/window_class.dart';

/// Which layout a width gets. The desktop window cannot be dragged narrower than
/// `window.min_width` (1024), so the three pane layout is not at risk from the
/// breakpoints; what these pin is that a phone never gets handed it.
void main() {
  test('a phone held upright is compact, a tablet is not', () {
    expect(WindowClass.fromWidth(360), WindowClass.compact); // small phone
    expect(WindowClass.fromWidth(411), WindowClass.compact); // Pixel-sized
    expect(WindowClass.fromWidth(768), WindowClass.medium); // tablet
  });

  test('the desktop minimum width lands on the desktop layout', () {
    expect(WindowClass.fromWidth(1024), WindowClass.expanded);
    expect(WindowClass.fromWidth(1280), WindowClass.expanded);
    expect(WindowClass.fromWidth(1024).isExpanded, isTrue);
  });

  test('each boundary belongs to the class above it', () {
    expect(WindowClass.fromWidth(599.5), WindowClass.compact);
    expect(WindowClass.fromWidth(600), WindowClass.medium);
    expect(WindowClass.fromWidth(1023.5), WindowClass.medium);
    expect(WindowClass.fromWidth(1024), WindowClass.expanded);
  });

  test('only compact changes the live screen', () {
    expect(WindowClass.fromWidth(360).isCompact, isTrue);
    expect(WindowClass.fromWidth(768).isCompact, isFalse);
    expect(WindowClass.fromWidth(1280).isCompact, isFalse);
  });
}
