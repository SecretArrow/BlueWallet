import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart'; // re-exports flutter_test
import 'package:provider/provider.dart';

import 'package:octopus_wallet/screens/dapp/dapp_browser_screen.dart';
import 'package:octopus_wallet/services/address_book_service.dart';
import 'package:octopus_wallet/services/local_web_server_service.dart';
import 'package:octopus_wallet/services/network_service.dart';
import 'package:octopus_wallet/services/polling_service.dart';
import 'package:octopus_wallet/services/tor_proxy_service.dart';
import 'package:octopus_wallet/services/wallet_service.dart';

/// E2E: the exact circle URL from the field report renders inside the
/// in-app DApp browser without errors.
///
/// Pumps the real browser screen (real WebView on the emulator) with real
/// services and no wallet: the oct:// read path needs only RPC. Passes when
/// no "Cannot open" error appears and loading settles.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const octUrl =
      'oct://oct99BWHFpV5r54DXKc2FhsBmZEaS6Q8zvCQrHRgXUcK4Fk/index.html';

  testWidgets('oct circle renders in the in-app browser', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => WalletService()),
          ChangeNotifierProvider(create: (_) => NetworkService()),
          ChangeNotifierProvider(create: (_) => AddressBookService()),
          ChangeNotifierProvider(create: (_) => PollingService()),
          ChangeNotifierProvider(create: (_) => TorProxyService.instance),
          ChangeNotifierProvider(create: (_) => LocalWebServerService.instance),
        ],
        child: const MaterialApp(
          home: DappBrowserScreen(initialUrl: octUrl),
        ),
      ),
    );

    // Allow the RPC fetch + WebView render to settle (generous on CI).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 5));
      if (find.textContaining('Cannot open').evaluate().isEmpty) {
        // Keep pumping a little to let the page finish.
        await tester.pump(const Duration(seconds: 5));
        break;
      }
    }

    expect(find.textContaining('Cannot open'), findsNothing,
        reason: 'the circle page must render without errors');
    expect(find.byType(DappBrowserScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
