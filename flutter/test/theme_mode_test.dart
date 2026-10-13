import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/theme/theme_manager.dart';

/// Mode persistence semantics + effective palette resolution. Brightness
/// is injected via the constructor / the settable [ThemeManager.systemBrightness]
/// field; `didChangePlatformBrightness` is exercised through the test
/// binding's platformBrightness override.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Fresh manager with its async persisted-state load completed.
  Future<ThemeManager> boot({Brightness? brightness}) async {
    final tm = ThemeManager(initialSystemBrightness: brightness);
    await tm.ready;
    return tm;
  }

  test('defaults: system mode, first dark/light palettes', () async {
    final tm = await boot();
    expect(tm.mode, 'system');
    expect(tm.themeMode, ThemeMode.system);
    expect(tm.darkPaletteId, 'zenith');
    expect(tm.lightPaletteId, 'frostline');
  });

  test('setMode persists and maps to ThemeMode', () async {
    final tm = await boot();
    await tm.setMode('dark');
    expect(tm.mode, 'dark');
    expect(tm.themeMode, ThemeMode.dark);
    await tm.setMode('light');
    expect(tm.themeMode, ThemeMode.light);
    await tm.setMode('system');
    expect(tm.themeMode, ThemeMode.system);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'system');
  });

  test('setMode rejects unknown modes', () async {
    final tm = await boot();
    expect(() => tm.setMode('blue'), throwsArgumentError);
  });

  test('system mode resolves via systemBrightness', () async {
    final tm = await boot(brightness: Brightness.dark);
    expect(tm.effectivePalette.isDark, isTrue);
    tm.systemBrightness = Brightness.light;
    expect(tm.effectivePalette.isDark, isFalse);
  });

  test('forced modes ignore the system brightness', () async {
    final tm = await boot(brightness: Brightness.dark);
    await tm.setMode('light');
    expect(tm.effectivePalette.isDark, isFalse);
    tm.systemBrightness = Brightness.light;
    await tm.setMode('dark');
    expect(tm.effectivePalette.isDark, isTrue);
  });

  test('setDarkPalette / setLightPalette persist per slot', () async {
    final tm = await boot();
    await tm.setDarkPalette('moonbloom');
    await tm.setLightPalette('ivorycircuit');
    expect(tm.darkPaletteId, 'moonbloom');
    expect(tm.lightPaletteId, 'ivorycircuit');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dark_palette_id'), 'moonbloom');
    expect(prefs.getString('light_palette_id'), 'ivorycircuit');
  });

  test("setPalette (legacy API) forces the palette's mode + slot", () async {
    final tm = await boot(brightness: Brightness.light);
    await tm.setPalette('moonbloom');
    expect(tm.mode, 'dark');
    expect(tm.effectivePalette.id, 'moonbloom');

    await tm.setPalette('solarpaper');
    expect(tm.mode, 'light');
    expect(tm.effectivePalette.id, 'solarpaper');
    // System resolution honors the seeded slots too.
    tm.systemBrightness = Brightness.dark;
    expect(tm.effectivePalette.id, 'moonbloom');
    tm.systemBrightness = Brightness.light;
    expect(tm.effectivePalette.id, 'solarpaper');
  });

  test('legacy selected_theme_id migrates transparently', () async {
    SharedPreferences.setMockInitialValues({'selected_theme_id': 'frostline'});
    final tm = await boot(brightness: Brightness.dark);
    // Frostline is light: the pre-upgrade user's choice is preserved by
    // forcing light mode instead of silently flipping to dark.
    expect(tm.mode, 'light');
    expect(tm.effectivePalette.id, 'frostline');
    expect(tm.lightPaletteId, 'frostline');
    // Dark slot falls back to the default.
    expect(tm.darkPaletteId, 'zenith');
  });

  test('didChangePlatformBrightness updates + notifies in system mode',
      () async {
    final binding = TestWidgetsFlutterBinding.instance;
    final tm = await boot(brightness: Brightness.light);
    var notified = 0;
    tm.addListener(() => notified++);

    binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(() {
      binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
    });

    tm.didChangePlatformBrightness();
    expect(tm.systemBrightness, Brightness.dark);
    expect(tm.effectivePalette.isDark, isTrue);
    expect(notified, 1);

    // Forced mode: brightness changes are irrelevant → no notify.
    await tm.setMode('light');
    notified = 0;
    binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    tm.didChangePlatformBrightness();
    expect(notified, 0);
  });
}
