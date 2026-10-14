import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/theme/app_colors.dart';
import 'package:octopus_wallet/theme/app_theme.dart';
import 'package:octopus_wallet/theme/theme_manager.dart';

/// MaterialApp slot wiring: the light and dark slots must each derive from
/// their OWN palette so `themeMode` alone decides what renders. Guards the
/// app.dart fix where both slots briefly shared one effectivePalette-derived
/// ThemeData (fragile against a stale platformBrightness read at startup).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ThemeManager> boot({Brightness? brightness}) async {
    final tm = ThemeManager(initialSystemBrightness: brightness);
    await tm.ready;
    return tm;
  }

  group('AppTheme.fromPalette slot mapping', () {
    test('light palette yields a LIGHT ThemeData', () {
      final p = AppPalette.byId('frostline');
      final td = AppTheme.fromPalette(p);
      expect(td.brightness, Brightness.light);
      expect(td.scaffoldBackgroundColor, p.background);
      expect(td.colorScheme.brightness, Brightness.light);
    });

    test('dark palette yields a DARK ThemeData', () {
      final p = AppPalette.byId('moonbloom');
      final td = AppTheme.fromPalette(p);
      expect(td.brightness, Brightness.dark);
      expect(td.scaffoldBackgroundColor, p.background);
      expect(td.colorScheme.brightness, Brightness.dark);
    });

    test('every registered palette maps to its own brightness', () {
      for (final p in AppPalette.all) {
        final td = AppTheme.fromPalette(p);
        expect(td.brightness, p.isDark ? Brightness.dark : Brightness.light,
            reason: 'palette ${p.id}');
      }
    });
  });

  group('slot independence (theme vs darkTheme inputs)', () {
    test('defaults: dark slot is dark, light slot is light', () async {
      final tm = await boot();
      expect(tm.darkPalette.isDark, isTrue);
      expect(tm.lightPalette.isDark, isFalse);
    });

    test('setDarkPalette only moves the dark slot', () async {
      final tm = await boot();
      await tm.setDarkPalette('moonbloom');
      expect(tm.darkPaletteId, 'moonbloom');
      expect(tm.lightPaletteId, 'frostline');
      // Light slot still renders light regardless of the dark pick.
      expect(AppTheme.fromPalette(tm.lightPalette).brightness,
          Brightness.light);
    });

    test('setLightPalette only moves the light slot', () async {
      final tm = await boot();
      final beforeDark = tm.darkPaletteId;
      await tm.setLightPalette(AppPalette.all.firstWhere((p) => !p.isDark && p.id != 'frostline').id);
      expect(tm.lightPaletteId, isNot('frostline'));
      expect(tm.darkPaletteId, beforeDark);
      expect(AppTheme.fromPalette(tm.darkPalette).brightness, Brightness.dark);
    });

    test('forced dark mode renders the dark slot even on a light system',
        () async {
      final tm = await boot(brightness: Brightness.light);
      await tm.setMode('dark');
      // What MaterialApp renders with themeMode=dark: the darkTheme input.
      expect(AppTheme.fromPalette(tm.darkPalette).brightness, Brightness.dark);
      expect(tm.themeMode, ThemeMode.dark);
    });

    test('forced light mode renders the light slot even on a dark system',
        () async {
      final tm = await boot(brightness: Brightness.dark);
      await tm.setMode('light');
      expect(AppTheme.fromPalette(tm.lightPalette).brightness,
          Brightness.light);
      expect(tm.themeMode, ThemeMode.light);
    });

    test('system mode: slots stay distinct while resolution follows the OS',
        () async {
      final tm = await boot(brightness: Brightness.dark);
      expect(tm.effectivePalette.isDark, isTrue);
      // Slot-derived ThemeData the app passes to MaterialApp:
      expect(AppTheme.fromPalette(tm.darkPalette).brightness, Brightness.dark);
      expect(AppTheme.fromPalette(tm.lightPalette).brightness,
          Brightness.light);
    });
  });
}
