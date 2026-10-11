/// Abstract contract for a modular dApp wallet adapter.
///
/// Each adapter serves one chain / protocol family (Octra, EVM, ...).
/// New networks are added by implementing [WalletAdapter] and registering
/// it in [AdapterRegistry] — no rewrite of the bridge or browser needed.
///
/// No mock / fake providers: adapters must throw [DappError] with an
/// explicit code when a method is unsupported, the wallet is locked,
/// the network is unavailable, or the RPC response is invalid.
library;

import 'dapp_session.dart';

/// Error codes shared with `DappBridgeProtocol` (RFC-O-1).
class DappError implements Exception {
  final String message;
  final int code;
  const DappError(this.message, [this.code = 0]);

  @override
  String toString() => message;
}

/// A single validated dApp request arriving over the JS bridge.
class DappRequest {
  final int jsId;
  final String origin;
  final String method;
  final List<dynamic> params;
  final DateTime receivedAt;

  const DappRequest({
    required this.jsId,
    required this.origin,
    required this.method,
    required this.params,
    required this.receivedAt,
  });
}

/// Services + UI callbacks an adapter may use. Adapters never touch
/// `BuildContext` or navigation directly — the browser screen injects
/// approval callbacks that show `ConfirmActionScreen` /
/// `ConfirmContractCallScreen` and return `true` only on explicit user
/// approval. A dismissed / cancelled dialog MUST resolve to `false`
/// (cancel != approve).
class AdapterContext {
  /// Show an approval dialog; resolves true only on explicit approval.
  final Future<bool> Function({
    required String title,
    required String body,
    required String confirmLabel,
    String? origin,
  }) requestApproval;

  /// Show a transaction confirmation dialog; resolves true only on confirm.
  final Future<bool> Function({
    required String title,
    required String to,
    required String amount,
    String? extra,
    String? origin,
  }) requestTxApproval;

  /// Current page origin (scheme + host) for session scoping.
  final String Function() currentOrigin;

  const AdapterContext({
    required this.requestApproval,
    required this.requestTxApproval,
    required this.currentOrigin,
  });
}

/// Result envelope: adapters return a JSON-encodable value.
typedef AdapterResult = Object?;

abstract class WalletAdapter {
  /// Stable id, e.g. 'octra'.
  String get id;

  /// Human chain label, e.g. 'Octra'.
  String get chainType;

  /// Canonical method names this adapter serves.
  Set<String> get supportedMethods;

  bool supports(String canonicalMethod) =>
      supportedMethods.contains(canonicalMethod);

  /// Handle [request]. May throw [DappError]. Must never return fake
  /// balances, hashes, or signatures — only real wallet/RPC data.
  Future<AdapterResult> handle(DappRequest request, AdapterContext ctx);
}

/// Shared validation helpers for all adapters.
class AdapterValidation {
  AdapterValidation._();

  /// Max inbound bridge message (256 KB). Larger payloads are rejected
  /// before JSON parsing effects propagate.
  static const int maxMessageBytes = 256 * 1024;

  /// Max encoded params payload (64 KB).
  static const int maxParamsBytes = 64 * 1024;

  /// Origins the bridge accepts for session binding. `about:blank` is
  /// allowed transiently (fresh tab) but never persisted as a session.
  /// `javascript:`, `data:`, `file:` and empty origins are rejected.
  static bool isValidOrigin(String origin) {
    if (origin.isEmpty) return false;
    final lower = origin.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('file:') ||
        lower.startsWith('blob:')) {
      return false;
    }
    // Bare about:blank (fresh tab) — transient only.
    if (lower == 'about:blank') return true;
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    if (uri.scheme != 'http' &&
        uri.scheme != 'https' &&
        uri.scheme != 'oct') {
      return false;
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isEmpty) {
      return false;
    }
    return true;
  }

  /// Session-persistable origin: valid AND not transient (`about:blank`).
  static bool isPersistableOrigin(String origin) {
    if (!isValidOrigin(origin)) return false;
    return origin.trim().toLowerCase() != 'about:blank';
  }

  /// Normalize an origin for session keys: scheme://host[:port] lowercased,
  /// or the trimmed input when unparseable (never throws).
  static String normalizeOrigin(String origin) {
    final t = origin.trim();
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty) return t.toLowerCase();
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final port = uri.hasPort ? ':${uri.port}' : '';
    if (scheme == 'oct') {
      // oct://circleId/... — session scope is the circle.
      final circle = t.substring('oct://'.length).split('/').first;
      return 'oct://$circle'.toLowerCase();
    }
    return '$scheme://$host$port';
  }
}
