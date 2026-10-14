import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/screens/settings/theme_palette_screen.dart';
import 'package:octopus_wallet/theme/app_colors.dart';
import 'package:octopus_wallet/theme/app_theme.dart';
import 'package:octopus_wallet/theme/theme_manager.dart';

/// End-to-end theme pipeline (the user-reported "theme doesn't work"):
/// tapping the mode segment / a palette cell on the REAL settings screen
/// must mutate the ThemeManager AND the MaterialApp slots wired exactly
/// like app.dart (theme = light slot, darkTheme = dark slot, themeMode).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Mirrors OctopusWalletApp's build (app.dart) minus the router: the
  /// Consumer rebuild is what propagates a ThemeManager change into the
  /// MaterialApp slots.
  Widget harness(ThemeManager tm) => ChangeNotifierProvider<ThemeManager>.value(
        value: tm,
        child: Consumer<ThemeManager>(
          builder: (_, tm, __) => MaterialApp(
            theme: AppTheme.fromPalette(tm.lightPalette),
            darkTheme: AppTheme.fromPalette(tm.darkPalette),
            themeMode: tm.themeMode,
            home: const ThemePaletteScreen(),
          ),
        ),
      );

  MaterialApp appOf(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  testWidgets('tapping a light palette cell re-renders through the '
      'MaterialApp light slot', (WidgetTester tester) async {
    final tm = ThemeManager(initialSystemBrightness: Brightness.light);
    await tm.ready;
    await tester.pumpWidget(harness(tm));
    await tester.pumpAndSettle();

    // Default light palette: frostline.
    expect(appOf(tester).theme!.scaffoldBackgroundColor,
        AppPalette.byId('frostline').background);

    // Tap the "Ivory Circuit" cell (light palette grid, below the fold in
    // the 600px test viewport). scrollUntilVisible also BUILDS lazily-
    // deferred ListView children (ensureVisible throws "Bad state: No
    // element" on widgets the ListView has not materialized yet).
    // scrollable MUST be pinned: this screen nests two shrinkWrap
    // GridViews (each a Scrollable) inside the outer ListView, and the
    // auto-detected `find.byType(Scrollable)` calls .single internally →
    // "Bad state: Too many elements". The outer ListView is the first
    // Scrollable in tree order.
    await tester.scrollUntilVisible(
      find.text('Ivory Circuit'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ivory Circuit'));
    await tester.pumpAndSettle();

    expect(tm.lightPaletteId, 'ivorycircuit');
    expect(appOf(tester).theme!.scaffoldBackgroundColor,
        AppPalette.byId('ivorycircuit').background);
    // Dark slot untouched.
    expect(appOf(tester).darkTheme!.scaffoldBackgroundColor,
        AppPalette.byId('zenith').background);

    // Persisted for the next launch.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('light_palette_id'), 'ivorycircuit');

    tm.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('switching the mode to Dark renders the dark slot '
      '(palette + brightness)', (WidgetTester tester) async {
    final tm = ThemeManager(initialSystemBrightness: Brightness.light);
    await tm.ready;
    await tester.pumpWidget(harness(tm));
    await tester.pumpAndSettle();

    // Tap the Dark MODE segment. find.text('Dark') is ambiguous (every
    // dark palette cell carries a "Dark" label) — the segment's icon is
    // unique.
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    expect(tm.mode, 'dark');
    expect(tm.themeMode, ThemeMode.dark);
    expect(appOf(tester).darkTheme!.brightness, Brightness.dark);
    // What MaterialApp renders in dark mode: the dark slot's palette.
    expect(appOf(tester).darkTheme!.scaffoldBackgroundColor,
        AppPalette.byId('zenith').background);

    // Pick a different dark palette and verify the dark slot moves.
    await tester.scrollUntilVisible(
      find.text('Moonbloom'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moonbloom'));
    await tester.pumpAndSettle();
    expect(tm.darkPaletteId, 'moonbloom');
    expect(appOf(tester).darkTheme!.scaffoldBackgroundColor,
        AppPalette.byId('moonbloom').background);

    tm.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('system mode keeps both slots editable and independent',
      (WidgetTester tester) async {
    final tm = ThemeManager(initialSystemBrightness: Brightness.dark);
    await tm.ready;
    await tester.pumpWidget(harness(tm));
    await tester.pumpAndSettle();

    // System + dark platform: renders the dark slot right now.
    expect(appOf(tester).darkTheme!.brightness, Brightness.dark);

    // Both grids are shown in system mode; pick from each.
    await tester.scrollUntilVisible(
      find.text('Moonbloom'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moonbloom'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Solar Paper'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solar Paper'));
    await tester.pumpAndSettle();

    expect(tm.darkPaletteId, 'moonbloom');
    expect(tm.lightPaletteId, 'solarpaper');
    // Slots still derive their own brightness — the core slot invariant.
    expect(AppTheme.fromPalette(tm.lightPalette).brightness, Brightness.light);
    expect(AppTheme.fromPalette(tm.darkPalette).brightness, Brightness.dark);

    tm.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
