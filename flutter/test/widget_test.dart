import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke: test harness renders a widget tree',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Octra Wallet')),
        ),
      ),
    );

    expect(find.text('Octra Wallet'), findsOneWidget);
  });
}
