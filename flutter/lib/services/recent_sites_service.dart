import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/visited_page.dart';

/// Stores the last 10 visited browser pages (most-recent first).
///
/// - Upsert with dedup: revisiting a URL moves it to the front and refreshes
///   its timestamp/title instead of duplicating.
/// - Filtered: `about:blank`, browser error pages, internal schemes
///   (`about:`, `chrome:`, `edge:`, `javascript:`, `data:`, `blob:`, `file:`),
///   and empty URLs are never recorded.
/// - Persisted in SharedPreferences (`recent_sites_v1`) so the list survives
///   restarts. Best-effort: storage failures keep the in-memory list for the
///   session and log without secrets.
/// - Privacy: callers pass `private: true` (private mode) to skip recording;
///   [clearAll] wipes the list and is called from clear-cache / clear-data
///   flows.
class RecentSitesService extends ChangeNotifier {
  static const String storeKey = 'recent_sites_v1';
  static const int maxEntries = 10;

  static final RecentSitesService instance = RecentSitesService._();
  factory RecentSitesService() => instance;
  RecentSitesService._();

  final List<VisitedPage> _pages = [];
  bool _loaded = false;
  String? _error;

  List<VisitedPage> get pages => List.unmodifiable(_pages);
  bool get isLoaded => _loaded;
  bool get isEmpty => _pages.isEmpty;

  /// Last load failure, rendered by the Startpage error state (with a
  /// retry). Non-null only after a failed [load]; cleared on retry.
  String? get error => _error;

  /// Load persisted history. Idempotent after a successful load; a FAILED
  /// load can be retried (that is what the Startpage retry button does).
  /// Failures are logged and exposed via [error] — never swallowed.
  Future<void> load() async {
    if (_loaded && _error == null) return;
    _error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storeKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final p = VisitedPage.fromJson(item);
            if (p != null && _isRecordable(p.url)) _pages.add(p);
          }
          _pages.sort((a, b) => b.visitedAtMs.compareTo(a.visitedAtMs));
          while (_pages.length > maxEntries) {
            _pages.removeLast();
          }
        }
      }
    } catch (e) {
      _pages.clear();
      _error = 'Could not load recent sites: $e';
      debugPrint('[RecentSites] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Record a successful navigation. No-op for filtered URLs or when
  /// [private] is true (private mode). Never throws.
  Future<void> record(String url,
      {String title = '', bool private = false}) async {
    if (private) return;
    final trimmed = url.trim();
    if (!_isRecordable(trimmed)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final domain = VisitedPage.domainOf(trimmed);
    // Dedup: drop any existing entry for the same URL, insert fresh at front.
    _pages.removeWhere((p) => p.url == trimmed);
    _pages.insert(
        0,
        VisitedPage(
            url: trimmed,
            title: title.trim(),
            domain: domain,
            visitedAtMs: now));
    while (_pages.length > maxEntries) {
      _pages.removeLast();
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String url) async {
    final before = _pages.length;
    _pages.removeWhere((p) => p.url == url);
    if (_pages.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    if (_pages.isEmpty) return;
    _pages.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storeKey);
    } catch (_) {
      debugPrint('[RecentSites] clear failed (storage unavailable?)');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          storeKey, jsonEncode(_pages.map((p) => p.toJson()).toList()));
    } catch (_) {
      debugPrint('[RecentSites] persist failed (storage unavailable?)');
    }
  }

  /// Pure filter so tests cover it without storage. Case-insensitive.
  static bool isRecordableUrl(String url) => _isRecordable(url);

  static bool _isRecordable(String url) {
    if (url.isEmpty) return false;
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower == 'about:blank') return false;
    // Browser error pages (Chromium + WebView).
    if (lower.startsWith('chrome-error://') ||
        lower.startsWith('edge-error://') ||
        lower.startsWith('about:error') ||
        lower.startsWith('about:neterror')) {
      return false;
    }
    // Internal / non-remote schemes.
    for (final prefix in [
      'about:',
      'chrome:',
      'chrome-error:',
      'edge:',
      'javascript:',
      'data:',
      'blob:',
      'file:',
      'content:',
    ]) {
      if (lower.startsWith(prefix)) return false;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    // Sensitive query leakage guard: never record URLs carrying obvious
    // secrets in the query string (token, key, seed, mnemonic, password).
    final q = uri.query.toLowerCase();
    for (final marker in [
      'mnemonic',
      'seed',
      'privatekey',
      'private_key',
      'password',
      'passwd',
    ]) {
      if (q.contains(marker)) return false;
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return uri.host.isNotEmpty;
    }
    if (lower.startsWith('oct://')) return true;
    return false;
  }
}
