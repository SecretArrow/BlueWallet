import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../services/local_web_server_service.dart';
import '../../services/oct_url.dart';

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
        await _handleRequest(
          id,
          msg['method'] as String? ?? '',
          (msg['params'] as List?)?.cast<dynamic>() ?? [],
        );
        break;
      default:
        _bridgeError(id, 'Unknown bridge message type: $type');
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
      _bridgeError(id, 'User rejected connection');
    }
  }

  Future<void> _handleRequest(int id, String method, List params) async {
    final ws = context.read<WalletService>();
    final ns = context.read<NetworkService>();
    try {
      switch (method) {
        case 'octra_accounts':
          final addr = ws.activeWallet?.address ?? '';
          _bridgeResult(id, jsonEncode([addr]));
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
          // params: [{to, amount, memo?}]
          final txParams = (params.isNotEmpty ? params[0] : {}) as Map;
          final to = txParams['to'] as String? ?? '';
          final amount = txParams['amount']?.toString() ?? '0';
          final memo = txParams['memo'] as String?;
          if (to.isEmpty) {
            _bridgeError(id, 'Missing recipient address');
            return;
          }
          final approved = await _showTxConfirmDialog(
            title: 'Send Transaction',
            to: to,
            amount: amount,
            extra: memo != null ? 'Memo: $memo' : null,
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
          _bridgeResult(id, jsonEncode({'tx_hash': hash, 'ok': true}));
          break;

        case 'octra_callContract':
          // params: [contractAddr, functionName, args, amount?]
          if (params.isEmpty) {
            _bridgeError(id, 'octra_callContract requires params');
            return;
          }
          final contractAddr = params[0] as String;
          final fn = params[1] as String;
          final callArgs = params.length > 2 ? (params[2] as List) : [];
          final callAmount = (params.length > 3 ? params[3] : '0').toString();
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
          _bridgeResult(id, jsonEncode({'tx_hash': txHash, 'ok': true}));
          break;

        default:
          _bridgeError(id, 'Unsupported method: $method');
      }
    } catch (e) {
      _bridgeError(id, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Sends a successful result back to the injected JS provider.
  void _bridgeResult(int id, String resultJson) {
    _controller.runJavaScript(
      'window.__octra_response($id, ${jsonEncode(resultJson)}, null)',
    );
  }

  /// Sends an error back to the injected JS provider.
  void _bridgeError(int id, String error) {
    _controller.runJavaScript(
      'window.__octra_response($id, null, ${jsonEncode(error)})',
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

  // Called by Flutter: window.__octra_response(id, resultJson, error)
  window.__octra_response = function(id, resultJson, error) {
    const p = _pending.get(id);
    if (!p) return;
    _pending.delete(id);
    if (error) {
      p.reject(new Error(error));
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
      if (!_connected && method !== 'octra_accounts' && method !== 'octra_chainId') {
        throw new Error('Wallet not connected. Call window.octra.connect() first.');
      }
      return _send({ type: 'request', id: ++_requestId, method, params });
    },

    // Convenience helpers
    async getBalance() {
      return this.request({ method: 'octra_getBalance', params: [] });
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

  Object.defineProperty(window, 'octra', {
    value: Object.freeze(octraProvider),
    writable: false,
    configurable: false,
  });
  window.dispatchEvent(new Event('octra#initialized'));
  console.log('[Octra] window.octra provider injected');
})();
''';
