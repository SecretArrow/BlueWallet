/// Wire registry for the in-app dApp bridge (`window.octra`).
///
/// Dual-stack: the legacy BlueWallet dialect keeps working, and RFC-O-1
/// aliases dispatch alongside it. Error codes follow RFC-O-1 so third-party
/// adapters auto-detect this wallet. Pure Dart — unit-tested.
class DappBridgeProtocol {
  DappBridgeProtocol._();

  /// No code attached (legacy path, message only).
  static const int noCode = 0;

  /// User rejected the request.
  static const int userRejected = 4001;

  /// Not connected / locked / unauthorized.
  static const int unauthorized = 4100;

  /// Unknown method.
  static const int unsupportedMethod = 4200;

  /// Provider disconnected.
  static const int disconnected = 4900;

  /// Node/network failure.
  static const int networkUnavailable = 4901;

  /// Legacy dialect (existing clients keep working).
  static const Set<String> legacyMethods = {
    'octra_accounts',
    'octra_chainId',
    'octra_getBalance',
    'octra_sendTransaction',
    'octra_callContract',
    'octra_callView',
  };

  /// RFC-O-1 alias: approval-gated account list.
  static const String requestAccounts = 'octra_requestAccounts';

  /// RFC-O-1 alias: PVAC encrypted-balance cipher for the active wallet.
  static const String getEncryptedBalance = 'octra_getEncryptedBalance';

  /// RFC-O-1 method names answered by the bridge.
  static const Set<String> rfcMethods = {
    requestAccounts,
    getEncryptedBalance,
  };

  /// Trim + null-guard a raw method name from JS.
  static String canonicalize(String? method) =>
      method?.trim() ?? '';

  /// True when the bridge dispatches this method (either dialect).
  static bool isSupported(String? method) {
    final m = canonicalize(method);
    return legacyMethods.contains(m) || rfcMethods.contains(m);
  }
}
