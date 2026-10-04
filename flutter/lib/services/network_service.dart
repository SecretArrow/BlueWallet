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

  /// Parse RPC URL (e.g., "https://rpc.octrascan.io" or "http://165.227.225.79:8080")
  void setUrl(String url) {
    String u = url;
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

    final colonIndex = _host.indexOf(':');
    if (colonIndex != -1) {
      _port = int.parse(_host.substring(colonIndex + 1));
      _host = _host.substring(0, colonIndex);
    }
  }

  /// Generic JSON-RPC call
  Future<RpcResult> call(
    String method, [
    List<dynamic>? params,
    int timeoutSec = 30,
  ]) async {
    _id++;
    final request = {
      'jsonrpc': '2.0',
      'method': method,
      'params': params ?? [],
      'id': _id,
    };

    try {
      final scheme = _ssl ? 'https' : 'http';
      final url = Uri.parse('$scheme://$_host:$_port$_path');
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request),
          )
          .timeout(Duration(seconds: timeoutSec));

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
      'call'
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

  /// Parse RPC response
  RpcResult _parseResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json.containsKey('result')) {
        return RpcResult.success(json['result']);
      }
      if (json.containsKey('error')) {
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

  /// Default RPC and Explorer — mirrors Android UrlSecurityValidator defaults.
  static const String defaultRpc = 'https://rpc.octrascan.io';
  static const String defaultExplorer = 'https://octrascan.io';

  static const String devnetRpc = 'http://165.227.225.79:8080';
  static const String devnetExplorer = 'https://devnet.octrascan.io';

  /// Mainnet endpoints per https://octrascan.io/docs.html
  static const String mainnetRpc = 'https://rpc.octrascan.io';
  static const String mainnetExplorer = 'https://octrascan.io';

  List<NetworkProfile> _profiles = [];

  List<NetworkProfile> get profiles => List.unmodifiable(_profiles);

  NetworkProfile? get activeProfile =>
      _profiles.where((p) => p.isActive).firstOrNull ?? _profiles.firstOrNull;

  String get activeNodeUrl => activeProfile?.nodeUrl ?? defaultRpc;

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
          nodeUrl: 'https://rpc.octrascan.io',
          explorerUrl: 'https://octrascan.io',
          isActive: true,
        ),
        const NetworkProfile(
          id: 'devnet',
          name: 'Octra Devnet',
          nodeUrl: 'http://165.227.225.79:8080',
          explorerUrl: 'https://devnet.octrascan.io',
          isActive: false,
        ),
      ];
      await _save();
    }
    notifyListeners();
  }

  Future<void> addProfile(NetworkProfile profile) async {
    _profiles.add(profile);
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

  Future<void> updateProfile(String id,
      {required String nodeUrl, required String explorerUrl}) async {
    _profiles = _profiles.map((p) {
      if (p.id != id) return p;
      return p.copyWith(nodeUrl: nodeUrl, explorerUrl: explorerUrl);
    }).toList();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString(_kNetworksKey, raw);
  }
}
