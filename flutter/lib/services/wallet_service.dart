import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/wallet_profile.dart';
import '../models/token_balance.dart';
import '../models/tx_record.dart';
import 'crypto_service.dart';
import 'mnemonic_service.dart';
import 'native_crypto.dart';
import 'database_service.dart';
import 'network_service.dart';
import 'background_polling_service.dart';

const _storage = FlutterSecureStorage();

class WalletService extends ChangeNotifier {
  static WalletService? _instance;
  static WalletService get instance => _instance!;

  static const _kWalletListKey = 'wallet_ids';
  static const _kActiveWalletKey = 'active_wallet_id';

  List<WalletProfile> _wallets = [];
  String? _activeId;

  String _publicBalance = '0.000000';
  String _encryptedBalance = '0.000000';
  String _totalBalance = '0.000000';
  int _balanceRaw = 0;
  int _encryptedBalanceRaw = 0;
  int _currentNonce = 0;
  String? _encryptedBalanceCipher;
  List<TokenBalance> _tokens = [];
  List<TxRecord> _history = [];
  bool _loading = false;
  String? _errorMessage;
  bool _accountNotFound = false;
  int _standardFee = 1000;
  int _stealthFee = 5000;
  bool _pvacInitialised = false;

  // Auto-scan background refresh
  Timer? _autoScanTimer;
  int _autoScanMinutes = 0;
  int _autoScanCheckCount = 0;
  int _autoScanNewTxCount = 0;
  String? _autoScanLastCheck;
  String? _autoScanLastError;
  String? _autoScanNodeUrl; // cached node URL for background refresh

  // Per-wallet cache tracking
  final Map<String, bool> _walletDataLoaded =
      {}; // Track if wallet has ever loaded data
  final Map<String, bool> _walletLoadingState =
      {}; // Track loading state per wallet

  List<WalletProfile> get wallets => List.unmodifiable(_wallets);
  WalletProfile? get activeWallet =>
      _wallets.where((w) => w.id == _activeId).firstOrNull;
  String get publicBalance => _publicBalance;
  String get encryptedBalance => _encryptedBalance;
  String get totalBalance => _totalBalance;
  int get balanceRaw => _balanceRaw;
  int get encryptedBalanceRaw => _encryptedBalanceRaw;
  int get currentNonce => _currentNonce;
  String? get encryptedBalanceCipher => _encryptedBalanceCipher;
  List<TokenBalance> get tokens => List.unmodifiable(_tokens);
  List<TxRecord> get history => List.unmodifiable(_history);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  /// Per-wallet loading state - true when actively fetching data for current wallet
  bool get isWalletLoading => _walletLoadingState[_activeId] ?? false;

  /// True if wallet has ever successfully loaded data (has cache)
  bool get hasWalletData => _walletDataLoaded[_activeId] ?? false;

  /// Show loading spinner when: no cache yet AND actively loading
  bool get shouldShowLoading => !hasWalletData && isWalletLoading;

  /// Show blank/empty state when: no cache yet AND not loading (initial state)
  bool get shouldShowBlank => !hasWalletData && !isWalletLoading;

  /// True when the node reports the address has no on-chain data yet
  /// (new wallet that has never been funded).
  bool get accountNotFound => _accountNotFound;
  bool get hasWallets => _wallets.isNotEmpty;
  int get standardFee => _standardFee;
  int get stealthFee => _stealthFee;
  bool get pvacAvailable => CryptoService.pvacAvailable;
  bool get pvacInitialised => _pvacInitialised;

  // Auto-scan getters
  bool get autoScanRunning =>
      _autoScanTimer != null && _autoScanTimer!.isActive;
  int get autoScanMinutes => _autoScanMinutes;
  int get autoScanCheckCount => _autoScanCheckCount;
  int get autoScanNewTxCount => _autoScanNewTxCount;
  String? get autoScanLastCheck => _autoScanLastCheck;
  String? get autoScanLastError => _autoScanLastError;

  WalletService() {
    _instance = this;
    _init();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Auto-scan background refresh
  // ══════════════════════════════════════════════════════════════════════════

  /// Starts periodic background refresh at the given interval.
  /// Stores the setting in SharedPreferences for persistence across restarts.
  Future<void> startAutoScan(int minutes, String nodeUrl) async {
    _autoScanTimer?.cancel();
    _autoScanMinutes = minutes;
    _autoScanNodeUrl = nodeUrl;
    _autoScanLastError = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_scan_minutes', minutes);

    if (minutes <= 0) {
      _autoScanTimer = null;
      notifyListeners();
      return;
    }

    _autoScanTimer =
        Timer.periodic(Duration(minutes: minutes), (_) => _autoScanTick());
    notifyListeners();
    // Run immediately on activation
    _autoScanTick();
  }

  /// Stops the auto-scan timer.
  Future<void> stopAutoScan() async {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    _autoScanMinutes = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_scan_minutes', 0);
    notifyListeners();
  }

  /// Restores auto-scan from persisted settings. Called from MainScreen on startup.
  Future<void> restoreAutoScan(String nodeUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt('auto_scan_minutes') ?? 0;
    if (minutes > 0 && !autoScanRunning) {
      await startAutoScan(minutes, nodeUrl);
    } else {
      _autoScanNodeUrl = nodeUrl;
    }
  }

  /// Internal tick — silently refreshes balance, history, and tokens.
  Future<void> _autoScanTick() async {
    final nodeUrl = _autoScanNodeUrl;
    if (nodeUrl == null || nodeUrl.isEmpty) return;
    if (activeWallet == null) return;

    final prevHistory = _history.length;
    try {
      await refresh(nodeUrl);
      await loadHistory(nodeUrl);
      await fetchTokens(nodeUrl);

      final newTxs = _history.length - prevHistory;
      final now = DateTime.now();
      _autoScanCheckCount++;
      if (newTxs > 0) _autoScanNewTxCount += newTxs;
      _autoScanLastCheck = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      _autoScanLastError = null;
    } catch (e) {
      _autoScanLastError = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Background polling for finality and PVAC registration
  // ══════════════════════════════════════════════════════════════════════════

  /// Start background polling for transaction finality and PVAC registration
  /// Mirrors webcli's pvac_bg thread and wallet.js polling
  Future<void> startBackgroundPolling(String nodeUrl) async {
    final pollingService = BackgroundPollingService.instance;

    // Start with both finality polling and PVAC checks enabled
    await pollingService.start(
      nodeUrl: nodeUrl,
      pollFinality: true,
      checkPvac: true,
    );

    debugPrint('[WalletService] Background polling started');
  }

  /// Stop background polling
  Future<void> stopBackgroundPolling() async {
    final pollingService = BackgroundPollingService.instance;
    pollingService.stop();
    debugPrint('[WalletService] Background polling stopped');
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_kWalletListKey) ?? [];
    _wallets = [];
    for (final id in ids) {
      final raw = prefs.getString('wallet_profile_$id');
      if (raw != null) {
        try {
          _wallets.add(WalletProfile.fromJson(jsonDecode(raw)));
        } catch (_) {}
      }
    }
    _activeId = prefs.getString(_kActiveWalletKey) ?? ids.firstOrNull;
    // Pre-load cached history so the history tab shows data immediately
    // without waiting for a network response.
    if (_activeId != null) {
      try {
        _history = await _loadHistoryFromDb(_activeId!);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setActiveWallet(String id) async {
    _activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveWalletKey, id);
    _publicBalance = '0.000000';
    _encryptedBalance = '0.000000';
    _totalBalance = '0.000000';
    _balanceRaw = 0;
    _encryptedBalanceRaw = 0;
    _currentNonce = 0;
    _history = [];
    _tokens = [];
    _pvacInitialised = false;
    _accountNotFound = false;
    _errorMessage = null;
    CryptoService.pvacReset();
    notifyListeners();
  }

  Future<WalletProfile> createNewWallet(String name) async {
    final kp = await CryptoService.generateKeyPair();
    return _addWalletInternal(
        name: name,
        address: kp['address']!,
        skBase64: kp['sk']!,
        walletType: 'random');
  }

  Future<WalletProfile> importWallet(
      {required String name, required String privateKey}) async {
    final kp = await CryptoService.importFromPrivateKey(privateKey);
    return _addWalletInternal(
        name: name,
        address: kp['address']!,
        skBase64: kp['sk']!,
        walletType: 'imported');
  }

  /// Creates a wallet from a BIP-39 mnemonic phrase at the given derivation path.
  Future<WalletProfile> createFromMnemonic({
    required String name,
    required String mnemonic,
    required String path,
  }) async {
    String chosenPath = path;

    // HD Version Autodetect: Probe RPC nodes parallelly when importing mnemonics
    if (path == "m/44'/540'/0'/0'/0'" || path == "m/44'/540'/0'/0'") {
      try {
        final prefs = await SharedPreferences.getInstance();
        String nodeUrl = 'https://rpc.octrascan.io';
        final rawProfiles = prefs.getString('network_profiles');
        if (rawProfiles != null) {
          try {
            final list = jsonDecode(rawProfiles) as List<dynamic>;
            for (final item in list) {
              if (item['isActive'] == true) {
                nodeUrl = item['nodeUrl'] ?? nodeUrl;
                break;
              }
            }
          } catch (_) {}
        }

        final client = RpcClient();
        client.setUrl(nodeUrl);

        final kp1 = MnemonicService.deriveKeypair(
            mnemonic: mnemonic, path: "m/44'/540'/0'/0'/0'");
        final kp2 = MnemonicService.deriveKeypair(
            mnemonic: mnemonic, path: "m/44'/540'/0'/0'");

        final futures = await Future.wait([
          client.getBalance(kp1['address']!),
          client.getBalance(kp2['address']!),
        ]);

        final bal1Result = futures[0];
        final bal2Result = futures[1];

        int bal1 = 0;
        int bal2 = 0;

        if (bal1Result.ok && bal1Result.result != null) {
          final res = bal1Result.result;
          if (res is Map) {
            bal1 = int.tryParse(res['public']?.toString() ?? '0') ?? 0;
          } else if (res is num) {
            bal1 = res.toInt();
          } else {
            bal1 = int.tryParse(res.toString()) ?? 0;
          }
        }

        if (bal2Result.ok && bal2Result.result != null) {
          final res = bal2Result.result;
          if (res is Map) {
            bal2 = int.tryParse(res['public']?.toString() ?? '0') ?? 0;
          } else if (res is num) {
            bal2 = res.toInt();
          } else {
            bal2 = int.tryParse(res.toString()) ?? 0;
          }
        }

        debugPrint(
            '[HD Autodetect] V1 Address: ${kp1['address']} Balance: $bal1');
        debugPrint(
            '[HD Autodetect] V2 Address: ${kp2['address']} Balance: $bal2');

        if (bal2 > 0 && bal1 == 0) {
          chosenPath = "m/44'/540'/0'/0'";
          debugPrint('[HD Autodetect] Auto-detected Version 2 path');
        } else if (bal1 > 0 && bal2 == 0) {
          chosenPath = "m/44'/540'/0'/0'/0'";
          debugPrint('[HD Autodetect] Auto-detected Version 1 path');
        } else if (bal2 > 0 && bal1 > 0) {
          chosenPath = "m/44'/540'/0'/0'";
          debugPrint(
              '[HD Autodetect] Both paths have funds, preferring Version 2');
        } else {
          // Check history if both balances are 0
          final histFutures = await Future.wait([
            client.getAccount(kp1['address']!, 1),
            client.getAccount(kp2['address']!, 1),
          ]);
          final hist1 = histFutures[0].ok;
          final hist2 = histFutures[1].ok;

          if (hist2 && !hist1) {
            chosenPath = "m/44'/540'/0'/0'";
            debugPrint(
                '[HD Autodetect] V2 has history, V1 does not. Choosing V2');
          } else {
            chosenPath = "m/44'/540'/0'/0'/0'";
            debugPrint('[HD Autodetect] Defaulting to Version 1 path');
          }
        }
      } catch (e) {
        debugPrint(
            '[HD Autodetect] Failed to auto-detect: $e. Using default path: $path');
      }
    }

    final kp =
        MnemonicService.deriveKeypair(mnemonic: mnemonic, path: chosenPath);
    final profile = await _addWalletInternal(
      name: name,
      address: kp['address']!,
      skBase64: kp['sk']!,
      walletType: 'mnemonic',
      derivationPath: chosenPath,
    );
    await _storage.write(key: 'mnemonic_${profile.id}', value: mnemonic);
    return profile;
  }

  /// Returns the stored mnemonic for [walletId], or null if not available.
  Future<String?> getMnemonic(String walletId) async {
    try {
      return await _storage.read(key: 'mnemonic_$walletId');
    } catch (e) {
      debugPrint('getMnemonic error: $e');
      return null;
    }
  }

  /// Derives a child wallet from a parent mnemonic wallet at the given [index].
  /// Replaces only the last path component with [index].
  Future<WalletProfile> deriveChildWallet({
    required String parentId,
    required String name,
    required int index,
  }) async {
    // Walk up to the root mnemonic wallet if needed
    String mnemonicId = parentId;
    final parentProfile = _wallets.firstWhere((w) => w.id == parentId,
        orElse: () => throw Exception('Parent wallet not found'));
    if (parentProfile.parentId != null) mnemonicId = parentProfile.parentId!;

    final mnemonic = await getMnemonic(mnemonicId);
    if (mnemonic == null) {
      throw Exception('Mnemonic not found for wallet $mnemonicId');
    }

    final basePath = _buildBasePath(parentProfile.derivationPath ??
        parentProfile.derivationPath ??
        "m/44'/540'/0'/0'");
    final childPath = "$basePath/$index'";

    final kp =
        MnemonicService.deriveKeypair(mnemonic: mnemonic, path: childPath);
    final profile = await _addWalletInternal(
      name: name,
      address: kp['address']!,
      skBase64: kp['sk']!,
      walletType: 'child',
      derivationPath: childPath,
      parentId: mnemonicId,
    );
    return profile;
  }

  static String _buildBasePath(String fullPath) {
    final p = fullPath.trim();
    final idx = p.lastIndexOf('/');
    if (idx <= 1) return "m/44'/540'/0'/0'";
    return p.substring(0, idx);
  }

  /// Adds a wallet directly from known address + secret key (base64).
  /// Used by SetupScreen after key generation / import validation.
  Future<WalletProfile> addWalletRaw({
    required String name,
    required String address,
    required String skBase64,
  }) =>
      _addWalletInternal(
          name: name,
          address: address,
          skBase64: skBase64,
          walletType: 'imported');

  Future<WalletProfile> _addWalletInternal({
    required String name,
    required String address,
    required String skBase64,
    String? walletType,
    String? derivationPath,
    String? parentId,
  }) async {
    final id = 'wallet_${DateTime.now().millisecondsSinceEpoch}';
    final profile = WalletProfile(
      id: id,
      name: name,
      address: address,
      walletType: walletType,
      derivationPath: derivationPath,
      parentId: parentId,
    );
    try {
      await _storage.write(key: 'sk_$id', value: skBase64);
    } catch (e) {
      debugPrint('SecureStorage write error: $e');
      throw Exception('Failed to store wallet key securely. '
          'On Linux, ensure libsecret-1-dev is installed and a keyring daemon is running.');
    }
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_kWalletListKey) ?? [];
    ids.add(id);
    await prefs.setStringList(_kWalletListKey, ids);
    await prefs.setString('wallet_profile_$id', jsonEncode(profile.toJson()));
    _wallets.add(profile);
    _activeId ??= id;
    await prefs.setString(_kActiveWalletKey, _activeId!);
    notifyListeners();
    return profile;
  }

  Future<void> removeWallet(String id) async {
    if (_wallets.length <= 1) return;
    try {
      await _storage.delete(key: 'sk_$id');
      await _storage.delete(key: 'mnemonic_$id');
    } catch (e) {
      debugPrint('SecureStorage delete error: $e');
    }
    _wallets.removeWhere((w) => w.id == id);
    final prefs = await SharedPreferences.getInstance();
    final ids = _wallets.map((w) => w.id).toList();
    await prefs.setStringList(_kWalletListKey, ids);
    await prefs.remove('wallet_profile_$id');
    if (_activeId == id) {
      _activeId = ids.firstOrNull;
      if (_activeId != null) {
        await prefs.setString(_kActiveWalletKey, _activeId!);
      }
      _pvacInitialised = false;
      CryptoService.pvacReset();
    }
    notifyListeners();
  }

  /// Renames a wallet profile by id
  Future<bool> renameWallet(String id, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return false;

    final nameExists = _wallets.any(
        (w) => w.id != id && w.name.toLowerCase() == cleanName.toLowerCase());
    if (nameExists) return false;

    final index = _wallets.indexWhere((w) => w.id == id);
    if (index == -1) return false;

    final oldProfile = _wallets[index];
    final updatedProfile = WalletProfile(
      id: oldProfile.id,
      name: cleanName,
      address: oldProfile.address,
      walletType: oldProfile.walletType,
      derivationPath: oldProfile.derivationPath,
      parentId: oldProfile.parentId,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'wallet_profile_$id', jsonEncode(updatedProfile.toJson()));
    _wallets[index] = updatedProfile;
    notifyListeners();
    return true;
  }

  Future<String?> getPrivateKey(String walletId) async {
    try {
      return await _storage.read(key: 'sk_$walletId') ??
          await _storage.read(key: 'pk_$walletId');
    } catch (e) {
      debugPrint('SecureStorage read error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PVAC lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  /// Initialises PVAC key material from the active wallet's secret key.
  /// Call once after wallet unlock / selection. No-op if PVAC is unavailable
  /// on this ABI or already initialised.
  Future<bool> initPvac() async {
    if (_pvacInitialised) return true;
    if (!CryptoService.pvacAvailable) return false;
    final wallet = activeWallet;
    if (wallet == null) return false;
    final skB64 = await getPrivateKey(wallet.id);
    if (skB64 == null) return false;
    final padded =
        skB64.length % 4 == 0 ? skB64 : skB64 + '=' * (4 - skB64.length % 4);
    final sk = Uint8List.fromList(base64.decode(padded));
    _pvacInitialised = CryptoService.pvacInit(sk);
    return _pvacInitialised;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  JSON-RPC 2.0
  // ══════════════════════════════════════════════════════════════════════════

  /// Mirrors Android's BaseTxActivity.buildRpcEndpoint().
  /// Appends /rpc to the base node URL unless the path already ends in /rpc.
  static String _buildRpcEndpoint(String nodeUrl) {
    final url = nodeUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null) return '$url/rpc';
    final path = uri.path;
    if (path.isEmpty || path == '/') return '$url/rpc';
    if (path.endsWith('/rpc') || path == 'rpc') return url;
    return '$url/rpc';
  }

  Future<dynamic> _rpc(
      String nodeUrl, String method, List<dynamic> params) async {
    final url = _buildRpcEndpoint(nodeUrl);
    final body = jsonEncode(
        {'jsonrpc': '2.0', 'method': method, 'params': params, 'id': 1});
    final resp = await torProxyClient
        .post(Uri.parse(url),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('RPC ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      final e = json['error'];
      throw Exception('RPC error: ${e is Map ? e['message'] : e}');
    }
    return json['result'];
  }

  /// Public RPC entry-point for the DApp browser (and any other component that
  /// needs low-level access to the node).  Equivalent to [_rpc] but publicly
  /// accessible.
  Future<dynamic> rpcCall(
          String nodeUrl, String method, List<dynamic> params) =>
      _rpc(nodeUrl, method, params);

  // ══════════════════════════════════════════════════════════════════════════
  //  Balance / nonce
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> refresh(String nodeUrl) async {
    final wallet = activeWallet;
    if (wallet == null) return;

    // Set loading state for this wallet
    _walletLoadingState[wallet.id] = true;
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result =
          await _rpc(nodeUrl, 'octra_balance', [wallet.address]) as Map;
      final rawBalance = result['balance_raw']?.toString() ?? '0';
      _balanceRaw = int.tryParse(rawBalance) ?? 0;
      // Prefer pending_nonce (mirrors webcli) so in-flight txs get the right seq
      final nonceVal = result['pending_nonce'] ?? result['nonce'];
      _currentNonce = (nonceVal as num?)?.toInt() ?? 0;
      _publicBalance = formatOct(_balanceRaw);
      _accountNotFound = false; // address found on-chain

      // Fetch encrypted balance via a SEPARATE authenticated RPC call.
      // octra_balance does NOT contain encrypted_balance — it requires
      // octra_encryptedBalance(address, signature, pubkey) → {"cipher":"..."}
      // which is then decrypted locally via PVAC (matching webcli reference).
      _encryptedBalanceCipher = null;
      _encryptedBalanceRaw = 0;
      _encryptedBalance = '0.000000';
      try {
        final sk = await getPrivateKey(wallet.id);
        if (sk != null) {
          // Ensure PVAC is initialised before attempting encrypted balance
          if (!_pvacInitialised) await initPvac();

          final cipher =
              await _fetchEncryptedBalanceCipher(nodeUrl, wallet.address, sk);
          if (cipher.isNotEmpty && cipher != '0') {
            _encryptedBalanceCipher = cipher;
            // Try to parse as a plain number first (pre-decrypted value)
            final directVal = int.tryParse(cipher);
            if (directVal != null && directVal > 0) {
              _encryptedBalanceRaw = directVal;
              _encryptedBalance = formatOct(_encryptedBalanceRaw);
            } else if (_pvacInitialised) {
              // It's a PVAC cipher — decrypt locally
              _encryptedBalanceRaw = CryptoService.pvacDecryptBalance(cipher);
              _encryptedBalance = formatOct(_encryptedBalanceRaw);
            } else {
              // PVAC unavailable on this ABI — show raw cipher length hint
              _encryptedBalance = '0.000000';
            }
          }
        }
      } catch (e) {
        debugPrint(
            'WalletService.refresh: encrypted balance fetch failed (non-fatal): $e');
        // Non-fatal: encrypted balance is optional, public balance still valid
      }

      _totalBalance = formatOct(_balanceRaw + _encryptedBalanceRaw);

      await DatabaseService.instance.cacheBalance(
        walletId: wallet.id,
        balanceRaw: rawBalance,
        nonce: _currentNonce,
        encryptedBalance: _encryptedBalanceCipher,
      );

      // Mark wallet as having loaded data successfully
      _walletDataLoaded[wallet.id] = true;
    } catch (e) {
      final msg = _friendlyError(e);
      // Detect "new wallet / address not on chain yet" errors.
      final lower = msg.toLowerCase();
      _accountNotFound = lower.contains('not found') ||
          lower.contains('no account') ||
          lower.contains('account does not exist') ||
          lower.contains('address not found') ||
          lower.contains('unknown address') ||
          lower.contains('404');
      // Only surface the message as a real error when it's a connectivity issue.
      _errorMessage = _accountNotFound ? null : msg;
      debugPrint('WalletService.refresh: $e');
      await _loadCachedBalance(wallet.id);
      // Even on error, if we have cache, mark as loaded
      if (_balanceRaw > 0 || _publicBalance != '0.000000') {
        _walletDataLoaded[wallet.id] = true;
      }
    }

    // Clear loading state
    _walletLoadingState[wallet.id] = false;
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadCachedBalance(String id) async {
    final c = await DatabaseService.instance.getCachedBalance(id);
    if (c != null) {
      _balanceRaw = int.tryParse(c['balance_raw'].toString()) ?? 0;
      _currentNonce = (c['nonce'] as int?) ?? 0;
      _publicBalance = formatOct(_balanceRaw);
      _totalBalance = _publicBalance;
      // Mark wallet as having loaded data from cache
      _walletDataLoaded[id] = true;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Transaction history
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadHistory(String nodeUrl,
      {int limit = 100, int offset = 0}) async {
    final wallet = activeWallet;
    if (wallet == null) return;

    // Show cached history immediately so the UI is never blank while loading.
    if (_history.isEmpty) {
      _history = await _loadHistoryFromDb(wallet.id);
      if (_history.isNotEmpty) notifyListeners();
    }

    _loading = true;
    notifyListeners();
    try {
      final result = await _rpc(nodeUrl, 'octra_transactionsByAddress',
          [wallet.address, limit, offset]) as Map;
      final txList = ((result['transactions'] ??
              result['history'] ??
              result['txs'] ??
              []) as List)
          .cast<Map<String, dynamic>>();
      // Refresh status of pending local txs: if the server now returns them,
      // their status will be updated (replace strategy in upsertTxHistory).
      await DatabaseService.instance.upsertTxHistory(wallet.id, txList);
    } catch (e) {
      debugPrint('WalletService.loadHistory: $e');
    }
    _history = await _loadHistoryFromDb(wallet.id);
    _loading = false;
    notifyListeners();
  }

  Future<List<TxRecord>> _loadHistoryFromDb(String walletId) async {
    final rows = await DatabaseService.instance.getTxHistory(walletId);
    final addr = activeWallet?.address ?? '';
    return rows.map((row) {
      final from = row['from_addr']?.toString() ?? '';
      return TxRecord(
        hash: row['hash']?.toString() ?? '',
        type: from == addr ? 'sent' : 'received',
        amount: _normalizeHistoryAmount(row['amount']?.toString() ?? '0'),
        fromAddress: from,
        toAddress: row['to_addr']?.toString() ?? '',
        timestamp: _normalizeTimestamp(row['timestamp']),
        status: _normalizeStatus(row['status']?.toString()),
        opType: row['op_type']?.toString() ?? 'standard',
        fee: row['fee']?.toString(),
        blockHash: row['block_hash']?.toString(),
      );
    }).toList();
  }

  /// Normalises node / DB status strings to a consistent internal set:
  /// 'confirmed' | 'sent' | 'pending' | 'failed' | 'error'
  static String _normalizeStatus(String? raw) {
    if (raw == null || raw.isEmpty) return 'confirmed';
    switch (raw.toLowerCase()) {
      case 'confirmed':
      case 'success':
      case 'ok':
        return 'confirmed';
      case 'sent':
      case 'broadcasted':
        return 'sent';
      case 'pending':
      case 'processing':
      case 'submitted':
      case 'mempool':
        return 'pending';
      case 'failed':
      case 'failure':
      case 'rejected':
      case 'invalid':
        return 'failed';
      case 'error':
        return 'error';
      default:
        return raw.toLowerCase();
    }
  }

  /// Normalizes a stored amount that may be either a raw microcoin integer
  /// (e.g. "1000000") or an already-formatted OCT decimal (e.g. "1.000000").
  /// Matches Android's formatOct(long) display path.
  static String _normalizeHistoryAmount(String amount) {
    if (amount.contains('.')) return amount; // already decimal OCT
    final i = int.tryParse(amount);
    if (i != null) return formatOct(i); // raw microcoin → OCT
    return amount;
  }

  /// Normalizes a DB timestamp that could be either Unix seconds or
  /// Unix milliseconds. Returns Unix milliseconds for use with
  /// DateTime.fromMillisecondsSinceEpoch().
  static int _normalizeTimestamp(dynamic ts) {
    if (ts == null) return 0;
    final i = ts is int ? ts : int.tryParse(ts.toString()) ?? 0;
    // Values above 1e12 are already in ms; below that are seconds.
    return i > 1000000000000 ? i : i * 1000;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Send transactions
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetches recommended fees via JSON-RPC {@code octra_recommendedFee}.
  ///
  /// Replaces the old REST `/api/fee` endpoint which only exists on the
  /// webcli local server, not on the blockchain node itself.
  Future<void> fetchFees(String nodeUrl) async {
    try {
      final result = await _rpc(nodeUrl, 'octra_recommendedFee', []) as Map;
      final standard = result['standard'] as Map?;
      final stealth = result['stealth'] as Map?;
      _standardFee =
          int.tryParse(standard?['recommended']?.toString() ?? '') ?? 1000;
      _stealthFee =
          int.tryParse(stealth?['recommended']?.toString() ?? '') ?? 5000;
      notifyListeners();
    } catch (_) {}
  }

  /// Sends a standard OCT transfer.
  Future<String> sendTransaction({
    required String nodeUrl,
    required String toAddress,
    required String amount,
    String? memo,
  }) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    // Convert decimal OCT to raw microcoins, matching Android's amountRaw = (long)(inputAmount * 1_000_000)
    final amountRaw = parseOct(amount);
    if (amountRaw < 0) throw Exception('Amount cannot be negative');

    await refresh(nodeUrl);
    final nonce = _currentNonce + 1;

    final signedTx = await CryptoService.buildSignedTransfer(
      skBase64: sk,
      fromAddress: wallet.address,
      toAddress: toAddress,
      amount: amountRaw.toString(),
      nonce: nonce,
      message: memo ?? '',
    );

    final result = await _rpc(nodeUrl, 'octra_submit', [signedTx]) as Map;
    final hash = result['tx_hash']?.toString() ?? '';

    await _recordTx(
        wallet, hash, toAddress, amountRaw.toString(), 'standard', memo);
    return hash;
  }

  /// Sends a contract call transaction (e.g. token transfer).
  Future<String> sendContractCallTx({
    required String nodeUrl,
    required String tokenAddress,
    required String toAddress,
    required String amount,
    String ou = '1000',
  }) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    await refresh(nodeUrl);
    final nonce = _currentNonce + 1;

    final signedTx = await CryptoService.buildSignedContractCall(
      skBase64: sk,
      fromAddress: wallet.address,
      tokenAddress: tokenAddress,
      toAddress: toAddress,
      amount: amount,
      nonce: nonce,
      ou: ou,
    );

    final result = await _rpc(nodeUrl, 'octra_submit', [signedTx]) as Map;
    final hash = result['tx_hash']?.toString() ?? '';

    await _recordTx(wallet, hash, tokenAddress, '0', 'call',
        'transfer $amount to $toAddress');
    return hash;
  }

  /// Encrypts a public balance amount into the PVAC encrypted balance.
  Future<String> sendEncryptTx({
    required String nodeUrl,
    required int amount,
  }) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    if (!_pvacInitialised) throw Exception('PVAC not initialised');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    // Ensure PVAC is registered on-chain before encrypt tx (mirrors Android ensurePvacRegistered)
    await _ensurePvacRegistered(nodeUrl, wallet.address, sk);

    await refresh(nodeUrl);
    final nonce = _currentNonce + 1;

    final signedTx = await CryptoService.buildSignedEncryptTx(
      skBase64: sk,
      fromAddress: wallet.address,
      amount: amount,
      nonce: nonce,
    );

    final result = await _rpc(nodeUrl, 'octra_submit', [signedTx]) as Map;
    final hash = result['tx_hash']?.toString() ?? '';

    await _recordTx(
        wallet, hash, wallet.address, amount.toString(), 'encrypt', null);
    return hash;
  }

  /// Decrypts a PVAC encrypted balance amount back to public balance.
  Future<String> sendDecryptTx({
    required String nodeUrl,
    required int amount,
  }) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    if (!_pvacInitialised) throw Exception('PVAC not initialised');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    // Ensure PVAC is registered on-chain before decrypt tx
    await _ensurePvacRegistered(nodeUrl, wallet.address, sk);

    await refresh(nodeUrl);
    final nonce = _currentNonce + 1;

    final signedTx = await CryptoService.buildSignedDecryptTx(
      skBase64: sk,
      fromAddress: wallet.address,
      amount: amount,
      nonce: nonce,
    );

    final result = await _rpc(nodeUrl, 'octra_submit', [signedTx]) as Map;
    final hash = result['tx_hash']?.toString() ?? '';

    await _recordTx(
        wallet, hash, wallet.address, amount.toString(), 'decrypt', null);
    return hash;
  }

  /// Sends a stealth transaction (private transfer via FHE).
  Future<String> sendStealthTx({
    required String nodeUrl,
    required String toAddress,
    required int amount,
  }) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    if (!_pvacInitialised) throw Exception('PVAC not initialised');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    // Fetch recipient's view pubkey
    final viewPubB64 = await getViewPubkey(nodeUrl, toAddress);
    if (viewPubB64 == null || viewPubB64.isEmpty) {
      throw Exception('Recipient has no registered view pubkey');
    }
    final viewPub = Uint8List.fromList(base64.decode(viewPubB64));

    // Ensure PVAC is registered on-chain before stealth tx
    await _ensurePvacRegistered(nodeUrl, wallet.address, sk);

    // Refresh nonce; then fetch encrypted cipher via authenticated RPC (mirrors Android fetchEncryptedBalanceCipher)
    await refresh(nodeUrl);
    final encCipher =
        await _fetchEncryptedBalanceCipher(nodeUrl, wallet.address, sk);
    if (encCipher.isEmpty || encCipher == '0') {
      throw Exception(
          'No encrypted balance available. Please encrypt some balance first.');
    }

    final nonce = _currentNonce + 1;

    final signedTx = await CryptoService.buildSignedStealthTx(
      skBase64: sk,
      fromAddress: wallet.address,
      amount: amount,
      nonce: nonce,
      currentEncCipher: encCipher,
      theirViewPubkey: viewPub,
      recipientAddress: toAddress,
    );

    final result = await _rpc(nodeUrl, 'octra_submit', [signedTx]) as Map;
    final hash = result['tx_hash']?.toString() ?? '';

    await _recordTx(
        wallet, hash, 'stealth', '0', 'stealth', 'stealth to $toAddress');
    return hash;
  }

  /// Records a pending transaction in the local database and updates history.
  Future<void> _recordTx(WalletProfile wallet, String hash, String to,
      String amount, String opType, String? memo) async {
    await DatabaseService.instance.upsertTxHistory(wallet.id, [
      {
        'hash': hash,
        'from': wallet.address,
        'to_': to,
        'amount': amount,
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
        'op_type': opType,
        'status': 'pending',
        'message': memo,
      }
    ]);
    _history = await _loadHistoryFromDb(wallet.id);
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Stealth / PVAC helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Looks up a transaction by hash via the node RPC.
  /// Returns status map with 'status' (confirmed|pending|failed) and details.
  Future<Map<String, dynamic>> lookupTransaction(
      String nodeUrl, String txHash) async {
    final result = await _rpc(nodeUrl, 'octra_transaction', [txHash])
        as Map<String, dynamic>;
    return result;
  }

  /// Reads a single storage slot from a contract via octra_contractStorage.
  /// Returns null on any error (missing key, RPC failure, etc.).
  Future<String?> _contractStorage(
      String nodeUrl, String addr, String key) async {
    try {
      final result =
          await _rpc(nodeUrl, 'octra_contractStorage', [addr, key]) as Map;
      return result['value']?.toString() ?? result['result']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Formats a raw token integer using the contract's decimal places.
  /// Uses pure integer/string arithmetic to avoid floating-point precision loss.
  static String _formatTokenBalance(String rawValue, int decimals) {
    if (rawValue.isEmpty || rawValue == '0') return '0';
    try {
      if (decimals <= 0) return rawValue;
      // Use BigInt for arbitrary-precision token amounts
      final raw = BigInt.tryParse(rawValue);
      if (raw == null || raw == BigInt.zero) return '0';
      final divisor = BigInt.from(10).pow(decimals);
      final whole = raw ~/ divisor;
      final frac = (raw % divisor).abs();
      if (frac == BigInt.zero) return whole.toString();
      String fracStr = frac.toString().padLeft(decimals, '0');
      // Strip trailing zeros
      int lastNonZero = fracStr.length;
      while (lastNonZero > 1 && fracStr[lastNonZero - 1] == '0') {
        lastNonZero--;
      }
      fracStr = fracStr.substring(0, lastNonZero);
      return '$whole.$fracStr';
    } catch (_) {
      return rawValue;
    }
  }

  /// Fetches the token list from the network.
  /// Mirrors Android MainActivity.fetchContractTokens():
  ///   1. octra_listContracts → {contracts: [...]}
  ///   2. octra_contractStorage(addr, 'symbol') — skip if empty
  ///   3. contract_call(addr, 'balance_of', [wallet], wallet) — skip if zero
  ///   4. octra_contractStorage for name + decimals
  ///
  /// Contracts are probed concurrently (up to 8 at a time) for performance.
  /// Results are cached to the local database for offline access.
  Future<void> fetchTokens(String nodeUrl) async {
    final wallet = activeWallet;
    if (wallet == null) return;

    // 0) Show cached tokens immediately while fresh data loads
    if (_tokens.isEmpty) {
      try {
        final cached =
            await DatabaseService.instance.getCachedTokens(wallet.id);
        if (cached.isNotEmpty) {
          _tokens = cached
              .map((m) => TokenBalance(
                    symbol: m['symbol']?.toString() ?? '',
                    name: m['name']?.toString() ?? '',
                    balance: m['balance']?.toString() ?? '0',
                    address: m['address']?.toString() ?? '',
                  ))
              .toList();
          notifyListeners();
        }
      } catch (_) {}
    }

    try {
      // Fast path (webcli GET /api/tokens parity): single
      // octra_tokensByAddress call instead of probing every contract.
      try {
        final dynamic fast =
            await _rpc(nodeUrl, 'octra_tokensByAddress', [wallet.address]);
        List fastList;
        if (fast is List) {
          fastList = fast;
        } else if (fast is Map && fast['tokens'] is List) {
          fastList = fast['tokens'];
        } else {
          fastList = [];
        }
        if (fastList.isNotEmpty) {
          final tokenList = <TokenBalance>[];
          for (final item in fastList) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            final addr = m['address']?.toString() ?? '';
            final symbol = m['symbol']?.toString() ?? '';
            final balance = m['balance']?.toString() ?? '0';
            if (addr.isEmpty ||
                symbol.isEmpty ||
                balance == '0' ||
                balance.isEmpty) {
              continue;
            }
            final name = (m['name']?.toString() ?? '').isEmpty
                ? symbol
                : m['name'].toString();
            final decimals = int.tryParse(m['decimals']?.toString() ?? '') ?? 0;
            tokenList.add(TokenBalance(
              symbol: symbol,
              name: name,
              balance: _formatTokenBalance(balance, decimals),
              address: addr,
            ));
          }
          if (tokenList.isNotEmpty) {
            _tokens = tokenList;
            notifyListeners();
            try {
              await DatabaseService.instance.cacheTokens(
                wallet.id,
                tokenList
                    .map((t) => {
                          'symbol': t.symbol,
                          'name': t.name,
                          'balance': t.balance,
                          'address': t.address,
                        })
                    .toList(),
              );
            } catch (_) {}
            return;
          }
        }
      } catch (_) {
        // fall through to listContracts probing
      }

      // octra_listContracts returns {contracts: [...]}, not a bare JSON array.
      final raw = await _rpc(nodeUrl, 'octra_listContracts', []) as Map;
      final contracts =
          ((raw['contracts'] as List?) ?? []).cast<Map<String, dynamic>>();

      // Process contracts in parallel batches of 8 for performance
      final tokenList = <TokenBalance>[];
      const batchSize = 8;
      for (int batchStart = 0;
          batchStart < contracts.length;
          batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize > contracts.length)
            ? contracts.length
            : batchStart + batchSize;
        final batch = contracts.sublist(batchStart, batchEnd);

        final futures = batch.map((contract) async {
          final addr = contract['address']?.toString() ?? '';
          if (addr.isEmpty) return null;
          try {
            // 1) Symbol from storage (required — skip contract if missing)
            String? symbol = await _contractStorage(nodeUrl, addr, 'symbol');
            if (symbol == null || symbol.isEmpty || symbol == '0') return null;

            // 2) Balance via contract_call (4 params incl. caller)
            final balResult = await _rpc(nodeUrl, 'contract_call', [
              addr,
              'balance_of',
              [wallet.address],
              wallet.address, // caller
            ]) as Map;
            final balance = balResult['result']?.toString() ?? '0';
            if (balance == '0' || balance.isEmpty) return null;

            // 3) Name + decimals from storage (can be fetched in parallel)
            final nameAndDecimals = await Future.wait([
              _contractStorage(nodeUrl, addr, 'name'),
              _contractStorage(nodeUrl, addr, 'decimals'),
            ]);
            String name = nameAndDecimals[0] ?? symbol;
            if (name.isEmpty) name = symbol;
            if (name.length > 32) name = name.substring(0, 32);

            final decimals = int.tryParse(nameAndDecimals[1] ?? '') ?? 0;

            return TokenBalance(
              symbol: symbol,
              name: name,
              balance: _formatTokenBalance(balance, decimals),
              address: addr,
            );
          } catch (_) {
            return null;
          }
        }).toList();

        final results = await Future.wait(futures);
        for (final token in results) {
          if (token != null) tokenList.add(token);
        }
      }
      _tokens = tokenList;
      notifyListeners();

      // Persist to local cache for offline access
      try {
        await DatabaseService.instance.cacheTokens(
          wallet.id,
          tokenList
              .map((t) => {
                    'symbol': t.symbol,
                    'name': t.name,
                    'balance': t.balance,
                    'address': t.address,
                  })
              .toList(),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('WalletService.fetchTokens: $e');
    }
  }

  /// Scans for incoming stealth outputs. Calls octra_stealthOutputs then
  /// tries ECDH with each output's ephPub to match our stealth tag.
  Future<List<Map<String, dynamic>>> scanStealthOutputs(String nodeUrl) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    final skBytes = Uint8List.fromList(base64.decode(sk));
    final viewKp = NativeCrypto.deriveViewKeypair(skBytes);
    final viewSk = viewKp['sk']!;

    // Fetch all stealth outputs from the network
    final result = await _rpc(nodeUrl, 'octra_stealthOutputs', []) as List;
    final found = <Map<String, dynamic>>[];

    for (final output in result) {
      try {
        final ephPubB64 = output['eph_pub']?.toString() ?? '';
        final stealthTagHex = output['stealth_tag']?.toString() ?? '';
        if (ephPubB64.isEmpty || stealthTagHex.isEmpty) continue;

        final ephPub = Uint8List.fromList(base64.decode(ephPubB64));
        // Compute ECDH with our view secret key and sender's ephemeral pubkey
        final shared = NativeCrypto.ecdh(viewSk, ephPub);
        final ourTag = NativeCrypto.stealthTag(shared);
        final ourTagHex =
            ourTag.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        if (ourTagHex == stealthTagHex) {
          // This stealth output is for us
          String amount = '(encrypted)';
          final encAmount = output['enc_amount']?.toString();
          if (encAmount != null && encAmount.isNotEmpty && _pvacInitialised) {
            try {
              final raw = CryptoService.pvacDecryptBalance(encAmount);
              amount = formatOct(raw);
            } catch (_) {}
          }
          found.add({
            'tx_hash': output['tx_hash']?.toString() ?? '',
            'amount': amount,
            'block': output['block']?.toString() ?? '',
            'eph_pub': ephPubB64,
            'stealth_tag': stealthTagHex,
            'claim_pub': output['claim_pub']?.toString() ?? '',
            'enc_amount': encAmount ?? '',
            'timestamp': output['timestamp'] ?? 0,
          });
        }
      } catch (_) {
        // Skip outputs that fail to process
      }
    }
    return found;
  }

  /// Sends a deploy contract transaction.
  Future<String> sendDeployTx({
    required String nodeUrl,
    required String bytecode,
    required String constructorArgs,
    String ou = '10000',
  }) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    await refresh(nodeUrl);
    final nonce = _currentNonce + 1;
    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final tx = <String, dynamic>{
      'from': wallet.address,
      'to_': '',
      'amount': '0',
      'nonce': nonce,
      'ou': ou,
      'timestamp': timestamp,
      'op_type': 'deploy',
      'encrypted_data': bytecode,
      'message': constructorArgs,
    };

    final canonical = CryptoService.canonicalJson(tx);
    final signature = await CryptoService.signMessage(canonical, sk);
    final pubKeyB64 = await CryptoService.publicKeyFromSk(sk);
    tx['signature'] = signature;
    tx['public_key'] = pubKeyB64;

    final result = await _rpc(nodeUrl, 'octra_submit', [tx]) as Map;
    final hash = result['tx_hash']?.toString() ?? '';
    await _recordTx(wallet, hash, '', '0', 'deploy', null);
    return hash;
  }

  /// Calls a smart contract function (state-changing).
  Future<String> sendContractCall({
    required String nodeUrl,
    required String contractAddress,
    required String functionName,
    required List<dynamic> args,
    String ou = '1000',
  }) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');

    await refresh(nodeUrl);
    final nonce = _currentNonce + 1;
    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final tx = <String, dynamic>{
      'from': wallet.address,
      'to_': contractAddress,
      'amount': '0',
      'nonce': nonce,
      'ou': ou,
      'timestamp': timestamp,
      'op_type': 'call',
      'encrypted_data': functionName,
      'message': jsonEncode(args),
    };

    final canonical = CryptoService.canonicalJson(tx);
    final signature = await CryptoService.signMessage(canonical, sk);
    final pubKeyB64 = await CryptoService.publicKeyFromSk(sk);
    tx['signature'] = signature;
    tx['public_key'] = pubKeyB64;

    final result = await _rpc(nodeUrl, 'octra_submit', [tx]) as Map;
    final hash = result['tx_hash']?.toString() ?? '';
    await _recordTx(wallet, hash, contractAddress, '0', 'call', functionName);
    return hash;
  }

  /// Views a smart contract function (read-only).
  Future<dynamic> contractView({
    required String nodeUrl,
    required String contractAddress,
    required String functionName,
    required List<dynamic> args,
  }) async {
    final result = await _rpc(nodeUrl, 'octra_contractView', [
      contractAddress,
      functionName,
      args,
    ]) as Map;
    return result['result'];
  }

  /// Gets contract info (ABI, storage, etc.).
  Future<Map<String, dynamic>> contractInfo(
      String nodeUrl, String contractAddress) async {
    final result = await _rpc(nodeUrl, 'octra_contractInfo', [contractAddress])
        as Map<String, dynamic>;
    return result;
  }

  /// Gets transaction receipt.
  Future<Map<String, dynamic>> getReceipt(String nodeUrl, String txHash) async {
    final result =
        await _rpc(nodeUrl, 'octra_receipt', [txHash]) as Map<String, dynamic>;
    return result;
  }

  /// Verifies a smart contract by submitting source code.
  Future<Map<String, dynamic>> verifyContract({
    required String nodeUrl,
    required String contractAddress,
    required String sourceCode,
  }) async {
    final result = await _rpc(nodeUrl, 'octra_verifyContract', [
      contractAddress,
      sourceCode,
    ]) as Map<String, dynamic>;
    return result;
  }

  /// Reads a contract's storage slot.
  Future<String> readContractStorage({
    required String nodeUrl,
    required String contractAddress,
    required String key,
  }) async {
    final result = await _rpc(nodeUrl, 'octra_contractStorage', [
      contractAddress,
      key,
    ]) as Map;
    return result['value']?.toString() ?? '';
  }

  /// Computes a contract address from deployer + nonce.
  Future<String> computeContractAddress(
      String nodeUrl, String deployer, int nonce) async {
    final result = await _rpc(nodeUrl, 'octra_computeContractAddress', [
      deployer,
      nonce,
    ]) as Map;
    return result['address']?.toString() ?? '';
  }

  Future<String> getPvacPubkey(String nodeUrl, String address) async {
    final r = await _rpc(nodeUrl, 'octra_pvacPubkey', [address]) as Map;
    return r['pubkey']?.toString() ?? '';
  }

  Future<String?> getViewPubkey(String nodeUrl, String address) async {
    try {
      final r = await _rpc(nodeUrl, 'octra_viewPubkey', [address]) as Map;
      return r['pubkey']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String> registerPvacPubkey(String nodeUrl, String pvacPubkey) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');
    final sig = await CryptoService.signPvacRegister(wallet.address, sk);
    // Node accepts 5 params with aes_kat (webcli parity); mirrors Android ensurePvacRegistered
    final pubKeyB64 = await CryptoService.publicKeyFromSk(sk);
    String aesKat = '';
    try {
      aesKat = NativeCrypto.computeAesKat();
    } catch (_) {}
    final params = [wallet.address, pvacPubkey, sig, pubKeyB64];
    if (aesKat.isNotEmpty) params.add(aesKat);
    final r = await _rpc(nodeUrl, 'octra_registerPvacPubkey', params) as Map;
    return r['status']?.toString() ?? '';
  }

  /// Submits a PVAC encryption-key rotation (op_type:key_switch),
  /// mirroring webcli POST /api/key_switch. Built with the generic
  /// transaction signer so the nonce is set correctly before signing.
  Future<Map<String, dynamic>> submitKeySwitch(String nodeUrl) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');
    final localPk = CryptoService.pvacGetPubkeyB64();
    if (localPk == null || localPk.isEmpty) {
      throw Exception('PVAC not available on this device/ABI');
    }
    final aesKat = NativeCrypto.computeAesKat();
    final pkRaw = base64.decode(localPk);
    final digest = NativeCrypto.sha256(Uint8List.fromList(pkRaw));
    final hexChars = '0123456789abcdef';
    final hex = StringBuffer();
    for (int i = 0; i < 8 && i < digest.length; i++) {
      hex.write(hexChars[(digest[i] >> 4) & 0xF]);
      hex.write(hexChars[digest[i] & 0xF]);
    }
    final message = 'encryption key switch | new_key:$hex';
    final encryptedData = jsonEncode({
      'new_pubkey': localPk,
      'aes_kat': aesKat,
    });
    await refresh(nodeUrl);
    final nonce = _currentNonce + 1;
    // OU from the fee oracle (upstream webcli parity), fallback 3000.
    String ou = '3000';
    try {
      final feeRes =
          await _rpc(nodeUrl, 'octra_recommendedFee', ['key_switch']);
      final rec = feeRes is Map ? feeRes['recommended']?.toString() ?? '' : '';
      if (rec.isNotEmpty && (int.tryParse(rec) ?? 0) > 0) ou = rec;
    } catch (_) {}
    final signedTx = await CryptoService.buildSignedGeneralTransaction(
      skBase64: sk,
      fromAddress: wallet.address,
      toAddress: wallet.address,
      amount: '0',
      nonce: nonce,
      ou: ou,
      opType: 'key_switch',
      message: message,
      encryptedData: encryptedData,
    );
    final result = await _rpc(nodeUrl, 'octra_submit', [signedTx]) as Map;
    return Map<String, dynamic>.from(result);
  }

  /// Batch fee estimation for all op types (webcli GET /api/fee parity).
  Future<Map<String, dynamic>> fetchFeeBatch(String nodeUrl) async {
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
        final r = await _rpc(nodeUrl, 'octra_recommendedFee', [op]);
        if (r != null) {
          fees[op] = r;
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

  /// Registers the view public key (x25519 from ed25519 sk) with the node.
  Future<String> registerViewPubkey(String nodeUrl) async {
    final wallet = activeWallet;
    if (wallet == null) throw Exception('No active wallet');
    final sk = await getPrivateKey(wallet.id);
    if (sk == null) throw Exception('Private key not found');
    final skBytes = Uint8List.fromList(base64.decode(sk));
    final viewPub = CryptoService.getViewPublicKey(skBytes);
    final viewPubB64 = base64.encode(viewPub);
    final sig =
        await CryptoService.signMessage('register_view|${wallet.address}', sk);
    final r = await _rpc(nodeUrl, 'octra_registerViewPubkey',
        [wallet.address, viewPubB64, sig]) as Map;
    return r['status']?.toString() ?? '';
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PVAC / encrypted-balance helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Auto-register PVAC pubkey on the node if not already registered.
  /// Mirrors Android's TxForegroundService.ensurePvacRegistered().
  Future<void> _ensurePvacRegistered(
      String nodeUrl, String address, String sk) async {
    final localPk = CryptoService.pvacGetPubkeyB64();
    if (localPk == null || localPk.isEmpty) {
      throw Exception('PVAC not available on this device/ABI');
    }
    // Check if already registered on-chain
    try {
      final r = await _rpc(nodeUrl, 'octra_pvacPubkey', [address]) as Map;
      final remotePk =
          r['pvac_pubkey']?.toString() ?? r['pubkey']?.toString() ?? '';
      if (remotePk.isNotEmpty && remotePk == localPk) {
        return; // already up-to-date
      }
    } catch (_) {}
    // Register (include aes_kat as 5th param — webcli parity)
    final sig = await CryptoService.signPvacRegister(address, sk);
    final pubKeyB64 = await CryptoService.publicKeyFromSk(sk);
    final params = [address, localPk, sig, pubKeyB64];
    try {
      final kat = NativeCrypto.computeAesKat();
      if (kat.isNotEmpty) params.add(kat);
    } catch (_) {}
    await _rpc(nodeUrl, 'octra_registerPvacPubkey', params);
  }

  /// Fetches the encrypted balance cipher via an authenticated RPC call.
  /// Mirrors Android's BaseTxActivity.fetchEncryptedBalance().
  /// Falls back to single-param call when the authenticated form fails.
  Future<String> _fetchEncryptedBalanceCipher(
      String nodeUrl, String address, String sk) async {
    // ── Form 1: authenticated 3-param call (preferred) ──────────────────────
    try {
      final sig = await CryptoService.signBalanceRequest(address, sk);
      final pubKeyB64 = await CryptoService.publicKeyFromSk(sk);
      final r = await _rpc(
          nodeUrl, 'octra_encryptedBalance', [address, sig, pubKeyB64]) as Map;
      final cipher = r['cipher']?.toString() ??
          r['encrypted_balance']?.toString() ??
          r['balance_encrypted']?.toString() ??
          r['balance']?.toString();
      if (cipher != null && cipher.isNotEmpty && cipher != '0') return cipher;
    } catch (e) {
      debugPrint('_fetchEncryptedBalanceCipher (3-param): $e');
    }
    // ── Form 2: simple 1-param call (some node versions) ────────────────────
    try {
      final r = await _rpc(nodeUrl, 'octra_encryptedBalance', [address]) as Map;
      final cipher = r['cipher']?.toString() ??
          r['encrypted_balance']?.toString() ??
          r['balance_encrypted']?.toString() ??
          r['balance']?.toString();
      if (cipher != null && cipher.isNotEmpty && cipher != '0') return cipher;
    } catch (_) {}
    // ── Fallback: reuse last known cipher ────────────────────────────────────
    return _encryptedBalanceCipher ?? '0';
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Balance formatting
  // ══════════════════════════════════════════════════════════════════════════

  /// Formats a raw microcoin value as a decimal OCT string (6 decimal places).
  ///
  /// Uses pure integer arithmetic to avoid floating-point precision loss.
  /// E.g. 100000 → "0.1", 1000000 → "1", 815680 → "0.81568".
  static String formatOct(int rawMicrocoins) {
    if (rawMicrocoins == 0) return '0.000000';
    final bool negative = rawMicrocoins < 0;
    int abs = negative ? -rawMicrocoins : rawMicrocoins;
    final int whole = abs ~/ 1000000;
    final int frac = abs % 1000000;
    String fracStr = frac.toString().padLeft(6, '0');
    // Strip trailing zeros but keep at least two decimal digits
    int lastNonZero = fracStr.length;
    while (lastNonZero > 2 && fracStr[lastNonZero - 1] == '0') {
      lastNonZero--;
    }
    fracStr = fracStr.substring(0, lastNonZero);
    final prefix = negative ? '-' : '';
    return '$prefix$whole.$fracStr';
  }

  /// Parses a decimal OCT string into raw microcoins using string manipulation
  /// to avoid floating-point precision loss.
  /// E.g. "0.1" → 100000, "1.5" → 1500000, "10" → 10000000.
  static int parseOct(String display) {
    final cleaned = display.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return 0;
    final parts = cleaned.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    int frac = 0;
    if (parts.length > 1) {
      // Pad or truncate to exactly 6 decimal digits
      String fracStr = parts[1].length > 6
          ? parts[1].substring(0, 6)
          : parts[1].padRight(6, '0');
      frac = int.tryParse(fracStr) ?? 0;
    }
    return whole * 1000000 + frac;
  }

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('refused')) {
      return 'Cannot connect to node';
    }
    if (s.contains('TimeoutException')) return 'Connection timed out';
    return s.replaceFirst('Exception: ', '');
  }

  /// Polls the transaction status continuously until it is no longer pending.
  /// Calls [onStatusChanged] when a status update is available.
  Future<void> pollTxStatus(
    String nodeUrl,
    String txHash, {
    Duration interval = const Duration(seconds: 5),
    Function(Map<String, dynamic>)? onStatusChanged,
  }) async {
    while (true) {
      try {
        final txInfo = await lookupTransaction(nodeUrl, txHash);
        if (onStatusChanged != null) {
          onStatusChanged(txInfo);
        }
        final status = txInfo['status']?.toString().toLowerCase();
        if (status != 'pending') {
          // It's confirmed or failed — stop polling
          break;
        }
      } catch (e) {
        debugPrint('pollTxStatus error: $e');
      }
      await Future.delayed(interval);
    }
  }
}
