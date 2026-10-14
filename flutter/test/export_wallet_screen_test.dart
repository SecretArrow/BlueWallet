import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<WalletService> bootTwoWallets() async {
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
    await Future<void>.delayed(const Duration(milliseconds: 50));
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
    final ws = await bootTwoWallets();
    expect(ws.activeWallet?.name, 'Main'); // precondition

    await tester.pumpWidget(harness(ws, walletId: 'wallet_other'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('no wallet id falls back to the active wallet',
      (WidgetTester tester) async {
    final ws = await bootTwoWallets();

    await tester.pumpWidget(harness(ws));
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsOneWidget);
    expect(find.text(mainAddr), findsOneWidget);
  });
}
