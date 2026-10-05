/// Pure helpers for the native `oct://` circle protocol.
///
/// Octra circle URLs look like `oct://<circleId>/<path>` (a bare circle ID
/// defaults to `/index.html`, mirroring the local web server `/oct/`
/// gateway). Parsing is manual — never `Uri` — so base58 circle IDs keep
/// their case. No Flutter, no network: fully unit-testable.
class OctCircleRef {
  final String circleId;
  final String path;
  const OctCircleRef(this.circleId, this.path);
}

class OctUrl {
  static const scheme = 'oct://';

  OctUrl._();

  static bool isOctUrl(String url) =>
      url.toLowerCase().startsWith(scheme);

  /// Split into [circleId, path]. Throws [ArgumentError] on empty input.
  static OctCircleRef parse(String url) {
    if (!isOctUrl(url)) {
      throw ArgumentError('Not an oct:// URL: "$url"');
    }
    var rest = url.substring(scheme.length);
    final cut = rest.indexOf(RegExp(r'[?#]'));
    if (cut != -1) rest = rest.substring(0, cut);
    final idx = rest.indexOf('/');
    if (idx == -1) {
      if (rest.isEmpty) {
        throw ArgumentError('oct:// URL has no circle ID: "$url"');
      }
      return OctCircleRef(rest, '/index.html');
    }
    var path = rest.substring(idx);
    if (path.isEmpty || path == '/') path = '/index.html';
    final circleId = rest.substring(0, idx);
    if (circleId.isEmpty) {
      throw ArgumentError('oct:// URL has no circle ID: "$url"');
    }
    return OctCircleRef(circleId, path);
  }

  /// Local gateway URL served by the embedded web server.
  static String gatewayHttpUrl(String circleId, String path,
      {int port = 8420}) {
    if (circleId.isEmpty) {
      throw ArgumentError('circleId must not be empty');
    }
    final p = path.isEmpty ? '/index.html' : path;
    return 'http://127.0.0.1:$port/oct/$circleId$p';
  }

  /// MIME types safe to render inline as text in a WebView.
  static bool isTextMime(String mime) =>
      mime.startsWith('text/') ||
      mime.contains('javascript') ||
      mime.contains('json') ||
      mime.endsWith('+xml') ||
      mime == 'image/svg+xml';

  /// Strip parameters (`;charset=…`) and fall back safely.
  static String cleanMime(String? raw) {
    var mime = (raw ?? '').trim();
    final semi = mime.indexOf(';');
    if (semi != -1) mime = mime.substring(0, semi).trim();
    if (mime.isEmpty) return 'application/octet-stream';
    return mime;
  }
}
