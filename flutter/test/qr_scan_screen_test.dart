import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:octopus_wallet/screens/scan/qr_scan_screen.dart';

/// Desktop-branch widget test for the QR scan screen. The camera branch
/// (MobileScanner) is not testable in JVM tests — no camera hardware — and
/// is intentionally not pumped here; the controller is only created lazily
/// on the mobile branch.
void main() {
  testWidgets('desktop branch: manual entry pops the typed address',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _runDesktopScanTest(tester);
    } finally {
      // Reset INSIDE the body (try/finally): the binding verifies
      // foundation debug variables before any teardown runs, so an
      // addTearDown/group tearDown reset would trip that check.
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _runDesktopScanTest(WidgetTester tester) async {
  const address = 'oct1qzw4t8yk3e0a2r9v6testaddress';
  String? popped;

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (c, __) => Scaffold(
          body: Center(
            child: OutlinedButton(
              // Capture the pop result of the pushed scanner route.
              onPressed: () async {
                popped = await c.push<String>('/qr-scan');
              },
              child: const Text('Open Scanner'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/qr-scan',
        builder: (_, __) => const QrScanScreen(),
      ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));

  await tester.tap(find.text('Open Scanner'));
  await tester.pumpAndSettle();

  // Desktop branch: manual entry card, not a camera preview.
  expect(find.text('Paste or type the recipient address'), findsOneWidget);
  expect(find.text('Scan QR Code'), findsNothing);
  expect(find.text('Enter Address'), findsOneWidget);

  await tester.enterText(find.byType(TextField), address);
  await tester.tap(find.text('Use Address'));
  await tester.pumpAndSettle();

  expect(popped, address);
  // Popped back to the home route.
  expect(find.text('Open Scanner'), findsOneWidget);
}
