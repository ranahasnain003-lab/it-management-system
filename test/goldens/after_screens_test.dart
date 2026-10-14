/// Writes "after" screenshots of the screens the redesign will touch.
///
/// Run on purpose, because it writes files:
///
///   flutter test test/goldens/before_screens_test.dart --update-goldens
///
/// Rendered in Roboto, which is what the app falls back to today - it bundles
/// no font of its own. Using the new Inter here would quietly flatter the
/// "before".
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:it_management_system/core/authentication/screens/login_screen.dart';
import 'package:it_management_system/core/dashboard/screens/dashboard_screen.dart';
import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/providers/bazaar_provider.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/notification_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/theme_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';
import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/theme/app_brand.dart';
import 'package:it_management_system/core/theme/app_theme.dart';
import 'package:it_management_system/web/pages/dashboard_page.dart';
import 'package:it_management_system/web/pages/web_login_page.dart';

import 'support/fake_providers.dart';
import 'support/golden_harness.dart';

/// Wraps [child] in the providers, theme and MotionScope the real app gives
/// it, so what is rendered is the screen itself rather than a mock-up of it.
Widget _hosted(Widget child, {required bool dark, required String fontFamily}) {
  final theme = dark ? AppTheme.dark() : AppTheme.light();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
      ChangeNotifierProvider<UserProvider>(create: (_) => FakeUserProvider()),
      ChangeNotifierProvider<AssetProvider>(create: (_) => FakeAssetProvider()),
      ChangeNotifierProvider<BazaarProvider>(create: (_) => FakeBazaarProvider()),
      ChangeNotifierProvider<DeploymentProvider>(
        create: (_) => FakeDeploymentProvider(),
      ),
      ChangeNotifierProvider<RequestProvider>(create: (_) => FakeRequestProvider()),
      ChangeNotifierProvider<NotificationProvider>(
        create: (_) => FakeNotificationProvider(),
      ),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => FakeThemeProvider(dark: dark),
      ),
    ],
    child: MotionScope(
      level: AnimationLevel.rich,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: withGoldenFont(theme, fontFamily),
        home: child,
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    setupFirebaseMocks();
    await Firebase.initializeApp();
    await loadGoldenFonts();
  });

  /// Every screen, at both sizes and in both themes.
  ///
  /// [settle] is how long the capture pumps for before the shot. The default
  /// comfortably outlasts a login screen; the dashboard needs longer, because
  /// its opening sequence runs for 1.45s and a shorter pump would photograph
  /// it halfway through.
  void screen(
    String name,
    Widget Function() build, {
    List<GoldenDevice>? only,
    Duration settle = const Duration(milliseconds: 1200),
  }) {
    for (final device in only ?? GoldenDevice.all) {
      for (final dark in [false, true]) {
        testWidgets('$name - ${device.name} - ${dark ? 'dark' : 'light'}', (
          tester,
        ) async {
          await captureScreen(
            tester,
            folder: 'after',
            name: name,
            device: device,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            dark: dark,
            settle: settle,
            child: _hosted(build(), dark: dark, fontFamily: AppType.family),
          );
        });
      }
    }
  }

  // The phone sign-in screen.
  screen(
    'login_mobile',
    () => const LoginScreen(),
    only: const [GoldenDevice.phone],
  );

  // The web sign-in page, which is a different widget entirely - this is the
  // one that looked unchanged, because none of the earlier work touched it.
  screen(
    'login_web',
    () => const WebLoginPage(),
    only: const [GoldenDevice.desktop],
  );

  // The phone dashboard.
  screen(
    'dashboard_mobile',
    () => const DashboardScreen(),
    only: const [GoldenDevice.phone],
    settle: const Duration(milliseconds: 2100),
  );

  // The web dashboard, which is its own page rather than a wide layout of the
  // Android one - so it has to be shot separately or half the redesign is
  // never looked at.
  screen(
    'dashboard_web',
    // The shell supplies the Scaffold in the real app; without one here every
    // Text renders with Flutter's missing-Material debug marks.
    () => const Scaffold(body: WebDashboardPage()),
    only: const [GoldenDevice.desktop],
    settle: const Duration(milliseconds: 2100),
  );
}
