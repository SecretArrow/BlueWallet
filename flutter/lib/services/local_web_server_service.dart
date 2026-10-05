import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'wallet_service.dart';
import 'network_service.dart';
import 'crypto_service.dart';
import 'pin_service.dart';
import '../router/app_router.dart';

class PendingTxRequest {
  final String id;
  final String address;
  final String method;
  final String params;
  final String amount;
  final String ou;
  final Completer<Map<String, dynamic>> completer;

  PendingTxRequest({
    required this.id,
    required this.address,
    required this.method,
    required this.params,
    required this.amount,
    required this.ou,
    required this.completer,
  });
}

class LocalWebServerService extends ChangeNotifier {
  static const String _kPrefsPrefix = 'local_web_server';
  static const String _kEnabled = 'enabled';
  static const String _kAuthToken = 'auth_token';
  static const int port = 8420;

  bool _enabled = false;
  String _authToken = '';
  HttpServer? _server;

  bool get enabled => _enabled;
  String get authToken => _authToken;
  bool get isRunning => _server != null;

  static final LocalWebServerService instance = LocalWebServerService._();
  factory LocalWebServerService() => instance;

  static final Map<String, PendingTxRequest> pendingRequests = {};

  LocalWebServerService._() {
    _loadSettingsAndStart();
  }

  Future<void> _loadSettingsAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('${_kPrefsPrefix}_$_kEnabled') ?? false;
    _authToken = prefs.getString('${_kPrefsPrefix}_$_kAuthToken') ?? '';

    if (_authToken.isEmpty) {
      _authToken = _generateRandomToken();
      await prefs.setString('${_kPrefsPrefix}_$_kAuthToken', _authToken);
    }

    if (_enabled) {
      await start();
    }
  }

  String _generateRandomToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kPrefsPrefix}_$_kEnabled', enabled);

    if (enabled) {
      await start();
    } else {
      await stop();
    }
    notifyListeners();
  }

  Future<void> regenerateToken() async {
    _authToken = _generateRandomToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_kPrefsPrefix}_$_kAuthToken', _authToken);

    if (_server != null) {
      await stop();
      await start();
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port,
          shared: true);
      debugPrint(
          '[LocalWebServerService] Server listening on http://127.0.0.1:$port');
      _listen();
    } catch (e) {
      debugPrint('[LocalWebServerService] Failed to start server: $e');
      _server = null;
    }
  }

  Future<void> stop() async {
    if (_server == null) return;
    await _server!.close(force: true);
    _server = null;
    debugPrint('[LocalWebServerService] Server stopped');
  }

  void _listen() {
    _server?.listen((HttpRequest request) async {
      final response = request.response;
      // Never leave a request hanging: any escaping error becomes a 500
      // instead of a silent endless wait.
      try {
        await _route(request, response);
      } catch (e) {
        try {
          await _sendJsonError(response, HttpStatus.internalServerError,
              'Internal server error: $e');
        } catch (_) {
          debugPrint('[LocalWebServerService] failed to send 500: $e');
        }
      }
    });
  }

  /// Full API routing, extracted so the listener stays a thin fail-safe shell.
  Future<void> _route(HttpRequest request, HttpResponse response) async {

      // Handle OPTIONS preflight
      if (request.method == 'OPTIONS') {
        _addCorsHeaders(response);
        response.statusCode = HttpStatus.ok;
        await response.close();
        return;
      }

      final uriPath = request.uri.path;

      // CORS checks & Host validation
      if (uriPath.startsWith('/api/')) {
        final origin = request.headers.value('origin');
        final referer = request.headers.value('referer');

        if (origin != null &&
            origin.trim().isNotEmpty &&
            !_isSafeHost(origin)) {
          debugPrint('[LocalWebServerService] CORS origin blocked: $origin');
          await _sendJsonError(
              response, HttpStatus.forbidden, 'Forbidden: Invalid Origin');
          return;
        }
        if (referer != null &&
            referer.trim().isNotEmpty &&
            !_isSafeHost(referer)) {
          debugPrint('[LocalWebServerService] CORS referer blocked: $referer');
          await _sendJsonError(
              response, HttpStatus.forbidden, 'Forbidden: Invalid Referer');
          return;
        }
      }

      // Dynamic Circle asset rendering
      if (uriPath.startsWith('/oct/')) {
        _addCorsHeaders(response);
        await _serveCircleAssetDynamic(request, response);
        return;
      }

      // Serve static assets for non-API calls
      if (!uriPath.startsWith('/api/')) {
        await _serveStaticAsset(request, response);
        return;
      }

      // ── API routing ──
      _addCorsHeaders(response);

      // Public APIs (No authorization)
      if (uriPath == '/api/status' || uriPath == '/api/wallet/status') {
        if (request.method == 'GET') {
          await _handleStatus(response);
        } else {
          await _sendJsonError(
              response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
        return;
      }

      if (uriPath == '/api/wallet/unlock') {
        if (request.method == 'POST') {
          await _handleUnlock(request, response);
        } else {
          await _sendJsonError(
              response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
        return;
      }

      if (uriPath == '/api/contract/view') {
        if (request.method == 'GET') {
          await _handleContractView(request, response);
        } else {
          await _sendJsonError(
              response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
        return;
      }

      if (uriPath == '/api/contract/receipt') {
        if (request.method == 'GET') {
          await _handleContractReceipt(request, response);
        } else {
          await _sendJsonError(
              response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
        return;
      }

      if (uriPath == '/api/contract/call') {
        if (request.method == 'POST') {
          await _handleContractCall(request, response);
        } else {
          await _sendJsonError(
              response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
        return;
      }

      // Public: batch fee estimation (webcli GET /api/fee parity).
      if (uriPath == '/api/fee') {
        if (request.method == 'GET') {
          await _handleFee(response);
        } else {
          await _sendJsonError(
              response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
        return;
      }

      // Authenticated APIs (Bearer token check)
      if (!_isAuthorized(request)) {
        await _sendJsonError(response, HttpStatus.unauthorized, 'Unauthorized');
        return;
      }

      if ((uriPath == '/api/wallet/info' || uriPath == '/api/wallet') &&
          request.method == 'GET') {
        await _handleWalletInfo(response);
        return;
      }

      if (uriPath == '/api/balance' && request.method == 'GET') {
        await _handleBalance(response);
        return;
      }

      if (uriPath == '/api/history' && request.method == 'GET') {
        await _handleHistory(request, response);
        return;
      }

      if (uriPath == '/api/token-history' && request.method == 'GET') {
        await _handleTokenHistory(request, response);
        return;
      }

      if (uriPath == '/api/keys/info' && request.method == 'GET') {
        await _handleKeysInfo(response);
        return;
      }

      if (uriPath == '/api/stealth/outputs' && request.method == 'GET') {
        await _handleStealthOutputs(request, response);
        return;
      }

      if (uriPath == '/api/wallet/rename' && request.method == 'POST') {
        await _handleRename(request, response);
        return;
      }

      if (uriPath == '/api/wallets' && request.method == 'GET') {
        await _handleWalletList(response);
        return;
      }

      if (uriPath == '/api/circle/info' && request.method == 'GET') {
        await _handleCircleInfo(request, response);
        return;
      }

      if (uriPath == '/api/circle/asset' && request.method == 'GET') {
        await _handleCircleAsset(request, response);
        return;
      }

      if (uriPath == '/api/circle/asset_ciphertext' &&
          request.method == 'GET') {
        await _handleCircleAssetCiphertext(request, response);
        return;
      }

      if (uriPath == '/api/circle/asset_ciphertext_by_key' &&
          request.method == 'GET') {
        await _handleCircleAssetCiphertextByKey(request, response);
        return;
      }

      if (uriPath == '/api/circle/deploy' && request.method == 'POST') {
        await _handleCircleDeploy(request, response);
        return;
      }

      if (uriPath == '/api/circle/asset_encrypted' &&
          request.method == 'POST') {
        await _handleCircleAssetEncrypted(request, response);
        return;
      }

      if (uriPath == '/api/fhe/encrypt' && request.method == 'POST') {
        await _handleFheEncrypt(request, response);
        return;
      }

      if (uriPath == '/api/fhe/decrypt' && request.method == 'POST') {
        await _handleFheDecrypt(request, response);
        return;
      }

      if (uriPath == '/api/bridge/signer' && request.method == 'POST') {
        await _handleBridgeSigner(request, response);
        return;
      }

      // PVAC key rotation (webcli POST /api/key_switch parity)
      if (uriPath == '/api/key_switch' && request.method == 'POST') {
        await _handleKeySwitch(request, response);
        return;
      }

      // Fast token listing (webcli GET /api/tokens parity)
      if (uriPath == '/api/tokens' && request.method == 'GET') {
        await _handleTokens(response);
        return;
      }

      // 404 Not Found
      await _sendJsonError(response, HttpStatus.notFound, 'Not found');
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers
        .add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }

  bool _isSafeHost(String url) {
    try {
      final uri = Uri.parse(url);
      final scheme = uri.scheme;
      if (scheme == 'chrome-extension' || scheme == 'moz-extension') {
        return true;
      }
      final host = uri.host;
      if (host.isEmpty) {
        if (url.startsWith('chrome-extension://') ||
            url.startsWith('moz-extension://')) {
          return true;
        }
        return false;
      }
      return host == 'localhost' || host == '127.0.0.1';
    } catch (_) {
      return false;
    }
  }

  bool _isAuthorized(HttpRequest request) {
    final auth = request.headers.value('authorization');
    return isAuthorizedToken(_authToken, auth);
  }

  /// Bearer-token check. Fail-closed: an empty/missing configured token
  /// denies everything. Constant-time comparison. Static + pure for tests.
  static bool isAuthorizedToken(String configuredToken, String? authHeader) {
    if (configuredToken.isEmpty) {
      debugPrint('[LocalWebServerService] no auth token configured — deny');
      return false;
    }
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return false;
    }
    final presented = authHeader.substring(7).trim();
    if (presented.isEmpty) return false;
    if (presented.length != configuredToken.length) return false;
    var diff = 0;
    for (var i = 0; i < presented.length; i++) {
      diff |= presented.codeUnitAt(i) ^ configuredToken.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Bounded query integer: garbage falls back, out-of-range clamps.
  /// Static + pure for tests.
  static int parseBoundedQueryInt(Map<String, String> params, String key,
      int defaultValue, int min, int max) {
    final v = int.tryParse(params[key] ?? '') ?? defaultValue;
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  /// Non-negative integer strings (microcoin amounts, OU). Static for tests.
  static bool isUintString(String value) =>
      RegExp(r'^\d+$').hasMatch(value);

  Future<void> _sendJson(
      HttpResponse response, int status, Map<String, dynamic> data) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
  }

  Future<void> _sendJsonError(
      HttpResponse response, int status, String message) async {
    await _sendJson(response, status, {'error': message});
  }

  // ── Asset serving ──
  Future<void> _serveStaticAsset(
      HttpRequest request, HttpResponse response) async {
    var path = request.uri.path;
    if (path.startsWith('/')) path = path.substring(1);
    if (path.isEmpty) path = 'index.html';

    if (path.contains('..')) {
      _addCorsHeaders(response);
      await _sendJsonError(response, HttpStatus.forbidden, 'Forbidden');
      return;
    }

    try {
      final bytes = await _loadAssetBytes('assets/webcli/$path');
      _addCorsHeaders(response);
      response.headers.contentType = ContentType.parse(_getMimeType(path));
      response.add(bytes);
      await response.close();
    } catch (_) {
      // Try with .html extension fallback
      try {
        final bytes = await _loadAssetBytes('assets/webcli/$path.html');
        _addCorsHeaders(response);
        response.headers.contentType = ContentType.html;
        response.add(bytes);
        await response.close();
      } catch (e) {
        _addCorsHeaders(response);
        await _sendJsonError(
            response, HttpStatus.notFound, 'File not found: $path');
      }
    }
  }

  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return byteData.buffer.asUint8List();
  }

  String _getMimeType(String path) {
    if (path.endsWith('.html') || path.endsWith('.htm')) {
      return 'text/html; charset=utf-8';
    }
    if (path.endsWith('.css')) {
      return 'text/css; charset=utf-8';
    }
    if (path.endsWith('.js')) {
      return 'application/javascript; charset=utf-8';
    }
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.svg')) return 'image/svg+xml; charset=utf-8';
    if (path.endsWith('.json')) return 'application/json; charset=utf-8';
    return 'application/octet-stream';
  }

  // ── Handlers ──

  Future<void> _handleStatus(HttpResponse response) async {
    final hasWallet = WalletService.instance.activeWallet != null;
    await _sendJson(response, HttpStatus.ok, {
      'status': 'running',
      'port': port,
      'version': '1.0',
      'loaded': hasWallet,
      'wallet_loaded': hasWallet,
      'has_encrypted': hasWallet, // standard FHE capability always available
    });
  }

  Future<void> _handleUnlock(HttpRequest request, HttpResponse response) async {
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final pin = body['pin']?.toString().trim() ?? '';

      if (pin.isEmpty) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'pin is required');
        return;
      }

      final verified = await PinService.verifyPin(pin);
      if (!verified) {
        await _sendJsonError(
            response, HttpStatus.unauthorized, 'Incorrect PIN');
        return;
      }

      final ws = WalletService.instance;
      final wallet = ws.activeWallet;
      if (wallet == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'No wallet configured');
        return;
      }

      // Initialize PVAC cryptos after unlock
      await ws.initPvac();

      await _sendJson(response, HttpStatus.ok, {
        'success': true,
        'address': wallet.address,
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleWalletInfo(HttpResponse response) async {
    final ws = WalletService.instance;
    final wallet = ws.activeWallet;
    if (wallet == null) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'Wallet not loaded');
      return;
    }

    final ns = NetworkService.instance;
    await _sendJson(response, HttpStatus.ok, {
      'id': wallet.id,
      'name': wallet.name,
      'address': wallet.address,
      'wallet_type': wallet.walletType ?? 'random',
      'derivation_path': wallet.derivationPath ?? '',
      'rpc_url': ns.activeNodeUrl,
      'explorer_url': ns.activeExplorerUrl,
      'chain_id': ns.activeChainId,
      'nonce': ws.currentNonce,
    });
  }

  Future<void> _handleBalance(HttpResponse response) async {
    final ws = WalletService.instance;
    final ns = NetworkService.instance;
    final wallet = ws.activeWallet;
    if (wallet == null) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'Wallet not loaded');
      return;
    }

    try {
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);
      final res = await client.getBalance(wallet.address);

      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'RPC balance check failed');
        return;
      }

      final r = res.result;
      var publicRaw = 0;
      var encryptedRaw = 0;
      var nonce = 0;

      if (r is Map) {
        publicRaw = int.tryParse(r['public']?.toString() ?? '0') ?? 0;
        encryptedRaw = int.tryParse(r['encrypted']?.toString() ?? '0') ?? 0;
        nonce = int.tryParse(r['nonce']?.toString() ?? '0') ?? 0;
      }

      final totalRaw = publicRaw + encryptedRaw;

      await _sendJson(response, HttpStatus.ok, {
        'public_raw': publicRaw,
        'encrypted_raw': encryptedRaw,
        'total_raw': totalRaw,
        'public_oct': _formatOct(publicRaw),
        'encrypted_oct': _formatOct(encryptedRaw),
        'total_oct': _formatOct(totalRaw),
        'nonce': nonce,
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  String _formatOct(int raw) {
    return (raw / 1000000.0).toStringAsFixed(6);
  }

  Future<void> _handleHistory(
      HttpRequest request, HttpResponse response) async {
    final ws = WalletService.instance;
    final ns = NetworkService.instance;
    final wallet = ws.activeWallet;
    if (wallet == null) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'Wallet not loaded');
      return;
    }

    final params = request.uri.queryParameters;
    final limit = parseBoundedQueryInt(params, 'limit', 20, 1, 200);
    final offset = parseBoundedQueryInt(params, 'offset', 0, 0, 1000000);

    try {
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);
      final res = await client.getTxsByAddress(wallet.address, limit, offset);

      if (!res.ok) {
        await _sendJsonError(
            response, HttpStatus.badRequest, res.error ?? 'RPC history failed');
        return;
      }

      await _sendJson(response, HttpStatus.ok, {
        'history': res.result ?? [],
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleTokenHistory(
      HttpRequest request, HttpResponse response) async {
    final ws = WalletService.instance;
    final ns = NetworkService.instance;
    final wallet = ws.activeWallet;
    if (wallet == null) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'Wallet not loaded');
      return;
    }

    final params = request.uri.queryParameters;
    final limit = parseBoundedQueryInt(params, 'limit', 20, 1, 200);
    final offset = parseBoundedQueryInt(params, 'offset', 0, 0, 1000000);

    try {
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);
      // specific token transfers
      final res = await client.call(
          'octra_tokenTransfersByAddress', [wallet.address, limit, offset]);

      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'RPC token history failed');
        return;
      }

      await _sendJson(response, HttpStatus.ok, {
        'history': res.result ?? [],
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleKeysInfo(HttpResponse response) async {
    final ws = WalletService.instance;
    final wallet = ws.activeWallet;
    if (wallet == null) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'Wallet not loaded');
      return;
    }

    final skB64 = await ws.getPrivateKey(wallet.id);
    if (skB64 == null) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'PrivateKey not found');
      return;
    }

    try {
      final pkB64 = await CryptoService.publicKeyFromSk(skB64);
      final viewPk = CryptoService.getViewPublicKey(base64.decode(skB64));

      await _sendJson(response, HttpStatus.ok, {
        'public_key': pkB64,
        'view_public_key': base64.encode(viewPk),
        'address': wallet.address,
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleStealthOutputs(
      HttpRequest request, HttpResponse response) async {
    final ns = NetworkService.instance;
    final params = request.uri.queryParameters;
    final fromEpoch =
        parseBoundedQueryInt(params, 'from_epoch', 0, 0, 2147483647);

    try {
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);
      final res = await client.getStealthOutputs(fromEpoch);

      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'RPC stealth lookup failed');
        return;
      }

      await _sendJson(response, HttpStatus.ok, {
        'outputs': res.result ?? [],
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleRename(HttpRequest request, HttpResponse response) async {
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final newName = body['name']?.toString().trim() ?? '';

      if (newName.isEmpty) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'name is required');
        return;
      }

      final ws = WalletService.instance;
      final wallet = ws.activeWallet;
      if (wallet == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'No wallet active');
        return;
      }

      final success = await ws.renameWallet(wallet.id, newName);
      if (success) {
        await _sendJson(response, HttpStatus.ok, {'success': true});
      } else {
        await _sendJsonError(response, HttpStatus.badRequest,
            'Failed to rename (name already exists or invalid)');
      }
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleWalletList(HttpResponse response) async {
    final ws = WalletService.instance;
    final walletsJson = ws.wallets
        .map((w) => {
              'id': w.id,
              'name': w.name,
              'address': w.address,
              'wallet_type': w.walletType ?? 'random',
            })
        .toList();

    await _sendJson(response, HttpStatus.ok, {
      'wallets': walletsJson,
    });
  }

  // ── Contract & Circle Handlers ──
  Future<void> _handleContractView(
      HttpRequest request, HttpResponse response) async {
    final ns = NetworkService.instance;
    final ws = WalletService.instance;
    final params = request.uri.queryParameters;

    final contractAddr = params['address'] ?? '';
    final method = params['method'] ?? '';
    final paramsStr = params['params'] ?? '[]';

    if (contractAddr.isEmpty || method.isEmpty) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'Missing address or method');
      return;
    }

    try {
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      final args = jsonDecode(paramsStr) as List<dynamic>;
      final caller = ws.activeWallet?.address ?? '';

      final res =
          await client.contractCallView(contractAddr, method, args, caller);

      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'RPC contractView failed');
        return;
      }

      final r = res.result;
      var outVal = r;
      if (r is Map) {
        outVal = r['value'] ?? r['result'] ?? r;
      }

      await _sendJson(response, HttpStatus.ok, {
        'result': outVal,
        'value': outVal,
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleContractReceipt(
      HttpRequest request, HttpResponse response) async {
    final ns = NetworkService.instance;
    final params = request.uri.queryParameters;
    final txHash = params['hash'] ?? '';

    if (txHash.isEmpty) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'Missing transaction hash');
      return;
    }

    try {
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      final res = await client.getContractReceipt(txHash);

      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'RPC receipt check failed');
        return;
      }

      final r = res.result;
      var success = false;
      var errorMsg = '';

      if (r is Map) {
        final status = r['status'];
        success = r['success'] == true ||
            status == 1 ||
            status == '1' ||
            status == 'success';
        errorMsg = r['error'] ?? r['revert_reason'] ?? r['message'] ?? '';
      }

      final out = <String, dynamic>{
        'success': success,
      };
      if (errorMsg.isNotEmpty) {
        out['error'] = errorMsg;
      }

      if (r is Map) {
        r.forEach((k, v) {
          if (!out.containsKey(k)) out[k] = v;
        });
      }

      await _sendJson(response, HttpStatus.ok, out);
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleContractCall(
      HttpRequest request, HttpResponse response) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
    } catch (_) {
      await _sendJsonError(response, HttpStatus.badRequest,
          'Request body must be a JSON object');
      return;
    }
    try {
      final contractAddr = body['address']?.toString().trim() ?? '';
      final method = body['method']?.toString().trim() ?? '';
      final params = body['params'] ?? [];
      if (params is! List) {
        await _sendJsonError(response, HttpStatus.badRequest,
            'params must be a JSON array');
        return;
      }
      final paramsStr = jsonEncode(params);
      final amount = body['amount']?.toString().trim() ?? '0';
      final ou = body['ou']?.toString().trim() ?? '1000';

      if (contractAddr.isEmpty || method.isEmpty) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Missing address or method');
        return;
      }
      if (!isUintString(amount) || !isUintString(ou)) {
        await _sendJsonError(response, HttpStatus.badRequest,
            'amount and ou must be non-negative integers');
        return;
      }

      final ws = WalletService.instance;
      final wallet = ws.activeWallet;
      if (wallet == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Wallet not loaded');
        return;
      }

      final requestId =
          'req_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
      final completer = Completer<Map<String, dynamic>>();

      final req = PendingTxRequest(
        id: requestId,
        address: contractAddr,
        method: method,
        params: paramsStr,
        amount: amount,
        ou: ou,
        completer: completer,
      );

      pendingRequests[requestId] = req;

      // Navigate to confirmation screen using global router config
      // Pushing via GoRouter
      importRouterAndNavigate(requestId);

      // Wait up to 5 minutes for user confirmation
      try {
        final result =
            await completer.future.timeout(const Duration(minutes: 5));
        pendingRequests.remove(requestId);

        if (result['success'] == true) {
          await _sendJson(response, HttpStatus.ok, {
            'success': true,
            'tx_hash': result['tx_hash'],
          });
        } else {
          await _sendJson(response, HttpStatus.ok, {
            'success': false,
            'error': result['error'] ?? 'Transaction rejected by user',
          });
        }
      } on TimeoutException {
        pendingRequests.remove(requestId);
        await _sendJsonError(response, HttpStatus.requestTimeout,
            'Transaction confirmation timed out');
      }
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  void importRouterAndNavigate(String requestId) {
    try {
      AppRouter.router.push('/confirm-contract-call?id=$requestId');
    } catch (e) {
      debugPrint('[LocalWebServerService] Router navigation error: $e');
    }
  }

  Future<void> _serveCircleAssetDynamic(
      HttpRequest request, HttpResponse response) async {
    final uri = request.uri.path;
    final sub = uri.substring(5); // strip "/oct/"
    if (sub.isEmpty) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'circle_id required');
      return;
    }

    final idx = sub.indexOf('/');
    String circleId;
    String assetPath;

    if (idx == -1) {
      circleId = sub;
      assetPath = '/index.html';
    } else {
      circleId = sub.substring(0, idx);
      assetPath = sub.substring(idx);
      if (assetPath.isEmpty || assetPath == '/') {
        assetPath = '/index.html';
      }
    }

    try {
      final ns = NetworkService.instance;
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      final res = await client.call('circle_asset', [circleId, assetPath]);
      if (!res.ok || res.result == null) {
        await _sendJsonError(
            response, HttpStatus.notFound, 'Circle asset not found');
        return;
      }

      final r = res.result;
      if (r is Map) {
        if (r.containsKey('error')) {
          await _sendJsonError(
              response, HttpStatus.notFound, r['error'].toString());
          return;
        }

        final contentType =
            r['content_type']?.toString() ?? 'application/octet-stream';
        final bodyB64 = r['body_b64']?.toString() ?? '';
        final raw = base64.decode(bodyB64);

        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.parse(contentType);
        response.headers.add('Cache-Control', 'no-store');
        response.headers.add('X-Content-Type-Options', 'nosniff');
        response.add(raw);
        await response.close();
      } else {
        await _sendJsonError(
            response, HttpStatus.notFound, 'Invalid response format');
      }
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  // ── Circle APIs ──
  Future<void> _handleCircleInfo(
      HttpRequest request, HttpResponse response) async {
    final circleId = request.uri.queryParameters['circle_id'] ?? '';
    if (circleId.isEmpty) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'circle_id required');
      return;
    }

    try {
      final ns = NetworkService.instance;
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      final res = await client.call('circle_info', [circleId]);
      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'circle_info query failed');
        return;
      }

      await _sendJson(
          response,
          HttpStatus.ok,
          res.result is Map
              ? res.result as Map<String, dynamic>
              : {'result': res.result});
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleCircleAsset(
      HttpRequest request, HttpResponse response) async {
    final params = request.uri.queryParameters;
    final circleId = params['circle_id'] ?? '';
    final path = params['path'] ?? '';

    if (circleId.isEmpty || path.isEmpty) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'circle_id and path required');
      return;
    }
    if (path.contains('..')) {
      await _sendJsonError(
          response, HttpStatus.forbidden, 'Path traversal not allowed');
      return;
    }

    try {
      final ns = NetworkService.instance;
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      final res = await client.call('circle_asset', [circleId, path]);
      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'circle_asset query failed');
        return;
      }

      await _sendJson(
          response,
          HttpStatus.ok,
          res.result is Map
              ? res.result as Map<String, dynamic>
              : {'result': res.result});
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleCircleAssetCiphertext(
      HttpRequest request, HttpResponse response) async {
    final params = request.uri.queryParameters;
    final circleId = params['circle_id'] ?? '';
    final path = params['path'] ?? '';

    if (circleId.isEmpty || path.isEmpty) {
      await _sendJsonError(
          response, HttpStatus.badRequest, 'circle_id and path required');
      return;
    }
    if (path.contains('..')) {
      await _sendJsonError(
          response, HttpStatus.forbidden, 'Path traversal not allowed');
      return;
    }

    try {
      final ns = NetworkService.instance;
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      final res =
          await client.call('circle_asset_ciphertext', [circleId, path]);
      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'circle_asset_ciphertext query failed');
        return;
      }

      await _sendJson(
          response,
          HttpStatus.ok,
          res.result is Map
              ? res.result as Map<String, dynamic>
              : {'result': res.result});
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleCircleAssetCiphertextByKey(
      HttpRequest request, HttpResponse response) async {
    final params = request.uri.queryParameters;
    final circleId = params['circle_id'] ?? '';
    final resourceKey = params['resource_key'] ?? '';

    if (circleId.isEmpty || resourceKey.isEmpty) {
      await _sendJsonError(response, HttpStatus.badRequest,
          'circle_id and resource_key required');
      return;
    }

    try {
      final ns = NetworkService.instance;
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      final res = await client
          .call('circle_asset_ciphertext_by_key', [circleId, resourceKey]);
      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            res.error ?? 'circle_asset_ciphertext_by_key failed');
        return;
      }

      await _sendJson(
          response,
          HttpStatus.ok,
          res.result is Map
              ? res.result as Map<String, dynamic>
              : {'result': res.result});
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleCircleDeploy(
      HttpRequest request, HttpResponse response) async {
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      final circleId = body['circle_id']?.toString().trim() ?? '';
      if (circleId.isEmpty) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'circle_id required');
        return;
      }

      final runtime = body['runtime']?.toString() ?? 'octb';
      final privacyClass = body['privacy_class']?.toString() ?? 'sealed';
      final browserMode = body['browser_mode']?.toString() ?? 'native_sealed';
      final resourceMode = body['resource_mode']?.toString() ?? 'sealed_read';
      final codeB64 = body['code_b64']?.toString() ?? '';
      final policyHash = body['policy_hash']?.toString() ?? '';
      final membersRoot = body['members_root']?.toString() ?? '';
      final exportPolicy = body['export_policy']?.toString() ?? '';
      final ou = body['ou']?.toString().trim() ?? '200000';

      final limits = body['limits'] as Map<String, dynamic>? ?? {};
      final payloadLimits = {
        'max_stable_bytes':
            limits['max_stable_bytes']?.toString() ?? '33554432',
        'max_assets_bytes':
            limits['max_assets_bytes']?.toString() ?? '33554432',
        'max_inline_value': limits['max_inline_value']?.toString() ?? '65536',
        'max_wasm_bytes': limits['max_wasm_bytes']?.toString() ?? '33554432',
      };

      final payload = <String, dynamic>{
        'runtime': runtime,
        'privacy_class': privacyClass,
        'browser_mode': browserMode,
        'resource_mode': resourceMode,
        'limits': payloadLimits,
      };

      if (codeB64.isNotEmpty) payload['code_b64'] = codeB64;
      if (policyHash.isNotEmpty) payload['policy_hash'] = policyHash;
      if (membersRoot.isNotEmpty) payload['members_root'] = membersRoot;
      if (exportPolicy.isNotEmpty) payload['export_policy'] = exportPolicy;

      final ws = WalletService.instance;
      final wallet = ws.activeWallet;
      if (wallet == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Wallet not loaded');
        return;
      }

      final sk = await ws.getPrivateKey(wallet.id);
      if (sk == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Secure keys missing');
        return;
      }

      final ns = NetworkService.instance;
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      // fetch balance to get the correct current nonce
      final balRes = await client.getBalance(wallet.address);
      if (!balRes.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            'Failed to fetch account balance and nonce');
        return;
      }

      var nonce = 0;
      if (balRes.result is Map) {
        nonce = int.tryParse(balRes.result['nonce']?.toString() ?? '0') ?? 0;
      }
      final nextNonce = nonce + 1;

      final signedTx = await CryptoService.buildSignedGeneralTransaction(
        skBase64: sk,
        fromAddress: wallet.address,
        toAddress: circleId,
        amount: '0',
        nonce: nextNonce,
        ou: ou,
        opType: 'deploy_circle',
        message: jsonEncode(payload),
        encryptedData: '',
      );

      final submitRes = await client.submitTx(signedTx);
      if (!submitRes.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            submitRes.error ?? 'Transaction submission failed');
        return;
      }

      final out = submitRes.result is Map
          ? Map<String, dynamic>.from(submitRes.result)
          : <String, dynamic>{'result': submitRes.result};
      out['circle_id'] = circleId;
      await _sendJson(response, HttpStatus.ok, out);
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleCircleAssetEncrypted(
      HttpRequest request, HttpResponse response) async {
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      final circleId = body['circle_id']?.toString().trim() ?? '';
      final path = body['path']?.toString().trim() ?? '';
      final contentType = body['content_type']?.toString().trim() ?? '';
      final ciphertextB64 = body['ciphertext_b64']?.toString().trim() ?? '';
      final keyId = body['key_id']?.toString().trim() ?? '';
      final plaintextHash = body['plaintext_hash']?.toString().trim() ?? '';
      final encoding = body['encoding']?.toString().trim() ?? '';
      final paddingClass = body['padding_class']?.toString().trim() ?? '';
      final ou = body['ou']?.toString().trim() ?? '5000';

      if (circleId.isEmpty ||
          path.isEmpty ||
          contentType.isEmpty ||
          ciphertextB64.isEmpty ||
          keyId.isEmpty ||
          plaintextHash.isEmpty) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Missing required fields');
        return;
      }

      final payload = <String, dynamic>{
        'path': path,
        'content_type': contentType,
        'key_id': keyId,
        'plaintext_hash': plaintextHash,
      };
      if (encoding.isNotEmpty) payload['encoding'] = encoding;
      if (paddingClass.isNotEmpty) payload['padding_class'] = paddingClass;

      final ws = WalletService.instance;
      final wallet = ws.activeWallet;
      if (wallet == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Wallet not loaded');
        return;
      }

      final sk = await ws.getPrivateKey(wallet.id);
      if (sk == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Secure keys missing');
        return;
      }

      final ns = NetworkService.instance;
      final client = RpcClient();
      client.setUrl(ns.activeNodeUrl);

      // fetch balance to get the correct current nonce
      final balRes = await client.getBalance(wallet.address);
      if (!balRes.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            'Failed to fetch account balance and nonce');
        return;
      }

      var nonce = 0;
      if (balRes.result is Map) {
        nonce = int.tryParse(balRes.result['nonce']?.toString() ?? '0') ?? 0;
      }
      final nextNonce = nonce + 1;

      final signedTx = await CryptoService.buildSignedGeneralTransaction(
        skBase64: sk,
        fromAddress: wallet.address,
        toAddress: circleId,
        amount: '0',
        nonce: nextNonce,
        ou: ou,
        opType: 'circle_asset_put_encrypted',
        message: jsonEncode(payload),
        encryptedData: ciphertextB64,
      );

      final submitRes = await client.submitTx(signedTx);
      if (!submitRes.ok) {
        await _sendJsonError(response, HttpStatus.badRequest,
            submitRes.error ?? 'Transaction submission failed');
        return;
      }

      await _sendJson(
          response,
          HttpStatus.ok,
          submitRes.result is Map
              ? submitRes.result as Map<String, dynamic>
              : {'result': submitRes.result});
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleFheEncrypt(
      HttpRequest request, HttpResponse response) async {
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      if (!body.containsKey('value')) {
        await _sendJsonError(response, HttpStatus.badRequest, 'missing value');
        return;
      }

      final value = int.tryParse(body['value']?.toString() ?? '');
      if (value == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'value must be an integer');
        return;
      }

      final result = CryptoService.fheEncrypt(value);
      if (result == null) {
        await _sendJsonError(response, HttpStatus.internalServerError,
            'fheEncrypt native call returned null');
        return;
      }

      await _sendJson(response, HttpStatus.ok, result);
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleFheDecrypt(
      HttpRequest request, HttpResponse response) async {
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      final ciphertext = body['ciphertext']?.toString() ?? '';
      if (ciphertext.isEmpty) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'missing ciphertext');
        return;
      }

      final value = CryptoService.fheDecrypt(ciphertext);
      if (value == null) {
        await _sendJsonError(response, HttpStatus.internalServerError,
            'fheDecrypt native call returned null');
        return;
      }

      await _sendJson(response, HttpStatus.ok, {'value': value});
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleFee(HttpResponse response) async {
    try {
      final ws = WalletService.instance;
      final nodeUrl = NetworkService.instance.activeNodeUrl;
      final fees = await ws.fetchFeeBatch(nodeUrl);
      await _sendJson(response, HttpStatus.ok, fees);
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleKeySwitch(
      HttpRequest request, HttpResponse response) async {
    try {
      final ws = WalletService.instance;
      final nodeUrl = NetworkService.instance.activeNodeUrl;
      final result = await ws.submitKeySwitch(nodeUrl);
      await _sendJson(response, HttpStatus.ok, result);
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, 'key_switch failed: $e');
    }
  }

  Future<void> _handleTokens(HttpResponse response) async {
    try {
      final ws = WalletService.instance;
      final wallet = ws.activeWallet;
      if (wallet == null) {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Wallet not loaded');
        return;
      }
      final nodeUrl = NetworkService.instance.activeNodeUrl;
      final client = RpcClient();
      client.setUrl(nodeUrl);
      final res = await client.getTokensByAddress(wallet.address);
      if (!res.ok) {
        await _sendJsonError(response, HttpStatus.badGateway,
            res.error ?? 'tokens lookup failed');
        return;
      }
      final tokens = res.result is List
          ? res.result as List
          : (res.result is Map
              ? ((res.result as Map)['tokens'] as List? ?? [])
              : []);
      await _sendJson(response, HttpStatus.ok, {
        'tokens': tokens,
        'count': tokens.length,
        'wallet_address': wallet.address,
      });
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<void> _handleBridgeSigner(
      HttpRequest request, HttpResponse response) async {
    try {
      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      final method = body['method']?.toString() ?? '';
      if (method != 'bridgeStatus' &&
          method != 'bridgeHeader' &&
          method != 'bridgeMessagesByEpoch' &&
          method != 'bridgeProofByLeafIndex' &&
          method != 'bridgeClaimCalldata') {
        await _sendJsonError(
            response, HttpStatus.badRequest, 'Method not allowed');
        return;
      }

      // Check system env or fallback for bridge signer URL
      // Since env variables are not easily set dynamically, we can use fallback
      final signerUrl = const String.fromEnvironment('OCTRA_BRIDGE_SIGNER_URL',
          defaultValue: 'https://relayer-002838819188.octra.network');

      // Use torProxyClient to send request - automatically respects proxy settings
      final client = torProxyClient;
      final resp = await client
          .post(
            Uri.parse(signerUrl),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      response.statusCode = resp.statusCode;
      response.headers.contentType = ContentType.json;
      response.write(resp.body);
      await response.close();
    } catch (e) {
      await _sendJsonError(
          response, HttpStatus.badGateway, 'Bridge signer unavailable: $e');
    }
  }
}
