import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:octopus_wallet/models/visited_page.dart';
import 'package:octopus_wallet/services/deep_link_router.dart';
import 'package:octopus_wallet/widgets/startpage_view.dart';

/// Native-library-free tests: the full app needs liboctra_native.so and is
/// therefore not pumpable in JVM tests. Deep-link parsing has its full
/// matrix in deep_link_router_test.dart; here a smoke subset plus the
/// Startpage UI contract.
void main() {
  group('DeepLinkRoute.parse (smoke subset)', () {
    test('send link parses to + amount', () {
      final r = DeepLinkRoute.parse('octra://send?to=oct1qabc&amount=2.5');
      expect(r, isNotNull);
      expect(r!.type, DeepLinkRouteType.send);
      expect(r.to, 'oct1qabc');
      expect(r.amount, 2.5);
    });

    test('non-wallet schemes are rejected', () {
      expect(DeepLinkRoute.parse('https://example.com'), isNull);
      // oct:// is the internal browser scheme, not an external deep link.
      expect(DeepLinkRoute.parse('oct://circle'), isNull);
    });
  });

  group('StartpageView', () {
    // oct:// URLs keep the test network-free (no favicon fetches).
    const pages = [
      VisitedPage(
        url: 'oct://circlea',
        title: 'Circle A',
        domain: 'circlea',
        visitedAtMs: 2,
      ),
      VisitedPage(
        url: 'oct://circleb',
        title: 'Circle B',
        domain: 'circleb',
        visitedAtMs: 1,
      ),
    ];

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders search field, bookmark chips and recent rows',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(StartpageView(
        isLoading: false,
        error: null,
        pages: pages,
        bookmarks: const [
          {'name': 'Explorer', 'url': 'oct://explorer'},
        ],
        onOpen: (_, __) async {},
        onDelete: (_) async {},
        onClearAll: () async {},
      )));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Explorer'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Circle A'), findsOneWidget);
      expect(find.text('Circle B'), findsOneWidget);
      expect(find.text('No bookmarks yet'), findsNothing);
    });

    testWidgets('tapping a recent row calls onOpen with the row url',
        (WidgetTester tester) async {
      final opened = <String>[];
      await tester.pumpWidget(wrap(StartpageView(
        isLoading: false,
        error: null,
        pages: pages,
        bookmarks: const [
          {'name': 'Explorer', 'url': 'oct://explorer'},
        ],
        onOpen: (url, _) async => opened.add(url),
        onDelete: (_) async {},
        onClearAll: () async {},
      )));

      await tester.tap(find.text('Circle B'));
      await tester.pump();

      expect(opened, ['oct://circleb']);
    });

    testWidgets('tapping a bookmark chip calls onOpen with its url',
        (WidgetTester tester) async {
      final opened = <String>[];
      await tester.pumpWidget(wrap(StartpageView(
        isLoading: false,
        error: null,
        pages: const [],
        bookmarks: const [
          {'name': 'Explorer', 'url': 'oct://explorer'},
        ],
        onOpen: (url, _) async => opened.add(url),
        onDelete: (_) async {},
        onClearAll: () async {},
      )));

      await tester.tap(find.text('Explorer'));
      await tester.pump();

      expect(opened, ['oct://explorer']);
    });

    testWidgets('error state renders the message and retry button',
        (WidgetTester tester) async {
      var retries = 0;
      await tester.pumpWidget(wrap(StartpageView(
        isLoading: false,
        error: 'storage broken',
        pages: const [],
        bookmarks: const [],
        onOpen: (_, __) async {},
        onDelete: (_) async {},
        onClearAll: () async {},
        onRetry: () async => retries++,
      )));

      expect(find.text('storage broken'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
    });
  });
}
