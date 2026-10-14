import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:octopus_wallet/screens/settings/about_screen.dart';
import 'package:octopus_wallet/services/oct_address.dart';

/// The donation address is REAL money routing: it must be a well-formed
/// oct address AND match the canonical address the native app displays
/// (AboutActivity.DONATION_ADDRESS). The Flutter side used to ship a
/// 67-char hex placeholder — anything copied from it was unsendable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep in sync with android-native AboutActivity.DONATION_ADDRESS.
  const nativeDonationAddress =
      'oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt';

  Widget harness() => const MaterialApp(home: AboutScreen());

  testWidgets('donation address shown on screen is valid oct format',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text(nativeDonationAddress), findsOneWidget);
  });

  testWidgets('donation address matches the native app (cross-app parity)',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Read the rendered address back and validate it with the app-wide rule.
    final text = tester.widget<Text>(find.text(nativeDonationAddress)).data!;
    expect(OctAddress.isValid(text), isTrue,
        reason: 'the address users copy to send donations must be sendable');
    expect(text, nativeDonationAddress);
  });

  testWidgets('copy puts the donation address on the clipboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy donation address'));
    await tester.pump();

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    expect(data?.text, nativeDonationAddress);
  });
}
