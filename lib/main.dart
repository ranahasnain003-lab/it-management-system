import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';

// Providers
import 'core/providers/auth_provider.dart';
import 'core/providers/asset_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/request_provider.dart';
import 'core/providers/notification_provider.dart';
import 'core/providers/log_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/deployment_provider.dart';
import 'core/providers/bazaar_provider.dart';

/// Development/testing only: host of the Firebase Local Emulator Suite
/// (e.g. `--dart-define=FIREBASE_EMULATOR_HOST=localhost`). Empty by default,
/// so release builds always use the production project it-inventory-8e690.
const String _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A screen that fails to build shows a readable panel instead of a blank
  // area, so the problem is visible and reportable in release builds too.
  ErrorWidget.builder = (details) {
    return Material(
      color: const Color(0xFFFFFFFF),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: Color(0xFFDC2626),
            ),
            const SizedBox(height: 12),
            const Text(
              'This section could not be displayed',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0A1020),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF3F4A5C)),
            ),
          ],
        ),
      ),
    );
  };

  // Web: clean URLs (/inventory instead of /#/inventory). No effect on
  // Android. Hosting must rewrite unknown paths to index.html (firebase.json).
  usePathUrlStrategy();

  // Firebase (same project and configuration for Android and Web).
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (_emulatorHost.isNotEmpty) {
    // Auth must be pointed at the emulator BEFORE Firestore is touched: on
    // the web, Firestore initializes Auth, which immediately starts restoring
    // the saved session against whichever endpoint is configured.
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  }

  // Wait until Firebase has restored any persisted session before the first
  // routing decision. On the web this restore is asynchronous; without
  // waiting, a browser refresh would briefly look signed out and bounce a
  // signed-in user to the login page. Resolves immediately on Android.
  await FirebaseAuth.instance
      .authStateChanges()
      .first
      .timeout(const Duration(seconds: 10), onTimeout: () => null);

  // ---------------------------------------------------------------------------
  // PUNJAB BAZAAR MASTER DATA
  // ---------------------------------------------------------------------------
  //
  // Missing master Bazaars are restored by the session watcher in App once a
  // Super Admin profile has loaded. Only a Super Admin may write Bazaar master
  // data, so seeding for any other account would always be denied.
  // ---------------------------------------------------------------------------

  // Theme
  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  // App
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider()..initialize(),
        ),

        ChangeNotifierProvider<AssetProvider>(create: (_) => AssetProvider()),

        ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),

        ChangeNotifierProvider<RequestProvider>(
          create: (_) => RequestProvider(),
        ),

        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),

        ChangeNotifierProvider<LogProvider>(create: (_) => LogProvider()),

        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),

        ChangeNotifierProvider<DeploymentProvider>(
          create: (_) => DeploymentProvider(),
        ),

        ChangeNotifierProvider<BazaarProvider>(create: (_) => BazaarProvider()),
      ],
      child: const App(),
    ),
  );
}
