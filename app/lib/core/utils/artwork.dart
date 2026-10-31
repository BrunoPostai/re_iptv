import 'formatters.dart';

/// Where to look for artwork the playlist's own data cannot serve.
///
/// An Xtream panel names each channel logo by full URL, and often names a host
/// that is not the panel: a CDN of its own, or the address the panel had before
/// it moved. When that host starts answering a bot challenge — every client is
/// told `403` — or goes away altogether, every row turns into a placeholder
/// letter while the panel goes on serving the same files under the same paths.
/// One retry against the panel is enough to recover them, and this is where its
/// address waits for the widgets that hold a URL but no playlist to ask.
abstract final class Artwork {
  static String? _panel;

  /// Remembers the panel the current playlist talks to, or forgets the last one
  /// when given null. An M3U playlist names its own hosts and has no panel to
  /// fall back to.
  static void usePanel(String? host) => _panel = _origin(host);

  /// The same path asked of the panel instead, or null when there is nothing
  /// better to try: no panel, a local file, or a URL already on the panel.
  static String? mirror(String url) {
    final panel = _panel;
    if (panel == null || !isRemote(url)) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || _origin(url) == panel) return null;
    return '$panel${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
  }
}

/// `scheme://host[:port]` with no trailing slash, or null when the string is not
/// an absolute URL. The port is kept only when it was written, so that
/// `http://host/` and `http://host:80/` are not the one address twice.
String? _origin(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
}
