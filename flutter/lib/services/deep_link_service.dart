import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Handles incoming deep links for `octra://` and `octra-wallet://` schemes.
///
/// Listens on a platform MethodChannel for links forwarded by the native
/// Android `MainActivity` (which has `launchMode="singleTop"`). The
/// [onDeepLink] callback fires for each received URI.
class DeepLinkService with WidgetsBindingObserver {
  static const _channel =
      MethodChannel('github.com.maragung.octopus_wallet/deeplink');

  final void Function(Uri uri)? onDeepLink;
  StreamSubscription<dynamic>? _sub;

  DeepLinkService({this.onDeepLink}) {
    _channel.setMethodCallHandler(_handleMethod);
    WidgetsBinding.instance.addObserver(this);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'onDeepLink') {
      final String? link = call.arguments as String?;
      if (link != null && link.isNotEmpty) {
        _dispatch(link);
      }
    }
    return null;
  }

  void _dispatch(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      onDeepLink?.call(uri);
    } catch (_) {
      // Malformed URI — ignore
    }
  }

  /// Check for an initial deep link that launched the app.
  Future<void> checkInitialLink() async {
    try {
      final String? link = await _channel.invokeMethod('getInitialLink');
      if (link != null && link.isNotEmpty) {
        _dispatch(link);
      }
    } on MissingPluginException {
      // Platform channel not available (e.g., desktop) — ignore
    } catch (e) {
      // Any other channel failure must not crash startup.
      debugPrint('DeepLinkService.checkInitialLink failed: $e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _channel.setMethodCallHandler(null);
  }
}
