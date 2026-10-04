import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'native_crypto.dart';
import 'network_service.dart';
import 'crypto_service.dart';

/// Background service for polling transaction finality and PVAC registration
/// Mirrors webcli's pvac_bg thread implementation
class BackgroundPollingService extends ChangeNotifier {
  static BackgroundPollingService? _instance;

  static const _pollInterval = Duration(seconds: 15);
  static const _pvacCheckInterval = Duration(seconds: 60);

  Timer? _pollTimer;
  Timer? _pvacTimer;
  bool _isRunning = false;
  String? _lastError;
  int _pollCount = 0;
  int _pvacCheckCount = 0;

  final RpcClient _rpcClient = RpcClient();
  final _secureStorage = const FlutterSecureStorage();

  bool get isRunning => _isRunning;
  String? get lastError => _lastError;
  int get pollCount => _pollCount;
  int get pvacCheckCount => _pvacCheckCount;

  /// Get singleton instance
  static BackgroundPollingService get instance {
    _instance ??= BackgroundPollingService._();
    return _instance!;
  }

  BackgroundPollingService._();

  /// Start background polling
  /// - [nodeUrl]: RPC endpoint
  /// - [pollFinality]: Enable transaction finality polling
  /// - [checkPvac]: Enable PVAC registration checks
  Future<void> start({
    required String nodeUrl,
    bool pollFinality = true,
    bool checkPvac = true,
  }) async {
    if (_isRunning) return;

    _isRunning = true;
    _rpcClient.setUrl(nodeUrl);
    notifyListeners();

    if (pollFinality) {
      _startPollTimer();
    }

    if (checkPvac) {
      _startPvacTimer();
    }

    debugPrint('[BackgroundPolling] Started with node: $nodeUrl');
  }

  /// Stop all background polling
  void stop() {
    _pollTimer?.cancel();
    _pvacTimer?.cancel();
    _isRunning = false;
    notifyListeners();
    debugPrint('[BackgroundPolling] Stopped');
  }

  void _startPollTimer() {
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      _pollCount++;
      await _pollPendingTransactions();
    });
  }

  void _startPvacTimer() {
    // Initial delay before first PVAC check
    _pvacTimer = Timer.periodic(_pvacCheckInterval, (_) async {
      _pvacCheckCount++;
      await _checkPvacRegistration();
    });
  }

  /// Poll pending transactions until they reach finality
  Future<void> _pollPendingTransactions() async {
    try {
      // Get list of pending txs from local storage
      final pendingTxs = await _getPendingTransactions();

      if (pendingTxs.isEmpty) return;

      for (final txHash in pendingTxs) {
        final result = await _rpcClient.getTransaction(txHash);

        if (result.ok && result.result != null) {
          final status = result.result['status']?.toString().toLowerCase();

          // Update local storage with new status
          await _updateTransactionStatus(txHash, status);

          // If no longer pending, remove from pending list
          if (status != 'pending') {
            await _removeFromPending(txHash);
            debugPrint(
                '[BackgroundPolling] TX $txHash reached finality: $status');
          }
        }
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[BackgroundPolling] Poll error: $e');
    }
  }

  /// Check and register PVAC pubkeys for all wallets
  Future<void> _checkPvacRegistration() async {
    try {
      // Get all wallet addresses
      final walletIds = await _getWalletIds();

      for (final walletId in walletIds) {
        await _checkWalletPvac(walletId);
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[BackgroundPolling] PVAC check error: $e');
    }
  }

  /// Check PVAC registration for a single wallet
  Future<void> _checkWalletPvac(String walletId) async {
    try {
      // Load wallet data
      final walletData = await _loadWalletData(walletId);
      if (walletData == null) return;

      final addr = walletData['address'] as String?;
      final privB64 = walletData['privateKeyB64'] as String?;
      final pubB64 = walletData['publicKeyB64'] as String?;

      if (addr == null || privB64 == null || pubB64 == null) return;

      // Check if PVAC pubkey is registered
      final pvacResult = await _rpcClient.getPvacPubkey(addr);

      bool needsRegistration = true;

      if (pvacResult.ok && pvacResult.result != null) {
        final registeredKey = pvacResult.result['pvac_pubkey']?.toString();
        if (registeredKey != null && registeredKey.isNotEmpty) {
          // Verify it matches our key
          final localKey = await _computeLocalPvacKey(privB64);
          if (localKey == registeredKey) {
            needsRegistration = false;
          }
        }
      }

      if (needsRegistration) {
        await _registerPvacPubkey(addr, privB64, pubB64);
      }
    } catch (e) {
      debugPrint('[BackgroundPolling] Wallet $walletId PVAC check failed: $e');
    }
  }

  /// Compute local PVAC public key
  Future<String?> _computeLocalPvacKey(String privB64) async {
    try {
      // Initialize PVAC with private key
      final privBytes = base64Decode(privB64);
      if (!CryptoService.pvacInit(privBytes)) {
        return null;
      }

      // Get PVAC pubkey
      final pubkey = NativeCrypto.pvacGetPubkeyB64();

      // Reset PVAC state
      NativeCrypto.pvacReset();

      return pubkey;
    } catch (e) {
      debugPrint('[BackgroundPolling] PVAC key compute error: $e');
      return null;
    }
  }

  /// Register PVAC pubkey
  Future<void> _registerPvacPubkey(
    String addr,
    String privB64,
    String pubB64,
  ) async {
    try {
      // Initialize PVAC
      final privBytes = base64Decode(privB64);
      if (!CryptoService.pvacInit(privBytes)) {
        debugPrint('[BackgroundPolling] PVAC init failed for $addr');
        return;
      }

      // Get PVAC pubkey
      NativeCrypto.pvacGetPubkeyB64();

      // Compute AES-KAT
      NativeCrypto.computeAesKat();

      // Reset PVAC
      NativeCrypto.pvacReset();

      debugPrint(
          '[BackgroundPolling] PVAC registration needed for $addr (signature requires wallet unlock)');
      // Note: Full PVAC registration requires signing with private key
      // This should be done when wallet is unlocked via WalletService
    } catch (e) {
      debugPrint('[BackgroundPolling] PVAC register error: $e');
    }
  }

  /// Get list of pending transaction hashes
  Future<List<String>> _getPendingTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('pending_transactions');

      if (pendingJson == null) return [];

      final pending = List<String>.from(jsonDecode(pendingJson));
      return pending;
    } catch (e) {
      return [];
    }
  }

  /// Update transaction status in local storage
  Future<void> _updateTransactionStatus(String txHash, String? status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'tx_status_$txHash';
      await prefs.setString(key, status ?? 'unknown');
    } catch (e) {
      debugPrint('[BackgroundPolling] Failed to update status for $txHash: $e');
    }
  }

  /// Remove transaction from pending list
  Future<void> _removeFromPending(String txHash) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('pending_transactions');

      if (pendingJson == null) return;

      final pending = List<String>.from(jsonDecode(pendingJson));
      pending.remove(txHash);

      await prefs.setString('pending_transactions', jsonEncode(pending));
    } catch (e) {
      debugPrint(
          '[BackgroundPolling] Failed to remove $txHash from pending: $e');
    }
  }

  /// Get all wallet IDs
  Future<List<String>> _getWalletIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final walletIdsJson = prefs.getString('wallet_ids');

      if (walletIdsJson == null) return [];

      return List<String>.from(jsonDecode(walletIdsJson));
    } catch (e) {
      return [];
    }
  }

  /// Load wallet data from secure storage
  Future<Map<String, dynamic>?> _loadWalletData(String walletId) async {
    try {
      final address =
          await _secureStorage.read(key: 'wallet_${walletId}_address');
      final privateKeyB64 =
          await _secureStorage.read(key: 'wallet_${walletId}_private_key');
      final publicKeyB64 =
          await _secureStorage.read(key: 'wallet_${walletId}_public_key');

      if (address == null || privateKeyB64 == null || publicKeyB64 == null) {
        return null;
      }

      return {
        'address': address,
        'privateKeyB64': privateKeyB64,
        'publicKeyB64': publicKeyB64,
      };
    } catch (e) {
      debugPrint('[BackgroundPolling] Failed to load wallet $walletId: $e');
      return null;
    }
  }

  @override
  void dispose() {
    stop();
    _rpcClient.dispose();
    super.dispose();
  }
}
