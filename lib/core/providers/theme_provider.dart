
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isLight => _themeMode == ThemeMode.light;

  bool get isDark => _themeMode == ThemeMode.dark;

  bool get isSystem => _themeMode == ThemeMode.system;

  String get selectedTheme {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System Default';
    }
  }

  // ================================================================
  // ACCENT COLOUR
  // ================================================================

  static const String _accentKey = 'app_accent_color';

  /// Selectable accent colours (label -> colour). The first is the brand
  /// default, used when nothing has been chosen.
  static const Map<String, Color> accentOptions = {
    'Default': Color(0xFF2457D6),
    'Indigo': Color(0xFF4F46E5),
    'Purple': Color(0xFF7C3AED),
    'Teal': Color(0xFF0D9488),
    'Green': Color(0xFF16A34A),
    'Orange': Color(0xFFEA580C),
    'Red': Color(0xFFDC2626),
    'Pink': Color(0xFFDB2777),
    'Slate': Color(0xFF475569),
  };

  String _accentName = 'Default';

  String get accentName => _accentName;

  /// Null for the brand default, so the theme keeps its original seed.
  Color? get accentColor =>
      _accentName == 'Default' ? null : accentOptions[_accentName];

  Future<void> setAccent(String name) async {
    if (!accentOptions.containsKey(name) || name == _accentName) {
      return;
    }

    _accentName = name;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentKey, name);
  }

  // ================================================================
  // LOAD SAVED THEME
  // ================================================================

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    final savedAccent = prefs.getString(_accentKey);

    if (savedAccent != null && accentOptions.containsKey(savedAccent)) {
      _accentName = savedAccent;
    }

    final savedTheme = prefs.getString(_themeKey);

    switch (savedTheme) {
      case 'Light':
        _themeMode = ThemeMode.light;
        break;

      case 'Dark':
        _themeMode = ThemeMode.dark;
        break;

      case 'System Default':
      default:
        _themeMode = ThemeMode.system;
        break;
    }

    notifyListeners();
  }

  // ================================================================
  // CHANGE THEME
  // ================================================================

  Future<void> setTheme(String theme) async {
    ThemeMode newMode;

    switch (theme) {
      case 'Light':
        newMode = ThemeMode.light;
        break;

      case 'Dark':
        newMode = ThemeMode.dark;
        break;

      case 'System Default':
      default:
        newMode = ThemeMode.system;
        break;
    }

    if (_themeMode == newMode) {
      return;
    }

    _themeMode = newMode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme);

    notifyListeners();
  }

  // ================================================================
  // SET THEME MODE
  // ================================================================

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;

    final String theme;

    switch (mode) {
      case ThemeMode.light:
        theme = 'Light';
        break;

      case ThemeMode.dark:
        theme = 'Dark';
        break;

      case ThemeMode.system:
        theme = 'System Default';
        break;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme);

    notifyListeners();
  }
}