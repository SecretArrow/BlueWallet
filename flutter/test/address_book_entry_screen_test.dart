import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/screens/settings/address_book_entry_screen.dart';
import 'package:octopus_wallet/services/address_book_service.dart';

/// Address book entry screen: the oct-address validation added for native
/// parity (mirrors AddressBookEntryActivity) rejects malformed addresses
/// before anything is persisted; valid entries round-trip through the
/// service's SharedPreferences store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const goodAddress = 'oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt';

  Widget harness() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (c, __) => Scaffold(
            body: Center(
              child: OutlinedButton(
                onPressed: () => c.push('/address-book-entry'),
                child: const Text('Open Entry'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/address-book-entry',
          builder: (_, __) => const AddressBookEntryScreen(),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AddressBookService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openEntry(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('Open Entry'));
    await tester.pumpAndSettle();
  }

  Finder labelField() => find.byType(TextField).at(0);
  Finder addressField() => find.byType(TextField).at(1);

  testWidgets('malformed address is rejected and nothing is saved',
      (WidgetTester tester) async {
    await openEntry(tester);

    await tester.enterText(labelField(), 'Alice');
    await tester.enterText(addressField(), 'oct123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid oct address'), findsOneWidget);
    // Still on the entry screen (no pop on validation failure).
    expect(find.text('Add Address'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('address_book'), anyOf(isNull, '[]'),
        reason: 'no entry may be persisted for a malformed address');
  });

  testWidgets('valid entry is saved and the screen pops',
      (WidgetTester tester) async {
    await openEntry(tester);

    await tester.enterText(labelField(), 'Alice');
    await tester.enterText(addressField(), goodAddress);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Popped back to the home route.
    expect(find.text('Open Entry'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('address_book');
    expect(raw, isNotNull);
    final list = jsonDecode(raw!) as List;
    expect(list, hasLength(1));
    expect(list.first['label'], 'Alice');
    expect(list.first['address'], goodAddress);
  });
}
