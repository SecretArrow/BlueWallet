import 'dart:async';
import 'dart:convert';

import '../dapp_bridge_protocol.dart';
import 'adapter_registry.dart';
import 'dapp_session_store.dart';
import 'wallet_adapter.dart';

/// Lifecycle + concurrency manager for the `window.octra` JS bridge.
///
/// Responsibilities:
/// - track pending JS requests (id -> completer + timeout + origin);
/// - reject duplicates (same JS id answered twice / still pending);
/// - time out reads (30 s) and approval-gated calls (5 min);
/// - cancel pending work on navigation away, tab close, WebView destroy;
/// - validate origin / method / payload size before dispatch;
/// - map [DappError] codes back to the provider (`__octra_response`).
///
/// The bridge never approves anything by itself: approval happens in
/// [AdapterContext] dialogs, and a cancelled dialog rejects.
class JsBridge {
  static const String channelName = 'OctraWalletBridge';
  static const String responseFn = 'window.__octra_response';

  static const Duration readTimeout = Duration(seconds: 30);
  static const Duration approvalTimeout = Duration(minutes: 5);

  /// Methods that open an approval dialog (long timeout).
  /// `wallet_sendTransaction` mirrors `octra_sendTransaction`
  /// (approval-gated submit); `wallet_callView` mirrors `octra_callView`
  /// (read-only, no approval) so it stays out of this set, like its twin.
  static const Set<String> approvalMethods = {
    'octra_requestAccounts',
    'octra_sendTransaction',
    'octra_sendContractTransaction',
    'octra_callContract',
    'octra_switchNetwork',
    'wallet_connect',
    'wallet_sendTransaction',
  };

  /// Methods callable without a granted session.
  /// `wallet_sendTransaction` / `wallet_callView` stay session-gated like
  /// their `octra_*` twins, so neither is listed here.
  static const Set<String> preConnectMethods = {
    'octra_accounts',
    'octra_chainId',
    'octra_requestAccounts',
    'disconnect',
    'wallet_disconnect',
    'wallet_ping',
    'wallet_getChainId',
    'wallet_connect',
  };

  final AdapterRegistry registry;
  final DappSessionStore sessions;

  /// Sends `fn(id, resultJson, error, code)` into the page.
  final void Function(int jsId, String? resultJson, String? error, int code)
      respond;

  /// Current page origin, e.g. `https://app.example.com`.
  final String Function() currentOrigin;

  final Map<int, _Pending> _pending = {};
  final Set<String> _answered = {};
  bool _disposed = false;

  JsBridge({
    required this.registry,
    required this.sessions,
    required this.respond,
    required this.currentOrigin,
  });

  bool get isDisposed => _disposed;
  int get pendingCount => _pending.length;

  /// Entry point for `OctraWalletBridge.postMessage(raw)`.
  Future<void> onMessage(String raw) async {
    if (_disposed) return;
    if (raw.length > AdapterValidation.maxMessageBytes) {
      return; // oversized: drop silently, page already misbehaving.
    }
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      msg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final type = msg['type']?.toString() ?? '';
    final jsId = (msg['id'] is num) ? (msg['id'] as num).toInt() : 0;
    if (jsId <= 0) return;

    // Duplicate response guard: an id answered before must never resolve again.
    final dupKey = '$jsId';
    if (_answered.contains(dupKey) || _pending.containsKey(jsId)) {
      _fail(jsId, 'Duplicate request id: $jsId');
      return;
    }

    if (type == 'connect') {
      await _handleLegacyConnect(jsId);
      return;
    }
    if (type != 'request') {
      _fail(jsId, 'Unknown bridge message type: $type',
          DappBridgeProtocol.unsupportedMethod);
      return;
    }

    final rawParams = msg['params'];
    final List<dynamic> params;
    if (rawParams is List) {
      params = List<dynamic>.from(rawParams);
    } else if (rawParams is Map) {
      params = [Map<String, dynamic>.from(rawParams)];
    } else if (rawParams == null) {
      params = [];
    } else {
      _fail(jsId, 'Invalid params: must be an object or array');
      return;
    }
    try {
      final encoded = jsonEncode(params);
      if (encoded.length > AdapterValidation.maxParamsBytes) {
        _fail(jsId, 'Invalid params: payload too large');
        return;
      }
    } catch (_) {
      _fail(jsId, 'Invalid params: not JSON-encodable');
      return;
    }

    final method =
        DappBridgeProtocol.canonicalize(msg['method']?.toString() ?? '');
    if (method.isEmpty) {
      _fail(jsId, 'Invalid params: missing method');
      return;
    }

    final origin = currentOrigin();
    if (!AdapterValidation.isValidOrigin(origin)) {
      _fail(
          jsId, 'Rejected: untrusted origin', DappBridgeProtocol.unauthorized);
      return;
    }

    // Session gate: connected-only methods need a granted session for this
    // origin. `disconnect` is always allowed (clearing an empty session
    // must never throw).
    final needsSession = !preConnectMethods.contains(method);
    if (needsSession && !sessions.isConnected(origin)) {
      _fail(jsId, 'Not connected', DappBridgeProtocol.unauthorized);
      return;
    }

    final request = DappRequest(
      jsId: jsId,
      origin: AdapterValidation.normalizeOrigin(origin),
      method: method,
      params: params,
      receivedAt: DateTime.now(),
    );

    final isApproval = approvalMethods.contains(method);
    final timeout = isApproval ? approvalTimeout : readTimeout;
    final completer = Completer<AdapterResult>();
    final timer = Timer(timeout, () {
      final p = _pending.remove(jsId);
      if (p != null && !p.completer.isCompleted) {
        p.completer.completeError(DappError(
            isApproval
                ? 'Request timed out (no approval within 5 minutes)'
                : 'Request timed out',
            DappBridgeProtocol.networkUnavailable));
      }
    });
    _pending[jsId] = _Pending(
        completer: completer,
        timer: timer,
        origin: request.origin,
        method: method);

    completer.future.then((value) {
      _succeed(jsId, value);
    }, onError: (Object e) {
      if (e is DappError) {
        _fail(jsId, e.message, e.code);
      } else {
        _fail(jsId, _shortErr(e));
      }
    });
    final hook = _dispatchHook;
    if (hook == null) {
      _pending.remove(jsId)?.timer.cancel();
      _fail(jsId, 'Bridge has no dispatcher',
          DappBridgeProtocol.networkUnavailable);
      return;
    }
    // The hook runs the registry and completes [completer]; completion
    // (or timeout / cancel) answers the page via the handlers above.
    try {
      hook(request, completer);
    } catch (e) {
      if (!completer.isCompleted) {
        if (e is DappError) {
          completer.completeError(e);
        } else {
          completer.completeError(DappError(_shortErr(e)));
        }
      }
    }
  }

  /// Dispatch hook installed by the browser screen: receives the validated
  /// [DappRequest] plus the completer [JsBridge] tracks, runs the registry,
  /// and completes (never responds directly).
  void Function(DappRequest request, Completer<AdapterResult> completer)?
      _dispatchHook;

  void setDispatchHook(
      void Function(DappRequest, Completer<AdapterResult>) hook) {
    _dispatchHook = hook;
  }

  /// Legacy `connect` (no params): approval-gated, grants a session.
  Future<void> _handleLegacyConnect(int jsId) async {
    final hook = _connectHook;
    if (hook == null) {
      _fail(jsId, 'No active wallet', DappBridgeProtocol.unauthorized);
      return;
    }
    if (_pending.containsKey(jsId) || _answered.contains('$jsId')) {
      _fail(jsId, 'Duplicate request id: $jsId');
      return;
    }
    final completer = Completer<String?>();
    final timer = Timer(approvalTimeout, () {
      final p = _pending.remove(jsId);
      if (p != null && !p.completer.isCompleted) {
        p.completer.completeError(const DappError(
            'Request timed out (no approval within 5 minutes)',
            DappBridgeProtocol.networkUnavailable));
      }
    });
    _pending[jsId] = _Pending(
        completer: completer,
        timer: timer,
        origin: currentOrigin(),
        method: 'connect');
    completer.future.then((address) {
      if (address == null || address.isEmpty) {
        _fail(
            jsId, 'User rejected connection', DappBridgeProtocol.userRejected);
      } else {
        _succeed(jsId, {'address': address, 'ok': true});
      }
    }, onError: (Object e) {
      if (e is DappError) {
        _fail(jsId, e.message, e.code);
      } else {
        _fail(jsId, _shortErr(e));
      }
    });
    try {
      await hook(jsId, completer);
    } catch (e) {
      _pending.remove(jsId)?.timer.cancel();
      if (e is DappError) {
        _fail(jsId, e.message, e.code);
      } else {
        _fail(jsId, _shortErr(e));
      }
    }
  }

  Future<void> Function(int jsId, Completer<String?> completer)? _connectHook;

  void setConnectHook(
      Future<void> Function(int jsId, Completer<String?> completer) hook) {
    _connectHook = hook;
  }

  /// Cancel pending requests for [origin] (navigation away / revoke).
  ///
  /// Cancellation completes the tracked future with a user-rejection error,
  /// which the completion handler delivers to the page — the dApp observes
  /// a rejection, never a hang. Late results are dropped by the answered-set.
  void cancelForOrigin(String origin, {String reason = 'Page navigated away'}) {
    final key = AdapterValidation.normalizeOrigin(origin);
    final ids = _pending.entries
        .where((e) => e.value.origin == key)
        .map((e) => e.key)
        .toList();
    for (final id in ids) {
      final p = _pending.remove(id);
      p?.timer.cancel();
      if (p != null && !p.completer.isCompleted) {
        p.completer
            .completeError(DappError(reason, DappBridgeProtocol.userRejected));
      }
    }
  }

  /// Cancel a single request (user dismissed the approval UI).
  void cancel(int jsId, {String reason = 'User rejected request'}) {
    final p = _pending.remove(jsId);
    p?.timer.cancel();
    if (p != null && !p.completer.isCompleted) {
      p.completer
          .completeError(DappError(reason, DappBridgeProtocol.userRejected));
    }
  }

  /// Cancel everything (tab close / WebView destroy / dispose).
  void cancelAll({String reason = 'Page closed'}) {
    final ids = _pending.keys.toList();
    for (final id in ids) {
      final p = _pending.remove(id);
      p?.timer.cancel();
      if (p != null && !p.completer.isCompleted) {
        p.completer
            .completeError(DappError(reason, DappBridgeProtocol.userRejected));
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelAll(reason: 'Browser closed');
  }

  void _succeed(int jsId, AdapterResult value) {
    final p = _pending.remove(jsId);
    p?.timer.cancel();
    if (_answered.contains('$jsId')) return;
    _answered.add('$jsId');
    // Bound the answered-set so long sessions cannot grow it forever.
    if (_answered.length > 1000) _answered.remove(_answered.first);
    String resultJson;
    try {
      resultJson = jsonEncode(value);
    } catch (_) {
      _fail(jsId, 'Internal error: result not encodable');
      return;
    }
    try {
      respond(jsId, resultJson, null, 0);
    } catch (_) {
      // WebView gone — nothing to answer.
    }
  }

  void _fail(int jsId, String error, [int code = 0]) {
    final p = _pending.remove(jsId);
    p?.timer.cancel();
    if (_answered.contains('$jsId')) return;
    _answered.add('$jsId');
    if (_answered.length > 1000) _answered.remove(_answered.first);
    try {
      respond(jsId, null, error, code);
    } catch (_) {
      // WebView gone — nothing to answer.
    }
  }

  static String _shortErr(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    // Never leak key material: truncate long native errors.
    return s.length > 220 ? '${s.substring(0, 220)}…' : s;
  }

  /// `window.octra` provider injected on every page load. `__CHAIN_ID__`
  /// is replaced by the browser with the active chain id. The provider
  /// only forwards over [channelName]; all policy lives in Dart.
  static const String providerJs = r'''
(function() {
  'use strict';
  if (window.octra) return;

  let _requestId = 0;
  const _pending = new Map();
  const _listeners = {};
  let _connected = false;
  let _accounts = [];

  function _emit(event, data) {
    for (const cb of (_listeners[event] || [])) {
      try { cb(data); } catch (_) {}
    }
  }

  window.__octra_response = function(id, resultJson, error, code) {
    const p = _pending.get(id);
    if (!p) return;
    _pending.delete(id);
    if (error) {
      const err = new Error(error);
      if (code) err.code = code;
      p.reject(err);
    } else {
      try {
        p.resolve(resultJson !== null ? JSON.parse(resultJson) : null);
      } catch(e) {
        p.resolve(resultJson);
      }
    }
  };

  function _send(msg) {
    return new Promise((resolve, reject) => {
      _pending.set(msg.id, { resolve, reject });
      OctraWalletBridge.postMessage(JSON.stringify(msg));
    });
  }

  const octraProvider = {
    isOctra: true,
    chainId: '__CHAIN_ID__',
    get accounts() { return [..._accounts]; },
    get isConnected() { return _connected; },

    async connect() {
      const r = await _send({ type: 'connect', id: ++_requestId });
      _connected = true;
      _accounts = [r.address];
      _emit('connect', r);
      _emit('accountsChanged', _accounts);
      return r;
    },

    async disconnect() {
      _connected = false;
      _accounts = [];
      _emit('disconnect', {});
      _emit('accountsChanged', []);
      return { ok: true };
    },

    async request({ method, params = [] }) {
      if (!_connected && method !== 'octra_accounts' && method !== 'octra_chainId'
          && method !== 'disconnect') {
        throw new Error('Wallet not connected. Call window.octra.connect() first.');
      }
      return _send({ type: 'request', id: ++_requestId, method, params }).then(r => {
        if (method === 'octra_requestAccounts' && Array.isArray(r)) {
          _connected = true;
          _accounts = r;
          _emit('connect', { address: r[0] });
          _emit('accountsChanged', _accounts);
        }
        if (method === 'disconnect') {
          _connected = false;
          _accounts = [];
          _emit('disconnect', {});
          _emit('accountsChanged', []);
        }
        return r;
      });
    },

    async getBalance() {
      return this.request({ method: 'octra_getBalance', params: [] });
    },
    async requestAccounts() {
      const accounts = await this.request({ method: 'octra_requestAccounts' });
      _connected = true;
      _accounts = accounts;
      _emit('connect', { address: accounts[0] });
      _emit('accountsChanged', _accounts);
      return accounts;
    },
    async getEncryptedBalance() {
      return this.request({ method: 'octra_getEncryptedBalance' });
    },
    async sendTransaction(to, amount, memo) {
      return this.request({
        method: 'octra_sendTransaction',
        params: [{ to, amount: String(amount), memo }]
      });
    },
    async callContract(address, method, params = [], amount = '0') {
      return this.request({
        method: 'octra_callContract',
        params: [address, method, params, String(amount)]
      });
    },
    async callView(address, method, params = []) {
      return this.request({
        method: 'octra_callView',
        params: [address, method, params]
      });
    },

    on(event, cb) {
      if (!_listeners[event]) _listeners[event] = [];
      _listeners[event].push(cb);
      return this;
    },
    off(event, cb) {
      if (_listeners[event]) {
        _listeners[event] = _listeners[event].filter(c => c !== cb);
      }
      return this;
    },
  };

  const _walletListeners = {};
  function _wemit(event, data) {
    for (const cb of (_walletListeners[event] || [])) {
      try { cb(data); } catch (_) {}
    }
  }
  function _wforbidden(method) {
    const err = new Error(method + ' is sign-only and not served by this wallet');
    err.code = 'METHOD_FORBIDDEN';
    throw err;
  }
  async function _walletConnectResult(address) {
    let publicKey = '';
    try {
      const pk = await octraProvider.request({method:'getPublicKey'});
      publicKey = (pk && pk.publicKey) || '';
    } catch (e) { publicKey = ''; }
    const networkInfo = await octraProvider.request({method:'octra_networkInfo'});
    const chainId = networkInfo.chainId;
    const permissions = await octraProvider.request({method:'octra_permissions'});
    return { address, publicKey, accounts: [{address}],
      network: networkInfo.id, networkInfo, chainId,
      capabilities: ['ping','events'] };
  }
  const walletProvider = {
    async connect() {
      const accounts = await octraProvider.request({method:'octra_requestAccounts', params:[]});
      const address = accounts[0];
      if (!address) throw new Error('Connect did not yield an address');
      const result = await _walletConnectResult(address);
      _wemit('connect', result);
      _wemit('accountChanged', {address});
      return result;
    },
    async disconnect() {
      await octraProvider.request({method:'disconnect'});
      _wemit('disconnect', {reason:'user disconnect'});
      return undefined;
    },
    isConnected() { return octraProvider.isConnected; },
    async getAccounts() {
      const a = await octraProvider.request({method:'wallet_getAccounts'});
      return a.filter(x => !!x).map(address => ({address}));
    },
    async getAddress() {
      const a = await octraProvider.request({method:'wallet_getAccounts'});
      return a[0] || '';
    },
    async getPublicKey() {
      const r = await octraProvider.request({method:'getPublicKey'});
      return r.publicKey;
    },
    async getBalance() {
      const r = await octraProvider.request({method:'wallet_getBalance'});
      const num = v => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
      return { balance: String(r.balance ?? r.public ?? ''),
        balanceRaw: String(r.balance_raw ?? r.raw ?? ''),
        nonce: num(r.nonce ?? r.pending_nonce) };
    },
    async getNetwork() {
      const n = await octraProvider.request({method:'octra_networkInfo'});
      return n.id;
    },
    async getNetworkInfo() {
      return octraProvider.request({method:'octra_networkInfo'});
    },
    async getNetworks() {
      const n = await octraProvider.request({method:'octra_networkInfo'});
      return [n];
    },
    async getChainId() {
      const n = await octraProvider.request({method:'octra_networkInfo'});
      return n.chainId;
    },
    async getPermissions() {
      return octraProvider.request({method:'octra_permissions'});
    },
    async signMessage() { _wforbidden('wallet_signMessage'); },
    async signTypedData() { _wforbidden('wallet_signTypedData'); },
    async approveContract() { _wforbidden('wallet_approveContract'); },
    async signContract() { _wforbidden('wallet_signContract'); },
    async signTransfer() { _wforbidden('wallet_signTransfer'); },
    async ping() {
      return { pong: true, v: 1, connected: octraProvider.isConnected,
        locked: !octraProvider.isConnected, capabilities: ['ping','events'],
        origin: window.location.origin, ts: Date.now() };
    },
    async isAlive() { return octraProvider.isConnected; },
    async request(method, params) {
      const m = String(method == null ? '' : method);
      const low = m.trim().toLowerCase();
      const canon = low.startsWith('orion_wallet_') ? 'wallet_' + low.slice(13) : low;
      // Dual-stack aliases: wallet_sendTransaction (approval-gated submit,
      // twin of octra_sendTransaction) and wallet_callView (read-only view,
      // twin of octra_callView) forward like their twins, never forbidden.
      const walletAliasPassthrough =
        canon === 'wallet_sendtransaction' || canon === 'wallet_callview';
      if (!walletAliasPassthrough
          && (/^(wallet_)?(signmessage|signtypeddata|approvecontract|signcontract|signtransfer|signtransaction|submittransaction|sendtransaction|broadcasttransaction|transfer|swap|bridge)$/.test(canon)
          || /(sendtransaction|broadcast|(^|_)transfer$|(^|_)swap$|(^|_)bridge$)/.test(canon))) {
        const err = new Error(canon + ' is prohibited: this wallet never broadcasts through the SDK');
        err.code = 'METHOD_FORBIDDEN';
        throw err;
      }
      return octraProvider.request({method: m, params});
    },
    on(event, cb) {
      if (!_walletListeners[event]) _walletListeners[event] = [];
      _walletListeners[event].push(cb);
      return this;
    },
    off(event, cb) {
      if (_walletListeners[event]) {
        _walletListeners[event] = _walletListeners[event].filter(c => c !== cb);
      }
      return this;
    },
    once(event, cb) {
      const self = this;
      const wrap = (d) => { self.off(event, wrap); cb(d); };
      return this.on(event, wrap);
    },
  };
  try {
    if (!window.wallet) {
      Object.defineProperty(window, 'wallet', {
        value: Object.freeze(walletProvider), writable: true, configurable: true });
    }
  } catch (e) { }
  window.dispatchEvent(new CustomEvent('octra:wallet#initialized',
    {detail: {provider: window.wallet || walletProvider}}));

  Object.defineProperty(window, 'octra', {
    value: Object.freeze(octraProvider),
    writable: false,
    configurable: false,
  });
  window.dispatchEvent(new Event('octra#initialized'));
  console.log('[Octra] window.octra provider injected');
})();
''';
}

class _Pending {
  final Completer completer;
  final Timer timer;
  final String origin;
  final String method;
  _Pending({
    required this.completer,
    required this.timer,
    required this.origin,
    required this.method,
  });
}
