import 'package:flutter/material.dart';

/// Brand and semantic colours shared by the Android app and the web
/// dashboard. Surfaces and text colours come from the active [ColorScheme]
/// (built in app_theme.dart) so light and dark mode stay consistent; the
/// semantic tones below are chosen to stay readable on both.
class AppColors {
  AppColors._();

  /// Brand blue (the "Default" accent).
  static const Color primary = Color(0xFF2457D6);

  static const Color secondary = Color(0xFF0F766E);

  // Semantic tones.
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF0284C7);
  static const Color neutral = Color(0xFF64748B);

  // Metric / category tones used by statistic cards and charts.
  static const Color inventory = Color(0xFF2457D6);
  static const Color headOffice = Color(0xFF0F9F6E);
  static const Color bazaar = Color(0xFF7C3AED);
  static const Color assigned = Color(0xFF4F46E5);
  static const Color damaged = Color(0xFFDC2626);
  static const Color repair = Color(0xFFEA580C);
  static const Color quantity = Color(0xFF0D9488);
  static const Color pending = Color(0xFFD97706);

  // Light surfaces (slate).
  static const Color lightBackground = Color(0xFFF4F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFDFE5EE);
  // High-contrast text: near-black slate (not pure black) for primary text,
  // a clearly readable dark grey for secondary text, lighter only for hints.
  static const Color lightText = Color(0xFF0A1020); // ~18.5:1 on white
  static const Color lightTextMuted = Color(0xFF3F4A5C); // ~9:1 on white
  static const Color lightTextHint = Color(0xFF677185); // ~4.9:1 on white

  // Dark surfaces (deep slate, not pure black, for comfortable contrast).
  static const Color darkBackground = Color(0xFF0B1120);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkCard = Color(0xFF151E2E);
  static const Color darkBorder = Color(0xFF2A3548);
  static const Color darkText = Color(0xFFF3F6FB);
  static const Color darkTextMuted = Color(0xFFBAC4D3);
  static const Color darkTextHint = Color(0xFF8E99AC);

  /// Colour for a status label (asset, request, account or Bazaar status).
  static Color forStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'available':
      case 'active':
      case 'approved':
      case 'completed':
      case 'returned':
      case 'good':
      case 'enabled':
        return success;
      case 'assigned':
      case 'deployed':
      case 'in transit':
      case 'transferred':
        return assigned;
      case 'pending':
      case 'under repair':
      case 'in repair':
      case 'maintenance':
      case 'under maintenance':
        return warning;
      case 'damaged':
      case 'damage':
      case 'lost':
      case 'missing':
      case 'rejected':
      case 'blocked':
      case 'deleted':
        return error;
      case 'disabled':
      case 'inactive':
      case 'retired':
      case 'disposed':
        return neutral;
      default:
        return info;
    }
  }

  /// Soft background for a tone (chips, icon tiles) in either brightness.
  static Color tint(Color tone, Brightness brightness) {
    return tone.withValues(alpha: brightness == Brightness.dark ? 0.20 : 0.10);
  }

  /// Readable foreground for a tone placed on its [tint].
  static Color onTint(Color tone, Brightness brightness) {
    if (brightness == Brightness.light) {
      return Color.lerp(tone, Colors.black, 0.18)!;
    }

    return Color.lerp(tone, Colors.white, 0.35)!;
  }
}

/// Shared spacing and corner radii.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radiusSm = 8; // chips, small tiles
  static const double radiusMd = 12; // inputs, buttons, menus
  static const double radiusLg = 16; // cards, sections, panels
  static const double radiusXl = 20; // dialogs, headers
}
