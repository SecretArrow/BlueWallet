/// Parsed deep link for the wallet's external URL schemes.
///
/// Supported shapes (matching the AndroidManifest intent filters):
/// - `octra://send?to=<address>[&amount=<value>]` →
///   [DeepLinkRouteType.send] ([to] is required and must start with
///   `oct`; [amount] is optional — missing or unparseable values become
///   null).
/// - `octra://<circleId>[/path]` → [DeepLinkRouteType.octPage] ([raw] is
///   kept as-is; circle IDs are base58 and case-sensitive).
/// - `octra-wallet://<anything>` → [DeepLinkRouteType.walletConnect].
/// - everything else → null.
///
/// Pure Dart (no Flutter imports) and therefore fully unit-testable.
/// Parsing is manual — never `Uri` for the `octra` scheme — so circle IDs
/// keep their case (Uri canonicalizes hosts to lowercase).
library;

/// What the app should do with a deep link.
enum DeepLinkRouteType {
  /// Prefilled send screen (`octra://send?to=…&amount=…`).
  send,

  /// Open a circle page in the dApp browser (`octra://<circleId>/…`).
  octPage,

  /// Wallet-connect request from an external dApp (`octra-wallet://…`).
  walletConnect,
}

/// A single parsed deep link.
class DeepLinkRoute {
  /// Action to take.
  final DeepLinkRouteType type;

  /// The (trimmed) source URL, preserved verbatim.
  final String raw;

  /// Recipient address — send links only (never null for [type] send).
  final String? to;

  /// Amount — send links only; null when missing or not a number.
  final double? amount;

  const DeepLinkRoute._(
    this.type,
    this.raw, {
    this.to,
    this.amount,
  });

  /// Parse [raw]; returns null for anything the wallet does not handle.
  static DeepLinkRoute? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    const walletScheme = 'octra-wallet://';
    if (_startsWithIgnoreCase(trimmed, walletScheme)) {
      if (trimmed.length == walletScheme.length) return null;
      return DeepLinkRoute._(DeepLinkRouteType.walletConnect, trimmed);
    }

    const scheme = 'octra://';
    if (!_startsWithIgnoreCase(trimmed, scheme) ||
        trimmed.length == scheme.length) {
      return null;
    }

    // Split off query / fragment before extracting the host segment so the
    // case-sensitive circle ID is never touched by URI normalization.
    var rest = trimmed.substring(scheme.length);
    final cut = rest.indexOf(RegExp(r'[?#]'));
    final query = cut == -1 ? '' : rest.substring(cut + 1);
    if (cut != -1) rest = rest.substring(0, cut);
    final host = rest.split('/').first;

    if (host.toLowerCase() == 'send') {
      final params = Uri.splitQueryString(query);
      final to = params['to'];
      if (to == null || to.isEmpty || !to.startsWith('oct')) return null;
      final amountRaw = params['amount'];
      return DeepLinkRoute._(
        DeepLinkRouteType.send,
        trimmed,
        to: to,
        amount: amountRaw == null || amountRaw.isEmpty
            ? null
            : double.tryParse(amountRaw),
      );
    }
    if (host.isEmpty) return null;
    return DeepLinkRoute._(DeepLinkRouteType.octPage, trimmed);
  }

  static bool _startsWithIgnoreCase(String value, String prefix) =>
      value.length >= prefix.length &&
      value.substring(0, prefix.length).toLowerCase() == prefix;
}
