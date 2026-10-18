import 'package:flutter/material.dart';

import '../../data/sources/playlist_source.dart';
import '../content/content_browser.dart';

/// Series catalogue (poster grid + category sidebar).
class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ContentBrowserScreen(kind: ContentKind.series, heading: 'Series');
}
