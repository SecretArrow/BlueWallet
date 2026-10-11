import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../services/local_web_server_service.dart';
import '../../services/oct_url.dart';
import '../../services/dapp_bridge_protocol.dart';

/// In-app DApp browser with an embedded WebView and a `window.octra` provider.
///
/// The wallet bridge works via a JavaScript channel named `OctraWalletBridge`.
/// The injected provider script (see [_octraProviderJs]) calls
/// `OctraWalletBridge.postMessage(JSON.stringify({type, id, ...}))` and the
/// Flutter side responds with `window.__octra_response(id, resultJson, error)`.
///
/// Supported wallet methods:
/// - `connect`                 → returns {address}
/// - `octra_accounts`          → [address]
/// - `octra_chainId`           → 'octra-devnet-1'
/// - `octra_getBalance`        → {balance, encryptedBalance, raw, encryptedRaw}
/// - `octra_callView`          → params: [contractAddr, function, args]
/// - `octra_sendTransaction`   → params: [{to, amount, memo?}]  (requires confirmation)
/// - `octra_callContract`      → params: [contractAddr, fn, args, amount]  (requires confirmation)
class DappBrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const DappBrowserScreen({super.key, this.initialUrl});

  @override
  State<DappBrowserScreen> createState() => _DappBrowserScreenState();
}

class _DappBrowserScreenState extends State<DappBrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlCtrl = TextEditingController();

  bool _isLoading = true;
  int _loadingProgress = 0;
  String _pageTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _connectedAddress;

  /// Scopes granted at the last approval, echoed back by `octra_permissions`.
  /// This wallet approves all-or-nothing, so the list is what the page asked
  /// for — never more. Defaults to `['accounts']`.
  List<String> _grantedPermissions = ['accounts'];

  // Default DApp shortcuts
  static const List<Map<String, String>> _devnetShortcuts = [
    {
      'name': 'Octra DEX',
      'url': 'http://localhost:3000',
      'description': 'Swap, Bridge & Liquidity',
      'icon': '🔄',
    },
    {
      'name': 'Octra Bridge',
      'url': 'http://localhost:3000/bridge',
      'description': 'oAVAX ↔ AVAX Cross-chain',
      'icon': '🌉',
    },
    {
      'name': 'Devnet Explorer',
      'url': 'https://devnet.octrascan.io',
      'description': 'Block Explorer (Devnet)',
      'icon': '🔍',
    },
    {
      'name': 'Mainnet Explorer',
      'url': 'https://octrascan.io',
      'description': 'Block Explorer (Mainnet)',
      'icon': '🔍',
    },
  ];

  List<Map<String, String>> get _dappShortcuts => _devnetShortcuts;

  @override
  void initState() {
    super.initState();
    final startUrl = widget.initialUrl ?? 'http://localhost:3000';
    _urlCtrl.text = startUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _loadingProgress = p),
        onPageStarted: (url) => setState(() {
          _isLoading = true;
          _urlCtrl.text = url;
          _pageTitle = '';
        }),
        onPageFinished: (url) async {
          final title = await _controller.getTitle();
          final canBack = await _controller.canGoBack();
          final canFwd = await _controller.canGoForward();
          if (mounted) {
            setState(() {
              _isLoading = false;
              _urlCtrl.text = url;
              _pageTitle = title ?? '';
              _canGoBack = canBack;
              _canGoForward = canFwd;
            });
          }
          // Inject the wallet provider on every page load.
          if (!mounted) return;
          final ns = context.read<NetworkService>();
          await _controller.runJavaScript(
              _octraProviderJs.replaceAll('__CHAIN_ID__', ns.activeChainId));
        },
        onUrlChange: (change) {
          if (change.url != null && mounted) {
            setState(() => _urlCtrl.text = change.url!);
          }
        },
        onNavigationRequest: (request) {
          // Native oct:// protocol — resolve circle URLs ourselves since
          // webview_flutter cannot intercept subresources. Top-level
          // navigations are rendered via gateway or direct RPC fetch.
          if (_isOctUrl(request.url)) {
            _loadOctUrl(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) {
          if (mounted) setState(() => _isLoading = false);
        },
      ))
      ..addJavaScriptChannel(
        'OctraWalletBridge',
        onMessageReceived: (msg) => _handleBridgeMessage(msg.message),
      )
      ..loadRequest(Uri.parse(startUrl));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  // ── Bridge message handler ───────────────────────────────────────────────

  void _handleBridgeMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = msg['type'] as String? ?? '';
    final id = (msg['id'] as num?)?.toInt() ?? 0;

    switch (type) {
      case 'connect':
        await _handleConnect(id);
        break;
      case 'request':
        // Third-party adapters (0xio) send a single object, not an array —
        // dropping a Map here used to silently empty every object-form call.
        final rawParams = msg['params'];
        final List<dynamic> params;
        if (rawParams is List) {
          params = rawParams.cast<dynamic>();
        } else if (rawParams is Map) {
          params = [rawParams];
        } else {
          params = [];
        }
        await _handleRequest(
          id,
          DappBridgeProtocol.canonicalize(msg['method'] as String? ?? ''),
          params,
        );
        break;
      default:
        _bridgeError(id, 'Unknown bridge message type: $type',
            DappBridgeProtocol.unsupportedMethod);
    }
  }

  Future<void> _handleConnect(int id) async {
    final ws = context.read<WalletService>();
    final address = ws.activeWallet?.address;
    if (address == null || address.isEmpty) {
      _bridgeError(id, 'No active wallet');
      return;
    }
    // Show connection-approval dialog.
    final approved = await _showApprovalDialog(
      title: 'Connect Wallet',
      body: 'This DApp wants to connect to your wallet.\n\n'
          'Address: ${_shortAddr(address)}',
      confirmLabel: 'Connect',
    );
    if (approved) {
      setState(() => _connectedAddress = address);
      _bridgeResult(id, jsonEncode({'address': address, 'ok': true}));
    } else {
      _bridgeError(
          id, 'User rejected connection', DappBridgeProtocol.userRejected);
    }
  }

  /// RFC-O-1 requestAccounts: approval-gated account list. Reuses the
  /// connect approval UI but answers with a plain address array.
  Future<void> _handleRequestAccounts(int id, List params) async {
    final requested = DappBridgeProtocol.requestedPermissions(params);
    final ws = context.read<WalletService>();
    final address = ws.activeWallet?.address;
    if (address == null || address.isEmpty) {
      _bridgeError(id, 'No active wallet', DappBridgeProtocol.unauthorized);
      return;
    }
    final approved = await _showApprovalDialog(
      title: 'Share Account',
      body: 'This DApp wants to see your Octra address.\n\n'
          'Address: ${_shortAddr(address)}',
      confirmLabel: 'Share',
    );
    if (approved) {
      setState(() {
        _connectedAddress = address;
        _grantedPermissions = requested;
      });
      _bridgeResult(id, jsonEncode([address]));
    } else {
      _bridgeError(
          id, 'User rejected connection', DappBridgeProtocol.userRejected);
    }
  }

  /// RFC-O-1 encrypted balance: cached PVAC cipher for the active wallet.
  Future<void> _handleGetEncryptedBalance(int id) async {
    final ws = context.read<WalletService>();
    final wallet = ws.activeWallet;
    if (wallet == null) {
      _bridgeError(id, 'No active wallet', DappBridgeProtocol.unauthorized);
      return;
    }
    final cipher = ws.encryptedBalanceCipher;
    if (cipher == null || cipher.isEmpty) {
      _bridgeError(
          id, 'Encrypted balance unavailable — refresh the wallet first');
      return;
    }
    _bridgeResult(
        id, jsonEncode({'address': wallet.address, 'cipher': cipher}));
  }

  Future<void> _handleRequest(int id, String method, List params) async {
    final ws = context.read<WalletService>();
    final ns = context.read<NetworkService>();
    // Pre-connect reads (mirrors the JS provider + Android gate). `disconnect`
    // is always allowed: clearing an empty session must never throw.
    const preConnect = {
      'octra_accounts',
      'octra_chainId',
      'octra_requestAccounts',
      'disconnect',
    };
    if (_connectedAddress == null && !preConnect.contains(method)) {
      _bridgeError(id, 'Not connected', DappBridgeProtocol.unauthorized);
      return;
    }
    try {
      switch (method) {
        case 'octra_accounts':
          final addr = ws.activeWallet?.address ?? '';
          _bridgeResult(id, jsonEncode([addr]));
          break;

        case 'octra_requestAccounts':
          await _handleRequestAccounts(id, params);
          break;

        case 'octra_getEncryptedBalance':
          await _handleGetEncryptedBalance(id);
          break;

        case 'octra_chainId':
          final ns = context.read<NetworkService>();
          _bridgeResult(id, jsonEncode(ns.activeChainId));
          break;

        case 'octra_getBalance':
          _bridgeResult(
              id,
              jsonEncode({
                'balance': ws.publicBalance,
                'encryptedBalance': ws.encryptedBalance,
                'raw': ws.balanceRaw,
                'encryptedRaw': ws.encryptedBalanceRaw,
              }));
          break;

        case 'getBalance':
          // 0xio provider path: the adapter reads `balance` (decimal OCT)
          // and defaults a missing `privateBalance` to 0.
          _bridgeResult(
              id,
              jsonEncode({
                'balance': ws.publicBalance,
                'privateBalance': ws.encryptedBalance,
              }));
          break;

        case 'octra_networkInfo':
          _bridgeResult(id, jsonEncode(_networkInfo(ns)));
          break;

        case 'octra_permissions':
          _bridgeResult(id, jsonEncode(_grantedPermissions));
          break;

        case 'disconnect':
        case 'wallet_disconnect':
          setState(() {
            _connectedAddress = null;
            _grantedPermissions = ['accounts'];
          });
          _bridgeResult(id, jsonEncode({'success': true}));
          break;

        // `window.wallet` facade (Orion-style high-level reads).
        case 'wallet_connect':
          await _handleRequestAccounts(id, params);
          break;

        case 'wallet_getAccounts':
          _bridgeResult(id, jsonEncode([_connectedAddress ?? '']));
          break;

        case 'wallet_getAddress':
          _bridgeResult(id, jsonEncode(_connectedAddress ?? ''));
          break;

        case 'wallet_getBalance':
          _bridgeResult(
              id,
              jsonEncode({
                'balance': ws.publicBalance,
                'encryptedBalance': ws.encryptedBalance,
                'raw': ws.balanceRaw,
                'encryptedRaw': ws.encryptedBalanceRaw,
              }));
          break;

        case 'wallet_getNetwork':
          _bridgeResult(
              id,
              jsonEncode(
                  DappBridgeProtocol.networkIdForChain(ns.activeChainId)));
          break;

        case 'wallet_getNetworkInfo':
          _bridgeResult(id, jsonEncode(_networkInfo(ns)));
          break;

        case 'wallet_getNetworks':
          _bridgeResult(id, jsonEncode([_networkInfo(ns)]));
          break;

        case 'wallet_getChainId':
          _bridgeResult(id, jsonEncode(ns.activeChainId));
          break;

        case 'wallet_getPermissions':
          _bridgeResult(id, jsonEncode(_grantedPermissions));
          break;

        case 'wallet_ping':
          final pingAddr = _connectedAddress ?? ws.activeWallet?.address ?? '';
          _bridgeResult(
              id,
              jsonEncode(DappBridgeProtocol.buildPing(
                connected: _connectedAddress != null,
                locked: pingAddr.isEmpty,
                origin: Uri.tryParse(_urlCtrl.text)?.host ?? '',
                tsMs: DateTime.now().millisecondsSinceEpoch,
              )));
          break;

        case 'getPublicKey':
          _bridgeError(id, 'No public key available for the active wallet');
          break;

        case 'octra_switchNetwork':
          await _handleSwitchNetwork(id, params, ns);
          break;

        case 'octra_callView':
          // params: [contractAddr, functionName, args, caller?]
          if (params.length < 2) {
            _bridgeError(id,
                'octra_callView requires [contractAddr, functionName, args]');
            return;
          }
          final addr = params[0] as String;
          final fn = params[1] as String;
          final args = params.length > 2 ? params[2] as List : [];
          final caller = params.length > 3
              ? params[3] as String
              : (ws.activeWallet?.address ?? '');
          final result = await ws.rpcCall(
              ns.activeNodeUrl, 'contract_call', [addr, fn, args, caller]);
          _bridgeResult(id, jsonEncode(result));
          break;

        case 'octra_sendTransaction':
          await _handleSend(id, params, ws, ns);
          break;

        case 'octra_sendContractTransaction':
          // 0xio state-changing call: {contract, method, params, amount?, ou?}.
          await _handleContractTransaction(id, params, ws, ns);
          break;

        case 'octra_callContract':
          // Legacy array form always submits (existing behaviour). The object
          // form is a view when it carries no value, a submission otherwise.
          if (params.isNotEmpty &&
              params[0] is Map &&
              DappBridgeProtocol.isViewCall(
                  Map<String, dynamic>.from(params[0] as Map))) {
            await _handleViewObject(id, params[0] as Map, ws, ns);
            return;
          }
          if (params.isEmpty) {
            _bridgeError(id, 'octra_callContract requires params');
            return;
          }
          final contractAddr = params[0] as String;
          final fn = params[1] as String;
          final callArgs = params.length > 2 ? (params[2] as List) : [];
          final callAmount = (params.length > 3 ? params[3] : '0').toString();
          await _submitContractCall(
              id, contractAddr, fn, callArgs, callAmount, ws, ns);
          break;

        default:
          if (DappBridgeProtocol.isKnownUnsupported(method)) {
            _bridgeError(
                id,
                '$method is not supported by this wallet (sign-only '
                'submission split, message signing and FHE-private '
                'primitives stay in the wallet UI)',
                DappBridgeProtocol.unsupportedMethod);
          } else {
            _bridgeError(id, 'Unsupported method: $method',
                DappBridgeProtocol.unsupportedMethod);
          }
      }
    } catch (e) {
      _bridgeError(id, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Network record for third-party adapters: stable id + display fields.
  Map<String, dynamic> _networkInfo(NetworkService ns) {
    final mainnet = ns.activeChainId.contains('mainnet');
    return {
      'id': mainnet ? 'mainnet' : 'devnet',
      'name': mainnet ? 'Octra Mainnet' : 'Octra Devnet',
      'chainId': ns.activeChainId,
      'rpcUrl': ns.activeNodeUrl,
      'explorerUrl': ns.activeExplorerUrl,
      'isTestnet': !mainnet,
    };
  }

  /// Network switch: the wallet follows its own configured node, so a page
  /// can never move it. Answered honestly — `switched` is true only when
  /// already there.
  Future<void> _handleSwitchNetwork(
      int id, List params, NetworkService ns) async {
    var wanted = '';
    try {
      final o = DappBridgeProtocol.txObject(params);
      wanted = (o['networkId'] ?? o['network'] ?? '').toString().trim();
    } catch (_) {
      // Fall through with empty wanted (answered below, never throws).
    }
    final current = ns.activeChainId.contains('mainnet') ? 'mainnet' : 'devnet';
    final same = wanted.isNotEmpty &&
        (wanted.toLowerCase() == current ||
            wanted.toLowerCase() == ns.activeChainId.toLowerCase());
    _bridgeResult(id, jsonEncode({'network': current, 'switched': same}));
  }

  /// Approval-gated native transfer. Accepts the legacy `[{to, amount, memo?}]`
  /// and the third-party object form `{to, amount, amountOct?, message?, ...}`.
  Future<void> _handleSend(
      int id, List params, WalletService ws, NetworkService ns) async {
    late final Map<String, dynamic> tx;
    try {
      tx = DappBridgeProtocol.txObject(params);
    } catch (e) {
      _bridgeError(id, 'Invalid params: $e');
      return;
    }
    if (tx['isPrivate'] == true) {
      _bridgeError(
          id,
          'Private transfers are not served over the provider — '
          'use the wallet UI',
          DappBridgeProtocol.unsupportedMethod);
      return;
    }
    final to = (tx['to'] ?? '').toString().trim();
    if (to.isEmpty) {
      _bridgeError(id, 'Invalid params: missing recipient address');
      return;
    }
    late final String amount;
    try {
      amount = DappBridgeProtocol.resolveTxAmount(tx);
    } catch (e) {
      _bridgeError(id, 'Invalid params: $e');
      return;
    }
    if (amount == '0') {
      _bridgeError(id, 'Invalid params: amount must be greater than 0');
      return;
    }
    var memo = (tx['message'] ?? tx['memo'])?.toString().trim();
    if (memo != null) {
      if (memo.isEmpty) {
        memo = null;
      } else if (memo.length > 1000) {
        _bridgeError(id, 'Invalid params: message over 1000 chars');
        return;
      }
    }
    final approved = await _showTxConfirmDialog(
      title: 'Send Transaction',
      to: to,
      amount: amount,
      extra: memo != null ? 'Message: $memo' : null,
    );
    if (!approved) {
      _bridgeError(id, 'User rejected transaction');
      return;
    }
    final hash = await ws.sendTransaction(
      nodeUrl: ns.activeNodeUrl,
      toAddress: to,
      amount: amount,
      memo: memo,
    );
    // `hash` + `accepted` for third-party adapters; raw `tx_hash` preserved.
    _bridgeResult(
        id,
        jsonEncode({
          'tx_hash': hash,
          'hash': hash,
          'accepted': true,
          'success': true,
          'ok': true
        }));
  }

  /// Approval-gated contract submit from the object form
  /// `{contract, method, params?, amount?, ou?}`.
  Future<void> _handleContractTransaction(
      int id, List params, WalletService ws, NetworkService ns) async {
    late final Map<String, dynamic> o;
    try {
      o = DappBridgeProtocol.txObject(params);
    } catch (e) {
      _bridgeError(id, 'Invalid params: $e');
      return;
    }
    final contract = (o['contract'] ?? '').toString().trim();
    final fn = (o['method'] ?? '').toString().trim();
    if (contract.isEmpty || fn.isEmpty) {
      _bridgeError(id, 'Invalid params: call needs contract + method');
      return;
    }
    final args = o['params'] is List ? (o['params'] as List) : [];
    late final String amount;
    try {
      amount = o.containsKey('amount') && o['amount'] != null
          ? DappBridgeProtocol.resolveTxAmount(o)
          : '0';
    } catch (e) {
      _bridgeError(id, 'Invalid params: $e');
      return;
    }
    await _submitContractCall(id, contract, fn, args, amount, ws, ns);
  }

  /// Read-only view from the object form (no unlock, no approval).
  Future<void> _handleViewObject(
      int id, Map view, WalletService ws, NetworkService ns) async {
    final contract = (view['contract'] ?? '').toString().trim();
    final fn = (view['method'] ?? '').toString().trim();
    if (contract.isEmpty || fn.isEmpty) {
      _bridgeError(id, 'Invalid params: view needs contract + method');
      return;
    }
    final args = view['params'] is List ? (view['params'] as List) : [];
    final caller =
        (view['caller'] ?? ws.activeWallet?.address ?? '').toString();
    final result = await ws.rpcCall(
        ns.activeNodeUrl, 'contract_call', [contract, fn, args, caller]);
    _bridgeResult(id, jsonEncode(result));
  }

  /// Shared approval + submit for contract calls (both param shapes).
  Future<void> _submitContractCall(
      int id,
      String contractAddr,
      String fn,
      List callArgs,
      String callAmount,
      WalletService ws,
      NetworkService ns) async {
    final approved = await _showTxConfirmDialog(
      title: 'Contract Call',
      to: contractAddr,
      amount: callAmount,
      extra: 'Function: $fn',
    );
    if (!approved) {
      _bridgeError(id, 'User rejected contract call');
      return;
    }
    String txHash;
    if (callAmount != '0' && callAmount.isNotEmpty) {
      txHash = await ws.sendContractCallTx(
        nodeUrl: ns.activeNodeUrl,
        tokenAddress: contractAddr,
        toAddress: contractAddr,
        amount: callAmount,
      );
    } else {
      txHash = await ws.sendContractCall(
        nodeUrl: ns.activeNodeUrl,
        contractAddress: contractAddr,
        functionName: fn,
        args: callArgs,
      );
    }
    _bridgeResult(
        id,
        jsonEncode({
          'tx_hash': txHash,
          'hash': txHash,
          'accepted': true,
          'success': true,
          'ok': true
        }));
  }

  /// Sends a successful result back to the injected JS provider.
  void _bridgeResult(int id, String resultJson) {
    _controller.runJavaScript(
      'window.__octra_response($id, ${jsonEncode(resultJson)}, null, 0)',
    );
  }

  /// Sends an error back to the injected JS provider. The numeric RFC-O-1
  /// code travels as the 4th argument (old dApps ignore extras).
  void _bridgeError(int id, String error, [int code = 0]) {
    _controller.runJavaScript(
      'window.__octra_response($id, null, ${jsonEncode(error)}, $code)',
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  Future<bool> _showApprovalDialog({
    required String title,
    required String body,
    String confirmLabel = 'Approve',
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showTxConfirmDialog({
    required String title,
    required String to,
    required String amount,
    String? extra,
  }) async {
    if (!mounted) return false;
    final cs = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TxDetailRow(label: 'To', value: to, mono: true),
                const SizedBox(height: 8),
                _TxDetailRow(label: 'Amount', value: '$amount OCT'),
                if (extra != null) ...[
                  const SizedBox(height: 8),
                  _TxDetailRow(label: 'Info', value: extra),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Review carefully. Blockchain transactions cannot be reversed.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Navigation helpers ───────────────────────────────────────────────────

  void _navigateTo(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return;
    // oct:// circle URLs and about:blank pass through untouched.
    if (_isOctUrl(url)) {
      _loadOctUrl(url);
      return;
    }
    if (url == 'about:blank') {
      _urlCtrl.text = url;
      _controller.loadRequest(Uri.parse(url));
      return;
    }
    // Auto-prefix scheme
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _urlCtrl.text = url;
    _controller.loadRequest(Uri.parse(url));
  }

  // ── oct:// protocol support ──────────────────────────────────────────
  //
  // Octra circle URLs look like oct://<circleId>/<path> (bare circle ID
  // defaults to /index.html). If the local web server is running, pages load
  // through its /oct/ gateway with full subresource + /api support.
  // Otherwise content is fetched directly over JSON-RPC (read-only render).

  bool _isOctUrl(String url) => OctUrl.isOctUrl(url);

  /// Split oct://circleId/path into [circleId, path], preserving base58 case.
  List<String> _parseOctUrl(String url) {
    final ref = OctUrl.parse(url);
    return [ref.circleId, ref.path];
  }

  bool _isTextMime(String mime) => OctUrl.isTextMime(mime);

  Future<void> _loadOctUrl(String octUrl) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _urlCtrl.text = octUrl;
    });
    try {
      final parts = _parseOctUrl(octUrl);
      if (parts[0].isEmpty) throw Exception('circle_id required');
      final server = LocalWebServerService.instance;
      if (server.enabled && server.isRunning) {
        // Full gateway: subresources + interactive /api/* work.
        await _controller.loadRequest(Uri.parse(OctUrl.gatewayHttpUrl(
            parts[0], parts[1],
            port: LocalWebServerService.port)));
        return;
      }
      // Direct RPC fetch (read-only render, no server needed).
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final asset = await ws
          .rpcCall(ns.activeNodeUrl, 'circle_asset', [parts[0], parts[1]]);
      final map = (asset as Map?)?.cast<String, dynamic>() ?? {};
      if (map.containsKey('error')) {
        throw Exception(map['error'].toString());
      }
      final mime = OctUrl.cleanMime(map['content_type']?.toString());
      final raw = base64Decode(map['body_b64']?.toString() ?? '');
      if (!mounted) return;
      if (OctUrl.exceedsDirectLimit(raw.lengthInBytes)) {
        if (server.enabled && server.isRunning) {
          await _controller.loadRequest(Uri.parse(OctUrl.gatewayHttpUrl(
              parts[0], parts[1],
              port: LocalWebServerService.port)));
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Page too large to render directly. '
                    'Enable Local Web Server in Settings for large circle pages.')),
          );
        }
        return;
      }
      if (_isTextMime(mime)) {
        await _controller.loadHtmlString(
          utf8.decode(raw, allowMalformed: true),
          baseUrl: octUrl,
        );
      } else if (mime.startsWith('image/')) {
        await _controller.loadRequest(Uri.dataFromBytes(raw, mimeType: mime));
      } else {
        throw Exception('Preview not supported for $mime');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open $octUrl: $e')),
      );
    }
  }

  static String _shortAddr(String addr) => addr.length > 16
      ? '${addr.substring(0, 8)}…${addr.substring(addr.length - 6)}'
      : addr;

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        // Page title (truncated) or "DApp Browser" fallback
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _pageTitle.isEmpty ? 'DApp Browser' : _pageTitle,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_connectedAddress != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: Colors.green, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Connected · ${_shortAddr(_connectedAddress!)}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options',
            onPressed: _showOptionsMenu,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _isLoading
              ? LinearProgressIndicator(
                  value: _loadingProgress == 0 ? null : _loadingProgress / 100,
                  minHeight: 3,
                  backgroundColor: cs.primary.withValues(alpha: 0.1),
                  color: cs.primary,
                )
              : const SizedBox(height: 3),
        ),
      ),
      body: Column(
        children: [
          // ── URL bar + navigation controls ──────────────────────────────
          Container(
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                // Back
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: _canGoBack ? () => _controller.goBack() : null,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
                // Forward
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                  onPressed:
                      _canGoForward ? () => _controller.goForward() : null,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
                // Reload / stop
                IconButton(
                  icon: Icon(
                    _isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                    size: 18,
                  ),
                  onPressed: _isLoading
                      ? () => _controller.reload()
                      : () => _controller.reload(),
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
                // URL field
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    decoration: InputDecoration(
                      hintText: 'Enter URL or DApp address…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: cs.surface,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        child: Icon(
                          _urlCtrl.text.startsWith('https://')
                              ? Icons.lock_rounded
                              : Icons.language_rounded,
                          size: 14,
                          color: _urlCtrl.text.startsWith('https://')
                              ? Colors.green
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 28),
                    ),
                    style: const TextStyle(fontSize: 13),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _navigateTo,
                  ),
                ),
              ],
            ),
          ),

          // ── WebView ───────────────────────────────────────────────────
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),

      // ── Shortcut speed-dial ──────────────────────────────────────────
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'DApp shortcuts',
        onPressed: _showShortcuts,
        child: const Icon(Icons.apps_rounded),
      ),
    );
  }

  void _showShortcuts() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('DApp Shortcuts',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            ..._dappShortcuts.map(
              (d) => ListTile(
                leading: Text(d['icon'] ?? '🌐',
                    style: const TextStyle(fontSize: 24)),
                title: Text(d['name'] ?? ''),
                subtitle: Text(d['description'] ?? ''),
                trailing: Icon(Icons.open_in_browser_rounded,
                    size: 18, color: cs.primary),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateTo(d['url'] ?? '');
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showOptionsMenu() async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final choice = await showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(value: 'copy_url', child: Text('Copy URL')),
        const PopupMenuItem(
            value: 'disconnect', child: Text('Disconnect wallet')),
        const PopupMenuItem(value: 'reload', child: Text('Reload page')),
        const PopupMenuItem(value: 'clear', child: Text('Back to home')),
      ],
    );

    switch (choice) {
      case 'copy_url':
        // ignore: use_build_context_synchronously
        await _copyUrl();
        break;
      case 'disconnect':
        setState(() => _connectedAddress = null);
        _controller.runJavaScript(
            '(function(){ if(window.octra) { window.octra.disconnect(); } })()');
        break;
      case 'reload':
        _controller.reload();
        break;
      case 'clear':
        _navigateTo('about:blank');
        break;
    }
  }

  Future<void> _copyUrl() async {
    final url = await _controller.currentUrl() ?? '';
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copied: $url')));
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Small helper widget for transaction confirm dialog rows
// ────────────────────────────────────────────────────────────────────────────

class _TxDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _TxDetailRow(
      {required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  window.octra provider script — injected on every page load
// ────────────────────────────────────────────────────────────────────────────

/// The JavaScript provider that DApps interact with via `window.octra`.
/// This mirrors the Chrome extension's inject.js API surface so DApps built
/// for the extension work seamlessly inside the in-app browser.
const String _octraProviderJs = r'''
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

  // Called by Flutter: window.__octra_response(id, resultJson, error, code)
  // RFC-O-1: the 4th argument carries the numeric error code (0 = none).
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
        // Third-party adapters drive request() directly (never the helpers
        // above) — keep the local session flags in sync so the pre-connect
        // gate and .isConnected stay truthful.
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

    // Convenience helpers
    async getBalance() {
      return this.request({ method: 'octra_getBalance', params: [] });
    },
    // RFC-O-1 aliases (dual-stack with the legacy dialect above).
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

  // window.wallet: Orion-style high-level facade over the same bridge.
  // Only reads + session calls are served; every sign method throws
  // METHOD_FORBIDDEN locally (approvals submit here — payloads are
  // never handed out). Deliberately writable+configurable so a dApp
  // bundling its own injector neither crashes nor silently loses.
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
    const chainId = await octraProvider.request({method:'octra_chainId'});
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
      const a = await octraProvider.request({method:'octra_accounts'});
      return a.filter(x => !!x).map(address => ({address}));
    },
    async getAddress() {
      const a = await octraProvider.request({method:'octra_accounts'});
      return a[0] || '';
    },
    async getPublicKey() {
      const r = await octraProvider.request({method:'getPublicKey'});
      return r.publicKey;
    },
    async getBalance() {
      const r = await octraProvider.request({method:'octra_getBalance'});
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
      return octraProvider.request({method:'octra_chainId'});
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
      if (/^(wallet_)?(signmessage|signtypeddata|approvecontract|signcontract|signtransfer|signtransaction|submittransaction|sendtransaction|broadcasttransaction|transfer|swap|bridge)$/.test(canon)
          || /(sendtransaction|broadcast|(^|_)transfer$|(^|_)swap$|(^|_)bridge$)/.test(canon)) {
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
  } catch (e) { /* another provider won the race; window.octra above still serves */ }
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
