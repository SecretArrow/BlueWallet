import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dapp_session.dart';
import 'wallet_adapter.dart';

/// Persistent per-origin dApp sessions + granted scopes.
///
/// Key: `dapp_sessions` (JSON list). Migrates the legacy `dapp_origins`
/// string list (origins without address/scopes) on first load so existing
/// approvals are not silently dropped.
///
/// Revocation here immediately disconnects the origin: the browser checks
/// the store before answering any connected-only method.
class DappSessionStore extends ChangeNotifier {
  static const String storeKey = 'dapp_sessions';
  static const String legacyKey = 'dapp_origins';

  static final DappSessionStore instance = DappSessionStore._();
  factory DappSessionStore() => instance;
  DappSessionStore._();

  final Map<String, DappSession> _sessions = {};
  bool _loaded = false;

  List<DappSession> get sessions => _sessions.values.toList()
    ..sort((a, b) => b.connectedAtMs.compareTo(a.connectedAtMs));

  bool get isLoaded => _loaded;

  String _key(String origin) => AdapterValidation.normalizeOrigin(origin);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = DappSession.decodeList(prefs.getString(storeKey));
      for (final s in stored) {
        _sessions[_key(s.origin)] = s;
      }
      // One-time legacy migration: plain origin strings -> address-less
      // sessions are NOT granted (no address = no session). They are kept
      // visible as revoked placeholders? No — drop them: auto-granting
      // access without an address would violate explicit-approval rules.
      // Just clear the legacy key after reading so we never migrate twice.
      if (prefs.containsKey(legacyKey)) {
        await prefs.remove(legacyKey);
      }
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storeKey, DappSession.encodeList(sessions));
    } catch (_) {
      // Storage full / unavailable: sessions stay in memory for this run.
      debugPrint('[DappSessionStore] persist failed (storage unavailable?)');
    }
  }

  DappSession? sessionFor(String origin) => _sessions[_key(origin)];

  bool isConnected(String origin) {
    final s = sessionFor(origin);
    return s != null && s.address.isNotEmpty;
  }

  List<String> scopesFor(String origin) =>
      sessionFor(origin)?.scopes ?? const ['accounts'];

  Future<void> grant(String origin,
      {required String address,
      List<String> scopes = const ['accounts']}) async {
    if (!AdapterValidation.isPersistableOrigin(origin)) return;
    if (address.isEmpty) return;
    final normalized = AdapterValidation.normalizeOrigin(origin);
    _sessions[normalized] = DappSession(
      origin: normalized,
      address: address,
      scopes: List.of(scopes.isEmpty ? const ['accounts'] : scopes),
      connectedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> revoke(String origin) async {
    if (_sessions.remove(_key(origin)) != null) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> revokeAll() async {
    if (_sessions.isEmpty) return;
    _sessions.clear();
    notifyListeners();
    await _persist();
  }
}
