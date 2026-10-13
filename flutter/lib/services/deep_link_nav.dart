import 'package:flutter/foundation.dart';

/// Tiny intent bus connecting context-free deep-link handling (app state)
/// to the browser tab.
///
/// The dApp browser lives inside MainScreen's IndexedStack — it is a tab,
/// not a GoRouter route — so a deep link cannot simply "push a browser
/// route". Instead the app-state deep-link handler calls [requestOpen];
/// [MainScreen] listens to switch to the Browser tab and
/// `DappBrowserScreen` listens to load the URL (then clears it via
/// [consumePending]).
///
/// Cold start: a link may arrive before MainScreen/the browser exist.
/// [requestOpen] stores the URL; MainScreen selects the Browser tab on
/// mount and the browser consumes the stored URL in its first post-frame
/// callback.
class DeepLinkNav extends ChangeNotifier {
  /// Singleton — used from both the app state (producer) and screens
  /// (consumers), which do not share a BuildContext.
  static final DeepLinkNav instance = DeepLinkNav._();

  DeepLinkNav._();

  String? _pendingUrl;

  /// URL the browser tab should open; non-null until consumed.
  String? get pendingUrl => _pendingUrl;

  /// Ask the browser tab to open [url]. ChangeNotifier notifies even for a
  /// repeated URL, so re-tapping the same external link works.
  void requestOpen(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _pendingUrl = trimmed;
    notifyListeners();
  }

  /// Called by the browser once it has taken the pending URL.
  void consumePending() {
    if (_pendingUrl == null) return;
    _pendingUrl = null;
    notifyListeners();
  }
}
