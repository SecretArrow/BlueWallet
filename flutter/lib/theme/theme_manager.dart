import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

const _kThemeKey = 'selected_theme_id';

class ThemeManager extends ChangeNotifier {
  AppPalette _palette = AppPalette.all.first;

  AppPalette get palette => _palette;
  String get paletteId => _palette.id;

  ThemeManager() {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kThemeKey) ?? AppPalette.all.first.id;
    _palette = AppPalette.byId(id);
    notifyListeners();
  }

  Future<void> setPalette(String id) async {
    _palette = AppPalette.byId(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, id);
    notifyListeners();
  }
}
