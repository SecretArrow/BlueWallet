import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/screens/settings/polling_settings_screen.dart';
import 'package:octopus_wallet/services/polling_service.dart';

/// Polling settings screen: persisted values must actually reach the text
/// fields (the service loads them asynchronously — a screen that only reads
/// the service synchronously on mount shows DEFAULTS, and a Save would then
/// overwrite the user's persisted settings), and the quick-select chips
/// must fill the interval field.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// GoRouter harness so the screen's `context.pop()` after Save works.
  Widget harness() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (c, __) => Scaffold(
            body: Center(
              child: OutlinedButton(
                onPressed: () => c.push('/polling-settings'),
                child: const Text('Open Settings'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/polling-settings',
          builder: (_, __) => const PollingSettingsScreen(),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PollingService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openScreen(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
  }

  /// Interval field is the first TextField on the screen.
  String intervalText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text;

  testWidgets('shows the PERSISTED settings once the service load lands',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'polling_interval_ms': 30000, // 30s
      'threshold_send_ms': 120000, // 2m
      'threshold_advanced_ms': 1200000, // 20m
    });
    await openScreen(tester);
    await tester.pumpAndSettle();

    expect(intervalText(tester), '30',
        reason: 'persisted interval, not the 5s default');
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '2');
    expect(tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        '20');
  });

  testWidgets('quick-chip fills the interval field with seconds',
      (WidgetTester tester) async {
    await openScreen(tester);
    await tester.pumpAndSettle();

    expect(intervalText(tester), '5'); // default

    await tester.tap(find.text('1 min'));
    await tester.pumpAndSettle();
    expect(intervalText(tester), '60');

    await tester.tap(find.text('30s'));
    await tester.pumpAndSettle();
    expect(intervalText(tester), '30');

    await tester.tap(find.text('15 min'));
    await tester.pumpAndSettle();
    expect(intervalText(tester), '900');
  });

  testWidgets('a user edit is never clobbered by the service load',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'polling_interval_ms': 30000});
    await openScreen(tester);

    // The persisted load may land at any moment; a quick-chip edit made
    // around that must always win over the post-`ready` re-sync.
    await tester.tap(find.text('5 min'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(intervalText(tester), '300',
        reason: 'a user edit must win over the re-sync after `ready`');
  });

  testWidgets('save persists the chip-selected interval and pops',
      (WidgetTester tester) async {
    await openScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('5 min'));
    await tester.pumpAndSettle();

    // Thresholds still hold the defaults (5m / 10m) — valid inputs.
    await tester.ensureVisible(find.text('Save Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('polling_interval_ms'), 300000);
    // The screen popped after saving — back to the home route.
    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.text('Save Settings'), findsNothing);
  });
}
