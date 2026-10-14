import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/screens/send/send_screen.dart';
import 'package:octopus_wallet/services/address_book_service.dart';
import 'package:octopus_wallet/services/network_service.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

/// Send screen guards: watch-only hard block, malformed-address validation
/// (the same 47-char "oct" rule the native SendActivity enforces before
/// signing) and deep-link/query prefill.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const goodAddress = 'oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt';

  setUp(() {
    // Official in-memory secure-storage platform. Unmocked platform
    // channels NEVER resolve inside FakeAsync — any storage read (key
    // lookups during screen builds) then hangs the suite until the
    // 10-minute timeout. (A MethodChannel mock is brittle: the real
    // channel is 'plugins.it_nomads.com/flutter_secure_storage' — note
    // "nomads" — and renames silently break it.)
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform(<String, String>{});
  });

  /// Bounded settle: renders the post-action state without waiting on
  /// open-ended animations/timers (pumpAndSettle hung CI twice here).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Wallets are seeded through SharedPreferences exactly like a real
  /// install (secure storage is never touched for these paths, so the JVM
  /// test needs no keyring).
  Future<WalletService> bootWallets({required bool watchOnly}) async {
    final id = watchOnly ? 'wallet_watch' : 'wallet_main';
    final profile = {
      'id': id,
      'name': watchOnly ? 'Vault Watch' : 'Main',
      'address': goodAddress,
      if (watchOnly) 'watchOnly': true,
    };
    SharedPreferences.setMockInitialValues({
      'wallet_ids': [id],
      'wallet_profile_$id': jsonEncode(profile),
      'active_wallet_id': id,
    });
    final ws = WalletService();
    // Let the async _init() settle before driving the UI.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return ws;
  }

  Widget harness(WalletService ws) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (c, __) => Scaffold(
            body: Center(
              child: OutlinedButton(
                onPressed: () => c.push('/send'),
                child: const Text('Open Send'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/send',
          builder: (_, __) => const SendScreen(),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletService>.value(value: ws),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProvider(create: (_) => AddressBookService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openSend(WidgetTester tester, WalletService ws) async {
    await tester.pumpWidget(harness(ws));
    await tester.tap(find.text('Open Send'));
    await settle(tester);
  }

  Finder sendButton() => find.widgetWithText(ElevatedButton, 'Send');

  testWidgets('malformed recipient address is rejected client-side',
      (WidgetTester tester) async {
    final ws = await bootWallets(watchOnly: false);
    await openSend(tester, ws);

    await tester.enterText(find.byType(TextFormField).at(0), 'notanaddress');
    await tester.enterText(find.byType(TextFormField).at(1), '1');
    await tester.ensureVisible(sendButton());
    await settle(tester);
    await tester.tap(sendButton());
    await settle(tester);

    expect(find.textContaining('Invalid oct address'), findsOneWidget);
    // Still on the send screen — nothing was signed or submitted.
    expect(find.text('Recipient Address'), findsOneWidget);
  });

  testWidgets('empty recipient address keeps the empty-field error',
      (WidgetTester tester) async {
    final ws = await bootWallets(watchOnly: false);
    await openSend(tester, ws);

    await tester.enterText(find.byType(TextFormField).at(1), '1');
    await tester.ensureVisible(sendButton());
    await settle(tester);
    await tester.tap(sendButton());
    await settle(tester);

    expect(find.text('Enter recipient address'), findsOneWidget);
  });

  testWidgets('watch-only wallet is hard-blocked with the canonical message',
      (WidgetTester tester) async {
    final ws = await bootWallets(watchOnly: true);
    await openSend(tester, ws);

    // Fully valid inputs — the guard must fire before anything else.
    await tester.enterText(find.byType(TextFormField).at(0), goodAddress);
    await tester.enterText(find.byType(TextFormField).at(1), '1');
    await tester.ensureVisible(sendButton());
    await settle(tester);
    await tester.tap(sendButton());
    await settle(tester);

    expect(find.text(WalletService.watchOnlySendBlockMessage), findsOneWidget);
    // No navigation to the tx-progress screen.
    expect(find.text('Transaction submitted!'), findsNothing);
  });

  testWidgets('deep-link prefill (address + amount) lands in the fields',
      (WidgetTester tester) async {
    final ws = await bootWallets(watchOnly: false);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletService>.value(value: ws),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProvider(create: (_) => AddressBookService()),
      ],
      child: const MaterialApp(
        home: SendScreen(
          prefillAddress: goodAddress,
          prefillAmount: '2.5',
        ),
      ),
    ));
    await settle(tester);

    expect(find.text(goodAddress), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    expect(ws.canSend, isTrue);
  });
}
