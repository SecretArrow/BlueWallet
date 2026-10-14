import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/screens/wallets/export_wallet_screen.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

/// Export screen must describe the wallet whose KEY it loaded: the screen is
/// reachable from a non-active row in WalletsScreen (`/export-wallet?id=…`),
/// so name/address have to resolve by id, not by "active wallet" (the old
/// behavior mixed the requested wallet's key with the ACTIVE wallet's
/// identity — a restored backup would then label the wrong address).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mainAddr = 'oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt';
  const otherAddr = 'oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFu';

  setUp(() {
    // Official in-memory secure-storage platform: _loadKey() awaits a
    // FlutterSecureStorage read; unmocked platform channels never resolve
    // inside FakeAsync, _loading stays true and the loading spinner's
    // infinite ticker keeps pumpAndSettle alive until the 10-minute test
    // timeout. With the shim, reads resolve (null) and the screen renders.
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
  });

  /// Bounded settle — never waits on open-ended animations (the loading
  /// spinner is the one that hung CI for two full runs).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<WalletService> bootTwoWallets(WidgetTester tester) async {
    const mainId = 'wallet_main';
    const otherId = 'wallet_other';
    SharedPreferences.setMockInitialValues({
      'wallet_ids': [mainId, otherId],
      'wallet_profile_$mainId': jsonEncode({
        'id': mainId,
        'name': 'Main',
        'address': mainAddr,
      }),
      'wallet_profile_$otherId': jsonEncode({
        'id': otherId,
        'name': 'Cold Storage',
        'address': otherAddr,
      }),
      'active_wallet_id': mainId,
    });
    final ws = WalletService();
    // Settle the fire-and-forget _init() on the REAL event loop. A bare
    // `await Future.delayed(...)` inside testWidgets waits on a fake timer
    // that never fires while the body is suspended — that FakeAsync
    // deadlock is what hung both export tests for 10 minutes on CI.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    return ws;
  }

  Widget harness(WalletService ws, {String? walletId}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<WalletService>.value(value: ws),
        ],
        child: MaterialApp(
          home: ExportWalletScreen(walletId: walletId),
        ),
      );

  testWidgets('exporting a NON-active wallet shows that wallet\'s identity',
      (WidgetTester tester) async {
    final ws = await bootTwoWallets(tester);
    expect(ws.activeWallet?.name, 'Main'); // precondition

    await tester.pumpWidget(harness(ws, walletId: 'wallet_other'));
    await settle(tester);

    // Identity resolves by id: Cold Storage + its own address.
    expect(find.text('Cold Storage'), findsOneWidget);
    expect(find.text(otherAddr), findsOneWidget);
    expect(find.text(mainAddr), findsNothing);
    expect(find.text('Main'), findsNothing);

    // Reveal: no secure storage in JVM tests → 'Not found' rather than a
    // key from the WRONG wallet — the important part is that the shown
    // identity and the loaded key belong to the same wallet id.
    await tester.ensureVisible(find.text('Reveal Private Key'));
    await tester.tap(find.text('Reveal Private Key'));
    await settle(tester);
    expect(find.text('Not found'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('no wallet id falls back to the active wallet',
      (WidgetTester tester) async {
    final ws = await bootTwoWallets(tester);

    await tester.pumpWidget(harness(ws));
    await settle(tester);

    expect(find.text('Main'), findsOneWidget);
    expect(find.text(mainAddr), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
