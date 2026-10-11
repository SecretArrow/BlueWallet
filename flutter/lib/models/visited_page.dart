/// A single visited page for the browser Startpage (last 10).
class VisitedPage {
  final String url;
  final String title;
  final String domain;
  final int visitedAtMs;

  const VisitedPage({
    required this.url,
    required this.title,
    required this.domain,
    required this.visitedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'domain': domain,
        'visitedAtMs': visitedAtMs,
      };

  static VisitedPage? fromJson(dynamic v) {
    try {
      if (v is! Map) return null;
      final url = v['url']?.toString() ?? '';
      if (url.isEmpty) return null;
      return VisitedPage(
        url: url,
        title: v['title']?.toString() ?? '',
        domain: v['domain']?.toString() ?? '',
        visitedAtMs: v['visitedAtMs'] is num
            ? (v['visitedAtMs'] as num).toInt()
            : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Domain for display: host lowercased, `www.` stripped.
  static String domainOf(String url) {
    try {
      final uri = Uri.parse(url);
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      if (host.isNotEmpty) return host;
      if (uri.scheme == 'oct') {
        final rest = url.substring('oct://'.length);
        return rest.split('/').first.toLowerCase();
      }
    } catch (_) {}
    return url;
  }
}
