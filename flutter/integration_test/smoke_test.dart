import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:octopus_wallet/main.dart' as app;

/// Minimal launch smoke test for CI E2E (Android emulator).
/// Asserts the app boots to a MaterialApp without exceptions.
/// No timers/pumpAndSettle: background polling would never settle.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches without crashing', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
