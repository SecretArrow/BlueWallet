import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/dapp/adapter_registry.dart';
import '../../services/dapp/dapp_session_store.dart';
import '../../services/dapp/js_bridge.dart';
import '../../services/dapp/octra_adapter.dart';
import '../../services/dapp/wallet_adapter.dart';
import '../../services/dapp_bridge_protocol.dart';
import '../../services/deep_link_nav.dart';
import '../../services/network_service.dart';
import '../../services/oct_url.dart';
import '../../services/recent_sites_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/startpage_view.dart';

/// In-app dApp browser: embedded WebView + modular `window.octra` provider.
///
/// Architecture:
/// - [JsBridge] owns the `OctraWalletBridge` channel: pending ids, timeouts,
///   duplicates, cancellation (navigation / tab close / WebView destroy),
///   origin + payload validation, and error-code mapping.
/// - [AdapterRegistry] + [OctraAdapter] serve methods over real wallet/RPC
///   data. Sensitive calls open an approval dialog; dismiss == reject.
/// - [DappSessionStore] grants per-origin sessions, revocable from the
///   dApp origins / permissions screens.
/// - [RecentSitesService] feeds the Startpage (last 10, deduped, persisted).
///
/// No local web server: `oct://` pages render via direct RPC fetch
/// (read-only; pages over 8 MB are refused with a clear message instead of
/// OOMing the WebView).
class DappBrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const DappBrowserScreen({super.key, this.initialUrl});

  @override
  State<DappBrowserScreen> createState() => _DappBrowserScreenState();
}

class _DappBrowserScreenState extends State<DappBrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlCtrl = TextEditingController();
  final RecentSitesService _recent = RecentSitesService.instance;
  final DappSessionStore _sessions = DappSessionStore.instance;

  JsBridge? _bridge;
  AdapterRegistry? _registry;

  bool _isLoading = false;
  int _loadingProgress = 0;
  String _pageTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _currentUrl = 'about:blank';
  bool _showingStartpage = true;
  bool _privateMode = false;
  bool _approvalOpen = false;
  bool _disposed = false;
  List<Map<String, String>> _bookmarks = [];

  static const String _kBookmarks = 'browser_bookmarks';

  static const List<Map<String, String>> _defaultShortcuts = [
    {
      'name': 'Devnet Explorer',
      'url': 'https://devnet.octrascan.io',
    },
    {
      'name': 'Mainnet Explorer',
      'url': 'https://octrascan.io',
    },
  ];

  @override
  void initState() {
    super.initState();
    final startUrl = widget.initialUrl?.trim() ?? '';
    _showingStartpage =
        startUrl.isEmpty || startUrl.toLowerCase() == 'about:blank';
    _currentUrl = _showingStartpage ? 'about:blank' : startUrl;
    _urlCtrl.text = _showingStartpage ? '' : startUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _loadingProgress = p);
        },
        onPageStarted: (url) {
          if (!mounted) return;
          final prevOrigin = _originOf(_currentUrl);
          final nextOrigin = _originOf(url);
          if (prevOrigin != nextOrigin) {
            // Navigation away cancels pending approvals for the old origin —
            // a page must never be answered after it is gone.
            _bridge?.cancelForOrigin(prevOrigin);
          }
          setState(() {
            _isLoading = true;
            _currentUrl = url;
            _urlCtrl.text = url == 'about:blank' ? '' : url;
            _pageTitle = '';
          });
        },
        onPageFinished: (url) async {
          String? title;
          bool back = false;
          bool fwd = false;
          try {
            title = await _controller.getTitle();
            back = await _controller.canGoBack();
            fwd = await _controller.canGoForward();
          } catch (_) {
            // WebView gone mid-query — keep previous state.
          }
          if (!mounted || _disposed) return;
          setState(() {
            _isLoading = false;
            _currentUrl = url;
            if (url != 'about:blank') _urlCtrl.text = url;
            _pageTitle = title ?? '';
            _canGoBack = back;
            _canGoForward = fwd;
          });
          if (!mounted || _disposed) return;
          try {
            final ns = context.read<NetworkService>();
            await _controller.runJavaScript(JsBridge.providerJs
                .replaceAll('__CHAIN_ID__', ns.activeChainId));
          } catch (_) {
            // Injection failure leaves the page without a provider; the
            // page observes no provider (honest) rather than a broken one.
          }
          // Record successful navigations for the Startpage (skips filtered
          // URLs internally; private mode skips entirely).
          if (url != 'about:blank') {
            unawaited(
                _recent.record(url, title: title ?? '', private: _privateMode));
          }
        },
        onUrlChange: (change) {
          if (change.url != null && mounted) {
            setState(() {
              _currentUrl = change.url!;
              if (change.url != 'about:blank') {
                _urlCtrl.text = change.url!;
              }
            });
          }
        },
        onNavigationRequest: (request) {
          if (OctUrl.isOctUrl(request.url)) {
            _loadOctUrl(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) {
          if (mounted) setState(() => _isLoading = false);
        },
      ));

    // Bridge wiring needs context-read services; defer one frame so
    // Provider ancestors exist.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      _initBridge();
      _loadExtras();
      if (!_showingStartpage) {
        _openUrl(_currentUrl);
      }
      // A cold-start deep link may already be pending (registered before
      // this screen existed).
      _handlePendingDeepLink();
    });

    // Deep links (octra:// circle pages, octra-wallet:// callbacks) are
    // dispatched by the app state via the DeepLinkNav bus.
    DeepLinkNav.instance.addListener(_onDeepLinkNav);
  }

  /// Deep-link listener: consume + load whatever the app state queued.
  void _onDeepLinkNav() {
    if (!mounted || _disposed) return;
    _handlePendingDeepLink();
  }

  /// Opens the URL queued by the deep-link handler (if any). Consumes it,
  /// then loads it — or explains why it cannot be opened (no silent dead
  /// ends).
  void _handlePendingDeepLink() {
    final url = DeepLinkNav.instance.pendingUrl;
    if (url == null) return;
    DeepLinkNav.instance.consumePending();
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') &&
        !lower.startsWith('https://') &&
        !lower.startsWith('oct://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deep link is not a browsable page: $url')),
      );
      return;
    }
    _openUrl(url);
  }

  void _initBridge() {
    final ws = context.read<WalletService>();
    final ns = context.read<NetworkService>();
    final registry = AdapterRegistry([OctraAdapter(wallets: ws, networks: ns)]);
    _registry = registry;
    final bridge = JsBridge(
      registry: registry,
      sessions: _sessions,
      respond: (jsId, resultJson, error, code) {
        if (_disposed) return;
        try {
          final rid = jsonEncode(jsId);
          final res = resultJson == null ? 'null' : jsonEncode(resultJson);
          final err = error == null ? 'null' : jsonEncode(error);
          unawaited(_controller.runJavaScript(
              '${JsBridge.responseFn}($rid, $res, $err, $code)'));
        } catch (_) {
          // WebView destroyed — drop the answer.
        }
      },
      currentOrigin: () => _originOf(_currentUrl),
    );
    bridge.setDispatchHook((request, completer) {
      unawaited(_dispatch(request, completer, ws, ns));
    });
    bridge.setConnectHook((jsId, completer) async {
      await _handleLegacyConnect(completer);
    });
    _bridge = bridge;
    _controller.addJavaScriptChannel(
      JsBridge.channelName,
      onMessageReceived: (msg) => unawaited(bridge.onMessage(msg.message)),
    );
    unawaited(_sessions.load());
  }

  Future<void> _loadExtras() async {
    await _recent.load();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBookmarks);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _bookmarks = decoded
              .whereType<Map>()
              .map((m) => {
                    'name': m['name']?.toString() ?? '',
                    'url': m['url']?.toString() ?? '',
                  })
              .where((m) => (m['url'] ?? '').isNotEmpty)
              .toList();
        }
      }
    } catch (_) {
      _bookmarks = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _dispatch(
      DappRequest request,
      Completer<AdapterResult> completer,
      WalletService ws,
      NetworkService ns) async {
    if (_disposed) return;
    final ctx = AdapterContext(
      requestApproval: (
              {required String title,
              required String body,
              required String confirmLabel,
              String? origin}) =>
          _showApprovalDialog(
              title: title, body: body, confirmLabel: confirmLabel),
      requestTxApproval: (
              {required String title,
              required String to,
              required String amount,
              String? extra,
              String? origin}) =>
          _showTxConfirmDialog(
              title: title, to: to, amount: amount, extra: extra),
      currentOrigin: () => _originOf(_currentUrl),
    );
    try {
      final registry = _registry;
      if (registry == null) {
        throw const DappError('Browser not ready yet');
      }
      final result = await registry.dispatch(request, ctx);
      if (_disposed || completer.isCompleted) return;
      // Grant / clear per-origin sessions for session methods.
      if (request.method == 'octra_requestAccounts' ||
          request.method == 'wallet_connect') {
        final addr =
            result is List && result.isNotEmpty ? result.first.toString() : '';
        if (addr.isNotEmpty) {
          await _sessions.grant(request.origin,
              address: addr,
              scopes: DappBridgeProtocol.requestedPermissions(request.params));
        }
      } else if (request.method == 'disconnect' ||
          request.method == 'wallet_disconnect') {
        await _sessions.revoke(request.origin);
        if (mounted) setState(() {});
      }
      if (!completer.isCompleted) completer.complete(result);
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

  Future<void> _handleLegacyConnect(Completer<String?> completer) async {
    if (_disposed) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    late final WalletService ws;
    try {
      ws = context.read<WalletService>();
    } catch (_) {
      if (!completer.isCompleted) {
        completer.completeError(const DappError(
            'No active wallet', DappBridgeProtocol.unauthorized));
      }
      return;
    }
    final address = ws.activeWallet?.address ?? '';
    if (address.isEmpty) {
      if (!completer.isCompleted) {
        completer.completeError(const DappError(
            'No active wallet', DappBridgeProtocol.unauthorized));
      }
      return;
    }
    final origin = _originOf(_currentUrl);
    final approved = await _showApprovalDialog(
      title: 'Connect Wallet',
      body: 'This dApp wants to connect to your wallet.\n\n'
          'Origin: $origin\n'
          'Address: ${_shortAddr(address)}',
      confirmLabel: 'Connect',
    );
    if (_disposed || completer.isCompleted) return;
    if (approved) {
      await _sessions.grant(origin, address: address);
      completer.complete(address);
      if (mounted) setState(() {});
    } else {
      completer.completeError(const DappError(
          'User rejected connection', DappBridgeProtocol.userRejected));
    }
  }

  // ── Approval dialogs (cancel / dismiss == reject) ──────────────────────

  /// Synchronous re-entrancy guard: only one approval dialog at a time.
  /// Parallel bridge requests beyond the first are rejected immediately
  /// (fail-safe) instead of stacking dialogs.
  bool _guardApproval() {
    if (_approvalOpen) return false;
    _approvalOpen = true;
    return true;
  }

  void _releaseApproval() => _approvalOpen = false;

  Future<bool> _showApprovalDialog({
    required String title,
    required String body,
    String confirmLabel = 'Approve',
  }) async {
    if (!mounted || _disposed) return false;
    if (!_guardApproval()) return false;
    try {
      final result = await showDialog<bool>(
            context: context,
            barrierDismissible: true,
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
      return result;
    } finally {
      _releaseApproval();
    }
  }

  Future<bool> _showTxConfirmDialog({
    required String title,
    required String to,
    required String amount,
    String? extra,
  }) async {
    if (!mounted || _disposed) return false;
    if (!_guardApproval()) return false;
    try {
      final cs = Theme.of(context).colorScheme;
      final result = await showDialog<bool>(
            context: context,
            barrierDismissible: true,
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
      return result;
    } finally {
      _releaseApproval();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  String _originOf(String url) {
    final t = url.trim();
    if (t.isEmpty || t.toLowerCase() == 'about:blank') return 'about:blank';
    if (OctUrl.isOctUrl(t)) {
      try {
        return AdapterValidation.normalizeOrigin(t);
      } catch (_) {
        return t;
      }
    }
    try {
      final uri = Uri.parse(t);
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return AdapterValidation.normalizeOrigin(t);
      }
    } catch (_) {}
    return t;
  }

  void _openUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return;
    if (OctUrl.isOctUrl(url)) {
      _loadOctUrl(url);
      return;
    }
    if (url.toLowerCase() == 'about:blank') {
      if (!mounted) return;
      setState(() {
        _showingStartpage = true;
        _currentUrl = 'about:blank';
        _urlCtrl.text = '';
        _isLoading = false;
      });
      unawaited(_controller.loadRequest(Uri.parse('about:blank')));
      return;
    }
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        !url.startsWith('oct://')) {
      url = 'https://$url';
    }
    if (!mounted) return;
    setState(() {
      _showingStartpage = false;
      _currentUrl = url;
      _urlCtrl.text = url;
      _isLoading = true;
    });
    final target = Uri.tryParse(url);
    if (target == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid URL')),
        );
      }
      return;
    }
    unawaited(_controller.loadRequest(target));
  }

  void _navigateTo(String raw) => _openUrl(raw);

  Future<void> _loadOctUrl(String octUrl) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _showingStartpage = false;
      _currentUrl = octUrl;
      _urlCtrl.text = octUrl;
    });
    try {
      final ref = OctUrl.parse(octUrl);
      if (ref.circleId.isEmpty) throw Exception('circle_id required');
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final asset = await ws
          .rpcCall(ns.activeNodeUrl, 'circle_asset', [ref.circleId, ref.path]);
      final map = asset is Map<String, dynamic>
          ? asset
          : asset is Map
              ? Map<String, dynamic>.from(asset)
              : <String, dynamic>{};
      if (map.containsKey('error')) {
        throw Exception(map['error'].toString());
      }
      final mime = OctUrl.cleanMime(map['content_type']?.toString());
      final raw = base64Decode(map['body_b64']?.toString() ?? '');
      if (!mounted || _disposed) return;
      if (OctUrl.exceedsDirectLimit(raw.lengthInBytes)) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Page too large to render directly '
                  '(over 8 MB). Only the direct-render path is supported.')),
        );
        return;
      }
      if (OctUrl.isTextMime(mime)) {
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
        SnackBar(content: Text('Cannot open $octUrl: ${_shortErr(e)}')),
      );
    }
  }

  static String _shortAddr(String addr) => addr.length > 16
      ? '${addr.substring(0, 8)}…${addr.substring(addr.length - 6)}'
      : addr;

  static String _shortErr(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 220 ? '${s.substring(0, 220)}…' : s;
  }

  @override
  void dispose() {
    _disposed = true;
    DeepLinkNav.instance.removeListener(_onDeepLinkNav);
    _bridge?.dispose();
    _bridge = null;
    _urlCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final connected =
        _sessions.isConnected(_originOf(_currentUrl)) && !_showingStartpage;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _showingStartpage
                  ? 'Browser'
                  : (_pageTitle.isEmpty ? 'DApp Browser' : _pageTitle),
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (connected)
              Text(
                'Connected · ${_originOf(_currentUrl)}${_privateMode ? ' · Private' : ''}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else if (_privateMode && !_showingStartpage)
              Text('Private mode',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () {
              if (!mounted) return;
              setState(() {
                _showingStartpage = true;
                _currentUrl = 'about:blank';
                _urlCtrl.text = '';
                _isLoading = false;
              });
              unawaited(_controller.loadRequest(Uri.parse('about:blank')));
            },
          ),
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
      body: SafeArea(
        top: false,
        bottom: true,
        left: false,
        right: false,
        child: Column(
          children: [
            Container(
              color: cs.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: _canGoBack && !_showingStartpage
                        ? () => unawaited(_controller.goBack())
                        : null,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    onPressed: _canGoForward && !_showingStartpage
                        ? () => unawaited(_controller.goForward())
                        : null,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    icon: Icon(
                      _isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                      size: 18,
                    ),
                    onPressed: _showingStartpage
                        ? null
                        : () => unawaited(_controller.reload()),
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      decoration: InputDecoration(
                        hintText: 'Enter URL or search…',
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
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 28),
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
            Expanded(
              child: _showingStartpage
                  ? ListenableBuilder(
                      listenable: Listenable.merge([_recent, _sessions]),
                      builder: (_, __) => StartpageView(
                        isLoading: !_recent.isLoaded,
                        error: _recent.error,
                        pages: _recent.pages,
                        bookmarks:
                            _bookmarks.isEmpty ? _defaultShortcuts : _bookmarks,
                        onOpen: (url, target) async {
                          // "New tab" is approximated by opening in place: the
                          // in-app browser is single-view. Documented in README.
                          _openUrl(url);
                        },
                        onDelete: (url) async => _recent.remove(url),
                        onClearAll: () async => _recent.clearAll(),
                        onRetry: () async => _recent.load(),
                        onSearch: (resolved) async => _openUrl(resolved),
                      ),
                    )
                  : WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
      floatingActionButton: _showingStartpage
          ? null
          : FloatingActionButton.small(
              tooltip: 'DApp shortcuts',
              onPressed: _showShortcuts,
              child: const Icon(Icons.apps_rounded),
            ),
    );
  }

  void _showShortcuts() {
    final cs = Theme.of(context).colorScheme;
    final shortcuts = _bookmarks.isEmpty ? _defaultShortcuts : _bookmarks;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
            ...shortcuts.map(
              (d) => ListTile(
                leading: _FaviconMini(url: d['url'] ?? ''),
                title: Text(d['name'] ?? d['url'] ?? ''),
                subtitle: Text(d['url'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          MediaQuery.sizeOf(context).width - 40, kToolbarHeight + 60, 8, 0),
      items: [
        const PopupMenuItem(value: 'copy_url', child: Text('Copy URL')),
        const PopupMenuItem(
            value: 'bookmark', child: Text('Bookmark this page')),
        PopupMenuItem(
            value: 'private',
            child: Text(_privateMode
                ? 'Exit private mode'
                : 'Private mode (no history)')),
        const PopupMenuItem(
            value: 'disconnect', child: Text('Disconnect this site')),
        const PopupMenuItem(value: 'reload', child: Text('Reload page')),
        const PopupMenuItem(value: 'home', child: Text('Back to home')),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'copy_url':
        await _copyUrl();
        break;
      case 'bookmark':
        await _addBookmark();
        break;
      case 'private':
        setState(() => _privateMode = !_privateMode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_privateMode
                  ? 'Private mode on — visits are not recorded'
                  : 'Private mode off')));
        }
        break;
      case 'disconnect':
        await _sessions.revoke(_originOf(_currentUrl));
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Site disconnected')));
        }
        try {
          await _controller.runJavaScript(
              '(function(){ if(window.octra) { window.octra.disconnect(); } })()');
        } catch (_) {}
        break;
      case 'reload':
        if (!_showingStartpage) unawaited(_controller.reload());
        break;
      case 'home':
        setState(() {
          _showingStartpage = true;
          _currentUrl = 'about:blank';
          _urlCtrl.text = '';
          _isLoading = false;
        });
        unawaited(_controller.loadRequest(Uri.parse('about:blank')));
        break;
    }
  }

  Future<void> _copyUrl() async {
    String url = '';
    try {
      url = await _controller.currentUrl() ?? _currentUrl;
    } catch (_) {
      url = _currentUrl;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copied: $url')));
  }

  Future<void> _addBookmark() async {
    if (_showingStartpage || _currentUrl == 'about:blank') return;
    final exists = _bookmarks.any((b) => b['url'] == _currentUrl);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Already bookmarked')));
      }
      return;
    }
    final updated = [
      ..._bookmarks,
      {
        'name': _pageTitle.isEmpty ? _currentUrl : _pageTitle,
        'url': _currentUrl
      }
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBookmarks, jsonEncode(updated));
    } catch (_) {}
    if (mounted) {
      setState(() => _bookmarks = updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bookmarked')));
    }
  }
}

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

class _FaviconMini extends StatelessWidget {
  final String url;
  const _FaviconMini({required this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.language_rounded, size: 18, color: cs.primary),
    );
  }
}
