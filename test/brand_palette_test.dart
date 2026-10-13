/// Tests for the design system.
///
/// The contrast checks matter most: they are the difference between "we meant
/// to meet AA" and "we meet AA", and a palette drifts the moment someone
/// nudges a colour by eye.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_brand.dart';
import 'package:it_management_system/core/theme/app_theme.dart';
import 'package:it_management_system/core/theme/colors.dart';

void main() {
  group('the brand colour comes from the logo', () {
    test('primary is the green sampled from the PSBA mark', () {
      // #0B6B3A covers 44,512 of the logo's opaque pixels. The app used to be
      // blue, which clashed with its own logo on every screen.
      expect(AppBrand.green, const Color(0xFF0B6B3A));
      expect(AppColors.primary, AppBrand.green);
    });

    test('the themes are built from it', () {
      expect(AppTheme.light().colorScheme.primary, AppBrand.green);
      expect(AppTheme.dark().colorScheme.primary, isNot(const Color(0xFF2457D6)));
    });
  });

  group('contrast meets WCAG AA', () {
    test('body text on both surfaces', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final scheme = theme.colorScheme;

        expect(
          AppBrand.contrastRatio(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'onSurface on surface (${scheme.brightness})',
        );
        expect(
          AppBrand.contrastRatio(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'onSurfaceVariant on surface (${scheme.brightness})',
        );
      }
    });

    test('text on the primary colour', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final scheme = theme.colorScheme;
        expect(
          AppBrand.contrastRatio(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
          reason: 'onPrimary on primary (${scheme.brightness})',
        );
      }
    });

    test('every status colour is readable on a light surface', () {
      // 3:1 is the AA bar for a UI shape or large text, which is what a status
      // chip and a chart slice are.
      const surface = Color(0xFFFFFFFF);

      for (final status in [
        'Available', 'Assigned', 'Reserved', 'Under Maintenance',
        'In Repair', 'Damaged', 'Lost', 'Disposed',
      ]) {
        final colour = AppBrand.forStatus(status);
        expect(
          AppBrand.contrastRatio(colour, surface),
          greaterThanOrEqualTo(3.0),
          reason: '$status on white',
        );
      }
    });

    test('the ratio helper agrees with known pairs', () {
      // Sanity: black on white is 21:1, a colour against itself is 1:1.
      expect(
        AppBrand.contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.1),
      );
      expect(
        AppBrand.contrastRatio(AppBrand.green, AppBrand.green),
        closeTo(1, 0.001),
      );
    });
  });

  group('the status language is one mapping', () {
    test('each status has its own colour', () {
      final colours = {
        for (final s in [
          'Available', 'Assigned', 'Reserved', 'Under Maintenance',
          'In Repair', 'Damaged', 'Lost',
        ])
          s: AppBrand.forStatus(s),
      };

      // Distinct, or the colour tells the reader nothing.
      expect(colours.values.toSet().length, colours.length);
    });

    test('spelling variants land on the same colour', () {
      expect(AppBrand.forStatus('available'), AppBrand.forStatus('In Stock'));
      expect(AppBrand.forStatus('Assigned'), AppBrand.forStatus('issued'));
      expect(AppBrand.forStatus('in repair'), AppBrand.forStatus('Repair'));
    });

    test('an unknown status gets the neutral, not a meaningful colour', () {
      expect(AppBrand.forStatus('something new'), AppBrand.statusDisposed);
    });
  });

  group('categories', () {
    test('the same category is always the same colour', () {
      // Hashed, not random: a list would otherwise recolour on every rebuild.
      expect(
        AppBrand.colourForCategory('Laptop'),
        AppBrand.colourForCategory('laptop'),
      );
      expect(
        AppBrand.colourForCategory('Printer'),
        isNot(AppBrand.colourForCategory('Laptop')),
      );
    });

    test('known categories get their own icon, unknown ones a default', () {
      expect(AppBrand.iconForCategory('Laptop'), Icons.laptop_mac_rounded);
      expect(AppBrand.iconForCategory('UPS'), Icons.battery_charging_full_rounded);
      expect(AppBrand.iconForCategory('Flux Capacitor'), Icons.inventory_2_rounded);
    });
  });

  group('typography', () {
    test('the bundled family is used, not a downloaded one', () {
      expect(AppType.family, 'Inter');
      expect(AppTheme.light().textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(AppTheme.dark().textTheme.titleLarge?.fontFamily, 'Inter');
    });

    test('figures are tabular, so columns of numbers line up', () {
      // Without this a counting-up number jumps sideways as its digits change.
      expect(AppType.metric.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(AppType.metricSmall.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('the scale is ordered', () {
      expect(AppType.metric.fontSize!, greaterThan(AppType.metricSmall.fontSize!));
      expect(AppType.pageTitle.fontSize!, greaterThan(AppType.sectionTitle.fontSize!));
      expect(AppType.sectionTitle.fontSize!, greaterThan(AppType.body.fontSize!));
      expect(AppType.body.fontSize!, greaterThan(AppType.label.fontSize!));
    });
  });
}
