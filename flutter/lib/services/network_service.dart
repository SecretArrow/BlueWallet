import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;
import '../models/network_profile.dart';
import 'tor_proxy_service.dart';

class TorProxyHttpClient extends http.BaseClient {
  http.Client? _currentClient;
  bool? _lastEnabled;
  String? _lastHost;
  int? _lastPort;
  String? _lastType;

  http.Client _getClient() {
    final tor = TorProxyService.instance;
    if (_currentClient == null ||
        _lastEnabled != tor.enabled ||
        _lastHost != tor.activeHost ||
        _lastPort != tor.activePort ||
        _lastType != tor.activeType) {
      _lastEnabled = tor.enabled;
      _lastHost = tor.activeHost;
      _lastPort = tor.activePort;
      _lastType = tor.activeType;
      _currentClient?.close();

      final inner = HttpClient();
      inner.connectionTimeout = const Duration(seconds: 15);
      if (tor.enabled) {
        inner.findProxy = (uri) {
          final typeStr = tor.activeType == 'SOCKS' ? 'SOCKS5' : 'PROXY';
          return '$typeStr ${tor.activeHost}:${tor.activePort}';
        };
      } else {
        inner.findProxy = (uri) => 'DIRECT';
      }
      _currentClient = io_client.IOClient(inner);
    }
    return _currentClient!;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _getClient().send(request);
  }

  @override
  void close() {
    _currentClient?.close();
    _currentClient = null;
    super.close();
  }
}

final http.Client torProxyClient = TorProxyHttpClient();

const _kNetworksKey = 'network_profiles';

/// RPC call result
class RpcResult {
  final bool ok;
  final dynamic result;
  final String? error;

  RpcResult({required this.ok, this.result, this.error});

  factory RpcResult.success(dynamic result) {
    return RpcResult(ok: true, result: result);
  }

  factory RpcResult.failure(String error) {
    return RpcResult(ok: false, error: error);
  }
}

/// Enhanced RPC client with all Octra methods
/// Mirrors webcli RpcClient implementation
class RpcClient {
  String _host = '';
  String _path = '/rpc';
  bool _ssl = true;
  int _port = 443;
  int _id = 0;
  final http.Client _httpClient;

  RpcClient({http.Client? httpClient})
      : _httpClient = httpClient ?? torProxyClient;

  /// Parse RPC URL (e.g., "https://rpc.octrascan.io" or "http://165.227.225.79:8080").
  /// Throws [ArgumentError] with a specific message for unusable input
  /// (fail fast at configuration time, before any network is touched).
  void setUrl(String url) {
    String u = url.trim();
    if (u.isEmpty) {
      throw ArgumentError('RPC URL must not be empty');
    }
    _ssl = false;
    _port = 80;

    if (u.startsWith('https://')) {
      _ssl = true;
      _port = 443;
      u = u.substring(8);
    } else if (u.startsWith('http://')) {
      u = u.substring(7);
    }

    final slashIndex = u.indexOf('/');
    if (slashIndex != -1) {
      _path = u.substring(slashIndex);
      _host = u.substring(0, slashIndex);
    } else {
      _path = '/rpc';
      _host = u;
    }

    if (_path.isEmpty) {
      _path = '/rpc';
    }

    final colonIndex = _host.indexOf(':');
    if (colonIndex != -1) {
      final portStr = _host.substring(colonIndex + 1);
      final port = int.tryParse(portStr);
      if (port == null || port < 1 || port > 65535) {
        throw ArgumentError('RPC URL has invalid port "$portStr": "$url"');
      }
      _port = port;
      _host = _host.substring(0, colonIndex);
      if (_host.isEmpty) {
        throw ArgumentError('RPC URL has no host: "$url"');
      }
    } else if (_host.isEmpty) {
      throw ArgumentError('RPC URL has no host: "$url"');
    }
  }

  /// Generic JSON-RPC call.
  ///
  /// Never throws: transport, timeout, encoding and protocol problems all
  /// come back as [RpcResult.failure] with a specific message. No automatic
  /// retry by design (a blind retry could double-submit a transaction —
  /// callers decide; see assumption A6 in docs/DEFENSIVE-AUDIT.md).
  Future<RpcResult> call(
    String method, [
    List<dynamic>? params,
    int timeoutSec = 30,
  ]) async {
    if (method.trim().isEmpty) {
      return RpcResult.failure('RPC method must not be empty');
    }
    if (_host.isEmpty) {
      return RpcResult.failure(
          'RPC host is not configured — call setUrl() with a valid URL first');
    }
    final timeout = timeoutSec.clamp(1, 300).toInt();
    _id++;
    final request = {
      'jsonrpc': '2.0',
      'method': method,
      'params': params ?? [],
      'id': _id,
    };

    final String body;
    try {
      body = jsonEncode(request);
    } catch (e) {
      return RpcResult.failure('Request encoding failed: ${e.toString()}');
    }

    try {
      final scheme = _ssl ? 'https' : 'http';
      final url = Uri.parse('$scheme://$_host:$_port$_path');
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(Duration(seconds: timeout));

      return _parseResponse(response.body);
    } catch (e) {
      return RpcResult.failure('Connection failed: ${e.toString()}');
    }
  }

  /// Balance lookup
  Future<RpcResult> getBalance(String addr) {
    return call('octra_balance', [addr]);
  }

  /// Account info with optional limit
  Future<RpcResult> getAccount(String addr, [int limit = 20]) {
    return call('octra_account', [addr, limit]);
  }

  /// Transaction lookup by hash
  Future<RpcResult> getTransaction(String hash) {
    return call('octra_transaction', [hash]);
  }

  /// Submit transaction
  Future<RpcResult> submitTx(Map<String, dynamic> tx) {
    return call('octra_submit', [tx]);
  }

  /// Get view pubkey
  Future<RpcResult> getViewPubkey(String addr) {
    return call('octra_viewPubkey', [addr]);
  }

  /// Get encrypted balance (requires signature)
  Future<RpcResult> getEncryptedBalance(
    String addr,
    String sigB64,
    String pubB64,
  ) {
    return call('octra_encryptedBalance', [addr, sigB64, pubB64]);
  }

  /// Get encrypted cipher
  Future<RpcResult> getEncryptedCipher(String addr) {
    return call('octra_encryptedCipher', [addr]);
  }

  /// Register PVAC pubkey with AES-KAT
  Future<RpcResult> registerPvacPubkey(
    String addr,
    String pkB64,
    String sigB64,
    String pubB64, [
    String aesKatHex = '',
  ]) {
    return call('octra_registerPvacPubkey', [
      addr,
      pkB64,
      sigB64,
      pubB64,
      if (aesKatHex.isNotEmpty) aesKatHex,
    ]);
  }

  /// Get PVAC pubkey
  Future<RpcResult> getPvacPubkey(String addr) {
    return call('octra_pvacPubkey', [addr]);
  }

  /// Register public key
  Future<RpcResult> registerPublicKey(
    String addr,
    String pubB64,
    String sigB64,
  ) {
    return call('octra_registerPublicKey', [addr, pubB64, sigB64]);
  }

  /// Get stealth outputs
  Future<RpcResult> getStealthOutputs([int fromEpoch = 0]) {
    return call('octra_stealthOutputs', [fromEpoch]);
  }

  /// Staging view
  Future<RpcResult> stagingView() {
    return call('staging_view', [], 5);
  }

  /// Compile assembly
  Future<RpcResult> compileAssembly(String source) {
    return call('octra_compileAssembly', [source], 10);
  }

  /// Compile AML
  Future<RpcResult> compileAml(String source) {
    return call('octra_compileAml', [source], 10);
  }

  /// Compute contract address
  Future<RpcResult> computeContractAddress(
    String bytecodeB64,
    String deployer, [
    int nonce = 0,
  ]) {
    return call('octra_computeContractAddress', [bytecodeB64, deployer, nonce]);
  }

  /// Get contract info
  Future<RpcResult> getContract(String addr) {
    return call('vm_contract', [addr]);
  }

  /// Contract receipt
  Future<RpcResult> getContractReceipt(String hash) {
    return call('contract_receipt', [hash]);
  }

  /// Contract call (view)
  Future<RpcResult> contractCallView(
    String addr,
    String method,
    List<dynamic> params,
    String caller,
  ) {
    return call('contract_call', [addr, method, params, caller], 15);
  }

  /// List contracts
  Future<RpcResult> listContracts() {
    return call('octra_listContracts', [], 10);
  }

  /// Contract storage
  Future<RpcResult> getContractStorage(String addr, String key) {
    return call('octra_contractStorage', [addr, key]);
  }

  /// Contract ABI
  Future<RpcResult> getContractAbi(String addr) {
    return call('octra_contractAbi', [addr]);
  }

  /// Save ABI
  Future<RpcResult> saveAbi(String addr, String abi) {
    return call('contract_saveAbi', [addr, abi]);
  }

  /// Get transactions by address
  Future<RpcResult> getTxsByAddress(
    String addr, [
    int limit = 50,
    int offset = 0,
  ]) {
    return call('octra_transactionsByAddress', [addr, limit, offset], 15);
  }

  /// Fast token listing (webcli GET /api/tokens parity).
  Future<RpcResult> getTokensByAddress(String addr) {
    return call('octra_tokensByAddress', [addr], 15);
  }

  /// Paginated token transfers (webcli GET /api/token-history parity).
  Future<RpcResult> getTokenTransfersByAddress(
    String addr, [
    int limit = 50,
    int offset = 0,
  ]) {
    return call('octra_tokenTransfersByAddress', [addr, limit, offset], 30);
  }

  /// Batch fee estimation for all op types (webcli GET /api/fee parity).
  /// Returns a map op -> fee bucket; failed ops get safe defaults.
  Future<Map<String, dynamic>> fetchFeeBatch() async {
    const ops = [
      'standard',
      'encrypt',
      'decrypt',
      'stealth',
      'claim',
      'deploy',
      'call',
      'program_deploy',
      'program_exec',
      'multi_exec'
    ];
    final fees = <String, dynamic>{};
    for (final op in ops) {
      try {
        final r = await call('octra_recommendedFee', [op], 10);
        if (r.ok && r.result != null) {
          fees[op] = r.result;
          continue;
        }
      } catch (_) {}
      fees[op] = {
        'minimum': '1000',
        'recommended': '1000',
        'fast': '2000',
      };
    }
    return fees;
  }

  /// Parse RPC response. Never throws; every shape maps to an explicit
  /// success or failure (null results and null errors are failures, not
  /// silent nulls passed downstream).
  RpcResult _parseResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json.containsKey('result')) {
        if (json['result'] == null) {
          return RpcResult.failure('Empty result in RPC response');
        }
        return RpcResult.success(json['result']);
      }
      if (json.containsKey('error') && json['error'] != null) {
        final error = json['error'];
        final msg =
            error is Map ? error['message'] ?? 'RPC error' : error.toString();
        return RpcResult.failure(msg.toString());
      }
      return RpcResult.failure('Unknown RPC response');
    } catch (e) {
      return RpcResult.failure('Parse error: ${e.toString()}');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

class NetworkService extends ChangeNotifier {
  static NetworkService? _instance;
  static NetworkService get instance => _instance!;

  /// Default RPC and Explorer — mirrors Android UrlSecurityValidator defaults
  /// (upstream webcli parity: old hosts are dead, see migrateDeadHost).
  static const String defaultRpc = 'https://octra.network/rpc';
  static const String defaultExplorer = 'https://octrascan.io';

  static const String devnetRpc = 'https://devnet.octrascan.io/rpc';
  static const String devnetExplorer = 'https://devnet.octrascan.io';

  /// Mainnet endpoints (upstream webcli parity).
  static const String mainnetRpc = 'https://octra.network/rpc';
  static const String mainnetExplorer = 'https://octrascan.io';

  /// Maps dead RPC hosts to live ones. Applied to stored profile URLs so
  /// existing installs heal automatically.
  static String migrateDeadHost(String url) {
    var t = url.trim();
    var low = t.toLowerCase();
    while (low.endsWith('/')) {
      low = low.substring(0, low.length - 1);
      t = t.substring(0, t.length - 1);
    }
    if (low == 'http://46.101.86.250:8080' ||
        low == 'http://46.101.86.250:8080/rpc') {
      return 'https://octra.network/rpc';
    }
    if (low == 'http://165.227.225.79:8080' ||
        low == 'http://165.227.225.79:8080/rpc') {
      return 'https://devnet.octrascan.io/rpc';
    }
    if (low == 'https://rpc.octrascan.io' ||
        low == 'https://rpc.octrascan.io/rpc') {
      return 'https://octra.network/rpc';
    }
    return url;
  }

  List<NetworkProfile> _profiles = [];

  List<NetworkProfile> get profiles => List.unmodifiable(_profiles);

  NetworkProfile? get activeProfile =>
      _profiles.where((p) => p.isActive).firstOrNull ?? _profiles.firstOrNull;

  String get activeNodeUrl =>
      migrateDeadHost(activeProfile?.nodeUrl ?? defaultRpc);

  String get activeExplorerUrl => activeProfile?.explorerUrl ?? defaultExplorer;

  /// Returns the chain ID string based on active network.
  String get activeChainId {
    final url = activeNodeUrl;
    if (url.contains('rpc.octrascan.io')) return 'octra-mainnet-1';
    return 'octra-devnet-1';
  }

  /// Whether the active network is mainnet.
  bool get isMainnet => activeChainId == 'octra-mainnet-1';

  NetworkService() {
    _instance = this;
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kNetworksKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => NetworkProfile.fromJson(e as Map<String, dynamic>))
            .toList();
        _profiles = list;
      } catch (_) {}
    }
    if (_profiles.isEmpty) {
      _profiles = [
        const NetworkProfile(
          id: 'mainnet',
          name: 'Octra Mainnet',
          nodeUrl: 'https://octra.network/rpc',
          explorerUrl: 'https://octrascan.io',
          isActive: true,
        ),
        const NetworkProfile(
          id: 'devnet',
          name: 'Octra Devnet',
          nodeUrl: 'https://devnet.octrascan.io/rpc',
          explorerUrl: 'https://devnet.octrascan.io',
          isActive: false,
        ),
      ];
      await _save();
    }
    notifyListeners();
  }

  /// Test-only: clears in-memory profiles (storage untouched).
  @visibleForTesting
  void debugResetForTest() {
    _profiles = [];
  }

  /// De-duplicates a display name ("X", "X 2", …). Pure, unit-tested.
  static String dedupeName(Iterable<String> taken, String base) {    var candidate = base;
    var index = 2;
    final set = taken.toSet();
    while (set.contains(candidate)) {
      candidate = '$base $index';
      index++;
    }
    return candidate;
  }

  /// Adds a profile after trimming, validating and de-duplicating.
  /// Throws [ArgumentError] on empty id/nodeUrl. The first profile of an
  /// empty list becomes active (mirrors Android ensureDefault).
  Future<void> addProfile(NetworkProfile profile) async {
    final nodeUrl = profile.nodeUrl.trim();
    if (profile.id.trim().isEmpty) {
      throw ArgumentError('Profile id must not be empty');
    }
    if (nodeUrl.isEmpty) {
      throw ArgumentError('Profile nodeUrl must not be empty');
    }
    var name = profile.name.trim();
    if (name.isEmpty) name = 'Node';
    final candidate = dedupeName(_profiles.map((p) => p.name), name);
    final active = _profiles.isEmpty ? true : profile.isActive;
    _profiles.add(profile.copyWith(
      name: candidate,
      nodeUrl: nodeUrl,
      explorerUrl: profile.explorerUrl.trim(),
      isActive: active,
    ));
    await _save();
    notifyListeners();
  }

  Future<void> removeProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    // Ensure at least one is active
    if (_profiles.isNotEmpty && !_profiles.any((p) => p.isActive)) {
      _profiles[0] = _profiles[0].copyWith(isActive: true);
    }
    await _save();
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    _profiles = _profiles.map((p) => p.copyWith(isActive: p.id == id)).toList();
    await _save();
    notifyListeners();
  }

  /// Returns true when a profile was actually updated.
  Future<bool> updateProfile(String id,
      {required String nodeUrl, required String explorerUrl}) async {
    var found = false;
    _profiles = _profiles.map((p) {
      if (p.id != id) return p;
      found = true;
      return p.copyWith(nodeUrl: nodeUrl, explorerUrl: explorerUrl);
    }).toList();
    if (!found) return false;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString(_kNetworksKey, raw);
  }
}
