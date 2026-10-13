import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

const _kThemeKey = 'selected_theme_id';
const _kModeKey = 'theme_mode';
const _kDarkPaletteKey = 'dark_palette_id';
const _kLightPaletteKey = 'light_palette_id';

const Set<String> _kModes = {'system', 'dark', 'light'};

/// Manages the app theme: a brightness mode (system / dark / light) plus
/// one palette per brightness slot.
///
/// Persistence (SharedPreferences):
/// - `theme_mode`: 'system' | 'dark' | 'light' (default 'system').
/// - `dark_palette_id` / `light_palette_id`: palette per slot (defaults:
///   first dark / first light palette of [AppPalette.all]).
/// - `selected_theme_id`: legacy single-palette key. A previously saved
///   choice transparently seeds the matching slot and forces the palette's
///   mode, so upgrading users never get a surprise visual flip.
///
/// In `system` mode the effective palette follows the live platform
/// brightness; [didChangePlatformBrightness] re-resolves and notifies
/// listeners so the UI rebuilds when the OS switches light/dark.
class ThemeManager extends ChangeNotifier with WidgetsBindingObserver {
  static final AppPalette _firstDark = AppPalette.all.firstWhere(
    (p) => p.isDark,
    orElse: () => AppPalette.all.first,
  );
  static final AppPalette _firstLight = AppPalette.all.firstWhere(
    (p) => !p.isDark,
    orElse: () => AppPalette.all.first,
  );

  /// Completes when persisted settings have been loaded. Production code
  /// can ignore it (the UI rebuilds via notifyListeners); tests await it
  /// to avoid load races.
  late final Future<void> ready;

  String _mode = 'system';
  AppPalette _darkPalette = _firstDark;
  AppPalette _lightPalette = _firstLight;

  /// Brightness used to resolve `system` mode. Settable (tests, tooling);
  /// the production default is the live platform brightness.
  Brightness systemBrightness;

  ThemeManager({Brightness? initialSystemBrightness})
      : systemBrightness = initialSystemBrightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness {
    ready = _loadSaved();
    WidgetsBinding.instance.addObserver(this);
  }

  // ── Getters ────────────────────────────────────────────────────────────

  /// Current mode: 'system' | 'dark' | 'light'.
  String get mode => _mode;

  /// [ThemeMode] for MaterialApp's `themeMode` parameter.
  ThemeMode get themeMode {
    switch (_mode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  /// Palette used when the app renders dark (forced dark or dark system).
  AppPalette get darkPalette => _darkPalette;
  String get darkPaletteId => _darkPalette.id;

  /// Palette used when the app renders light.
  AppPalette get lightPalette => _lightPalette;
  String get lightPaletteId => _lightPalette.id;

  /// The palette the app renders with right now.
  AppPalette get effectivePalette {
    switch (_mode) {
      case 'dark':
        return _darkPalette;
      case 'light':
        return _lightPalette;
      default:
        return systemBrightness == Brightness.dark
            ? _darkPalette
            : _lightPalette;
    }
  }

  /// Back-compat alias of [effectivePalette].
  AppPalette get palette => effectivePalette;
  String get paletteId => palette.id;

  // ── Mutations (persist + notify) ───────────────────────────────────────

  /// Set the mode ('system' | 'dark' | 'light'). Invalid values throw.
  Future<void> setMode(String mode) async {
    if (!_kModes.contains(mode)) {
      throw ArgumentError("mode must be 'system', 'dark' or 'light'");
    }
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeKey, mode);
    notifyListeners();
  }

  /// Set the dark-slot palette (rendered in dark mode, and in system mode
  /// whenever the platform is dark).
  Future<void> setDarkPalette(String id) async {
    _darkPalette = AppPalette.byId(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDarkPaletteKey, id);
    notifyListeners();
  }

  /// Set the light-slot palette (rendered in light mode, and in system
  /// mode whenever the platform is light).
  Future<void> setLightPalette(String id) async {
    _lightPalette = AppPalette.byId(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLightPaletteKey, id);
    notifyListeners();
  }

  /// Back-compat: pick one specific palette (the old settings-screen
  /// behavior). Applies immediately — forces the palette's matching mode
  /// and stores it in its slot so system resolution honors it too.
  Future<void> setPalette(String id) async {
    final p = AppPalette.byId(id);
    _mode = p.isDark ? 'dark' : 'light';
    if (p.isDark) {
      _darkPalette = p;
    } else {
      _lightPalette = p;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, id);
    await prefs.setString(_kModeKey, _mode);
    await prefs.setString(
      p.isDark ? _kDarkPaletteKey : _kLightPaletteKey,
      id,
    );
    notifyListeners();
  }

  // ── WidgetsBindingObserver ─────────────────────────────────────────────

  @override
  void didChangePlatformBrightness() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (brightness == systemBrightness) return;
    systemBrightness = brightness;
    // Only a live system-mode resolution changes the rendered palette.
    if (_mode == 'system') notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();

    final savedMode = prefs.getString(_kModeKey);
    _mode = savedMode != null && _kModes.contains(savedMode)
        ? savedMode
        : 'system';

    final darkSaved = _findPalette(prefs.getString(_kDarkPaletteKey));
    final lightSaved = _findPalette(prefs.getString(_kLightPaletteKey));

    // Legacy single-palette pick (pre-upgrade installs).
    final legacy = _findPalette(prefs.getString(_kThemeKey));
    if (legacy != null) {
      if (legacy.isDark) {
        _darkPalette = darkSaved ?? legacy;
      } else {
        _lightPalette = lightSaved ?? legacy;
      }
      // No explicit mode saved yet: keep the user's visual choice instead
      // of silently flipping to the (possibly opposite) system theme.
      if (savedMode == null) {
        _mode = legacy.isDark ? 'dark' : 'light';
      }
    } else {
      _darkPalette = darkSaved ?? _firstDark;
      _lightPalette = lightSaved ?? _firstLight;
    }

    notifyListeners();
  }

  static AppPalette? _findPalette(String? id) {
    if (id == null) return null;
    for (final p in AppPalette.all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
