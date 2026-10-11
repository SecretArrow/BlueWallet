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

  /// Reads + session calls the bridge answers for third-party adapters
  /// (0xio SDK OctraProviderAdapter — clean-room name mapping, no vendored code).
  static const Set<String> xioServedMethods = {
    'octra_networkInfo',
    'octra_permissions',
    'disconnect',
    'getBalance',
    'getPublicKey',
    'octra_sendContractTransaction',
    'octra_switchNetwork',
  };

  /// Recognised but unserved: sign-only split, message signing, FHE-private
  /// primitives. Rejected explicitly (never silently) with [unsupportedMethod].
  static const Set<String> knownUnsupportedMethods = {
    'octra_signTransaction',
    'octra_submitTransaction',
    'octra_signMessage',
    'octra_encryptBalance',
    'octra_decryptBalance',
    'octra_sendPrivateTransfer',
    'octra_claimStealth',
    'octra_getPrivateCapabilities',
    'octra_getPrivateBalance',
    'octra_encryptValue',
    'octra_decryptValue',
    'octra_makeZeroProof',
    'octra_makeRangeProof',
    'octra_registerPrivateViewKey',
    'octra_sendContractTransactionSequence',
    'octra_submitBatch',
    'wallet_signMessage',
    'wallet_signTypedData',
    'wallet_approveContract',
    'wallet_signContract',
    'wallet_signTransfer',
  };

  /// Orion-brand prefix; an alias for the matching `wallet_*` method.
  static const String orionPrefix = 'orion_wallet_';

  /// Reads + session calls answered for the `window.wallet` facade.
  static const Set<String> walletServedMethods = {
    'wallet_connect',
    'wallet_disconnect',
    'wallet_getAccounts',
    'wallet_getAddress',
    'wallet_getBalance',
    'wallet_getNetwork',
    'wallet_getNetworkInfo',
    'wallet_getNetworks',
    'wallet_getChainId',
    'wallet_getPermissions',
    'wallet_ping',
  };

  /// Reduce a method name to canonical form: trim, then fold the
  /// `orion_wallet_` alias onto `wallet_*`. Unknown names pass through
  /// unchanged and are rejected downstream.
  static String canonicalize(String? method) {
    final trimmed = method?.trim() ?? '';
    if (trimmed.startsWith(orionPrefix)) {
      return 'wallet_${trimmed.substring(orionPrefix.length)}';
    }
    return trimmed;
  }

  /// True when the bridge dispatches this method (any dialect).
  static bool isSupported(String? method) {
    final m = canonicalize(method);
    return legacyMethods.contains(m) ||
        rfcMethods.contains(m) ||
        xioServedMethods.contains(m) ||
        walletServedMethods.contains(m);
  }

  /// True for a recognised-but-unserved method (explicit reject, never silent).
  static bool isKnownUnsupported(String? method) =>
      knownUnsupportedMethods.contains(canonicalize(method));

  /// Stable network id ('mainnet' or 'devnet') for a chain id.
  static String networkIdForChain(String? chainId) =>
      (chainId != null && chainId.contains('mainnet')) ? 'mainnet' : 'devnet';

  /// Liveness record for `wallet_ping`: answers without touching wallet
  /// state, opening a popup, or mutating the session it observes.
  static Map<String, dynamic> buildPing({
    required bool connected,
    required bool locked,
    required String origin,
    required int tsMs,
  }) {
    return {
      'pong': true,
      'v': 1,
      'connected': connected,
      'locked': locked,
      'capabilities': ['ping', 'events'],
      'origin': origin,
      'ts': tsMs,
    };
  }

  /// Permissions a page asked for (`[{permissions: [...]}]`), or
  /// `['accounts']` when nothing parseable was asked. Never throws: a
  /// malformed request still gets the default — the approval dialog, not this
  /// parser, is the security boundary.
  static List<String> requestedPermissions(dynamic params) {
    const fallback = ['accounts'];
    try {
      final first =
          params is List ? (params.isEmpty ? null : params.first) : params;
      final list = first is Map ? first['permissions'] : null;
      if (list is! List || list.isEmpty) return List.of(fallback);
      final out = <String>[];
      for (final p in list) {
        final s = p.toString().trim();
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
      return out.isEmpty ? List.of(fallback) : out;
    } catch (_) {
      return List.of(fallback);
    }
  }

  /// The single transaction object out of either param shape: a legacy
  /// `[{...}]` array or a bare `{...}` object (third-party adapters).
  /// Throws [FormatException] naming the problem (never returns null).
  static Map<String, dynamic> txObject(dynamic params) {
    final first =
        params is List ? (params.isEmpty ? null : params.first) : params;
    if (first is Map) return Map<String, dynamic>.from(first);
    throw FormatException(
        'params must be an object or a single-element array, got ${params == null ? 'null' : params.runtimeType}');
  }

  /// Exactly one of `amount` (raw micro-OCT) / `amountOct` (decimal OCT, max 6
  /// decimals). Mirrors the exact-arithmetic rule: inexact input is rejected,
  /// never rounded.
  static String resolveTxAmount(Map<String, dynamic> tx) {
    final raw = tx['amount']?.toString() ?? '';
    final oct = tx['amountOct']?.toString() ?? '';
    final hasRaw = raw.isNotEmpty;
    final hasOct = oct.isNotEmpty;
    if (hasRaw && hasOct) {
      throw const FormatException(
          'pass either amount or amountOct, never both');
    }
    if (hasRaw) {
      final s = raw.trim().replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (!RegExp(r'^\d+$').hasMatch(s)) {
        throw const FormatException(
            'amount must be a non-negative integer string');
      }
      return s;
    }
    if (hasOct) return octToMicro(oct.trim());
    throw const FormatException('missing amount or amountOct');
  }

  /// Exact OCT → micro-OCT decimal conversion (max 6 decimals, no floats).
  static String octToMicro(String input) {
    final t = input.trim();
    if (t.isEmpty) throw const FormatException('empty amountOct');
    final dot = t.indexOf('.');
    final whole = dot < 0 ? t : t.substring(0, dot);
    var frac = dot < 0 ? '' : t.substring(dot + 1);
    if (!RegExp(r'^\d+$').hasMatch(whole) ||
        !RegExp(r'^\d*$').hasMatch(frac) ||
        frac.length > 6) {
      throw const FormatException(
          'amountOct must be a decimal with at most 6 places');
    }
    while (frac.length < 6) {
      frac += '0';
    }
    final micro = (whole.replaceFirst(RegExp(r'^0+(?=\d)'), '') + frac)
        .replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return micro.isEmpty ? '0' : micro;
  }

  /// True for a read-only view call: an object WITHOUT any attached value.
  /// Third-party adapters send views as `{contract, method, params, caller?}`;
  /// submissions always carry `amount` (and usually `ou`).
  static bool isViewCall(Map<String, dynamic> o) =>
      !o.containsKey('amount') && !o.containsKey('ou');
}
