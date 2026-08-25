import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider()..initialize(),
        ),
        ChangeNotifierProvider<AssetProvider>(
          create: (_) => AssetProvider(),
        ),
        ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(),
        ),
        ChangeNotifierProvider<RequestProvider>(
          create: (_) => RequestProvider(),
        ),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProvider<LogProvider>(
          create: (_) => LogProvider(),
        ),
      ],
      child: const App(),
    ),
  );
}