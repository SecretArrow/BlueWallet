import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/services/wallet_service.dart';

/// `WalletService.clearCaches()` — the engine behind the settings "Clear
/// Cache" row. It must drop cached data WITHOUT touching wallet profiles or
/// keys, survive a missing sqflite backend (JVM tests have no SQLite FFI),
/// and notify listeners so tabs drop their stale copies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const addr = 'oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt';

  Future<WalletService> bootWithWallet() async {
    SharedPreferences.setMockInitialValues({
      'wallet_ids': ['wallet_main'],
      'wallet_profile_wallet_main': jsonEncode({
        'id': 'wallet_main',
        'name': 'Main',
        'address': addr,
      }),
      'active_wallet_id': 'wallet_main',
    });
    final ws = WalletService();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return ws;
  }

  test('clearCaches completes without throwing (no sqflite backend needed)',
      () async {
    final ws = await bootWithWallet();
    // SQLite calls fail inside (MissingPluginException) — they must be
    // swallowed, not propagated to the settings screen.
    await ws.clearCaches();
  });

  test('clearCaches keeps wallets + active selection intact', () async {
    final ws = await bootWithWallet();
    await ws.clearCaches();

    expect(ws.wallets, hasLength(1));
    expect(ws.activeWallet?.id, 'wallet_main');
    expect(ws.activeWallet?.name, 'Main');
    // In-memory cached copies reset to their defaults.
    expect(ws.history, isEmpty);
    expect(ws.tokens, isEmpty);
    expect(ws.publicBalance, '0.000000');
    expect(ws.totalBalance, '0.000000');
    expect(ws.accountNotFound, isFalse);

    // Persistence untouched: profiles survive, so the wallet list rebuilds
    // identically on next launch.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('wallet_ids'), ['wallet_main']);
    expect(prefs.getString('wallet_profile_wallet_main'), isNotNull);
  });

  test('clearCaches notifies listeners', () async {
    final ws = await bootWithWallet();
    var notified = 0;
    ws.addListener(() => notified++);
    await ws.clearCaches();
    expect(notified, 1);
  });
}
