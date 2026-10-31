import 'package:flutter/widgets.dart';

/// How much room the app has been given to draw in.
///
/// The desktop window is never narrower than 1024 (`window.min_width` in
/// `app_config.json`), so it always lands on [expanded] and keeps the layout it
/// has always had. Everything below that is a tablet or a phone, where panes
/// that sit side by side on the desktop have to take turns.
enum WindowClass {
  /// A phone held upright: one pane at a time.
  compact,

  /// A tablet, or a phone turned sideways: two panes fit.
  medium,

  /// The desktop window, where every pane is on screen at once.
  expanded;

  static WindowClass of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  /// The same test against a width, for widgets that measure themselves with a
  /// [LayoutBuilder] rather than the whole screen.
  static WindowClass fromWidth(double width) {
    if (width < 600) return compact;
    if (width < 1024) return medium;
    return expanded;
  }

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;
}
