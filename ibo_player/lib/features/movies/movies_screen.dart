import 'package:flutter/material.dart';

import '../../data/sources/playlist_source.dart';
import '../content/content_browser.dart';

/// Movies catalogue (poster grid + category sidebar).
class MoviesScreen extends StatelessWidget {
  const MoviesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ContentBrowserScreen(kind: ContentKind.movie, heading: 'Movies');
}
