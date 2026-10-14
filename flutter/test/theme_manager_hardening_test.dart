import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:octopus_wallet/theme/theme_manager.dart';

/// Guards for the two weak points found in the theme pipeline after the
/// "theme doesn't work" report:
/// 1. mutations racing the async persisted-state load (a just-made choice
///    silently reverted by `_loadSaved()` applying stale values);
/// 2. slot-brightness corruption (a dark palette landing in the LIGHT slot,
///    which makes `themeMode` render the wrong brightness).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('mutation vs. persisted-state load race', () {
    test('a mutation issued before the load completes survives it', () async {
      // Device boots with dark mode persisted.
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final tm = ThemeManager(initialSystemBrightness: Brightness.dark);

      // The user flips to light BEFORE _loadSaved() has applied the
      // persisted values (no await of `ready` in between).
      final pending = tm.setMode('light');
      await tm.ready;
      await pending;

      expect(tm.mode, 'light');
      expect(tm.themeMode, ThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'light');
    });

    test('a palette pick issued before the load completes survives it',
        () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'system',
        'dark_palette_id': 'zenith',
      });
      final tm = ThemeManager(initialSystemBrightness: Brightness.dark);

      final pending = tm.setDarkPalette('moonbloom');
      await tm.ready;
      await pending;

      expect(tm.darkPaletteId, 'moonbloom');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dark_palette_id'), 'moonbloom');
    });
  });

  group('slot-brightness hardening', () {
    test('a light palette id saved into the DARK slot falls back safely',
        () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'dark_palette_id': 'frostline', // light palette — corrupt value
      });
      final tm = ThemeManager(initialSystemBrightness: Brightness.dark);
      await tm.ready;

      expect(tm.darkPalette.isDark, isTrue,
          reason: 'dark slot must never hold a light palette');
      expect(tm.darkPaletteId, 'zenith');
    });

    test('a dark palette id saved into the LIGHT slot falls back safely',
        () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'light',
        'light_palette_id': 'zenith', // dark palette — corrupt value
      });
      final tm = ThemeManager(initialSystemBrightness: Brightness.light);
      await tm.ready;

      expect(tm.lightPalette.isDark, isFalse,
          reason: 'light slot must never hold a dark palette');
      expect(tm.lightPaletteId, 'frostline');
    });

    test('unknown palette ids keep their slot\'s brightness', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'system',
        'dark_palette_id': 'not-a-palette',
        'light_palette_id': 'also-not-a-palette',
      });
      final tm = ThemeManager(initialSystemBrightness: Brightness.light);
      await tm.ready;

      expect(tm.darkPalette.isDark, isTrue);
      expect(tm.lightPalette.isDark, isFalse);
    });

    test('setDarkPalette with an unknown/light id keeps the slot dark',
        () async {
      final tm = ThemeManager(initialSystemBrightness: Brightness.dark);
      await tm.ready;

      await tm.setDarkPalette('bogus-id');
      expect(tm.darkPalette.isDark, isTrue);

      await tm.setDarkPalette('frostline'); // light palette into dark slot
      expect(tm.darkPalette.isDark, isTrue);
    });

    test('setLightPalette with an unknown/dark id keeps the slot light',
        () async {
      final tm = ThemeManager(initialSystemBrightness: Brightness.light);
      await tm.ready;

      await tm.setLightPalette('bogus-id');
      expect(tm.lightPalette.isDark, isFalse);

      await tm.setLightPalette('moonbloom'); // dark palette into light slot
      expect(tm.lightPalette.isDark, isFalse);
    });
  });
}
